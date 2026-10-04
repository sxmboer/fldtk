// D transliteration of FLTK's test/device.cxx (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh device
import fl;
import std.math : sqrt;
import std.stdio : File;
import std.format : format;

// pixmaps/porsche.xpm, transcribed verbatim from the FLTK file.
immutable string[] porscheXpm = [
    "64 64 4 1",
    " 	c #background",
    ".	c #000000000000",
    "X	c #ffd100",
    "o	c #FFFF00000000",
    "                                                                ",
    "                   ..........................                   ",
    "              .....................................             ",
    "        ............XXXXXXXXXXXXXXXXXXXXXXXX............        ",
    "        ......XXXXXXX...XX...XXXXXXXX...XXXXXXXXXX......        ",
    "        ..XXXXXXXXXX..X..XX..XXXX.XXXX..XXXXXXXXXXXXXX..        ",
    "        ..XXXXXXXXXX..X..XX..XXX..XXXX..X...XXXXXXXXXX..        ",
    "        ..XXXXXXXXXX..XXXXX..XX.....XX..XX.XXXXXXXXXXX..        ",
    "        ..XXXXXXXXX.....XXX..XXX..XXXX..X.XXXXXXXXXXXX..        ",
    "        ..XXXXXXXXXX..XXXXX..XXX..XXXX....XXXXXXXXXXXX..        ",
    "        ..XXXXXXXXXX..XXXXX..XXX..XXXX..X..XXXXXXXXXXX..        ",
    "        ..XXXXXXXXXX..XXXXX..XXX..X.XX..XX..XXXXXXXXXX..        ",
    "        ..XXXXXXXXX....XXX....XXX..XX....XX..XXXXXXXXX..        ",
    "        ..XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX..        ",
    "        ..XXXXXXXXX..........................XXXXXXXXX..        ",
    "        ..XXX.......XXXXXXXXXXX...................XXXX..        ",
    "        ......XX.XXX.XXX..XXXXX.........................        ",
    "        ..XXXXX.XXX.XXX.XXXX.XX.........................        ",
    "        ..XXXX.XXX.XX.......XXX.........................        ",
    "        ..XXXX.......XXXXXX..XX..ooooooooooooooooooooo..        ",
    "        ..X.....XXXXXXXXXXXXXXX..ooooooooooooooooooooo..        ",
    "        ..X...XXXXXXXXXXXXXXXXX..ooooooooooooooooooooo..        ",
    "        ..X..XXXXXXX.XX.XXXXXXX..ooooooooooooooooooooo..        ",
    "        ..XXXXX.XXX.XX.XXXXXXXX..ooooooooooooooooooooo..        ",
    "        ..XXXX.XXX.XX.XX................................        ",
    "        ..XXXX.X.........X....X.X.X.....................        ",
    "        ..XXXX...XXXXXXX.X..X...X.X.X.X.................        ",
    "        ..X....XXXXXXXXXX.X...X.X.X.....................        ",
    "        ..X...XXXXXXXXXX.XXXXXXXXXXXXXX.................        ",
    "        ..X..XXXXXX.XX.X.XXX...XXXXXXXX.................        ",
    "        ..XXXXX.XX.XX.XX.XX.....XXXXXXX.oooooooooooooo..        ",
    "        ..XXXX.XX.XX.XX..XX.X...XXXXX.X.oooooooooooooo..        ",
    "        ..XXXX.X.......X.XXXX...XXXX..X.oooooooooooooo..        ",
    "        ..X......XXXXXX..XXXX...XXXX..X.oooooooooooooo..        ",
    "        ..X...XXXXXXXXXX.XXX.....XXX.XX.oooooooooooooo..        ",
    "        ..X..XXXXXXXXXXX.X...........XX.oooooooooooooo..        ",
    "        .................X.X.........XX.................        ",
    "        .................X.X.XXXX....XX.XXXXXXXXXXXXXX..        ",
    "        .................XXX.XXXXX.X.XX.XXX.XX.XXXXXXX..        ",
    "         ................XXXX.XXX..X..X.XX.XX.XXX.XXX..         ",
    "         ................XXXXXXXX.XX.XX.X.XX.XXX.XXXX..         ",
    "         .................XXXXXX.XX.XX.X..........XXX..         ",
    "          ..oooooooooooooo.XXXXXXXXXX....XXXXXXXX..X..          ",
    "          ..ooooooooooooooo.XXXXXXXX....XXXXXXXXXXXX..          ",
    "           ..ooooooooooooooo........XXXXXXX.XX.XXXX..           ",
    "           ..oooooooooooooooooo..XXXXX.XXX.XX.XX.XX..           ",
    "            ..ooooooooooooooooo..XXXX.XXX.XX.XX.XX..            ",
    "            ..ooooooooooooooooo..XXX.XX........XXX..            ",
    "             ....................XXX....XXXXXX..X..             ",
    "              ...................XX...XXXXXXXXXXX.              ",
    "              ...................X...XXXXXXXXXXX..              ",
    "               ..................X..XXXX.XXXXXX..               ",
    "                .................XXX.XX.XX.XXX..                ",
    "                 ................XX.XX.XX.XXX..                 ",
    "                  ..ooooooooooo..XX.......XX..                  ",
    "                   ..oooooooooo..X...XXXX.X..                   ",
    "                    ..ooooooooo..X..XXXXXX..                    ",
    "                     ...ooooooo..X..XXXX...                     ",
    "                      ....ooooo..XXXXX....                      ",
    "                        ....ooo..XXX....                        ",
    "                          ....o..X....                          ",
    "                            ........                            ",
    "                              ....                              ",
    "                                                                "
];

