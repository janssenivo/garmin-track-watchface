import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Circuit of the Americas centreline from OpenStreetMap (highway=raceway ways
// Turn 1..Turn 20, (c) OpenStreetMap contributors, ODbL), simplified and
// normalised to 0..1000, north up, y grows downward. Flat [x, y, x, y, ...]
// pairs in race direction (counterclockwise), starting at the start/finish line.
// Scaled to the screen in onLayout().
const TRACK_POINTS = [
    191, 459,  316, 557,  339, 571,  345, 571,  349, 570,  352, 565,  351, 558,  324, 479,
    322, 470,  323, 453,  329, 435,  336, 424,  346, 414,  419, 369,  434, 358,  441, 352,
    445, 344,  455, 320,  462, 308,  471, 302,  494, 293,  503, 285,  508, 279,  511, 272,
    518, 236,  523, 226,  531, 217,  543, 208,  558, 200,  568, 198,  578, 197,  591, 200,
    643, 224,  651, 224,  665, 216,  677, 207,  688, 196,  698, 181,  703, 176,  710, 172,
    718, 170,  730, 171,  738, 175,  746, 182,  755, 195,  758, 197,  765, 199,  865, 176,
    871, 172,  991, 26,  999, 15,  1000, 10,  999, 5,  996, 2,  993, 0,  986, 0,
    886, 32,  776, 61,  717, 75,  650, 88,  546, 104,  363, 125,  360, 129,  361, 135,
    389, 172,  421, 220,  423, 227,  421, 233,  418, 237,  413, 239,  376, 236,  370, 232,
    367, 228,  356, 201,  335, 179,  328, 175,  317, 173,  305, 172,  300, 175,  299, 178,
    299, 184,  345, 265,  349, 275,  351, 287,  346, 307,  341, 320,  334, 330,  328, 334,
    290, 352,  279, 353,  262, 351,  244, 345,  227, 336,  221, 330,  190, 287,  165, 254,
    155, 243,  147, 239,  137, 239,  123, 243,  6, 295,  2, 298,  0, 303,  0, 307,
    4, 313
] as Array<Number>;
const TRACK_COLOR = 0xAAAAAA;

class track_garmin_watchfaceView extends WatchUi.WatchFace {

    private var _xs as Array<Float> = [] as Array<Float>;
    private var _ys as Array<Float> = [] as Array<Float>;
    // Distance along the track from the start line to each sampled point
    private var _cumLen as Array<Float> = [] as Array<Float>;
    private var _totalLen as Float = 0.0;
    private var _isAwake as Boolean = true;
    private var _timeFont as FontType = Graphics.FONT_NUMBER_MEDIUM;
    // Dimensions were designed for 454px; scaled for smaller screens
    private var _px as Float = 1.0;
    private var _carbon as BitmapResource?;

    // Time layout: "HH:MM:" is right-aligned and "SS" left-aligned at _splitX,
    // so the seconds can be redrawn on their own in onPartialUpdate()
    private var _timeY as Number = 0;
    private var _splitX as Number = 0;
    private var _secWidth as Number = 0;
    // Half-height of the seconds repaint area. MIP display cost grows with the
    // number of rows refreshed, so this hugs the digit glyphs (about half the
    // font's line height) instead of using the full line height.
    private var _secHalfHeight as Number = 0;

    // MIP devices (fenix 6X) keep seconds running in low power via onPartialUpdate().
    // _buffer caches the background and track so each partial update only has to
    // repaint the seconds and the area around the dot. The time can't live in it:
    // anti-aliased fonts can't be drawn to a paletted buffer.
    private var _buffer as BufferedBitmap?;
    private var _bufferReady as Boolean = false;
    private var _partialAllowed as Boolean = false;

    // Dot positions for each second, sizes and colour, precomputed so per-second
    // updates stay cheap
    private var _dotX as Array<Number> = [] as Array<Number>;
    private var _dotY as Array<Number> = [] as Array<Number>;
    private var _dotOuter as Number = 0;
    private var _dotInner as Number = 0;
    private var _dotColor as Number = Graphics.COLOR_ORANGE;

    function initialize() {
        WatchFace.initialize();
    }

    // Load your resources here
    function onLayout(dc as Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        _px = width / 454.0;
        _carbon = WatchUi.loadResource(Rez.Drawables.CarbonFiber) as BitmapResource;
        buildTrack(width, height);
        loadTimeFont(dc);

        _dotOuter = scaled(14);
        _dotInner = scaled(11);
        _dotX = new Array<Number>[60];
        _dotY = new Array<Number>[60];
        for (var sec = 0; sec < 60; sec++) {
            var pos = positionAt(sec / 60.0);
            _dotX[sec] = (pos[0] + 0.5).toNumber();
            _dotY[sec] = (pos[1] + 0.5).toNumber();
        }

        var fullWidth = dc.getTextWidthInPixels("00:00:00", _timeFont);
        _timeY = (height * 0.24).toNumber();
        _splitX = width / 2 - fullWidth / 2 + dc.getTextWidthInPixels("00:00:", _timeFont);
        var digitWidth = 0;
        for (var d = 0; d < 10; d++) {
            var w = dc.getTextWidthInPixels(d.toString(), _timeFont);
            if (w > digitWidth) { digitWidth = w; }
        }
        _secWidth = digitWidth * 2 + 2;
        _secHalfHeight = (Graphics.getFontHeight(_timeFont) * 0.27).toNumber() + 1;

        // AMOLED devices never get partial updates (and can't afford a full-screen buffer)
        if ((WatchUi.WatchFace has :onPartialUpdate) && !System.getDeviceSettings().requiresBurnInProtection) {
            var options = {
                :width => width,
                :height => height,
                :palette => [Graphics.COLOR_BLACK, 0x555555, TRACK_COLOR, Graphics.COLOR_WHITE]
            };
            if (Graphics has :createBufferedBitmap) {
                _buffer = Graphics.createBufferedBitmap(options).get() as BufferedBitmap?;
            } else {
                _buffer = new Graphics.BufferedBitmap(options);
            }
            _partialAllowed = _buffer != null;
        }
    }

    // Called when this View is brought to the foreground. Restore
    // the state of this View and prepare it to be shown. This includes
    // loading resources into memory.
    function onShow() as Void {
    }

    // Update the view
    function onUpdate(dc as Dc) as Void {
        var clockTime = System.getClockTime();
        var hh = clockTime.hour.format("%02d");
        var mm = clockTime.min.format("%02d");
        var width = dc.getWidth();
        var height = dc.getHeight();
        dc.clearClip();
        _dotColor = Application.Properties.getValue("DotColor") as Number;

        if (!_isAwake && System.getDeviceSettings().requiresBurnInProtection) {
            // AMOLED always-on mode: only a dim time, shifted every minute to avoid burn-in
            var shift = (clockTime.min % 5 - 2) * 4;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(width / 2 + shift, height / 2 + shift, Graphics.FONT_NUMBER_MEDIUM, hh + ":" + mm,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Without partial updates, seconds would go stale in low power (one update a minute)
        var showSeconds = _isAwake || _partialAllowed;
        var buffer = _buffer;
        if (buffer != null) {
            if (!_bufferReady) {
                drawBackground(buffer.getDc());
                _bufferReady = true;
            }
            dc.drawBitmap(0, 0, buffer);
        } else {
            if (dc has :setAntiAlias) {
                dc.setAntiAlias(true);
            }
            drawBackground(dc);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        if (showSeconds) {
            dc.drawText(_splitX, _timeY, _timeFont, hh + ":" + mm + ":",
                Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            dc.drawText(width / 2, _timeY, _timeFont, hh + ":" + mm,
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }

        if (showSeconds) {
            drawSeconds(dc, clockTime.sec);
        }
        // The dot only moves while awake (see onPartialUpdate()), so hide it in low power
        if (_isAwake) {
            drawDot(dc, clockTime.sec);
        }
    }

    // Low-power update once a second (MIP devices), limited to 30 ms on average.
    // Only the seconds digits are repainted: the display refreshes one band of
    // rows spanning everything drawn, so also moving the dot (far below the time)
    // would refresh most of the screen and exceed the budget (~33 ms measured,
    // vs ~15 ms for the seconds alone).
    function onPartialUpdate(dc as Dc) as Void {
        var buffer = _buffer;
        if (!_partialAllowed || buffer == null) {
            return;
        }
        dc.setClip(_splitX, _timeY - _secHalfHeight, _secWidth, _secHalfHeight * 2);
        dc.drawBitmap(0, 0, buffer);
        drawSeconds(dc, System.getClockTime().sec);
        dc.clearClip();
    }

    // Called by the delegate when partial updates use too much power; fall back
    // to HH:MM only in low power
    function disablePartialUpdates() as Void {
        _partialAllowed = false;
        WatchUi.requestUpdate();
    }

    // Called when this View is removed from the screen. Save the
    // state of this View here. This includes freeing resources from
    // memory.
    function onHide() as Void {
    }

    // The user has just looked at their watch. Timers and animations may be started here.
    function onExitSleep() as Void {
        _isAwake = true;
        WatchUi.requestUpdate();
    }

    // Terminate any active timers and prepare for slow updates.
    function onEnterSleep() as Void {
        _isAwake = false;
        WatchUi.requestUpdate();
    }

    private function drawBackground(dc as Dc) as Void {
        var carbon = _carbon;
        if (carbon != null) {
            dc.drawBitmap(0, 0, carbon);
        }
        drawTrack(dc);
    }

    private function drawSeconds(dc as Dc, sec as Number) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_splitX, _timeY, _timeFont, sec.format("%02d"),
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawDot(dc as Dc, sec as Number) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_dotX[sec], _dotY[sec], _dotOuter);
        dc.setColor(_dotColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(_dotX[sec], _dotY[sec], _dotInner);
    }

    // Pick the largest bold font where HH:MM:SS fits the top of the screen
    private function loadTimeFont(dc as Dc) as Void {
        if (!(Graphics has :getVectorFont)) {
            // CIQ 3.x devices (fenix 6X): use the largest built-in number font that fits
            var fonts = [Graphics.FONT_NUMBER_THAI_HOT, Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM];
            for (var i = 0; i < fonts.size(); i++) {
                _timeFont = fonts[i];
                if (dc.getTextWidthInPixels("00:00:00", _timeFont) <= dc.getWidth() * 0.75) {
                    return;
                }
            }
            return;
        }
        var faces = ["BionicBold", "RobotoCondensedBold"];
        var probeSize = 80;
        var probe = Graphics.getVectorFont({:face => faces, :size => probeSize});
        if (probe == null) {
            return;
        }
        var probeWidth = dc.getTextWidthInPixels("00:00:00", probe);
        var size = (probeSize * dc.getWidth() * 0.7 / probeWidth).toNumber();
        var font = Graphics.getVectorFont({:face => faces, :size => size});
        if (font != null) {
            _timeFont = font;
        }
    }

    // Scale TRACK_POINTS into the lower part of the screen and precompute arc lengths.
    private function buildTrack(width as Number, height as Number) as Void {
        var count = TRACK_POINTS.size() / 2;
        _xs = new Array<Float>[count];
        _ys = new Array<Float>[count];

        var minX = 1.0e9, maxX = -1.0e9, minY = 1.0e9, maxY = -1.0e9;
        for (var i = 0; i < count; i++) {
            var x = TRACK_POINTS[i * 2].toFloat();
            var y = TRACK_POINTS[i * 2 + 1].toFloat();
            _xs[i] = x;
            _ys[i] = y;
            if (x < minX) { minX = x; }
            if (x > maxX) { maxX = x; }
            if (y < minY) { minY = y; }
            if (y > maxY) { maxY = y; }
        }

        // Fit into a box below the time, centered horizontally
        var scaleX = width * 0.8 / (maxX - minX);
        var scaleY = height * 0.48 / (maxY - minY);
        var scale = scaleX < scaleY ? scaleX : scaleY;
        var centerX = width / 2.0;
        var centerY = height * 0.6;
        var midX = (minX + maxX) / 2.0;
        var midY = (minY + maxY) / 2.0;

        _cumLen = new Array<Float>[count];
        var length = 0.0;
        for (var i = 0; i < count; i++) {
            _xs[i] = centerX + (_xs[i] - midX) * scale;
            _ys[i] = centerY + (_ys[i] - midY) * scale;
            if (i > 0) {
                length += distance(_xs[i - 1], _ys[i - 1], _xs[i], _ys[i]);
            }
            _cumLen[i] = length;
        }
        _totalLen = length + distance(_xs[count - 1], _ys[count - 1], _xs[0], _ys[0]);
    }

    private function distance(x1 as Float, y1 as Float, x2 as Float, y2 as Float) as Float {
        var dx = x2 - x1;
        var dy = y2 - y1;
        return Math.sqrt(dx * dx + dy * dy).toFloat();
    }

    // Screen position at the given fraction (0..1) of a lap
    private function positionAt(fraction as Float) as [Float, Float] {
        var target = fraction * _totalLen;
        var count = _xs.size();
        for (var i = 0; i < count; i++) {
            var next = (i + 1) % count;
            var segEnd = next == 0 ? _totalLen : _cumLen[next];
            if (target <= segEnd) {
                var segLen = segEnd - _cumLen[i];
                var t = segLen > 0 ? (target - _cumLen[i]) / segLen : 0.0;
                return [_xs[i] + (_xs[next] - _xs[i]) * t, _ys[i] + (_ys[next] - _ys[i]) * t];
            }
        }
        return [_xs[0], _ys[0]];
    }

    private function scaled(value as Number) as Number {
        var result = (value * _px + 0.5).toNumber();
        return result < 2 ? 2 : result;
    }

    private function drawTrack(dc as Dc) as Void {
        var count = _xs.size();
        dc.setColor(TRACK_COLOR, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(scaled(7));
        for (var i = 0; i < count; i++) {
            var next = (i + 1) % count;
            dc.drawLine(_xs[i], _ys[i], _xs[next], _ys[next]);
        }

        // Start/finish line, perpendicular to the direction of travel
        var dx = _xs[1] - _xs[0];
        var dy = _ys[1] - _ys[0];
        var len = Math.sqrt(dx * dx + dy * dy).toFloat();
        var nx = -dy / len * scaled(16);
        var ny = dx / len * scaled(16);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(scaled(3));
        dc.drawLine(_xs[0] - nx, _ys[0] - ny, _xs[0] + nx, _ys[0] + ny);
        dc.setPenWidth(1);
    }

}
