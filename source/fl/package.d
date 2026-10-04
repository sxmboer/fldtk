module fl;

public import fl.core;
public import fl.enumerations;
public import fl.rgb_colors;
public import fl.filename;
public import fl.ask;
public import fl.text_buffer;
public import fl.input_;
public import fl.input;
public import fl.float_input;
public import fl.int_input;
public import fl.multiline_input;
public import fl.output;
public import fl.multiline_output;
public import fl.secret_input;
public import fl.file_input;
public import fl.spinner;
public import fl.rect;
public import fl.widget;
public import fl.widget_tracker;
public import fl.group;
public import fl.positioner;
public import fl.progress;
public import fl.box;
public import fl.button;
public import fl.repeat_button;
public import fl.radio_button;
public import fl.toggle_button;
public import fl.light_button;
public import fl.round_button;
public import fl.check_button;
public import fl.radio_light_button;
public import fl.radio_round_button;
public import fl.toggle_light_button;
public import fl.toggle_round_button;
public import fl.return_button;
public import fl.shortcut_button;
public import fl.scroll;
public import fl.browser_;
public import fl.browser;
public import fl.select_browser;
public import fl.hold_browser;
public import fl.multi_browser;
public import fl.check_browser;
public import fl.file_icon;
public import fl.file_browser;
public import fl.file_chooser;
public import fl.native_file_chooser;
public import fl.chart;
public import fl.valuator;
public import fl.adjuster;
public import fl.counter;
public import fl.simple_counter;
public import fl.dial;
public import fl.fill_dial;
public import fl.line_dial;
public import fl.value_output;
public import fl.value_input;
public import fl.slider;
public import fl.hor_slider;
public import fl.fill_slider;
public import fl.hor_fill_slider;
public import fl.nice_slider;
public import fl.hor_nice_slider;
public import fl.value_slider;
public import fl.hor_value_slider;
public import fl.roller;
public import fl.clock;
public import fl.round_clock;
public import fl.scrollbar;
public import fl.text_display;
public import fl.text_editor;
public import fl.window;
public import fl.double_window;
public import fl.single_window;
public import fl.overlay_window;
public import fl.gl_choice;
public import fl.gl_window;
public import fl.gl;
public import fl.glut;
public import fl.wizard;
public import fl.pack;
public import fl.flex;
public import fl.tile;
public import fl.grid;
public import fl.tabs;
public import fl.tree_prefs;
public import fl.tree_item;
public import fl.tree;
public import fl.table;
public import fl.table_row;
public import fl.color_chooser;
public import fl.show_colormap;
public import fl.preferences;
public import fl.multi_label;
public import fl.menu_item;
public import fl.menu_;
public import fl.menu_window;
public import fl.menu_popup;
public import fl.menu_button;
public import fl.menu_bar;
public import fl.sys_menu_bar;
public import fl.choice;
public import fl.input_choice;
public import fl.scheme_choice;
public import fl.image;
public import fl.bitmap;
public import fl.pixmap;
public import fl.xbm_image;
public import fl.xpm_image;
public import fl.pnm_image;
public import fl.tiled_image;
public import fl.shared_image;
public import fl.bmp_image;
public import fl.ico_image;
public import fl.gif_image;
public import fl.anim_gif_image;
public import fl.png_image;
public import fl.jpeg_image;
public import fl.nanosvg;
public import fl.nanosvg_rast;
public import fl.svg_image;
public import fl.draw;
public import fl.graphics_driver;
public import fl.widget_surface;
public import fl.image_surface;
public import fl.svg_file_surface;
public import fl.paged_device;
public import fl.postscript;
public import fl.printer;
public import fl.symbols;
public import fl.names;
public import fl.tooltip;
public import fl.help_view;
public import fl.help_dialog;
public import fl.terminal;
public import fl.opengl;
public import fl.glu;
public import fl.glew;


