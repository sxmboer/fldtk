// D transliteration of FLTK's test/glut_test.cxx.
// Build: rdmd buildsamples.d test glut_test
//
// GLUT compatibility test. fldtk has no GL/GLUT support at all yet (no
// FL/glut.H port) -- the glut*() calls below keep their FLTK C
// names verbatim (foreign GLUT API, not FLTK's own naming surface).
// Expected to fail on essentially every line; the point is recording
// the surface this program exercises, not perfecting the transliteration.
import fl;
import std.stdio : writefln;

// Empty callback functions for testing.
void displayFunc() {}
void reshapeFunc(int w, int h) {}
void keyboardFunc(ubyte key, int x, int y) {}
void mouseFunc(int b, int state, int x, int y) {}
void motionFunc(int x, int y) {}
void passiveMotionFunc(int x, int y) {}
void entryFunc(int s) {}
void visibilityFunc(int s) {}
void idleFunc() {}
void timerFunc(int value) {}
void menuStateFunc(int state) {}
void menuStatusFunc(int status, int x, int y) {}
void specialFunc(int key, int x, int y) {}
void overlayDisplayFunc() {}

void main(string[] args)
{
    glutInit(args);

    // Create 2 windows.
    int win1 = glutCreateWindow("Window 1");
    int win2 = glutCreateWindow("Window 2");
    writefln("Window 1 created, number = %d", win1);
    writefln("Window 2 created, number = %d", win2);

    // Run tests twice, with (1) a valid and (2) an invalid current window
    for (int i = 0; i < 2; i++)
    {
        // Find out which window is current.
        int current = glutGetWindow();
        writefln("Window %d is current", current);

        // Ask GLUT to redisplay things.
        glutPostRedisplay();

        // Set window title
        glutSetWindowTitle("Non-existent");

        // Set icon title
        glutSetIconTitle("Non-existent");

        // Position window
        glutPositionWindow(10, 20);

        // Reshape window
        glutReshapeWindow(100, 200);

        // Pop window
        glutPopWindow();

        // Iconify window
        glutIconifyWindow();

        // Show window
        glutShowWindow();

        // Hide window
        glutHideWindow();

        // Go to full screen mode
        glutFullScreen();

        // Set the cursor
        glutSetCursor(GLUT_CURSOR_INFO);

        // Establish an overlay
        glutEstablishOverlay();

        // Remove overlay
        glutRemoveOverlay();

        // Choose a layer
        glutUseLayer(GLUT_NORMAL);
        glutUseLayer(GLUT_OVERLAY);

        // Post display on a layer
        glutPostOverlayRedisplay();

        // Show overlay
        glutShowOverlay();

        // Hide overlay
        glutHideOverlay();

        // Attach a menu
        glutAttachMenu(0);

        // Detach a menu
        glutDetachMenu(0);

        // Specify callbacks
        glutDisplayFunc(&displayFunc);
        glutReshapeFunc(&reshapeFunc);
        glutKeyboardFunc(&keyboardFunc);
        glutMouseFunc(&mouseFunc);
        glutMotionFunc(&motionFunc);
        glutPassiveMotionFunc(&passiveMotionFunc);
        glutEntryFunc(&entryFunc);
        glutVisibilityFunc(&visibilityFunc);
        glutIdleFunc(&idleFunc);
        glutTimerFunc(1000, &timerFunc, 42);
        glutMenuStateFunc(&menuStateFunc);
        glutMenuStatusFunc(&menuStatusFunc);
        glutSpecialFunc(&specialFunc);
        glutOverlayDisplayFunc(&overlayDisplayFunc);

        // Swap buffers
        glutSwapBuffers();

        // GLUT gets
        writefln("GLUT_WINDOW_X = %d", glutGet(GLUT_WINDOW_X));
        writefln("GLUT_WINDOW_Y = %d", glutGet(GLUT_WINDOW_Y));
        writefln("GLUT_WINDOW_WIDTH = %d", glutGet(GLUT_WINDOW_WIDTH));
        writefln("GLUT_WINDOW_HEIGHT = %d", glutGet(GLUT_WINDOW_HEIGHT));
        writefln("GLUT_WINDOW_PARENT = %d", glutGet(GLUT_WINDOW_PARENT));

        // GLUT layer gets
        writefln("GLUT_OVERLAY_POSSIBLE = %d", glutLayerGet(GLUT_OVERLAY_POSSIBLE));
        writefln("GLUT_NORMAL_DAMAGED = %d", glutLayerGet(GLUT_NORMAL_DAMAGED));

        // Destroy the current window - this sets glut_window to NULL
        writefln("Destroy the current window (%d)\n", glutGetWindow());
        glutDestroyWindow(current);
    } // loop with current window

    writefln("All tests done, exiting.");
}