// pixmaps/sorceress.xbm, transcribed verbatim from the FLTK file
// (see samples/test/bitmap.d, which transcribes the same FLTK file).
enum sorceressWidth = 75;
enum sorceressHeight = 75;
immutable ubyte[] sorceressBits = [
  0xfc, 0x7e, 0x40, 0x20, 0x90, 0x00, 0x07, 0x80, 0x23, 0x00, 0x00, 0xc6,
  0xc1, 0x41, 0x98, 0xb8, 0x01, 0x07, 0x66, 0x00, 0x15, 0x9f, 0x03, 0x47,
  0x8c, 0xc6, 0xdc, 0x7b, 0xcc, 0x00, 0xb0, 0x71, 0x0e, 0x4d, 0x06, 0x66,
  0x73, 0x8e, 0x8f, 0x01, 0x18, 0xc4, 0x39, 0x4b, 0x02, 0x23, 0x0c, 0x04,
  0x1e, 0x03, 0x0c, 0x08, 0xc7, 0xef, 0x08, 0x30, 0x06, 0x07, 0x1c, 0x02,
  0x06, 0x30, 0x18, 0xae, 0xc8, 0x98, 0x3f, 0x78, 0x20, 0x06, 0x02, 0x20,
  0x60, 0xa0, 0xc4, 0x1d, 0xc0, 0xff, 0x41, 0x04, 0xfa, 0x63, 0x80, 0xa1,
  0xa4, 0x3d, 0x00, 0x84, 0xbf, 0x04, 0x0f, 0x06, 0xfc, 0xa1, 0x34, 0x6b,
  0x01, 0x1c, 0xc9, 0x05, 0x06, 0xc7, 0x06, 0xbe, 0x11, 0x1e, 0x43, 0x30,
  0x91, 0x05, 0xc3, 0x61, 0x02, 0x30, 0x1b, 0x30, 0xcc, 0x20, 0x11, 0x00,
  0xc1, 0x3c, 0x03, 0x20, 0x0a, 0x00, 0xe8, 0x60, 0x21, 0x00, 0x61, 0x1b,
  0xc1, 0x63, 0x08, 0xf0, 0xc6, 0xc7, 0x21, 0x03, 0xf8, 0x08, 0xe1, 0xcf,
  0x0a, 0xfc, 0x4d, 0x99, 0x43, 0x07, 0x3c, 0x0c, 0xf1, 0x9f, 0x0b, 0xfc,
  0x5b, 0x81, 0x47, 0x02, 0x16, 0x04, 0x31, 0x1c, 0x0b, 0x1f, 0x17, 0x89,
  0x4d, 0x06, 0x1a, 0x04, 0x31, 0x38, 0x02, 0x07, 0x56, 0x89, 0x49, 0x04,
  0x0b, 0x04, 0xb1, 0x72, 0x82, 0xa1, 0x54, 0x9a, 0x49, 0x04, 0x1d, 0x66,
  0x50, 0xe7, 0xc2, 0xf0, 0x54, 0x9a, 0x58, 0x04, 0x0d, 0x62, 0xc1, 0x1f,
  0x44, 0xfc, 0x51, 0x90, 0x90, 0x04, 0x86, 0x63, 0xe0, 0x74, 0x04, 0xef,
  0x31, 0x1a, 0x91, 0x00, 0x02, 0xe2, 0xc1, 0xfd, 0x84, 0xf9, 0x30, 0x0a,
  0x91, 0x00, 0x82, 0xa9, 0xc0, 0xb9, 0x84, 0xf9, 0x31, 0x16, 0x81, 0x00,
  0x42, 0xa9, 0xdb, 0x7f, 0x0c, 0xff, 0x1c, 0x16, 0x11, 0x00, 0x02, 0x28,
  0x0b, 0x07, 0x08, 0x60, 0x1c, 0x02, 0x91, 0x00, 0x46, 0x29, 0x0e, 0x00,
  0x00, 0x00, 0x10, 0x16, 0x11, 0x02, 0x06, 0x29, 0x04, 0x00, 0x00, 0x00,
  0x10, 0x16, 0x91, 0x06, 0xa6, 0x2a, 0x04, 0x00, 0x00, 0x00, 0x18, 0x24,
  0x91, 0x04, 0x86, 0x2a, 0x04, 0x00, 0x00, 0x00, 0x18, 0x27, 0x93, 0x04,
  0x96, 0x4a, 0x04, 0x00, 0x00, 0x00, 0x04, 0x02, 0x91, 0x04, 0x86, 0x4a,
  0x0c, 0x00, 0x00, 0x00, 0x1e, 0x23, 0x93, 0x04, 0x56, 0x88, 0x08, 0x00,
  0x00, 0x00, 0x90, 0x21, 0x93, 0x04, 0x52, 0x0a, 0x09, 0x80, 0x01, 0x00,
  0xd0, 0x21, 0x95, 0x04, 0x57, 0x0a, 0x0f, 0x80, 0x27, 0x00, 0xd8, 0x20,
  0x9d, 0x04, 0x5d, 0x08, 0x1c, 0x80, 0x67, 0x00, 0xe4, 0x01, 0x85, 0x04,
  0x79, 0x8a, 0x3f, 0x00, 0x00, 0x00, 0xf4, 0x11, 0x85, 0x06, 0x39, 0x08,
  0x7d, 0x00, 0x00, 0x18, 0xb7, 0x10, 0x81, 0x03, 0x29, 0x12, 0xcb, 0x00,
  0x7e, 0x30, 0x28, 0x00, 0x85, 0x03, 0x29, 0x10, 0xbe, 0x81, 0xff, 0x27,
  0x0c, 0x10, 0x85, 0x03, 0x29, 0x32, 0xfa, 0xc1, 0xff, 0x27, 0x94, 0x11,
  0x85, 0x03, 0x28, 0x20, 0x6c, 0xe1, 0xff, 0x07, 0x0c, 0x01, 0x85, 0x01,
  0x28, 0x62, 0x5c, 0xe3, 0x8f, 0x03, 0x4e, 0x91, 0x80, 0x05, 0x39, 0x40,
  0xf4, 0xc2, 0xff, 0x00, 0x9f, 0x91, 0x84, 0x05, 0x31, 0xc6, 0xe8, 0x07,
  0x7f, 0x80, 0xcd, 0x00, 0xc4, 0x04, 0x31, 0x06, 0xc9, 0x0e, 0x00, 0xc0,
  0x48, 0x88, 0xe0, 0x04, 0x79, 0x04, 0xdb, 0x12, 0x00, 0x30, 0x0c, 0xc8,
  0xe4, 0x04, 0x6d, 0x06, 0xb6, 0x23, 0x00, 0x18, 0x1c, 0xc0, 0x84, 0x04,
  0x25, 0x0c, 0xff, 0xc2, 0x00, 0x4e, 0x06, 0xb0, 0x80, 0x04, 0x3f, 0x8a,
  0xb3, 0x83, 0xff, 0xc3, 0x03, 0x91, 0x84, 0x04, 0x2e, 0xd8, 0x0f, 0x3f,
  0x00, 0x00, 0x5f, 0x83, 0x84, 0x04, 0x2a, 0x70, 0xfd, 0x7f, 0x00, 0x00,
  0xc8, 0xc0, 0x84, 0x04, 0x4b, 0xe2, 0x2f, 0x01, 0x00, 0x08, 0x58, 0x60,
  0x80, 0x04, 0x5b, 0x82, 0xff, 0x01, 0x00, 0x08, 0xd0, 0xa0, 0x84, 0x04,
  0x72, 0x80, 0xe5, 0x00, 0x00, 0x08, 0xd2, 0x20, 0x44, 0x04, 0xca, 0x02,
  0xff, 0x00, 0x00, 0x08, 0xde, 0xa0, 0x44, 0x04, 0x82, 0x02, 0x6d, 0x00,
  0x00, 0x08, 0xf6, 0xb0, 0x40, 0x02, 0x82, 0x07, 0x3f, 0x00, 0x00, 0x08,
  0x44, 0x58, 0x44, 0x02, 0x93, 0x3f, 0x1f, 0x00, 0x00, 0x30, 0x88, 0x4f,
  0x44, 0x03, 0x83, 0x23, 0x3e, 0x00, 0x00, 0x00, 0x18, 0x60, 0xe0, 0x07,
  0xe3, 0x0f, 0xfe, 0x00, 0x00, 0x00, 0x70, 0x70, 0xe4, 0x07, 0xc7, 0x1b,
  0xfe, 0x01, 0x00, 0x00, 0xe0, 0x3c, 0xe4, 0x07, 0xc7, 0xe3, 0xfe, 0x1f,
  0x00, 0x00, 0xff, 0x1f, 0xfc, 0x07, 0xc7, 0x03, 0xf8, 0x33, 0x00, 0xc0,
  0xf0, 0x07, 0xff, 0x07, 0x87, 0x02, 0xfc, 0x43, 0x00, 0x60, 0xf0, 0xff,
  0xff, 0x07, 0x8f, 0x06, 0xbe, 0x87, 0x00, 0x30, 0xf8, 0xff, 0xff, 0x07,
  0x8f, 0x14, 0x9c, 0x8f, 0x00, 0x00, 0xfc, 0xff, 0xff, 0x07, 0x9f, 0x8d,
  0x8a, 0x0f, 0x00, 0x00, 0xfe, 0xff, 0xff, 0x07, 0xbf, 0x0b, 0x80, 0x1f,
  0x00, 0x00, 0xff, 0xff, 0xff, 0x07, 0x7f, 0x3a, 0x80, 0x3f, 0x00, 0x80,
  0xff, 0xff, 0xff, 0x07, 0xff, 0x20, 0xc0, 0x3f, 0x00, 0x80, 0xff, 0xff,
  0xff, 0x07, 0xff, 0x01, 0xe0, 0x7f, 0x00, 0xc0, 0xff, 0xff, 0xff, 0x07,
  0xff, 0x0f, 0xf8, 0xff, 0x40, 0xe0, 0xff, 0xff, 0xff, 0x07, 0xff, 0xff,
  0xff, 0xff, 0x40, 0xf0, 0xff, 0xff, 0xff, 0x07, 0xff, 0xff, 0xff, 0xff,
  0x41, 0xf0, 0xff, 0xff, 0xff, 0x07];

