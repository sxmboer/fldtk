// D transliteration of FLTK's examples/OpenGL3test.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh OpenGL3test
//
// Tiny OpenGL v3 demo program for FLTK.
//
// Uses the real `fl.opengl`/`fl.glew` bindings (see `fl.glew`'s own doc
// comment for why modern GL functions need GLEW rather than a plain
// fl.opengl extern(C) declaration).
import fl;
import std.stdio : stderr, writefln;
import std.string : format, fromStringz, strip;
import std.conv : parse;

void addOutput(string text);

// Parses one leading base-10 integer off the front of s, consuming it (and
// any leading whitespace) -- a small stand-in for sscanf's "%d", matching
// its "stop at the first non-digit" behavior. Returns 0 and leaves s
// unconsumed on parse failure.
private int parseLeadingInt(ref string s)
{
    import std.ascii : isDigit;

    s = s.strip;
    size_t i = 0;
    if (i < s.length && (s[i] == '-' || s[i] == '+')) i++;
    size_t digitsStart = i;
    while (i < s.length && isDigit(s[i])) i++;
    if (i == digitsStart) return 0;
    auto digits = s[0 .. i];
    int val = parse!int(digits);
    s = s[i .. $];
    return val;
}

class SimpleGl3Window : GlWindow
{
    private GLuint shaderProgram;
    private GLuint vertexArrayObject;
    private GLuint vertexBuffer;
    private GLint positionUniform;
    private GLint colourAttribute;
    private GLint positionAttribute;
    private int glVersionMajor;

    this(int x, int y, int w, int h)
    {
        super(x, y, w, h);
        mode(modeRgb8 | modeDouble | modeOpengl3);
        shaderProgram = 0;
        glVersionMajor = 0;
    }

