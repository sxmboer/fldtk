// D transliteration of FLTK's test/CubeView.cxx + test/CubeView.h.

module CubeView;

import fl;

class CubeView : GlWindow
{
    // This value determines the scaling factor used to draw the cube.
    double size = 10.0;

    private double vAng = 0.0, hAng = 0.0;
    private double xshift = 0.0, yshift = 0.0;

    private float[3] boxv0, boxv1, boxv2, boxv3, boxv4, boxv5, boxv6, boxv7;

    this(int x, int y, int w, int h, string l = null)
    {
        super(x, y, w, h, l);

        // The cube definition. These are the vertices of a unit cube
        // centered on the origin.
        boxv0 = [-0.5, -0.5, -0.5];
        boxv1 = [0.5, -0.5, -0.5];
        boxv2 = [0.5, 0.5, -0.5];
        boxv3 = [-0.5, 0.5, -0.5];
        boxv4 = [-0.5, -0.5, 0.5];
        boxv5 = [0.5, -0.5, 0.5];
        boxv6 = [0.5, 0.5, 0.5];
        boxv7 = [-0.5, 0.5, 0.5];
    }

    /// Set the rotation about the vertical (y) axis.
    void vAngle(double angle) { vAng = angle; }
    /// Return the rotation about the vertical (y) axis.
    double vAngle() const { return vAng; }

    /// Set the rotation about the horizontal (x) axis.
    void hAngle(double angle) { hAng = angle; }
    /// The rotation about the horizontal (x) axis.
    double hAngle() const { return hAng; }

    /// Sets the x shift of the cube view camera.
    void panx(double x) { xshift = x; }
    /// Sets the y shift of the cube view camera.
    void pany(double y) { yshift = y; }

    private void drawCube()
    {
        // Draw a colored cube
        enum float alpha = 0.5;
        glShadeModel(GL_FLAT);

        glBegin(GL_QUADS);
        glColor4f(0.0, 0.0, 1.0, alpha);
        glVertex3fv(boxv0.ptr);
        glVertex3fv(boxv1.ptr);
        glVertex3fv(boxv2.ptr);
        glVertex3fv(boxv3.ptr);

        glColor4f(1.0, 1.0, 0.0, alpha);
        glVertex3fv(boxv0.ptr);
        glVertex3fv(boxv4.ptr);
        glVertex3fv(boxv5.ptr);
        glVertex3fv(boxv1.ptr);

        glColor4f(0.0, 1.0, 1.0, alpha);
        glVertex3fv(boxv2.ptr);
        glVertex3fv(boxv6.ptr);
        glVertex3fv(boxv7.ptr);
        glVertex3fv(boxv3.ptr);

        glColor4f(1.0, 0.0, 0.0, alpha);
        glVertex3fv(boxv4.ptr);
        glVertex3fv(boxv5.ptr);
        glVertex3fv(boxv6.ptr);
        glVertex3fv(boxv7.ptr);

        glColor4f(1.0, 0.0, 1.0, alpha);
        glVertex3fv(boxv0.ptr);
        glVertex3fv(boxv3.ptr);
        glVertex3fv(boxv7.ptr);
        glVertex3fv(boxv4.ptr);

        glColor4f(0.0, 1.0, 0.0, alpha);
        glVertex3fv(boxv1.ptr);
        glVertex3fv(boxv5.ptr);
        glVertex3fv(boxv6.ptr);
        glVertex3fv(boxv2.ptr);
        glEnd();

        glColor3f(1.0, 1.0, 1.0);
        glBegin(GL_LINES);
        glVertex3fv(boxv0.ptr);
        glVertex3fv(boxv1.ptr);

        glVertex3fv(boxv1.ptr);
        glVertex3fv(boxv2.ptr);

        glVertex3fv(boxv2.ptr);
        glVertex3fv(boxv3.ptr);

        glVertex3fv(boxv3.ptr);
        glVertex3fv(boxv0.ptr);

        glVertex3fv(boxv4.ptr);
        glVertex3fv(boxv5.ptr);

        glVertex3fv(boxv5.ptr);
        glVertex3fv(boxv6.ptr);

        glVertex3fv(boxv6.ptr);
        glVertex3fv(boxv7.ptr);

        glVertex3fv(boxv7.ptr);
        glVertex3fv(boxv4.ptr);

        glVertex3fv(boxv0.ptr);
        glVertex3fv(boxv4.ptr);

        glVertex3fv(boxv1.ptr);
        glVertex3fv(boxv5.ptr);

        glVertex3fv(boxv2.ptr);
        glVertex3fv(boxv6.ptr);

        glVertex3fv(boxv3.ptr);
        glVertex3fv(boxv7.ptr);
        glEnd();
    }

    override void draw()
    {
        if (!valid())
        {
            glLoadIdentity();
            glViewport(0, 0, pixelW(), pixelH());
            glOrtho(-10, 10, -10, 10, -20050, 10000);
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }

        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        glPushMatrix();

        glTranslatef(cast(GLfloat) xshift, cast(GLfloat) yshift, 0);
        glRotatef(cast(GLfloat) hAng, 0, 1, 0);
        glRotatef(cast(GLfloat) vAng, 1, 0, 0);
        glScalef(cast(float) size, cast(float) size, cast(float) size);

        drawCube();

        glPopMatrix();
    }
}