class MyWidget : Box
{
    override void draw()
    {
        super.draw();
        fl_color(red);
        fl_rectf(x() + 5, y() + 5, w() - 10, h() - 10);
        pushClip(x() + 6, y() + 6, w() - 12, h() - 12);
        fl_color(darkGreen);
        fl_rectf(x() + 5, y() + 5, w() - 10, h() - 10);
        popClip();
        fl_color(yellow);
        fl_rectf(x() + 7, y() + 7, w() - 14, h() - 14);
        fl_color(blue);

        fl_rect(x() + 8, y() + 8, w() - 16, h() - 16);
        pushClip(x() + 25, y() + 25, w() - 50, h() - 50);
        fl_color(black);
        fl_rect(x() + 24, y() + 24, w() - 48, h() - 48);
        fl_line(x() + 27, y() + 27, x() + w() - 27, y() + h() - 27);
        fl_line(x() + 27, y() + h() - 27, x() + w() - 27, y() + 27);
        popClip();
    }

    this(int x, int y)
    {
        super(x, y, 100, 100, "Clipping and rect(f):\nYellow rect.framed\nby B-Y-G-R rect. 1 p.\nthick. Your printer may \nrender very thin lines\nsurrounding \"X\"");
        alignment(alignTop);
        labelsize(10);
    }
}

