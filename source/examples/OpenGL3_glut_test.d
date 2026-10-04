// D transliteration of FLTK's examples/OpenGL3-glut-test.cxx
// (~/Repositories/fltk).
// Part of the samples/ contract -- see samples/README.md.
// Check: ./samples/build.sh OpenGL3-glut-test
//
// Tiny OpenGL v3 + glut demo program for FLTK.
//
// Uses the real `fl.opengl`/`fl.glew`/`fl.glu` bindings (`fl.glut`
// itself is re-exported from `fl`, see fl.package's own doc comment, so
// no separate import is needed for glut*/GLUT_* symbols).
import fl;
import std.stdio : stderr, writefln;
import std.conv : parse;
import std.string : fromStringz, strip;

// Globals
// Real programs don't use globals :-D
// Data would normally be read from files
GLfloat[9] vertices = [-1.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 0.0f];
GLfloat[9] colours = [1.0f, 0.0f, 0.0f,
    0.0f, 1.0f, 0.0f,
    0.0f, 0.0f, 1.0f];
GLfloat[9] vertices2 = [0.0f, 0.0f, 0.0f,
    0.0f, -1.0f, 0.0f,
    1.0f, 0.0f, 0.0f];

// two vertex array objects, one for each object drawn
uint[2] vertexArrayObjID;
// three vertex buffer objects in this example
uint[3] vertexBufferObjID;

void printShaderInfoLog(GLint shader)
{
    int infoLogLen = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &infoLogLen);
    if (infoLogLen > 0)
    {
        auto infoLog = new GLchar[infoLogLen];
        // error check for fail to allocate memory omitted
        glGetShaderInfoLog(shader, infoLogLen, null, infoLog.ptr);
        stderr.writefln("InfoLog:\n%s", infoLog);
    }
}

void init()
{
    // Would load objects from file here - but using globals in this example

    // Allocate Vertex Array Objects
    glGenVertexArrays(2, &vertexArrayObjID[0]);
    // Setup first Vertex Array Object
    glBindVertexArray(vertexArrayObjID[0]);
    glGenBuffers(2, vertexBufferObjID.ptr);

    // VBO for vertex data
    glBindBuffer(GL_ARRAY_BUFFER, vertexBufferObjID[0]);
    glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, vertices.ptr, GL_STATIC_DRAW);
    glVertexAttribPointer(cast(GLuint) 0, 3, GL_FLOAT, GL_FALSE, 0, null);
    glEnableVertexAttribArray(0);

    // VBO for colour data
    glBindBuffer(GL_ARRAY_BUFFER, vertexBufferObjID[1]);
    glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, colours.ptr, GL_STATIC_DRAW);
    glVertexAttribPointer(cast(GLuint) 1, 3, GL_FLOAT, GL_FALSE, 0, null);
    glEnableVertexAttribArray(1);

    // Setup second Vertex Array Object
    glBindVertexArray(vertexArrayObjID[1]);
    glGenBuffers(1, &vertexBufferObjID[2]);

    // VBO for vertex data
    glBindBuffer(GL_ARRAY_BUFFER, vertexBufferObjID[2]);
    glBufferData(GL_ARRAY_BUFFER, 9 * GLfloat.sizeof, vertices2.ptr, GL_STATIC_DRAW);
    glVertexAttribPointer(cast(GLuint) 0, 3, GL_FLOAT, GL_FALSE, 0, null);
    glEnableVertexAttribArray(0);

    glBindVertexArray(0);
}

version (OSX)
    enum shadingLangVers = "140";
else
    enum shadingLangVers = "130";

