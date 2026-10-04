# FLTK `fl_`-prefix to fldtk mapping

FLTK names its free functions and a handful of global variables with a
lowercase `fl_` prefix (`fl_color()`, `fl_draw()`, `fl_no`, ...). This port's
convention is camelCase with no prefix (`pushClip()`, `drawBoxAt()`,
`utf8Encode()`), so every public `fl_`-prefixed free function or global
variable in `source/fl/` was checked against the rest of this port's public
surface for a bare-name collision -- mainly `Widget` instance methods and
other classes' methods, since D resolves an unqualified call in the
enclosing scope. A name only keeps its `fl_` prefix here when dropping it
would collide with a real, already-declared identifier -- the same reason
FLTK's own C++ API keeps the prefix on most of these exact functions in the
first place.

This covers the public free-function/global-variable surface that mirrors
FLTK's own `fl_`-prefixed API (`fl_draw.H`, `fl_ask.H`, and similar). It does
not cover widget method names, module names, or this port's own private
helpers.

- **135** names checked
- **105** renamed to camelCase, no prefix
- **30** kept `fl_`-prefixed because dropping the prefix collides with a
  real, already-existing identifier

## Renamed (105)

| FLTK name | fldtk name |
|---|---|
| `fl_add_symbol` | `addSymbol` |
| `fl_alert` | `alert` |
| `fl_antialias` | `antialias` |
| `fl_begin_complex_polygon` | `beginComplexPolygon` |
| `fl_begin_line` | `beginLine` |
| `fl_begin_loop` | `beginLoop` |
| `fl_begin_offscreen` | `beginOffscreen` |
| `fl_begin_points` | `beginPoints` |
| `fl_begin_polygon` | `beginPolygon` |
| `fl_capture_window` | `captureWindow` |
| `fl_choice` | `choice` |
| `fl_choice_n` | `choiceN` |
| `fl_circle` | `circle` |
| `fl_color_average` | `colorAverage` |
| `fl_color_chooser` | `colorChooser` |
| `fl_contrast` | `contrast` |
| `fl_contrast_legacy` | `contrastLegacy` |
| `fl_contrast_function` | `contrastFunction` |
| `fl_contrast_level` | `contrastLevel` |
| `fl_contrast_mode` | `contrastMode` |
| `fl_copy_offscreen` | `copyOffscreen` |
| `fl_create_offscreen` | `createOffscreen` |
| `fl_curve` | `curve` |
| `fl_darker` | `darker` |
| `fl_delete_offscreen` | `deleteOffscreen` |
| `fl_descent` | `descent` |
| `fl_dir_chooser` | `dirChooser` |
| `fl_draw_arrow` | `drawArrow` |
| `fl_draw_box_focus` | `drawBoxFocus` |
| `fl_draw_check` | `drawCheck` |
| `fl_draw_circle` | `drawCircle` |
| `fl_draw_image` | `drawImage` |
| `fl_draw_image_mono` | `drawImageMono` |
| `fl_draw_radio` | `drawRadio` |
| `fl_draw_symbol` | `drawSymbol` |
| `fl_embossed_label_draw` | `embossedLabelDraw` |
| `fl_end_complex_polygon` | `endComplexPolygon` |
| `fl_end_line` | `endLine` |
| `fl_end_loop` | `endLoop` |
| `fl_end_offscreen` | `endOffscreen` |
| `fl_end_points` | `endPoints` |
| `fl_end_polygon` | `endPolygon` |
| `fl_engraved_label_draw` | `engravedLabelDraw` |
| `fl_file_chooser` | `fileChooser` |
| `fl_file_chooser_callback` | `fileChooserCallback` |
| `fl_file_chooser_ok_label` | `fileChooserOkLabel` |
| `fl_focus_rect` | `focusRect` |
| `fl_height` | `height` |
| `fl_inactive` | `inactive` |
| `fl_lighter` | `lighter` |
| `fl_lightness` | `lightness` |
| `fl_line_style` | `lineStyle` |
| `fl_load_identity` | `loadIdentity` |
| `fl_load_matrix` | `loadMatrix` |
| `fl_loop` | `loop` |
| `fl_luminance` | `luminance` |
| `fl_message` | `message` |
| `fl_message_hotspot` | `messageHotspot` |
| `fl_message_icon` | `messageIcon` (merged with a private helper of the same name that already existed in `fl.ask`; the one call site with a same-named local variable, `source/test/ask.d`, qualifies as `fl.ask.messageIcon()`) |
| `fl_message_icon_label` | `messageIconLabel` |
| `fl_message_position` | `messagePosition` |
| `fl_message_title` | `messageTitle` |
| `fl_message_title_default` | `messageTitleDefault` |
| `fl_mult_matrix` | `multMatrix` |
| `fl_no` | `no` |
| `fl_nonspacing` | `nonspacing` |
| `fl_ok` | `ok` |
| `fl_open_callback` | `openCallback` |
| `fl_open_uri` | `openUri` |
| `fl_overlay_clear` | `overlayClear` |
| `fl_overlay_rect` | `overlayRect` |
| `fl_parse_color` | `parseColor` |
| `fl_password` | `password` |
| `fl_point` | `point` |
| `fl_pop_matrix` | `popMatrix` |
| `fl_push_matrix` | `pushMatrix` |
| `fl_push_no_clip` | `pushNoClip` |
| `fl_read_image` | `readImage` |
| `fl_rectbound` | `rectbound` |
| `fl_remove_symbol` | `removeSymbol` |
| `fl_rescale_offscreen` | `rescaleOffscreen` |
| `fl_reset_spot` | `resetSpot` |
| `fl_return_arrow` | `returnArrow` |
| `fl_rgb_color` | `rgbColor` |
| `fl_rounded_rect` | `roundedRect` |
| `fl_rounded_rectf` | `roundedRectf` |
| `fl_rtl_draw` | `rtlDraw` |
| `fl_screen` | `x11Screen` |
| `fl_set_spot` | `setSpot` |
| `fl_shadow_label_draw` | `shadowLabelDraw` |
| `fl_show_colormap` | `showColormap` |
| `fl_text_extents` | `textExtents` |
| `fl_transform_dx` | `transformDx` |
| `fl_transform_dy` | `transformDy` |
| `fl_transform_x` | `transformX` |
| `fl_transform_y` | `transformY` |
| `fl_transformed_vertex` | `transformedVertex` |
| `fl_vertex` | `vertex` |
| `fl_width` | `width` |
| `fl_wl_display` | `wlDisplay` |
| `fl_write_jpeg` | `writeJpeg` |
| `fl_write_png` | `writePng` |
| `fl_x11_display` | `x11Display` |
| `fl_xpixel` | `xpixel` |
| `fl_yes` | `yes` |