class MyWidget2 : Box
{
    override void draw()
    {
        super.draw();
        int d;
        for (d = y() + 5; d < 48 + y(); d += 2)
            fl_xyline(x() + 5, d, x() + 48);

        pushClip(x() + 52, y() + 5, 45, 43);
        for (d = y() + 5; d < 150 + y(); d += 3)
            fl_line(x() + 52, d, x() + 92, d - 40);
        popClip();

        lineStyle(lineDash);
        fl_xyline(x() + 5, y() + 55, x() + 48);
        lineStyle(lineDot);
        fl_xyline(x() + 5, y() + 58, x() + 48);
        lineStyle(lineDashDot);
        fl_xyline(x() + 5, y() + 61, x() + 48);
        lineStyle(lineDashDotDot);
        fl_xyline(x() + 5, y() + 64, x() + 48);
        lineStyle(0, 0, [7, 3, 7, 2]);
        fl_xyline(x() + 5, y() + 67, x() + 48);

        lineStyle(0);

        fl_line(x() + 5, y() + 72, x() + 25, y() + 95);
        fl_line(x() + 8, y() + 72, x() + 28, y() + 95, x() + 31, y() + 72);

        fl_color(yellow);
        fl_polygon(x() + 11, y() + 72, x() + 27, y() + 91, x() + 29, y() + 72);
        fl_color(red);
        loop(x() + 11, y() + 72, x() + 27, y() + 91, x() + 29, y() + 72);

        fl_color(blue);
        lineStyle(lineSolid, 6);
        loop(x() + 31, y() + 12, x() + 47, y() + 31, x() + 49, y() + 12);
        lineStyle(0);

        fl_color(rgbColor(200, 0, 200));
        fl_polygon(x() + 35, y() + 72, x() + 33, y() + 95, x() + 48, y() + 95, x() + 43, y() + 72);
        fl_color(green);
        loop(x() + 35, y() + 72, x() + 33, y() + 95, x() + 48, y() + 95, x() + 43, y() + 72);

        fl_color(blue);
        fl_yxline(x() + 65, y() + 63, y() + 66);
        fl_color(green);
        fl_yxline(x() + 66, y() + 66, y() + 63);

        fl_color(blue);
        fl_rect(x() + 80, y() + 55, 5, 5);
        fl_color(yellow);
        fl_rectf(x() + 81, y() + 56, 3, 3);
        fl_color(black);
        point(x() + 82, y() + 57);

        fl_color(blue);
        fl_rect(x() + 56, y() + 79, 24, 17);
        fl_color(cyan);
        fl_rectf(x() + 57, y() + 80, 22, 15);
        fl_color(red);
        fl_arc(x() + 57, y() + 80, 22, 15, 40, 270);
        fl_color(yellow);
        fl_pie(x() + 58, y() + 81, 20, 13, 40, 270);

        lineStyle(0);

        fl_color(black);
        point(x() + 58, y() + 58);
        fl_color(red);
        fl_yxline(x() + 59, y() + 58, y() + 59);
        fl_color(green);
        fl_yxline(x() + 60, y() + 59, y() + 58);
        fl_color(black);
        fl_xyline(x() + 61, y() + 58, x() + 62);
        fl_color(red);
        fl_xyline(x() + 62, y() + 59, x() + 61);

        fl_color(green);
        fl_yxline(x() + 57, y() + 58, y() + 59, x() + 58);
        fl_color(blue);
        fl_xyline(x() + 58, y() + 60, x() + 56, y() + 58);
        fl_color(red);
        fl_xyline(x() + 58, y() + 61, x() + 56, y() + 63);
        fl_color(green);
        fl_yxline(x() + 57, y() + 63, y() + 62, x() + 58);

        fl_color(blue);
        fl_line(x() + 58, y() + 63, x() + 60, y() + 65);
        fl_color(black);
        fl_line(x() + 61, y() + 65, x() + 59, y() + 63);

        fl_color(black);
    }

    this(int x, int y)
    {
        super(x, y, 100, 100, "Integer primitives");
        labelsize(10);
        alignment(alignTop);
    }
}

class MyWidget3 : Box
{
    override void draw()
    {
        super.draw();
        double d;
        pushClip(x() + 5, y() + 5, 45, 43);
        for (d = y() + 5; d < 95 + y(); d += 1.63)
        {
            beginLine();
            vertex(x() + 5, d);
            vertex(x() + 48, d);
            endLine();
        }
        popClip();

        pushClip(x() + 52, y() + 5, 45, 43);
        for (d = y() + 5; d < 150 + y(); d += 2.3052)
        {
            beginLine();
            vertex(x() + 52, d);
            vertex(x() + 92, d - 43);
            endLine();
        }
        popClip();
    }

