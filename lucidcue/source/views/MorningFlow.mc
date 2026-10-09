import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The three morning questions, in order.
function lcQuestion(k as Number) as String {
    if (k == 0) {
        return "Remember a dream?";
    } else if (k == 1) {
        return "Felt the cue in a dream?";
    }
    return "Became lucid?";
}

// Morning check-in: three yes/no Confirmations over a plain Morning view, then
// session.logMorning(...) and the Summary. NightSession.stop() has already written the
// end battery and night_end (R15), so this writes only the morning line.
//
// Stack: [Menu, Morning, Question] for each question, then [Menu, Summary].
// Every step is deferred by a short timer so the previous Confirmation has been
// dismissed before the next view is pushed or switched in.
class MorningFlow {
    const QUESTIONS = 3;
    const STEP_DELAY_MS = 100;

    var mSession as NightSession or Null;
    var mSummary as NightSummary;
    var mStep as Number = 0;            // questions answered so far
    var mAnswers as Array<Boolean>;
    var mTimer as Timer.Timer or Null = null;
    var mDone as Boolean = false;

    function initialize(session as NightSession or Null, summary as NightSummary) {
        mSession = session;
        mSummary = summary;
        mAnswers = [false, false, false] as Array<Boolean>;
    }

    function step() as Number {
        return mStep;
    }

    function answered() as Boolean {
        return mStep >= QUESTIONS;
    }

    // Replaces the Night view with the Morning view, then asks question 1.
    function begin() as Void {
        WatchUi.switchToView(new MorningView(self), new MorningDelegate(self),
            WatchUi.SLIDE_IMMEDIATE);
        later(method(:ask));
    }

    // Pushes the current question. Also called by START on the Morning view, in case a
    // question was dismissed without an answer.
    function ask() as Void {
        cancel();
        if (mStep >= QUESTIONS || mDone) {
            return;
        }
        WatchUi.pushView(new WatchUi.Confirmation($.lcQuestion(mStep)),
            new MorningAnswerDelegate(self), WatchUi.SLIDE_IMMEDIATE);
    }

    function answer(yes as Boolean) as Void {
        if (mStep >= QUESTIONS) {
            return;
        }
        mAnswers[mStep] = yes;
        mStep += 1;
        WatchUi.requestUpdate();
        if (mStep < QUESTIONS) {
            later(method(:ask));
        } else {
            later(method(:finish));
        }
    }

    // Logs the answers and replaces the Morning view with the Summary.
    function finish() as Void {
        cancel();
        if (mDone) {
            return;
        }
        mDone = true;
        var session = mSession;
        if (session != null) {
            session.logMorning(Time.now().value(), mAnswers[0], mAnswers[1], mAnswers[2]);
        }
        WatchUi.switchToView(new SummaryView(mSummary), new SummaryDelegate(),
            WatchUi.SLIDE_LEFT);
    }

    function later(callback as Method() as Void) as Void {
        cancel();
        var t = new Timer.Timer();
        t.start(callback, STEP_DELAY_MS, false);
        mTimer = t;
    }

    function cancel() as Void {
        var t = mTimer;
        if (t != null) {
            t.stop();
            mTimer = null;
        }
    }
}

// Shown under the questions.
class MorningView extends WatchUi.View {
    var mFlow as MorningFlow;

    function initialize(flow as MorningFlow) {
        View.initialize();
        mFlow = flow;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var n = mFlow.step();
        if (mFlow.answered()) {
            $.lcDrawScreen(dc, ["Morning check-in", "Done"] as Array<String>);
        } else {
            $.lcDrawScreen(dc, ["Morning check-in", "Question " + (n + 1) + " / 3",
                "START: answer"] as Array<String>);
        }
    }
}

class MorningDelegate extends WatchUi.BehaviorDelegate {
    var mFlow as MorningFlow;

    function initialize(flow as MorningFlow) {
        BehaviorDelegate.initialize();
        mFlow = flow;
    }

    // START re-asks the current question (if one was dismissed without an answer).
    function onSelect() as Boolean {
        mFlow.ask();
        return true;
    }

    // Back is consumed: finish the questions first.
    function onBack() as Boolean {
        return true;
    }
}

class MorningAnswerDelegate extends WatchUi.ConfirmationDelegate {
    var mFlow as MorningFlow;

    function initialize(flow as MorningFlow) {
        ConfirmationDelegate.initialize();
        mFlow = flow;
    }

    function onResponse(response as WatchUi.Confirm) as Boolean {
        mFlow.answer(response == WatchUi.CONFIRM_YES);
        return true;
    }
}
