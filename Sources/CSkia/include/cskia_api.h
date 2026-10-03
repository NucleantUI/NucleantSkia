//
//  cskia_api.h
//  CSkia — plain-C mirror of Skia's core drawing API (m132), one handle per
//  Skia class: SkCanvas, SkPaint, SkPath, SkFont, SkTypeface, SkShader,
//  SkPathEffect, SkImage, plus a raster SkSurface.
//
//  Ownership follows Skia's own:
//    * SkCanvas is borrowed — it belongs to the surface it came from.
//    * SkPaint / SkPath / SkFont are values in Skia; here they are heap
//      copies the caller owns: `*_new` / `*_copy` → `*_delete`.
//    * SkTypeface / SkShader / SkPathEffect / SkImage are ref-counted in
//      Skia; every `*_make*` returns one reference the caller owns, given
//      back with `*_unref`. A setter that stores one (`paint_set_shader`,
//      `font_set_typeface`) takes its own reference.
//
//  Enum arguments are int32_t carrying the Skia enum's own value (the Swift
//  side declares matching enums); out-of-range values are clamped.
//

#ifndef CSKIA_API_H
#define CSKIA_API_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cskia_canvas_t      cskia_canvas_t;
typedef struct cskia_paint_t       cskia_paint_t;
typedef struct cskia_path_t        cskia_path_t;
typedef struct cskia_font_t        cskia_font_t;
typedef struct cskia_typeface_t    cskia_typeface_t;
typedef struct cskia_shader_t      cskia_shader_t;
typedef struct cskia_path_effect_t cskia_path_effect_t;
typedef struct cskia_image_t       cskia_image_t;
typedef struct cskia_raster_surface_t cskia_raster_surface_t;

/// SkMatrix, in SkMatrix's own order (kMScaleX … kMPersp2).
typedef struct cskia_matrix {
    float scale_x, skew_x,  trans_x;
    float skew_y,  scale_y, trans_y;
    float persp_0, persp_1, persp_2;
} cskia_matrix;

/// A rect as position + size (SkRect::MakeXYWH).
typedef struct cskia_rect {
    float x, y, w, h;
} cskia_rect;

/// SkFontMetrics.
typedef struct cskia_font_metrics {
    uint32_t flags;
    float top, ascent, descent, bottom, leading;
    float avg_char_width, max_char_width;
    float x_min, x_max, x_height, cap_height;
    float underline_thickness, underline_position;
    float strikeout_thickness, strikeout_position;
} cskia_font_metrics;

// MARK: - SkCanvas

int32_t cskia_canvas_save(cskia_canvas_t* canvas);
int32_t cskia_canvas_save_layer(cskia_canvas_t* canvas, const cskia_rect* bounds, const cskia_paint_t* paint);
int32_t cskia_canvas_save_layer_alphaf(cskia_canvas_t* canvas, const cskia_rect* bounds, float alpha);
void    cskia_canvas_restore(cskia_canvas_t* canvas);
void    cskia_canvas_restore_to_count(cskia_canvas_t* canvas, int32_t count);
int32_t cskia_canvas_get_save_count(cskia_canvas_t* canvas);

void cskia_canvas_translate(cskia_canvas_t* canvas, float dx, float dy);
void cskia_canvas_scale(cskia_canvas_t* canvas, float sx, float sy);
void cskia_canvas_rotate(cskia_canvas_t* canvas, float degrees);
void cskia_canvas_rotate_about(cskia_canvas_t* canvas, float degrees, float px, float py);
void cskia_canvas_skew(cskia_canvas_t* canvas, float sx, float sy);
void cskia_canvas_concat(cskia_canvas_t* canvas, const cskia_matrix* matrix);
void cskia_canvas_set_matrix(cskia_canvas_t* canvas, const cskia_matrix* matrix);
void cskia_canvas_reset_matrix(cskia_canvas_t* canvas);
void cskia_canvas_get_total_matrix(cskia_canvas_t* canvas, cskia_matrix* out);

void cskia_canvas_clip_rect(cskia_canvas_t* canvas, float x, float y, float w, float h, int32_t op, bool anti_alias);
void cskia_canvas_clip_rrect(cskia_canvas_t* canvas, float x, float y, float w, float h, float rx, float ry, int32_t op, bool anti_alias);
void cskia_canvas_clip_path(cskia_canvas_t* canvas, const cskia_path_t* path, int32_t op, bool anti_alias);

