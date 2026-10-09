import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Main menu: Train, Start Night, Buzz test, Settings. Back on it exits the app.
function lcMainMenu() as WatchUi.Menu2 {
    var menu = new WatchUi.Menu2({:title => "LucidCue"});
    menu.addItem(new WatchUi.MenuItem("Train", null, :train, null));
    menu.addItem(new WatchUi.MenuItem("Start Night", null, :night, null));
    menu.addItem(new WatchUi.MenuItem("Buzz test", null, :buzz, null));
    menu.addItem(new WatchUi.MenuItem("Settings", null, :settings, null));
    return menu;
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :train) {
            var train = new TrainView();
            WatchUi.pushView(train, new TrainDelegate(train), WatchUi.SLIDE_LEFT);
        } else if (id == :night) {
            $.lcStartNight(false);
        } else if (id == :buzz) {
            var buzz = new BuzzTestView();
            WatchUi.pushView(buzz, new BuzzTestDelegate(buzz), WatchUi.SLIDE_LEFT);
        } else if (id == :settings) {
            WatchUi.pushView($.lcSettingsMenu(), new SettingsMenuDelegate(), WatchUi.SLIDE_LEFT);
        }
    }
}

// On-watch settings (R10): phone settings may not appear for a sideloaded app, so the
// go-live switch (calibrationMode) and vibeByLength can be toggled here. Each toggle is
// written to Application.Properties at once; loadConfig() reads it at the next Start
// Night, so a change applies from the next night.
function lcSettingsMenu() as WatchUi.Menu2 {
    var dflt = new LcConfig();
    var menu = new WatchUi.Menu2({:title => "Settings"});
    menu.addItem(new WatchUi.ToggleMenuItem("Calibration mode", "From next night",
        :calibrationMode, $.lcReadBoolean("calibrationMode", dflt.calibrationMode), null));
    menu.addItem(new WatchUi.ToggleMenuItem("Buzz by length", "From next night",
        :vibeByLength, $.lcReadBoolean("vibeByLength", dflt.vibeByLength), null));
    return menu;
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    // The item has already flipped when onSelect runs; store its new state.
    function onSelect(item as WatchUi.MenuItem) as Void {
        if (!(item instanceof WatchUi.ToggleMenuItem)) {
            return;
        }
        var on = (item as WatchUi.ToggleMenuItem).isEnabled();
        var id = item.getId();
        if (id == :calibrationMode) {
            Application.Properties.setValue("calibrationMode", on);
        } else if (id == :vibeByLength) {
            Application.Properties.setValue("vibeByLength", on);
        }
    }
}
