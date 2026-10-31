// fldtk test program: text in GL windows, and rotated text.
// Build: rdmd buildsamples.d test gl_text
//
// The left panel draws a label at 0, 30, 90 and 180 degrees about a red
// dot through the window's own graphics driver; the right panel is a GL
// window with gl_draw() text and the same rotated labels drawn over the
// GL scene. "Bitmap fonts in GL" switches GL text from textures to the
// platform's bitmap fonts (glXUseXFont() on X11, wglUseFontBitmapsW() on
// Windows). Bitmap fonts on X11 cover only Latin-1, so the Greek line
// goes missing, and bitmap text cannot turn, so the GL panel's labels
// are drawn level. Wayland has no bitmap fonts for GL; there the check
// button unticks itself.
import fl;
import fl.opengl;
import std.conv : to;
import std.stdio : writeln;

CheckButton bitmapFonts;

class TextGl : GlWindow
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    override void draw()
    {
        if (!valid())
        {
            valid(1);
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
            glOrtho(0, w(), 0, h(), -1, 1);
        }
        glClearColor(0.05f, 0.1f, 0.3f, 1);
        glClear(GL_COLOR_BUFFER_BIT);

        gl_font(helvetica, 16);
        reportPath();
        gl_color(yellow);
        gl_draw("Plain ASCII text", 20, h() - 30);
        gl_draw("Latin-1: café, Größe, ½", 20, h() - 55);
        gl_draw("Greek: αβγ", 20, h() - 80);
        gl_font(helveticaBold, 24);
        gl_draw("Bold 24 point", 20, h() - 115);

        super.draw(); // the widgets over the scene
    }

    // Prints the text path when it changes, and keeps the check button
    // in step with it (it unticks itself where bitmap fonts are missing).
    private void reportPath()
    {
        static int last = -1;
        bool textures = drawGlTextWithTextures();
        if (last != textures)
        {
            last = textures;
            writeln("GL text uses ", textures ? "textures" : "bitmap fonts");
        }
        if (bitmapFonts.value() == textures) bitmapFonts.value(!textures);
    }
}

/// Draws a label at four angles about the centre of the widget, through
/// whatever graphics driver is current: the window's own in a plain
/// window, the GL driver inside a GlWindow.
class RotatedLabels : Widget
{
    this(int x, int y, int w, int h) { super(x, y, w, h); }

    override void draw()
    {
        int cx = x() + w() / 2, cy = y() + h() / 2;
        fl_font(helvetica, 18);
        fl_color(white);
        foreach (angle; [0, 30, 90, 180])
            fl_draw(angle, "  rotated " ~ angle.to!string, cx, cy);
        fl_color(red);
        fl_pie(cx - 3, cy - 3, 6, 6, 0, 360);
    }
}

void main(string[] args)
{
    auto win = new Window(860, 510, "GL text and rotated text");

    auto plain = new Box(10, 10, 330, 440, "plain window");
    plain.box(Boxtype.downBox);
    plain.color(darkBlue);
    plain.labelcolor(white);
    plain.alignment(alignTop | alignInside);
    new RotatedLabels(20, 160, 310, 270);

    auto gl = new TextGl(350, 10, 500, 440);
    gl.begin(); // a GlWindow ends itself, as it usually has no children
    new RotatedLabels(10, 160, 480, 270);
    gl.end();

    bitmapFonts = new CheckButton(350, 465, 250, 30, "Bitmap fonts in GL");
    bitmapFonts.callback((w) {
        drawGlTextWithTextures(!bitmapFonts.value());
        gl.redraw();
    });

    win.end();
    win.show(args);
    run();
}
