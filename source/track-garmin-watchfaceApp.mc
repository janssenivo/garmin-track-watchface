import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class track_garmin_watchfaceApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state as Dictionary?) as Void {
    }

    // onStop() is called when your application is exiting
    function onStop(state as Dictionary?) as Void {
    }

    // Return the initial view of your application here
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new track_garmin_watchfaceView();
        return [ view, new track_garmin_watchfaceDelegate(view) ];
    }

    // New app settings have been received so trigger a UI update
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

}

// Receives power budget reports for onPartialUpdate()
class track_garmin_watchfaceDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as track_garmin_watchfaceView;

    function initialize(view as track_garmin_watchfaceView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPowerBudgetExceeded(powerInfo as WatchUi.WatchFacePowerInfo) as Void {
        System.println("Partial update budget exceeded: " + powerInfo.executionTimeAverage
            + " ms avg, limit " + powerInfo.executionTimeLimit + " ms");
        _view.disablePartialUpdates();
    }

}

function getApp() as track_garmin_watchfaceApp {
    return Application.getApp() as track_garmin_watchfaceApp;
}