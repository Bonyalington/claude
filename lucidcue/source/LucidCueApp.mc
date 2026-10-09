import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// App entry point (manifest entry="LucidCueApp"). The initial view is the main menu
// (source/views/MainMenu.mc).
class LucidCueApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    // If the app is closed while a night is running, end it so the log still gets the
    // end battery and night_end. A night already ended writes nothing (stop() is idempotent).
    function onStop(state as Dictionary?) as Void {
        var night = $.lcActiveNight;
        if (night != null) {
            night.stop();
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [$.lcMainMenu(), new MainMenuDelegate()];
    }
}
