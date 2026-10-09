import Toybox.Graphics;
import Toybox.Lang;

// Small drawing helpers shared by the screens. No layouts: every screen is a few
// centred lines of text.

// Splits s at each "\n".
function lcSplitLines(s as String) as Array<String> {
    var out = [] as Array<String>;
    var rest = s;
    var at = rest.find("\n");
    while (at != null) {
        var cut = at as Number;
        out.add(rest.substring(0, cut) as String);
        rest = rest.substring(cut + 1, rest.length()) as String;
        at = rest.find("\n");
    }
    out.add(rest);
    return out;
}

// Draws lines centred horizontally, the block centred vertically, in the largest of
// SMALL / TINY / XTINY whose total height fits in 3/4 of the screen. Does not clear.
function lcDrawLines(dc as Graphics.Dc, lines as Array<String>, color as Graphics.ColorType) as Void {
    var n = lines.size();
    if (n == 0) {
        return;
    }
    var fonts = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY]
        as Array<Graphics.FontDefinition>;
    var font = Graphics.FONT_XTINY;
    var limit = (dc.getHeight() * 3) / 4;
    for (var k = 0; k < fonts.size(); k++) {
        if (n * dc.getFontHeight(fonts[k]) <= limit) {
            font = fonts[k];
            break;
        }
    }
    var h = dc.getFontHeight(font);
    var y = (dc.getHeight() - n * h) / 2;
    var x = dc.getWidth() / 2;
    dc.setColor(color, Graphics.COLOR_TRANSPARENT);
    for (var k = 0; k < n; k++) {
        dc.drawText(x, y + k * h, font, lines[k], Graphics.TEXT_JUSTIFY_CENTER);
    }
}

// Clears the screen to black, then draws lines in white.
function lcDrawScreen(dc as Graphics.Dc, lines as Array<String>) as Void {
    dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
    dc.clear();
    lcDrawLines(dc, lines, Graphics.COLOR_WHITE);
}
