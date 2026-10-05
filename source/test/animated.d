// D transliteration of FLTK's test/animated.cxx.
// Build: rdmd buildsamples.d test animated
import fl;
import std.math : abs;

// These constants define the image dimensions and
// the number of frames of the animation
enum uint dim = 256;
enum uint frames = 48;

RGBImage[frames] img;
ubyte curframe;

void makeImages()
{
    for (uint i = 0; i < frames; i++)
    {
        enum size = dim * dim * 4;
        ubyte[] data = new ubyte[size];
        data[] = 0;

        // First a black box, 10x10 pixels in the top-left corner
        for (int x = 0; x < 10; x++)
            for (int y = 0; y < 10; y++)
                data[y * dim * 4 + x * 4 + 3] = 255;

        // A fading sphere
        ubyte alpha = 255;
        if (i < frames / 2)
            alpha = cast(ubyte)(255 * (i / cast(float) frames / 2));
        else
            alpha = cast(ubyte)(255 * (((frames / 2) - (i - frames / 2)) / (cast(float) frames / 2)));

        enum spherew = 60;
        enum spherex = (dim - spherew) / 2;
        enum maxdist = (spherew / 2) * (spherew / 2);
        for (int x = spherex; x < spherex + spherew; x++)
        {
            for (int y = 20; y < 20 + spherew; y++)
            {
                float distx = x - (spherex + cast(float) spherew / 2);
                float disty = y - (20 + cast(float) spherew / 2);
                float dist = distx * distx + disty * disty;

                if (dist > maxdist) continue;

                const float fill = dist / maxdist;
                const ubyte grey = cast(ubyte)(fill * 255);

                ubyte myalpha = alpha;
                if (fill > 0.9)
                    myalpha *= cast(ubyte)((1.0f - fill) * 10);

                data[y * dim * 4 + x * 4 + 0] = grey;
                data[y * dim * 4 + x * 4 + 1] = grey;
                data[y * dim * 4 + x * 4 + 2] = grey;
                data[y * dim * 4 + x * 4 + 3] = myalpha;
            }
        }

        // A moving blob
        const float pos = (i / cast(float) frames) * 2 - 0.5f;

        const int xoffset = cast(int)(pos * dim);
        const int yoffset = 2 * dim / 3;
        const int w = dim / 4;

        for (int x = -w; x < w; x++)
        {
            if (x + xoffset < 0 || x + xoffset >= cast(int) dim) continue;
            for (int y = yoffset - w; y < yoffset + w; y++)
            {
                const ubyte grey = cast(ubyte) abs(y - yoffset);
                data[y * dim * 4 + (x + xoffset) * 4 + 2] = grey;
                data[y * dim * 4 + (x + xoffset) * 4 + 3] = 127;
            }
        }

        img[i] = new RGBImage(data, dim, dim, 4);
    }
}

class MyWindow : DoubleWindow
{
    this(int x, int y, string lbl) { super(x, y, lbl); }

    override void draw()
    {
        super.draw();

        // Test both cx/cy offset and clipping. Both borders should have a
        // 5-pixel edge, and the upper-left black box should not be visible.
        pushClip(5, 5, w() - 5, h() - 5);
        img[curframe].draw(0, 0, dim, dim, 5, 5);
        popClip();
    }
}

MyWindow win;

void cb()
{
    win.redraw();
    fl.repeatTimeout(1.0 / 24, () { cb(); });
    curframe++;
    curframe %= frames;
}

void main()
{
    win = new MyWindow(256, 256, "Alpha rendering benchmark, watch CPU use");
    win.color(rgbColor(142, 0, 0));

    makeImages();

    win.end();
    win.show();

    fl.addTimeout(1.0 / 24, () { cb(); });

    fl.run();
}