void initShaders()
{
    glClearColor(1.0, 1.0, 1.0, 0.0);

    GLuint v = glCreateShader(GL_VERTEX_SHADER);
    GLuint f = glCreateShader(GL_FRAGMENT_SHADER);

    // load shaders
    immutable string vv = "#version " ~ shadingLangVers ~ "\n"
        ~ "in  vec3 in_Position;"
        ~ "in  vec3 in_Color;"
        ~ "out vec3 ex_Color;"
        ~ "void main(void)"
        ~ "{"
        ~ "  ex_Color = in_Color;"
        ~ "  gl_Position = vec4(in_Position, 1.0);"
        ~ "}";

    immutable string ff = "#version " ~ shadingLangVers ~ "\n"
        ~ "precision highp float;"
        ~ "in  vec3 ex_Color;"
        ~ "out vec4 out_Color;"
        ~ "void main(void)"
        ~ "{"
        ~ "  out_Color = vec4(ex_Color,1.0);"
        ~ "}";

    auto vvz = vv.ptr;
    auto ffz = ff.ptr;
    glShaderSource(v, 1, &vvz, null);
    glShaderSource(f, 1, &ffz, null);

    GLint compiled;

    glCompileShader(v);
    glGetShaderiv(v, GL_COMPILE_STATUS, &compiled);
    if (!compiled)
    {
        stderr.writefln("Vertex shader not compiled.");
        printShaderInfoLog(v);
    }

    glCompileShader(f);
    glGetShaderiv(f, GL_COMPILE_STATUS, &compiled);
    if (!compiled)
    {
        stderr.writefln("Fragment shader not compiled.");
        printShaderInfoLog(f);
    }

    GLuint p = glCreateProgram();

    glAttachShader(p, v);
    glAttachShader(p, f);
    glBindAttribLocation(p, 0, "in_Position");
    glBindAttribLocation(p, 1, "in_Color");

    glLinkProgram(p);
    glGetProgramiv(p, GL_LINK_STATUS, &compiled);
    if (compiled != GL_TRUE)
    {
        GLint length;
        glGetProgramiv(p, GL_INFO_LOG_LENGTH, &length);
        auto infoLog = new GLchar[length];
        glGetProgramInfoLog(p, length, null, infoLog.ptr);
        stderr.writefln("Link log=%s", infoLog);
    }
    glUseProgram(p);
}

void display()
{
    // clear the screen
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glBindVertexArray(vertexArrayObjID[0]); // First VAO
    glDrawArrays(GL_TRIANGLES, 0, 3);       // draw first object

    glBindVertexArray(vertexArrayObjID[1]);         // select second VAO
    glVertexAttrib3f(cast(GLuint) 1, 1.0, 0.0, 0.0); // set constant color attribute
    glDrawArrays(GL_TRIANGLES, 0, 3);               // draw second object
}

bool fullscreen = false;

void main(string[] args)
{
    fl.useHighResGL(true);
    glutInit(args);
    glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGBA | modeOpengl3);
    glutInitWindowSize(400, 400);
    glutCreateWindow("Triangle Test");
    version (OSX)
    {
    }
    else
    {
        GLenum err = glewInit(); // defines pters to functions of OpenGL V 1.2 and above
        if (err != GLEW_OK)
            stderr.writefln("glewInit() failed returning %u", err); // fl.error() has no equivalent here
        stderr.writefln("Status: Using GLEW %s", fromStringz(cast(const(char)*) glewGetString(GLEW_VERSION)));
    }
    int glVersionMajor;
    const(char)* glv = cast(const(char)*) glGetString(GL_VERSION);
    {
        // Ported from FLTK's sscanf(glv, "%d", &glVersionMajor).
        auto s = fromStringz(glv).strip;
        try glVersionMajor = parse!int(s);
        catch (Exception) glVersionMajor = 0;
    }
    stderr.writefln("OpenGL version %s supported", fromStringz(glv));
    if (glVersionMajor < 3)
    {
        stderr.writefln("\nThis platform does not support OpenGL V3\n");
        // ensure that users see a message on Windows w/o console output:
        import std.format : format;

        alert(format("OpenGL version %s supported.\nThis platform does not support OpenGL V3!",
                fromStringz(glv)));
        return;
    }
    initShaders();
    init();
    glutDisplayFunc(&display);
    if (fullscreen)
        fl.firstWindow().fullscreen();
    glutMainLoop();
}