void cskia_canvas_clear_color4f(cskia_canvas_t* canvas, float r, float g, float b, float a);
void cskia_canvas_draw_color4f(cskia_canvas_t* canvas, float r, float g, float b, float a, int32_t blend_mode);
void cskia_canvas_draw_paint(cskia_canvas_t* canvas, const cskia_paint_t* paint);
void cskia_canvas_draw_rect_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, const cskia_paint_t* paint);
void cskia_canvas_draw_rrect_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, float rx, float ry, const cskia_paint_t* paint);
void cskia_canvas_draw_oval_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, const cskia_paint_t* paint);
void cskia_canvas_draw_circle_at(cskia_canvas_t* canvas, float cx, float cy, float radius, const cskia_paint_t* paint);
void cskia_canvas_draw_arc_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, float start_angle, float sweep_angle, bool use_center, const cskia_paint_t* paint);
void cskia_canvas_draw_line_points(cskia_canvas_t* canvas, float x0, float y0, float x1, float y1, const cskia_paint_t* paint);
void cskia_canvas_draw_point(cskia_canvas_t* canvas, float x, float y, const cskia_paint_t* paint);
void cskia_canvas_draw_path(cskia_canvas_t* canvas, const cskia_path_t* path, const cskia_paint_t* paint);
/// `paint` may be NULL. Linear filtering.
void cskia_canvas_draw_image(cskia_canvas_t* canvas, const cskia_image_t* image, float x, float y, const cskia_paint_t* paint);
/// `paint` may be NULL. Linear filtering; the whole image into the rect.
void cskia_canvas_draw_image_rect(cskia_canvas_t* canvas, const cskia_image_t* image, float x, float y, float w, float h, const cskia_paint_t* paint);
/// UTF-8, `byte_length` bytes; (x, y) is the baseline origin.
void cskia_canvas_draw_simple_text(cskia_canvas_t* canvas, const char* utf8, size_t byte_length, float x, float y, const cskia_font_t* font, const cskia_paint_t* paint);

// MARK: - SkPaint

cskia_paint_t* cskia_paint_new(void);
cskia_paint_t* cskia_paint_copy(const cskia_paint_t* paint);
void cskia_paint_delete(cskia_paint_t* paint);
void cskia_paint_reset(cskia_paint_t* paint);

void cskia_paint_set_anti_alias(cskia_paint_t* paint, bool aa);
bool cskia_paint_is_anti_alias(const cskia_paint_t* paint);
void cskia_paint_set_dither(cskia_paint_t* paint, bool dither);
bool cskia_paint_is_dither(const cskia_paint_t* paint);

/// SkColor: 0xAARRGGBB.
void     cskia_paint_set_color(cskia_paint_t* paint, uint32_t argb);
uint32_t cskia_paint_get_color(const cskia_paint_t* paint);
void     cskia_paint_set_color4f(cskia_paint_t* paint, float r, float g, float b, float a);
/// Writes r, g, b, a.
void     cskia_paint_get_color4f(const cskia_paint_t* paint, float* rgba);
void     cskia_paint_set_alphaf(cskia_paint_t* paint, float alpha);
float    cskia_paint_get_alphaf(const cskia_paint_t* paint);

void    cskia_paint_set_style(cskia_paint_t* paint, int32_t style);
int32_t cskia_paint_get_style(const cskia_paint_t* paint);
void    cskia_paint_set_stroke_width(cskia_paint_t* paint, float width);
float   cskia_paint_get_stroke_width(const cskia_paint_t* paint);
void    cskia_paint_set_stroke_miter(cskia_paint_t* paint, float miter);
float   cskia_paint_get_stroke_miter(const cskia_paint_t* paint);
void    cskia_paint_set_stroke_cap(cskia_paint_t* paint, int32_t cap);
int32_t cskia_paint_get_stroke_cap(const cskia_paint_t* paint);
void    cskia_paint_set_stroke_join(cskia_paint_t* paint, int32_t join);
int32_t cskia_paint_get_stroke_join(const cskia_paint_t* paint);