    override void draw()
    {
        if (glVersionMajor >= 3 && !shaderProgram)
        {
            int mSlv, mslv; // major and minor version numbers of the shading language
            {
                // Ported from FLTK's sscanf(..., "%d.%d", &mSlv, &mslv).
                string s = cast(string) fromStringz(cast(const(char)*) glGetString(GL_SHADING_LANGUAGE_VERSION));
                mSlv = parseLeadingInt(s);
                if (s.length > 0 && s[0] == '.') s = s[1 .. $];
                mslv = parseLeadingInt(s);
            }
            addOutput(format("Shading Language Version=%d.%d\n", mSlv, mslv));

            immutable string vssFormat = "#version %d%d\n"
                ~ "uniform vec2 p;"
                ~ "in vec4 position;"
                ~ "in vec4 colour;"
                ~ "out vec4 colourV;"
                ~ "void main (void)"
                ~ "{"
                ~ "colourV = colour;"
                ~ "gl_Position = vec4(p, 0.0, 0.0) + position;"
                ~ "}";
            string vss = format(vssFormat, mSlv, mslv);

            immutable string fssFormat = "#version %d%d\n"
                ~ "in vec4 colourV;"
                ~ "out vec4 fragColour;"
                ~ "void main(void)"
                ~ "{"
                ~ "fragColour = colourV;"
                ~ "}";
            string fss = format(fssFormat, mSlv, mslv);

            GLint err;
            GLchar[1000] clog;
            GLsizei length;
            GLuint vs = glCreateShader(GL_VERTEX_SHADER);
            auto vssz = vss.ptr;
            glShaderSource(vs, 1, &vssz, null);
            glCompileShader(vs);
            glGetShaderiv(vs, GL_COMPILE_STATUS, &err);
            if (err != GL_TRUE)
            {
                glGetShaderInfoLog(vs, clog.length, &length, clog.ptr);
                addOutput(format("vs ShaderInfoLog=%s\n", clog));
            }
            GLuint fs = glCreateShader(GL_FRAGMENT_SHADER);
            auto fssz = fss.ptr;
            glShaderSource(fs, 1, &fssz, null);
            glCompileShader(fs);
            glGetShaderiv(fs, GL_COMPILE_STATUS, &err);
            if (err != GL_TRUE)
            {
                glGetShaderInfoLog(fs, clog.length, &length, clog.ptr);
                addOutput(format("fs ShaderInfoLog=%s\n", clog));
            }
            // Attach the shaders
            shaderProgram = glCreateProgram();
            glAttachShader(shaderProgram, vs);
            glAttachShader(shaderProgram, fs);
            glBindFragDataLocation(shaderProgram, 0, "fragColour");
            glLinkProgram(shaderProgram);
            glGetProgramiv(shaderProgram, GL_LINK_STATUS, &err);
            if (err != GL_TRUE)
            {
                glGetProgramInfoLog(shaderProgram, clog.length, &length, clog.ptr);
                addOutput(format("link log=%s\n", clog));
            }
            // Get pointers to uniforms and attributes
            positionUniform = glGetUniformLocation(shaderProgram, "p");
            colourAttribute = glGetAttribLocation(shaderProgram, "colour");
            positionAttribute = glGetAttribLocation(shaderProgram, "position");
            glDeleteShader(vs);
            glDeleteShader(fs);
            // Upload vertices (1st four values in a row) and colours (following four values)
            GLfloat[32] vertexData = [
                -0.5, -0.5, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0,
                -0.5, 0.5, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0,
                0.5, 0.5, 0.0, 1.0, 0.0, 0.0, 1.0, 1.0,
                0.5, -0.5, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0,
            ];
            glGenVertexArrays(1, &vertexArrayObject);
            glBindVertexArray(vertexArrayObject);

            glGenBuffers(1, &vertexBuffer);
            glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
            glBufferData(GL_ARRAY_BUFFER, 4 * 8 * GLfloat.sizeof, vertexData.ptr, GL_STATIC_DRAW);

            glEnableVertexAttribArray(cast(GLuint) positionAttribute);
            glEnableVertexAttribArray(cast(GLuint) colourAttribute);
            glVertexAttribPointer(cast(GLuint) positionAttribute, 4, GL_FLOAT, GL_FALSE, 8 * GLfloat.sizeof, null);
            glVertexAttribPointer(cast(GLuint) colourAttribute, 4, GL_FLOAT, GL_FALSE, 8 * GLfloat.sizeof,
                    cast(void*)(4 * GLfloat.sizeof));
            glUseProgram(shaderProgram);
        }
        else if (!valid())
        {
            glViewport(0, 0, pixelW(), pixelH());
        }
        glClearColor(0.08f, 0.8f, 0.8f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
        if (shaderProgram)
        {
            GLfloat[2] p = [0, 0];
            glUniform2fv(positionUniform, 1, p.ptr);
            glDrawArrays(GL_TRIANGLE_FAN, 0, 4);
        }
        super.draw(); // Draw FLTK child widgets.
    }

    override int handle(Event event)
    {
        static bool first = true;
        if (first && event == Event.show && shown())
        {
            first = false;
            makeCurrent();
            GLenum err = glewInit(); // defines pters to functions of OpenGL V 1.2 and above
            if (err)
                stderr.writefln("glewInit() failed returning %u", err); // fl.warning() has no equivalent here
            else
                addOutput(format("Using GLEW %s\n", fromStringz(cast(const(char)*) glewGetString(GLEW_VERSION))));
            const(ubyte)* glv = glGetString(GL_VERSION);
            addOutput(format("GL_VERSION=%s\n", fromStringz(cast(const(char)*) glv)));
            {
                // Ported from FLTK's sscanf((const char*)glv, "%d",
                // &glVersionMajor).
                string s = cast(string) fromStringz(cast(const(char)*) glv);
                glVersionMajor = parseLeadingInt(s);
            }
            if (glVersionMajor < 3)
            {
                addOutput("\nThis platform does not support OpenGL V3 :\n"
                        ~ "FLTK widgets will appear but the programmed "
                        ~ "rendering pipeline will not run.\n");
                mode(mode() & ~modeOpengl3);
            }
            redraw();
        }

        int retval = super.handle(event);
        if (retval) return retval;

        if (event == Event.push && glVersionMajor >= 3)
        {
            static float factor = 1.1f;
            GLfloat[4] data;
            glGetBufferSubData(GL_ARRAY_BUFFER, 0, 4 * GLfloat.sizeof, data.ptr);
            if (data[0] < -0.88 || data[0] > -0.5) factor = 1 / factor;
            data[0] *= factor;
            glBufferSubData(GL_ARRAY_BUFFER, 0, 4 * GLfloat.sizeof, data.ptr);
            glGetBufferSubData(GL_ARRAY_BUFFER, 24 * GLfloat.sizeof, 4 * GLfloat.sizeof, data.ptr);
            data[0] *= factor;
            glBufferSubData(GL_ARRAY_BUFFER, 24 * GLfloat.sizeof, 4 * GLfloat.sizeof, data.ptr);
            redraw();
            addOutput(format("push  GlWindow.pixelsPerUnit()=%.1f\n", pixelsPerUnit()));
            return 1;
        }
        return retval;
    }

    void reset()
    {
        shaderProgram = 0;
        gl_texture_reset();
    }
}

void toggleDouble(Widget wid, SimpleGl3Window glwin)
{
    static bool doublebuff = true;
    doublebuff = !doublebuff;
    int flags = glwin.mode();
    if (doublebuff) flags |= modeDouble; else flags &= ~modeDouble;
    glwin.reset();
    glwin.hide();
    glwin.mode(flags);
    glwin.show();
}

TextDisplay output; // shared between outputWin() and addOutput()

void outputWin(SimpleGl3Window gl)
{
    output = new TextDisplay(300, 0, 500, 280);
    auto lb = new LightButton(300, 280, 500, 20, "Double-Buffered");
    lb.callback((w) { toggleDouble(w, gl); });
    lb.value(true);
    output.buffer(new TextBuffer());
}

void addOutput(string text)
{
    output.buffer().append(text);
    output.scroll(10000, 0);
    output.redraw();
}

void buttonCb(Widget widget)
{
    addOutput(format("run %s callback\n", widget.label()));
}

void addWidgets(GlWindow g)
{
    fl.setColor(freeColor, 255, 255, 255, 140); // partially transparent white
    g.begin();
    // Create here widgets to go above the GL3 scene
    auto b = new Button(0, 0, 60, 30, "button");
    b.color(freeColor);
    b.box(Boxtype.downBox);
    b.callback((w) { buttonCb(w); });
    auto b2 = new Button(0, 170, 60, 30, "button2");
    b2.color(freeColor);
    b2.box(Boxtype.borderBox);
    b2.callback((w) { buttonCb(w); });
    g.end();
}

void main(string[] args)
{
    fl.useHighResGL(true);
    auto topwin = new Window(800, 300);
    auto win = new SimpleGl3Window(0, 0, 300, 300);
    win.end();
    outputWin(win);
    addWidgets(win);
    topwin.end();
    topwin.resizable(win);
    topwin.label("Click GL panel to reshape");
    topwin.show();
    fl.run();
}