    this(int x, int y)
    {
        super(x, y, 100, 100, "Sub-pixel drawing of\nlines 1.63 points apart\nOn the screen you\ncan see aliasing, the\nprinter should render\nthem properly");
        labelsize(10);
        alignment(alignTop);
    }
}

class MyWidget4 : Box
{
    override void draw()
    {
        super.draw();
        pushMatrix();
        fl_translate(x(), y());
        fl_scale(.75, .75);

        lineStyle(lineSolid, 5);
        beginLine();
        vertex(10, 160);
        vertex(40, 160);
        vertex(40, 190);
        endLine();
        lineStyle(0);

        fl_color(red);
        lineStyle(lineSolid | capFlat | joinMiter, 5);
        beginLine();
        vertex(10, 150);
        vertex(50, 150);
        vertex(50, 190);
        endLine();
        lineStyle(0);

        fl_color(green);
        lineStyle(lineSolid | capRound | joinRound, 5);
        beginLine();
        vertex(10, 140);
        vertex(60, 140);
        vertex(60, 190);
        endLine();
        lineStyle(0);

        fl_color(blue);
        lineStyle(lineSolid | capSquare | joinBevel, 5);
        beginLine();
        vertex(10, 130);
        vertex(70, 130);
        vertex(70, 190);
        endLine();
        lineStyle(0);

        fl_color(black);
        lineStyle(lineDash, 5);
        beginLine();
        vertex(10, 120);
        vertex(80, 120);
        vertex(80, 190);
        endLine();
        lineStyle(0);

        fl_color(red);
        lineStyle(lineDash | capFlat, 5);
        beginLine();
        vertex(10, 110);
        vertex(90, 110);
        vertex(90, 190);
        endLine();
        lineStyle(0);

        fl_color(green);
        lineStyle(lineDash | capRound, 5);
        beginLine();
        vertex(10, 100);
        vertex(100, 100);
        vertex(100, 190);
        endLine();
        lineStyle(0);

        fl_color(blue);
        lineStyle(lineDash | capSquare, 5);
        beginLine();
        vertex(10, 90);
        vertex(110, 90);
        vertex(110, 190);
        endLine();
        lineStyle(0);

        fl_color(black);
        lineStyle(lineDot, 5);
        beginLine();
        vertex(10, 80);
        vertex(120, 80);
        vertex(120, 190);
        endLine();
        lineStyle(0);

        fl_color(red);
        lineStyle(lineDot | capFlat, 5);
        beginLine();
        vertex(10, 70);
        vertex(130, 70);
        vertex(130, 190);
        endLine();
        lineStyle(0);

        fl_color(green);
        lineStyle(lineDot | capRound, 5);
        beginLine();
        vertex(10, 60);
        vertex(140, 60);
        vertex(140, 190);
        endLine();
        lineStyle(0);

        fl_color(blue);
        lineStyle(lineDot | capSquare, 5);
        beginLine();
        vertex(10, 50);
        vertex(150, 50);
        vertex(150, 190);
        endLine();
        lineStyle(0);

        fl_color(black);
        lineStyle(lineDashDot | capRound | joinRound, 5);
        beginLine();
        vertex(10, 40);
        vertex(160, 40);
        vertex(160, 190);
        endLine();
        lineStyle(0);

        fl_color(red);
        lineStyle(lineDashDotDot | capSquare | joinBevel, 5);
        beginLine();
        vertex(10, 30);
        vertex(170, 30);
        vertex(170, 190);
        endLine();
        lineStyle(0);

        fl_color(green);
        lineStyle(lineDashDotDot | capRound | joinRound, 5);
        beginLine();
        vertex(10, 20);
        vertex(180, 20);
        vertex(180, 190);
        endLine();
        lineStyle(0);

        fl_color(blue);
        lineStyle(0, 5, cast(const(ubyte)[]) "\12\3\4\2\2\1");
        beginLine();
        vertex(10, 10);
        vertex(190, 10);
        vertex(190, 190);

        endLine();
        lineStyle(0);
        popMatrix();

        fl_color(black);
    }

    this(int x, int y)
    {
        super(x, y + 10, 150, 150, "Line styles");
        labelsize(10);
        alignment(alignTop);
    }
}

class MyWidget5 : Box
{
    override void draw()
    {
        super.draw();
        pushMatrix();

        fl_translate(x(), y());
        pushMatrix();
        multMatrix(1, 3, 0, 1, 0, -20);
        fl_color(green);
        beginPolygon();
        vertex(10, 10);
        vertex(100, -80);
        vertex(100, -190);
        endPolygon();

        fl_color(red);
        lineStyle(lineDashDot, 7);
        beginLoop();

        vertex(10, 10);
        vertex(100, -80);
        vertex(100, -190);
        endLoop();
        lineStyle(0);

        fl_color(blue);
        lineStyle(lineSolid, 3);
        beginLoop();
        circle(60, -50, 30);
        endLoop();
        lineStyle(0);

        popMatrix();
        fl_scale(1.8, 1);

        fl_color(yellow);
        beginPolygon();
        fl_arc(30, 90, 20, -45, 200);
        endPolygon();

        fl_color(black);
        lineStyle(lineDash, 3);
        beginLine();
        fl_arc(30, 90, 20, -45, 200);
        endLine();
        lineStyle(0);

        fl_translate(15, 0);
        fl_scale(1.5, 3);
        beginComplexPolygon();
        vertex(30, 70);
        fl_arc(45, 55, 10, 200, 90);
        fl_arc(55, 45, 8, -170, 20);
        vertex(60, 40);
        vertex(30, 20);
        vertex(40, 5);
        vertex(60, 25);
        curve(35, 30, 30, 53, 0, 35, 65, 65);
        fl_gap();
        vertex(50, 25);
        vertex(40, 10);
        vertex(35, 20);
        endComplexPolygon();

        popMatrix();
    }