## Kept `fl_`-prefixed (30)

| FLTK/fldtk name | Would collide with |
|---|---|
| `fl_arc` | `GraphicsDriver.arc()` (abstract) + overrides (`svg_file_surface`, `postscript`, `gl_graphics_driver`) |
| `fl_beep` | `platform_x11.beep()`, `core.beep()` |
| `fl_box` | `Widget.box()`/`box(Boxtype)` + boxtype-setting calls across nearly every widget constructor |
| `fl_cancel` | `menu_popup`'s private `PopupEngine.cancel()` |
| `fl_close` | `close()` methods in `fl.postscript` and `TreeItem.close()` (`fl.tree_item`) |
| `fl_color` | `Widget.color()`/`color(Color)`/`color(Color,Color)`, `GraphicsDriver.color()`, `Tooltip.color()`, `FileChooser.color()`, `Spinner.color()`, and more override/forwarding sites |
| `fl_colormap` | a `__gshared` global; `platform_x11.createWindow()`'s own `colormap` parameter shadows it in the same file |
| `fl_down` | `Terminal`'s private nested `down()` (row-increment helper) |
| `fl_draw` | `Widget.draw()` (abstract) + well over a hundred override sites across nearly every widget/image/driver |
| `fl_draw_shortcut` | `menu_popup`'s private `MenuLevelWindow.drawShortcut()` |
| `fl_font` | `Tooltip.font()`/`font(Font)` |
| `fl_frame` | `AnimGifImage.frame()`/`frame(int)` |
| `fl_gap` | `Grid.gap(int,int)`, `Flex.gap()`/`gap(int)` |
| `fl_graphics_driver` | a module-scope import alias for `fl.graphics_driver`, `import graphicsDriver = fl.graphics_driver;` (`image_surface.d`, plus unittest-scoped aliases in `postscript.d`/`svg_file_surface.d`) |
| `fl_gray_ramp` | the `Color` enum member `grayRamp` (`fl.enumerations`), used pervasively in `fl.core`'s gamma/ramp math |
| `fl_input` | `InputChoice.input()` (returns the embedded `Input` widget) |
| `fl_line` | `GraphicsDriver.line()` (abstract) + overrides |
| `fl_measure` | `Widget.measure()`, `MenuItem.measure()`, `MultiLabel.measure()`, `FileBrowser`'s private `measure()` |
| `fl_pie` | `GraphicsDriver.pie()` (abstract) + overrides |
| `fl_polygon` | `GraphicsDriver.polygon()` (2 overloads, abstract) + overrides |
| `fl_rect` | `GraphicsDriver.rect()` (abstract) + overrides |
| `fl_rectf` | `GraphicsDriver.rectf()` (abstract) + overrides |
| `fl_rotate` | `PagedDevice.rotate()`, `Postscript.rotate()` override |
| `fl_scale` | `PagedDevice.scale()`, `Postscript.scale()` override, `Slider.scale()`/`scale(ScaleType)`, `SvgImage.scale()`, `Image.scale()`, `fl.draw`'s own local `scale()` |
| `fl_scroll` | `Terminal.scroll()` (3 overloads), `TextDisplay.scroll()` |
| `fl_size` | a widely-used plain method name: `Chart.size()`, `TextBuffer.size()`, `Window.size(int,int)`, `Widget.size(int,int)`, `Browser.size()`/`size(int,int)`, `Tooltip.size()`/`size(Fontsize)`, `Menu_.size()`, `MenuItem.size()`, `HelpView.size()`, and more |
| `fl_translate` | `WidgetSurface.translate()` + overrides (`postscript` x2, `svg_file_surface`, `image_surface` x2) |
| `fl_visual` | a `__gshared` global; `platform_x11.createWindow()`'s own `visual` parameter shadows it in the same file (same shape as `fl_colormap`) |
| `fl_xyline` | `GraphicsDriver.xyline()` (abstract) + overrides |
| `fl_yxline` | `GraphicsDriver.yxline()` (abstract) + overrides |