/// NULL clears it.
void cskia_paint_set_shader(cskia_paint_t* paint, cskia_shader_t* shader);
/// NULL clears it.
void cskia_paint_set_path_effect(cskia_paint_t* paint, cskia_path_effect_t* effect);
void cskia_paint_set_blend_mode(cskia_paint_t* paint, int32_t blend_mode);
int32_t cskia_paint_get_blend_mode(const cskia_paint_t* paint);
/// SkMaskFilter::MakeBlur; `sigma <= 0` clears the mask filter.
void cskia_paint_set_mask_filter_blur(cskia_paint_t* paint, int32_t blur_style, float sigma);

// MARK: - SkPath

cskia_path_t* cskia_path_new(void);
cskia_path_t* cskia_path_copy(const cskia_path_t* path);
void cskia_path_delete(cskia_path_t* path);
void cskia_path_reset(cskia_path_t* path);
void cskia_path_rewind(cskia_path_t* path);

void cskia_path_move_to(cskia_path_t* path, float x, float y);
void cskia_path_line_to(cskia_path_t* path, float x, float y);
void cskia_path_quad_to(cskia_path_t* path, float x1, float y1, float x2, float y2);
void cskia_path_conic_to(cskia_path_t* path, float x1, float y1, float x2, float y2, float weight);
void cskia_path_cubic_to(cskia_path_t* path, float x1, float y1, float x2, float y2, float x3, float y3);
void cskia_path_close(cskia_path_t* path);

void cskia_path_add_rect(cskia_path_t* path, float x, float y, float w, float h, int32_t direction);
void cskia_path_add_rrect(cskia_path_t* path, float x, float y, float w, float h, float rx, float ry, int32_t direction);
void cskia_path_add_oval(cskia_path_t* path, float x, float y, float w, float h, int32_t direction);
void cskia_path_add_circle(cskia_path_t* path, float cx, float cy, float radius, int32_t direction);
void cskia_path_add_arc(cskia_path_t* path, float x, float y, float w, float h, float start_angle, float sweep_angle);
void cskia_path_add_path(cskia_path_t* path, const cskia_path_t* src, float dx, float dy);

void    cskia_path_set_fill_type(cskia_path_t* path, int32_t fill_type);
int32_t cskia_path_get_fill_type(const cskia_path_t* path);
void    cskia_path_get_bounds(const cskia_path_t* path, cskia_rect* out);
void    cskia_path_compute_tight_bounds(const cskia_path_t* path, cskia_rect* out);
bool    cskia_path_contains(const cskia_path_t* path, float x, float y);
bool    cskia_path_is_empty(const cskia_path_t* path);
int32_t cskia_path_count_points(const cskia_path_t* path);
int32_t cskia_path_count_verbs(const cskia_path_t* path);
void    cskia_path_offset(cskia_path_t* path, float dx, float dy);
void    cskia_path_transform(cskia_path_t* path, const cskia_matrix* matrix);

// MARK: - SkShader (SkGradientShader / SkShaders)
//
// `colors` is `count` × (r, g, b, a) floats; `positions` is `count` floats
// in 0…1, or NULL for evenly spaced.