// fl.scheme (FL/Fl_Scheme.H's names()/numSchemes()/addSchemeName()
// registry, backing fl.scheme_choice's SchemeChoice) is deliberately
// NOT re-exported here either, same category of problem as
// fl.platform_x11 just below: its module name is literally `scheme`,
// which collides with fl.core's own `scheme()`/`scheme(string)`
// functions (the real Fl::scheme() reactivity, ported for
// core-roadmap item 11) once both are visible under a single
// `import fl;` -- a bare `scheme(...)` call resolved to the *module*
// instead of the function, breaking every caller of fl.core.scheme()
// (e.g. tabs-simple/message/tree-custom-sort, all `scheme(...)`
// callers) the moment both are visible under one `import fl;`.
// fl.scheme_choice imports fl.scheme directly and doesn't need it
// re-exported; nothing else in this port calls fl.scheme's own
// functions directly.
//
// fl.platform_x11 deliberately NOT re-exported here: it's the concrete
// X11 backend (infrastructure, not a header port -- see PORTING.md),
// and several of its symbols (`run()`, `beep()`) collide with fl.core's
// wrappers of the same name under a single `import fl;` -- fl.core's
// versions are the actual public API (Fl::run()/Fl::beep()); platform
// modules are meant to be called through fl.core, not directly.
// Nothing outside fl.core/fl.window needs it, and both already
// `import fl.platform_x11` directly (aliased as `platformX11`).
//
// fl.xlib is excluded for the same kind of reason: it's raw extern(C)
// Xlib bindings, and its `alias Window = XID` collides with fl.window's
// `Window` class under a single `import fl;`. Modules that need real
// Xlib types (fl.window, fl.platform_x11) already `import fl.xlib`
// directly.
//
// fl.opengl/fl.glu/fl.glew ARE re-exported (see above) -- unlike
// fl.xlib, they're not just infrastructure a driver module happens to
// need internally: real GL sample programs call their functions
// directly from their own `draw()` overrides, the same "genuine
// user-facing public API" test fl.gl/fl.glut already have to pass
// (`fl.opengl`'s `glVertex3f()`/etc in `samples/test/cube.d`,
// `fl.glu`'s `gluPerspective()`/`gluLookAt()` in `fracviewer.d`/
// `glpuzzle.d`/`fractals.d`/`OpenGL3_glut_test.d`, `fl.glew`'s
// `glShaderSource()`/etc in `OpenGL3test.d`/`OpenGL3_glut_test.d`).
// Checked for real: no symbol in any of the three collides with
// anything else re-exported here (`glCreateShader`/`glGenVertexArrays`/
// `glXGetProcAddress` appear in `fl.opengl`'s own doc comments, not as
// actual declarations, so there's no redefinition either).
//
// fl.glx and fl.gl_window_driver stay excluded, though -- unlike the
// three above, grepping every sample under `source/test`/
// `source/examples` turns up zero direct importers of either: they're
// used only internally, by `fl.gl_window`/`fl.gl_window_driver`
// themselves, to implement double-buffering/context management no
// sample is expected to touch directly. fl.gl_window_driver's own
// free functions (`swapBuffers()`, `setGlContext()`, `switchToGl1()`,
// ...) are generically named exactly because they're private
// implementation plumbing dispatched automatically by `GlWindow`'s
// methods (`win.swapBuffers()` etc.), not something a real FLTK
// program calls by that name itself -- re-exporting them would put
// driver internals in the public `import fl;` surface for no sample
// to ever use. fl.gl_choice/fl.gl_window (the actual port-target/
// public-API modules, `GlChoice`/`GlWindow`) ARE re-exported above --
// consumers needing the lower-level driver pieces `import
// fl.gl_window_driver` directly, matching how fl.window/fl.gl_window
// already do.
//
// fl.gl_graphics_driver/fl.gl_display_device (the
// `fl.graphics_driver.GraphicsDriver` subclass that redirects
// `fl.draw` primitives through GL, and the `SurfaceDevice` that pushes
// it current) are excluded for the same reason as fl.gl_window_driver
// above -- internal driver plumbing `fl.gl_window.GlWindow.drawBegin()`/
// `drawEnd()` already wires up automatically; no sample needs to name
// either module directly.
//
// fl.gl (`gl_color()`/`gl_font()`/`gl_draw()`/etc, the real `FL/gl.h`
// wrapper-function port) IS re-exported, unlike the four modules just
// above -- it's real, user-facing public API real GL programs call
// directly from their own
// immediate-mode `draw()` overrides (`samples/test/cube.d`'s own
// `gl_color(gray0); gl_font(helveticaBold, 16); gl_draw(...)`, matching
// FLTK's real usage exactly), the same "actual port-target/
// public-API module" category `fl.gl_choice`/`fl.gl_window` are in, not
// internal driver plumbing. No name in it collides with anything else
// re-exported here (the `gl_` prefix keeps it distinct from both
// `fl.opengl`'s raw `glFoo()` bindings and every widget/module name).
//
// fl.glut (`FL/glut.H` + `src/glut_compatibility.cxx`'s GLUT emulation
// layer) is re-exported for the same "real, user-facing
// public-API module" reason `fl.gl` is -- a GLUT-style sample calls
// `glutDisplayFunc()`/`glutCreateWindow()`/etc directly, matching
// FLTK's real usage. Its own `glut*`-prefixed functions and
// `GLUT_*`-prefixed constants collide with nothing else re-exported
// here. `fl.glu` is re-exported too now (see the fl.opengl/fl.glu/
// fl.glew note above) -- a GLUT-based sample needing GLU no longer
// needs its own explicit `import fl.glu;`.
