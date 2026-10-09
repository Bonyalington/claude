import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// After the morning questions: summaryLines(summary). Back returns to the main menu
// (stack [Menu, Summary] -> [Menu]).
class SummaryView extends WatchUi.View {
    var mLines as Array<String>;

    function initialize(summary as NightSummary) {
        View.initialize();
        mLines = $.summaryLines(summary);
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        $.lcDrawScreen(dc, mLines);
    }
}

class SummaryDelegate extends WatchUi.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