    this(int x, int y)
    {
        super(x, y, 230, 250, "Complex (double) drawings:\nBlue ellipse may not be\ncorrectly transformed\ndue to non-orthogonal\ntransformation");
        labelsize(10);
        alignment(alignTop);
    }
}

ubyte[] image;
int width = 80;
int height = 80;

void makeImage()
{
    image = new ubyte[4 * width * height];
    size_t p = 0;
    for (int y = 0; y < height; y++)
    {
        double Y = cast(double) y / (height - 1);
        for (int x = 0; x < width; x++)
        {
            double X = cast(double) x / (width - 1);
            image[p++] = cast(ubyte)(255 * ((1 - X) * (1 - Y))); // red in upper-left
            image[p++] = cast(ubyte)(255 * ((1 - X) * Y));       // green in lower-left
            image[p++] = cast(ubyte)(255 * (X * Y));             // blue in lower-right
            X -= 0.5;
            Y -= 0.5;
            int alpha = cast(int)(350 * sqrt(X * X + Y * Y));
            image[p++] = alpha < 255 ? cast(ubyte) alpha : 255; // alpha transparency
            Y += 0.5;
        }
    }
}

void closeTmpWin(Widget win, Image data)
{
    // FLTK's own close_tmp_win() blindly reinterprets a plain
    // Fl_Image* as Fl_Shared_Image* to call release() -- undefined
    // behavior in strict C++, but harmless there since release() is a
    // plain Fl_Image virtual with no Fl_Shared_Image-specific state
    // involved, so the object's real vtable slot still runs correctly
    // regardless of the pointer's declared type. A D `cast(SharedImage)`
    // on an object that isn't actually one has no such loophole -- it's
    // a real dynamic downcast, and fails (returns null) for the
    // RGBImage/Image instances both call sites below actually pass,
    // crashing on `data.release()` on a null reference. Fixed by
    // declaring this parameter as the real static type instead of
    // replicating the cast.
    data.release();
    fl.deleteWidget(win);
}

Widget target;
string operation;