cskia_shader_t* cskia_shader_make_linear_gradient(float x0, float y0, float x1, float y1, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_radial_gradient(float cx, float cy, float radius, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_two_point_conical_gradient(float sx, float sy, float start_radius, float ex, float ey, float end_radius, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_sweep_gradient(float cx, float cy, float start_angle, float end_angle, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_color(float r, float g, float b, float a);
void cskia_shader_ref(cskia_shader_t* shader);
void cskia_shader_unref(cskia_shader_t* shader);

// MARK: - SkPathEffect (SkDashPathEffect / SkCornerPathEffect)

cskia_path_effect_t* cskia_path_effect_make_dash(const float* intervals, int32_t count, float phase);
cskia_path_effect_t* cskia_path_effect_make_corner(float radius);
void cskia_path_effect_ref(cskia_path_effect_t* effect);
void cskia_path_effect_unref(cskia_path_effect_t* effect);

// MARK: - SkTypeface (through the platform SkFontMgr)

cskia_typeface_t* cskia_typeface_make_from_data(const void* bytes, size_t length, int32_t ttc_index);
cskia_typeface_t* cskia_typeface_make_from_file(const char* path, int32_t ttc_index);
/// `family` may be NULL for the platform default. `slant`: 0 upright, 1 italic, 2 oblique.
cskia_typeface_t* cskia_typeface_match_family_style(const char* family, int32_t weight, int32_t width, int32_t slant);
/// Copies the family name (NUL-terminated, truncated to `capacity`);
/// returns its full length in bytes.
size_t cskia_typeface_get_family_name(const cskia_typeface_t* typeface, char* buffer, size_t capacity);
int32_t cskia_typeface_count_glyphs(const cskia_typeface_t* typeface);
void cskia_typeface_ref(cskia_typeface_t* typeface);
void cskia_typeface_unref(cskia_typeface_t* typeface);

// MARK: - SkFont

/// `typeface` may be NULL (Skia's empty default).
cskia_font_t* cskia_font_new(cskia_typeface_t* typeface, float size);
cskia_font_t* cskia_font_copy(const cskia_font_t* font);
void cskia_font_delete(cskia_font_t* font);

void  cskia_font_set_typeface(cskia_font_t* font, cskia_typeface_t* typeface);
/// One new reference, or NULL.
cskia_typeface_t* cskia_font_ref_typeface(const cskia_font_t* font);
void  cskia_font_set_size(cskia_font_t* font, float size);
float cskia_font_get_size(const cskia_font_t* font);
void  cskia_font_set_scale_x(cskia_font_t* font, float scale);
float cskia_font_get_scale_x(const cskia_font_t* font);
void  cskia_font_set_skew_x(cskia_font_t* font, float skew);
float cskia_font_get_skew_x(const cskia_font_t* font);
void  cskia_font_set_embolden(cskia_font_t* font, bool embolden);
void  cskia_font_set_subpixel(cskia_font_t* font, bool subpixel);
void  cskia_font_set_linear_metrics(cskia_font_t* font, bool linear);
void  cskia_font_set_baseline_snap(cskia_font_t* font, bool snap);
void  cskia_font_set_edging(cskia_font_t* font, int32_t edging);
void  cskia_font_set_hinting(cskia_font_t* font, int32_t hinting);

/// Advance width of the UTF-8 text; `bounds` (may be NULL) gets its ink box.
float   cskia_font_measure_text(const cskia_font_t* font, const char* utf8, size_t byte_length, cskia_rect* bounds);
/// Glyph ids for the UTF-8 text into `glyphs` (up to `max_glyphs`); returns
/// how many the text has.
int32_t cskia_font_text_to_glyphs(const cskia_font_t* font, const char* utf8, size_t byte_length, uint16_t* glyphs, int32_t max_glyphs);
void    cskia_font_get_widths(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float* widths);
/// Fills `metrics`; returns the recommended line spacing.
float   cskia_font_get_metrics(const cskia_font_t* font, cskia_font_metrics* metrics);
float   cskia_font_get_spacing(const cskia_font_t* font);

// MARK: - SkImage (SkImages)

/// `color_type`: 0 RGBA_8888, 1 BGRA_8888. `alpha_type`: SkAlphaType
/// (1 opaque, 2 premul, 3 unpremul). The pixels are copied.
cskia_image_t* cskia_image_make_raster_copy(const void* pixels, int32_t width, int32_t height, size_t row_bytes, int32_t color_type, int32_t alpha_type);
int32_t cskia_image_get_width(const cskia_image_t* image);
int32_t cskia_image_get_height(const cskia_image_t* image);
void cskia_image_ref(cskia_image_t* image);
void cskia_image_unref(cskia_image_t* image);

// MARK: - Raster SkSurface (SkSurfaces::Raster)

/// CPU-backed RGBA_8888 premul surface.
cskia_raster_surface_t* cskia_raster_surface_make(int32_t width, int32_t height);
void cskia_raster_surface_delete(cskia_raster_surface_t* surface);
/// Borrowed — valid as long as the surface.
cskia_canvas_t* cskia_raster_surface_get_canvas(cskia_raster_surface_t* surface);
int32_t cskia_raster_surface_get_width(const cskia_raster_surface_t* surface);
int32_t cskia_raster_surface_get_height(const cskia_raster_surface_t* surface);
/// Copies the pixels out as RGBA_8888 unpremul into `dst` (`row_bytes` per row).
bool cskia_raster_surface_read_pixels(cskia_raster_surface_t* surface, void* dst, size_t row_bytes);
/// SkSurface::makeImageSnapshot — one new reference.
cskia_image_t* cskia_raster_surface_make_image_snapshot(cskia_raster_surface_t* surface);

#ifdef __cplusplus
}
#endif

#endif /* CSKIA_API_H */