void copy(Widget, Object)
{
    if (operation == "ImageSurface")
    {
        ImageSurface rgbSurf;
        int W, H;
        bool decorated;
        if (target.asWindow() !is null && target.parent() is null)
        {
            W = target.asWindow().decoratedW();
            H = target.asWindow().decoratedH();
            decorated = true;
        }
        else
        {
            W = target.w();
            H = target.h();
            decorated = false;
        }
        rgbSurf = new ImageSurface(W, H, 1);
        SurfaceDevice.pushCurrent(rgbSurf);
        fl_color(yellow);
        fl_rectf(0, 0, W, H);
        if (decorated)
            rgbSurf.drawDecoratedWindow(target.asWindow());
        else
            rgbSurf.draw(target);
        Image img = rgbSurf.image();
        destroy(rgbSurf);
        SurfaceDevice.popCurrent();
        if (img !is null)
        {
            auto g2 = new Window(img.w() + 10, img.h() + 10, "ImageSurface");
            g2.color(yellow);
            auto b = new Box(Boxtype.noBox, 5, 5, img.w(), img.h(), null);
            b.image(img);
            g2.end();
            g2.callback((w) { closeTmpWin(w, img); });
            g2.show();
        }
        return;
    }

    if (operation == "CopySurface")
    {
        CopySurface copySurf;
        if (target.asWindow() !is null && target.parent() is null)
        {
            copySurf = new CopySurface(target.asWindow().decoratedW(), target.asWindow().decoratedH());
            SurfaceDevice.pushCurrent(copySurf);
            copySurf.drawDecoratedWindow(target.asWindow(), 0, 0);
        }
        else
        {
            copySurf = new CopySurface(target.w() + 10, target.h() + 20);
            SurfaceDevice.pushCurrent(copySurf);
            fl_color(yellow);
            fl_rectf(0, 0, copySurf.w(), copySurf.h());
            copySurf.draw(target, 5, 10);
        }
        destroy(copySurf);
        SurfaceDevice.popCurrent();
    }

    if (operation == "PdfFileSurface")
    {
        // fl.pdf_file_surface doesn't exist yet -- PORTING.md's own
        // FL/Fl_PDF_File_Surface.H row marks this Deferred (Pango):
        // FLTK's own implementation is unconditionally gated on Pango
        // on Linux too, the same project-wide deferred decision (see
        // CLAUDE.md's "Deferred: external-library-backed features"),
        // not a fresh gap this sample can just port around.
        message("PDF output isn't ported yet (see PORTING.md's\n"
            ~ "FL/Fl_PDF_File_Surface.H row -- deferred pending the\n"
            ~ "project-wide Pango decision).");
        return;
    }

    if (operation == "Printer" || operation == "PostscriptFileDevice")
    {
        PagedDevice p;
        int err;
        string errMessage;
        if (operation == "Printer")
        {
            auto printer = new Printer();
            err = printer.beginJob(1, errMessage);
            p = printer;
        }
        else
        {
            auto ps = new PostscriptFileDevice();
            // FLTK's Fl_PostScript_File_Device::start_job() is a
            // pure FLTK-1.3.x-compat synonym for begin_job() -- this
            // port only kept the real name (see fl.postscript's own
            // doc comment), matching the default pagecount/format/
            // layout FLTK's own start_job() gives it.
            err = ps.beginJob(1, a4, portrait);
            p = ps;
        }
        if (!err)
        {
            p.beginPage();
            Window win = target.asWindow();
            int targetW = win !is null ? win.decoratedW() : target.w();
            int targetH = win !is null ? win.decoratedH() : target.h();
            int w, h;
            p.printableRect(w, h);
            float s = 1, sAux = 1;
            if (targetW > w) sAux = cast(float) w / targetW;
            if (targetH > h) s = cast(float) h / targetH;
            if (sAux < s) s = sAux;
            p.scale(s);
            p.printableRect(w, h);
            p.origin(w / 2, h / 2);
            if (win !is null) p.drawDecoratedWindow(win, -targetW / 2, -targetH / 2);
            else p.draw(target, -targetW / 2, -targetH / 2);
            p.endPage();
            p.endJob();
        }
        else if (err > 1 && errMessage !is null)
        {
            alert(errMessage);
        }
        destroy(p);
    }

    if (operation == "SvgFileSurface")
    {
        auto fnfc = new NativeFileChooser();
        fnfc.title("Save a .svg file");
        fnfc.type(BrowseType.browseSaveFile);
        fnfc.filter("SVG\t*.svg\n");
        fnfc.options(saveasConfirm | useFilterExt);
        if (!fnfc.show())
        {
            // fl.fopen() (Fl::fopen()'s UTF-8-aware wrapper) isn't
            // ported; std.stdio.File is this port's own established
            // substitute for a raw C FILE* everywhere else it comes up
            // (see fl.nanosvg/fl.svg_image's own doc comments) --
            // File() throws rather than returning null on failure, so
            // the open-failed branch becomes a catch instead of an
            // `if`.
            File svg;
            try svg = File(fnfc.filename(), "w");
            catch (Exception) svg = File.init;
            if (svg.isOpen)
            {
                int ww, wh;
                if (target.asWindow() !is null)
                {
                    ww = target.asWindow().decoratedW();
                    wh = target.asWindow().decoratedH();
                }
                else
                {
                    ww = target.w();
                    wh = target.h();
                }
                auto surface = new SvgFileSurface(ww, wh, svg);
                if (surface.file().isOpen)
                {
                    if (target.asWindow() !is null) surface.drawDecoratedWindow(target.asWindow());
                    else surface.draw(target);
                    if (surface.close()) message(format("Error while writing to SVG file %s", fnfc.filename()));
                }
            }
        }
    }

    if (operation == "captureWindow()")
    {
        Window win = target.asWindow() !is null ? target.asWindow() : target.window();
        int X = target.asWindow() !is null ? 0 : target.x();
        int Y = target.asWindow() !is null ? 0 : target.y();
        RGBImage img = captureWindow(win, X, Y, target.w(), target.h());
        if (img !is null)
        {
            auto g2 = new Window(img.w() + 10, img.h() + 10, "captureWindow()");
            g2.color(yellow);
            auto b = new Box(Boxtype.noBox, 5, 5, img.w(), img.h(), null);
            b.image(img);
            g2.end();
            g2.callback((w) { closeTmpWin(w, img); });
            g2.show();
        }
    }

    if (operation == "ImageSurface.mask()")
    {
        auto surf = new ImageSurface(target.w(), target.h(), 1);
        SurfaceDevice.pushCurrent(surf);
        fl_color(black);
        fl_rectf(0, 0, target.w(), target.h());
        fl_color(white);
        fl_pie(0, 0, target.w(), target.h(), 0, 360);
        if (target.topWindow() is target)
        {
            fl_color(black);
            int mini = cast(int)((target.w() < target.h() ? target.w() : target.h()) * 0.66);
            fl_pie(target.w() / 2 - mini / 2, target.h() / 2 - mini / 2, mini, mini, 0, 360);
            fl_color(white);
            fl_font(timesBold, 120);
            int dx, dy, l, h;
            textExtents("FLTK", dx, dy, l, h);
            fl_draw("FLTK", target.w() / 2 - l / 2, target.h() / 2 + h / 2);
        }
        RGBImage mask = surf.image();
        fl_color(yellow);
        fl_rectf(0, 0, target.w(), target.h());
        SurfaceDevice.popCurrent();
        surf.mask(mask);
        destroy(mask);
        SurfaceDevice.pushCurrent(surf);
        surf.draw(target, 0, 0);
        mask = surf.image();
        SurfaceDevice.popCurrent();
        destroy(surf);
        auto win = new Window(mask.w(), mask.h(), operation);
        auto box = new Box(0, 0, mask.w(), mask.h());
        box.bindImage(mask);
        win.end();
        win.show();
    }
}

class MyButton : Button
{
    override void draw()
    {
        if (type() == hiddenButton) return;
        Color col = value() ? selectionColor() : color();
        drawBox(value() ? (downBox() ? downBox() : fl_down(box())) : box(), col);
        fl_color(white);
        lineStyle(lineSolid, 5);
        fl_line(x() + 15, y() + 10, x() + w() - 15, y() + h() - 23);
        fl_line(x() + w() - 15, y() + 10, x() + 15, y() + h() - 23);
        lineStyle(0);
        drawLabel();
    }

    this(int x, int y, int w, int h, string label = null) { super(x, y, w, h, label); }
}

void targetCb(Widget wid, Widget data)
{
    target = data;
}

void operationCb(Widget wid)
{
    operation = wid.label();
}

void main()
{
    auto w2 = new Window(500, 568, "Graphics test");

    auto c2 = new FlGroup(3, 56, 494, 514);

    new MyWidget(10, 140 + 16);
    new MyWidget2(110, 80 + 16);
    new MyWidget3(220, 140 + 16);
    new MyWidget4(330, 70 + 16);
    new MyWidget5(140, 270 + 16);

    makeImage();
    auto rgb = new RGBImage(image, width, height, 4);
    auto bRgb = new MyButton(10, 245 + 16, 100, 100, "RGB with alpha");
    bRgb.image(rgb);

    auto bPixmap = new MyButton(10, 345 + 16, 100, 100, "Pixmap");
    auto pixmap = new Pixmap(porscheXpm);
    bPixmap.image(pixmap);

    auto bBitmap = new MyButton(10, 445 + 16, 100, 100, "Bitmap");
    bBitmap.labelcolor(green);
    bBitmap.image(new Bitmap(sorceressBits, sorceressWidth, sorceressHeight));

    new FlClock(360, 230 + 16, 120, 120);
    auto ret = new ReturnButton(360, 360 + 16, 120, 30, "Return");
    ret.deactivate();
    auto but1 = new Button(360, 390 + 16, 30, 30, "@->|");
    but1.labelcolor(dark3);
    auto but2 = new Button(390, 390 + 16, 30, 30, "@UpArrow");
    but2.labelcolor(dark3);
    auto but3 = new Button(420, 390 + 16, 30, 30, "@DnArrow");
    but3.labelcolor(dark3);
    auto but4 = new Button(450, 390 + 16, 30, 30, "@+");
    but4.labelcolor(dark3);
    auto but5 = new Button(360, 425 + 16, 120, 30, "Hello, World");
    but5.labelfont(bold | italic);
    but5.labeltype(Labeltype.shadowLabel);
    but5.box(Boxtype.roundUpBox);

    auto but6 = new Button(360, 460 + 16, 120, 30, "Plastic");
    but6.box(Boxtype.plasticUpBox);

    FlGroup group;
    {
        auto o = new FlGroup(360, 495 + 16, 120, 40);
        group = o;
        o.box(Boxtype.upBox);
        {
            auto inner = new FlGroup(365, 500 + 16, 110, 30);
            inner.box(Boxtype.thinUpFrame);
            {
                auto rad = new RoundButton(365, 500 + 16, 40, 30, "rad");
                rad.value(true);
            }
            {
                auto check = new CheckButton(410, 500 + 16, 60, 30, "check");
                check.value(true);
            }
            inner.end();
        }
        o.end();
        o.deactivate();
    }
    auto tx = new Box(120, 492 + 16, 230, 50, "Background is not printed because\nencapsulating group, which we are\n printing, has not set the box type");
    tx.box(Boxtype.shadowBox);
    tx.labelsize(12);

    tx.hide();

    c2.end();

    RadioRoundButton rb;
    auto w3 = new Window(2, 5, w2.w() - 10, 73);
    w3.box(Boxtype.downBox);
    auto g1 = new FlGroup(0, 0, w3.w(), w3.h());
    rb = new RadioRoundButton(5, 4, 150, 12, "ImageSurface");
    rb.set();
    rb.callback((w) { operationCb(w); });
    operation = rb.label();
    rb.labelsize(12);
    rb = new RadioRoundButton(170, 4, 150, 12, "CopySurface");
    rb.callback((w) { operationCb(w); });
    rb.labelsize(12);
    rb = new RadioRoundButton(5, 17, 150, 12, "Printer");
    rb.callback((w) { operationCb(w); });
    rb.labelsize(12);
    rb = new RadioRoundButton(170, 17, 150, 12, "PostscriptFileDevice");
    rb.callback((w) { operationCb(w); });
    rb.labelsize(12);
    rb = new RadioRoundButton(5, 30, 150, 12, "PdfFileSurface");
    rb.callback((w) { operationCb(w); });
    rb.labelsize(12);
    rb = new RadioRoundButton(170, 30, 150, 12, "SvgFileSurface");
    rb.callback((w) { operationCb(w); });
    rb.labelsize(12);
    rb = new RadioRoundButton(5, 43, 150, 12, "captureWindow()");
    rb.callback((w) { operationCb(w); });
    rb.labelsize(12);
    rb = new RadioRoundButton(170, 43, 150, 12, "ImageSurface.mask()");
    rb.callback((w) { operationCb(w); });
    rb.labelsize(12);
    g1.end();

    auto g2 = new FlGroup(0, 0, w3.w(), w3.h());
    auto box = new Box(Boxtype.borderBox, 4, 55, 340, 16, null);
    box.color(light3);
    rb = new RadioRoundButton(5, 57, 140, 12, "Decorated window");
    rb.labelsize(12);
    rb.set();
    rb.callback((w) { targetCb(w, w2); });
    target = w2;
    rb = new RadioRoundButton(160, 57, 100, 12, "Sub-window");
    rb.labelsize(12);
    rb.callback((w) { targetCb(w, w3); });
    rb = new RadioRoundButton(275, 57, 60, 12, "Group");
    rb.labelsize(12);
    rb.callback((w) { targetCb(w, group); });
    g2.end();
    auto b4 = new Button(380, (w3.h() - 25) / 2, 100, 25, "GO");
    b4.callback((w) { copy(w, null); });
    w3.end();

    w2.end();
    auto rgbaIcon = new RGBImage(pixmap);
    Window.defaultIcon(rgbaIcon);
    destroy(rgbaIcon);
    w2.show();

    fl.run();
}
