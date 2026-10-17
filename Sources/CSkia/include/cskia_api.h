//
//  cskia_api.h
//  CSkia — plain-C mirror of Skia's core drawing API (m132), one handle per
//  Skia class: SkCanvas, SkPaint, SkPath, SkFont, SkTypeface, SkShader,
//  SkPathEffect, SkImage, SkCodec, SkSVGDOM, SkTextBlob, SkPathMeasure,
//  SkData, SkFontStyleSet, plus a raster SkSurface.
//
//  Ownership follows Skia's own:
//    * SkCanvas is borrowed — it belongs to the surface it came from.
//    * SkPaint / SkPath / SkFont are values in Skia; here they are heap
//      copies the caller owns: `*_new` / `*_copy` → `*_delete`.
//    * SkTypeface / SkShader / SkPathEffect / SkImage / SkSVGDOM are ref-counted in
//      Skia; every `*_make*` returns one reference the caller owns, given
//      back with `*_unref`. A setter that stores one (`paint_set_shader`,
//      `font_set_typeface`) takes its own reference.
//    * SkCodec is uniquely owned in Skia; `codec_make_from_data` hands it to
//      the caller, given back with `codec_delete`. So are SkPathMeasure,
//      SkOpBuilder, SkPath::Iter and SkTextBlobBuilder (`*_new` → `*_delete`).
//    * SkTextBlob / SkData / SkFontStyleSet are ref-counted, as above.
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
typedef struct cskia_codec_t       cskia_codec_t;
typedef struct cskia_raster_surface_t cskia_raster_surface_t;
typedef struct cskia_svg_dom_t     cskia_svg_dom_t;
typedef struct cskia_path_iter_t   cskia_path_iter_t;
typedef struct cskia_path_measure_t cskia_path_measure_t;
typedef struct cskia_op_builder_t  cskia_op_builder_t;
typedef struct cskia_text_blob_t   cskia_text_blob_t;
typedef struct cskia_text_blob_builder_t cskia_text_blob_builder_t;
typedef struct cskia_data_t        cskia_data_t;
typedef struct cskia_font_style_set_t cskia_font_style_set_t;

/// SkSamplingOptions: `filter` 0 nearest, 1 linear; `mipmap` 0 none,
/// 1 nearest, 2 linear. `cubic` uses SkCubicResampler{B, C} instead (filter
/// and mipmap ignored).
typedef struct cskia_sampling {
    int32_t filter;
    int32_t mipmap;
    bool    cubic;
    float   cubic_b, cubic_c;
} cskia_sampling;

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
/// `src` of the image into `dst`. `constraint`: 0 strict (sample only
/// inside `src`), 1 fast. `paint` may be NULL.
void cskia_canvas_draw_image_rect_src(cskia_canvas_t* canvas, const cskia_image_t* image, const cskia_rect* src, const cskia_rect* dst, const cskia_sampling* sampling, const cskia_paint_t* paint, int32_t constraint);
/// Nine-patch: `center` (an integer rect of the image) stretches, the
/// corners keep their size. `filter` 0 nearest, 1 linear. `paint` may be NULL.
void cskia_canvas_draw_image_nine(cskia_canvas_t* canvas, const cskia_image_t* image, int32_t cx, int32_t cy, int32_t cw, int32_t ch, const cskia_rect* dst, int32_t filter, const cskia_paint_t* paint);
void cskia_canvas_draw_text_blob(cskia_canvas_t* canvas, const cskia_text_blob_t* blob, float x, float y, const cskia_paint_t* paint);
/// `count` glyphs at their own (x, y) `positions`, offset by `origin`.
void cskia_canvas_draw_glyphs(cskia_canvas_t* canvas, const uint16_t* glyphs, const float* positions, int32_t count, float origin_x, float origin_y, const cskia_font_t* font, const cskia_paint_t* paint);
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

// Relative to the last point.
void cskia_path_r_move_to(cskia_path_t* path, float dx, float dy);
void cskia_path_r_line_to(cskia_path_t* path, float dx, float dy);
void cskia_path_r_quad_to(cskia_path_t* path, float dx1, float dy1, float dx2, float dy2);
void cskia_path_r_conic_to(cskia_path_t* path, float dx1, float dy1, float dx2, float dy2, float weight);
void cskia_path_r_cubic_to(cskia_path_t* path, float dx1, float dy1, float dx2, float dy2, float dx3, float dy3);

/// arcTo(x1, y1, x2, y2, radius): an arc tangent to the lines from the last
/// point to (x1, y1) and from there to (x2, y2).
void cskia_path_arc_to_tangent(cskia_path_t* path, float x1, float y1, float x2, float y2, float radius);
/// arcTo(oval, startAngle, sweepAngle, forceMoveTo), angles in degrees.
void cskia_path_arc_to_oval(cskia_path_t* path, float x, float y, float w, float h, float start_angle, float sweep_angle, bool force_move_to);
/// SVG's arc: arcTo(rx, ry, xAxisRotate, largeArc, sweep, x, y); `direction`
/// as SkPathDirection (0 cw, 1 ccw). `relative`: rArcTo, (x, y) from the last point.
void cskia_path_arc_to_svg(cskia_path_t* path, float rx, float ry, float x_axis_rotate, bool large_arc, int32_t direction, float x, float y, bool relative);

/// `radii` is 4 × (x, y), SkRRect's corner order: upper-left, upper-right,
/// lower-right, lower-left.
void cskia_path_add_rrect_radii(cskia_path_t* path, float x, float y, float w, float h, const float* radii, int32_t direction);
/// `points` is `count` × (x, y).
void cskia_path_add_poly(cskia_path_t* path, const float* points, int32_t count, bool close);
/// `mode`: 0 append (a new contour), 1 extend (joined to the last contour).
void cskia_path_add_path_matrix(cskia_path_t* path, const cskia_path_t* src, const cskia_matrix* matrix, int32_t mode);
/// `src`'s contours in reverse order, each reversed.
void cskia_path_reverse_add_path(cskia_path_t* path, const cskia_path_t* src);

void cskia_path_toggle_inverse_fill_type(cskia_path_t* path);
bool cskia_path_is_inverse_fill_type(const cskia_path_t* path);

/// False for an index out of range.
bool    cskia_path_get_point(const cskia_path_t* path, int32_t index, float* x, float* y);
/// The points as (x, y) pairs, up to `max_points`; returns how many the path has.
int32_t cskia_path_get_points(const cskia_path_t* path, float* xy, int32_t max_points);
/// False for an empty path.
bool    cskia_path_get_last_pt(const cskia_path_t* path, float* x, float* y);
void    cskia_path_set_last_pt(cskia_path_t* path, float x, float y);

/// Whether the path is that shape; `out` (may be NULL) gets its rect / the
/// oval's bounds / the line's two points (x0, y0, x1, y1).
bool cskia_path_is_rect(const cskia_path_t* path, cskia_rect* out);
bool cskia_path_is_oval(const cskia_path_t* path, cskia_rect* out);
bool cskia_path_is_line(const cskia_path_t* path, float* line);
bool cskia_path_is_convex(const cskia_path_t* path);
bool cskia_path_is_finite(const cskia_path_t* path);
bool cskia_path_is_last_contour_closed(const cskia_path_t* path);
bool cskia_path_conservatively_contains_rect(const cskia_path_t* path, float x, float y, float w, float h);

/// Same verbs and as many points, so `interpolate` works.
bool cskia_path_is_interpolatable(const cskia_path_t* path, const cskia_path_t* other);
/// `out` = path × weight + ending × (1 − weight); false (out unchanged) when
/// they aren't interpolatable.
bool cskia_path_interpolate(const cskia_path_t* path, const cskia_path_t* ending, float weight, cskia_path_t* out);

/// writeToMemory: the bytes it takes when `buffer` is NULL, else writes
/// them (`buffer` must hold that many) and returns the count.
size_t cskia_path_write_to_memory(const cskia_path_t* path, void* buffer);
/// SkPath::ReadFromMemory; NULL when the bytes aren't a written path.
cskia_path_t* cskia_path_read_from_memory(const void* buffer, size_t length);

/// SkParsePath::FromSVGString — an SVG path's `d`; NULL when it doesn't parse.
cskia_path_t* cskia_path_make_from_svg_string(const char* svg);
/// SkParsePath::ToSVGString (absolute or relative commands). Copies it
/// (NUL-terminated, truncated to `capacity`); returns its full length.
size_t cskia_path_to_svg_string(const cskia_path_t* path, bool relative, char* buffer, size_t capacity);

// MARK: - SkPath::Iter

/// Verbs: 0 move, 1 line, 2 quad, 3 conic, 4 cubic, 5 close, 6 done.
cskia_path_iter_t* cskia_path_iter_new(const cskia_path_t* path, bool force_close);
void cskia_path_iter_delete(cskia_path_iter_t* iter);
/// The next verb; `points` gets up to 4 × (x, y) — a move its point, the
/// rest their start point then the others — and `conic_weight` (may be
/// NULL) the weight of a conic. The path must outlive the iterator.
int32_t cskia_path_iter_next(cskia_path_iter_t* iter, float* points, float* conic_weight);

// MARK: - PathOps (SkPathOps.h)

/// `op`: 0 difference, 1 intersect, 2 union, 3 xor, 4 reverse difference.
/// False (out unchanged) when it can't be computed.
bool cskia_path_op(const cskia_path_t* one, const cskia_path_t* two, int32_t op, cskia_path_t* out);
bool cskia_path_simplify(const cskia_path_t* path, cskia_path_t* out);
/// The same area, with a winding fill type.
bool cskia_path_as_winding(const cskia_path_t* path, cskia_path_t* out);
/// SkOpBuilder: `add` paths with an op each, `resolve` them all at once.
cskia_op_builder_t* cskia_op_builder_new(void);
void cskia_op_builder_delete(cskia_op_builder_t* builder);
void cskia_op_builder_add(cskia_op_builder_t* builder, const cskia_path_t* path, int32_t op);
bool cskia_op_builder_resolve(cskia_op_builder_t* builder, cskia_path_t* out);

// MARK: - SkPathMeasure

/// Over a copy of `path`, contour by contour from the first.
cskia_path_measure_t* cskia_path_measure_new(const cskia_path_t* path, bool force_closed, float res_scale);
void  cskia_path_measure_delete(cskia_path_measure_t* measure);
/// Length of the current contour.
float cskia_path_measure_get_length(cskia_path_measure_t* measure);
/// Position and unit tangent at `distance` along the contour (pinned to it).
bool  cskia_path_measure_get_pos_tan(cskia_path_measure_t* measure, float distance, float* position, float* tangent);
/// The piece from `start` to `stop` appended to `dst`.
bool  cskia_path_measure_get_segment(cskia_path_measure_t* measure, float start, float stop, cskia_path_t* dst, bool start_with_move_to);
bool  cskia_path_measure_is_closed(cskia_path_measure_t* measure);
/// On to the next contour; false when there is none.
bool  cskia_path_measure_next_contour(cskia_path_measure_t* measure);

// MARK: - SkShader (SkGradientShader / SkShaders)
//
// `colors` is `count` × (r, g, b, a) floats; `positions` is `count` floats
// in 0…1, or NULL for evenly spaced.

cskia_shader_t* cskia_shader_make_linear_gradient(float x0, float y0, float x1, float y1, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_radial_gradient(float cx, float cy, float radius, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_two_point_conical_gradient(float sx, float sy, float start_radius, float ex, float ey, float end_radius, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_sweep_gradient(float cx, float cy, float start_angle, float end_angle, const float* colors, const float* positions, int32_t count, int32_t tile_mode);
cskia_shader_t* cskia_shader_make_color(float r, float g, float b, float a);
/// SkImage::makeShader — the image tiled per `tile_x` / `tile_y`
/// (SkTileMode), `matrix` (may be NULL) mapping it.
cskia_shader_t* cskia_shader_make_image(const cskia_image_t* image, int32_t tile_x, int32_t tile_y, const cskia_sampling* sampling, const cskia_matrix* matrix);
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
/// SkTypeface::fontStyle.
void cskia_typeface_get_style(const cskia_typeface_t* typeface, int32_t* weight, int32_t* width, int32_t* slant);
bool cskia_typeface_is_bold(const cskia_typeface_t* typeface);
bool cskia_typeface_is_italic(const cskia_typeface_t* typeface);
bool cskia_typeface_is_fixed_pitch(const cskia_typeface_t* typeface);
int32_t cskia_typeface_get_units_per_em(const cskia_typeface_t* typeface);
/// 0 when the face has no glyph for it.
uint16_t cskia_typeface_unichar_to_glyph(const cskia_typeface_t* typeface, int32_t unichar);
/// The sfnt table tags into `tags` (up to `max_tags`); returns how many.
int32_t cskia_typeface_get_table_tags(const cskia_typeface_t* typeface, uint32_t* tags, int32_t max_tags);
/// The table's size when `data` is NULL, else copies up to `length` bytes
/// from `offset` and returns how many.
size_t cskia_typeface_get_table_data(const cskia_typeface_t* typeface, uint32_t tag, size_t offset, size_t length, void* data);
void cskia_typeface_ref(cskia_typeface_t* typeface);
void cskia_typeface_unref(cskia_typeface_t* typeface);

// MARK: - SkFontMgr (the platform's)

int32_t cskia_font_mgr_count_families(void);
/// As cskia_typeface_get_family_name, for family `index`.
size_t cskia_font_mgr_get_family_name(int32_t index, char* buffer, size_t capacity);
/// The family's faces; never NULL (empty when there's no such family).
cskia_font_style_set_t* cskia_font_mgr_match_family(const char* family);
/// A face in `family` (may be NULL) near the style with a glyph for
/// `unichar` — fallback for a character. `bcp47` is `bcp47_count` language
/// tags, most preferred last. NULL when none has it.
cskia_typeface_t* cskia_font_mgr_match_family_style_character(const char* family, int32_t weight, int32_t width, int32_t slant, const char* const* bcp47, int32_t bcp47_count, int32_t unichar);

// MARK: - SkFontStyleSet

int32_t cskia_font_style_set_count(cskia_font_style_set_t* set);
/// Face `index`'s style, and its style name (as cskia_typeface_get_family_name).
size_t cskia_font_style_set_get_style(cskia_font_style_set_t* set, int32_t index, int32_t* weight, int32_t* width, int32_t* slant, char* name, size_t capacity);
cskia_typeface_t* cskia_font_style_set_create_typeface(cskia_font_style_set_t* set, int32_t index);
cskia_typeface_t* cskia_font_style_set_match_style(cskia_font_style_set_t* set, int32_t weight, int32_t width, int32_t slant);
void cskia_font_style_set_unref(cskia_font_style_set_t* set);

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

bool    cskia_font_is_embolden(const cskia_font_t* font);
bool    cskia_font_is_subpixel(const cskia_font_t* font);
bool    cskia_font_is_linear_metrics(const cskia_font_t* font);
bool    cskia_font_is_baseline_snap(const cskia_font_t* font);
void    cskia_font_set_force_auto_hinting(cskia_font_t* font, bool force);
bool    cskia_font_is_force_auto_hinting(const cskia_font_t* font);
void    cskia_font_set_embedded_bitmaps(cskia_font_t* font, bool embedded);
bool    cskia_font_is_embedded_bitmaps(const cskia_font_t* font);
int32_t cskia_font_get_edging(const cskia_font_t* font);
int32_t cskia_font_get_hinting(const cskia_font_t* font);

uint16_t cskia_font_unichar_to_glyph(const cskia_font_t* font, int32_t unichar);
void     cskia_font_unichars_to_glyphs(const cskia_font_t* font, const int32_t* unichars, int32_t count, uint16_t* glyphs);
/// Per glyph: advance into `widths` and ink box into `bounds` (either may
/// be NULL), as `paint` (may be NULL) would draw it.
void     cskia_font_get_widths_bounds(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float* widths, cskia_rect* bounds, const cskia_paint_t* paint);
/// Glyph origins laid one after another from (origin_x, origin_y), as
/// (x, y) pairs into `positions`.
void     cskia_font_get_pos(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float origin_x, float origin_y, float* positions);
void     cskia_font_get_x_pos(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float origin, float* xpos);
/// The glyph's outline into `out` (replacing it); false for a glyph with
/// none (a bitmap glyph).
bool     cskia_font_get_path(const cskia_font_t* font, uint16_t glyph, cskia_path_t* out);

// MARK: - SkTextBlob

/// UTF-8 laid out in one run with `font`, from (0, 0). NULL for no glyphs.
cskia_text_blob_t* cskia_text_blob_make_from_text(const char* utf8, size_t byte_length, const cskia_font_t* font);
/// Glyphs at their own (x, y) positions.
cskia_text_blob_t* cskia_text_blob_make_from_pos_glyphs(const uint16_t* glyphs, const float* positions, int32_t count, const cskia_font_t* font);
/// Glyphs at their own x on one baseline `y`.
cskia_text_blob_t* cskia_text_blob_make_from_pos_h_glyphs(const uint16_t* glyphs, const float* xpos, int32_t count, float y, const cskia_font_t* font);
/// Conservative bounds of everything in it.
void cskia_text_blob_get_bounds(const cskia_text_blob_t* blob, cskia_rect* out);
/// Where the glyphs cross the band `upper`…`lower` (underlines that skip
/// descenders): pairs of x into `intervals` (up to `max`); returns how many
/// values there are. `paint` may be NULL.
int32_t cskia_text_blob_get_intercepts(const cskia_text_blob_t* blob, float upper, float lower, float* intervals, int32_t max, const cskia_paint_t* paint);
void cskia_text_blob_ref(cskia_text_blob_t* blob);
void cskia_text_blob_unref(cskia_text_blob_t* blob);

// MARK: - SkTextBlobBuilder

cskia_text_blob_builder_t* cskia_text_blob_builder_new(void);
void cskia_text_blob_builder_delete(cskia_text_blob_builder_t* builder);
/// A run of glyphs laid one after another from (x, y).
void cskia_text_blob_builder_add_run(cskia_text_blob_builder_t* builder, const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float x, float y);
/// A run of glyphs at their own x, on baseline `y`.
void cskia_text_blob_builder_add_run_pos_h(cskia_text_blob_builder_t* builder, const cskia_font_t* font, const uint16_t* glyphs, const float* xpos, int32_t count, float y);
/// A run of glyphs at their own (x, y).
void cskia_text_blob_builder_add_run_pos(cskia_text_blob_builder_t* builder, const cskia_font_t* font, const uint16_t* glyphs, const float* positions, int32_t count);
/// The blob of the runs so far (the builder starts empty again); NULL for none.
cskia_text_blob_t* cskia_text_blob_builder_make(cskia_text_blob_builder_t* builder);

// MARK: - SkData

const void* cskia_data_get_bytes(const cskia_data_t* data);
size_t cskia_data_get_size(const cskia_data_t* data);
void cskia_data_unref(cskia_data_t* data);

// MARK: - SkImage (SkImages)

/// `color_type`: 0 RGBA_8888, 1 BGRA_8888. `alpha_type`: SkAlphaType
/// (1 opaque, 2 premul, 3 unpremul). The pixels are copied.
cskia_image_t* cskia_image_make_raster_copy(const void* pixels, int32_t width, int32_t height, size_t row_bytes, int32_t color_type, int32_t alpha_type);
int32_t cskia_image_get_width(const cskia_image_t* image);
int32_t cskia_image_get_height(const cskia_image_t* image);
/// SkImages::DeferredFromEncodedData over a copy of the bytes (PNG, …),
/// decoded when first drawn. NULL when no decoder reads it.
cskia_image_t* cskia_image_make_from_encoded(const void* data, size_t size);
int32_t cskia_image_get_color_type(const cskia_image_t* image);
int32_t cskia_image_get_alpha_type(const cskia_image_t* image);
bool cskia_image_is_opaque(const cskia_image_t* image);
/// Copies the `width` × `height` pixels at (src_x, src_y) into `pixels`
/// (`row_bytes` per row), converted to `color_type` / `alpha_type`.
bool cskia_image_read_pixels(const cskia_image_t* image, void* pixels, size_t row_bytes, int32_t width, int32_t height, int32_t color_type, int32_t alpha_type, int32_t src_x, int32_t src_y);
/// The pixels in place, for a raster image: false for one not in memory.
/// Borrowed — valid as long as the image.
bool cskia_image_peek_pixels(const cskia_image_t* image, const void** pixels, size_t* row_bytes);
/// The pixels in (x, y, w, h), as a new image; NULL for a rect outside it.
cskia_image_t* cskia_image_make_subset(const cskia_image_t* image, int32_t x, int32_t y, int32_t w, int32_t h);
/// Decoded into memory (a lazy or GPU image); the same image if it already is.
cskia_image_t* cskia_image_make_raster_image(const cskia_image_t* image);
/// Encoded: `format` 0 PNG, 1 JPEG, 2 WebP; `quality` 0…100 (JPEG, WebP;
/// WebP 100 is lossless). NULL when it can't be.
cskia_data_t* cskia_image_encode(const cskia_image_t* image, int32_t format, int32_t quality);
void cskia_image_ref(cskia_image_t* image);
void cskia_image_unref(cskia_image_t* image);

// MARK: - SkCodec

/// SkCodec::MakeFromData over a copy of `size` bytes of `data`, with the
/// decoders this Skia build was compiled with (PNG on every platform).
/// NULL when none of them reads it.
cskia_codec_t* cskia_codec_make_from_data(const void* data, size_t size);
void cskia_codec_delete(cskia_codec_t* codec);
int32_t cskia_codec_get_width(const cskia_codec_t* codec);
int32_t cskia_codec_get_height(const cskia_codec_t* codec);
/// SkCodec::getPixels — the whole image into `pixels`, `row_bytes` per row,
/// `color_type` / `alpha_type` as for cskia_image_make_raster_copy. False
/// unless every row decoded.
bool cskia_codec_get_pixels(cskia_codec_t* codec, void* pixels, size_t row_bytes, int32_t color_type, int32_t alpha_type);

// MARK: - SkSVGDOM (Skia's SVG module)

/// SkSVGDOM::Builder().make over a copy of the document's `size` bytes,
/// <text> laid out with the platform's fonts. One new reference; NULL when
/// it doesn't parse.
cskia_svg_dom_t* cskia_svg_dom_make_from_data(const void* data, size_t size);
void cskia_svg_dom_unref(cskia_svg_dom_t* dom);
/// getRoot()->intrinsicSize: the root <svg>'s width and height in pixels,
/// 0 for one given in percent (the default) — then the viewBox says the size.
void cskia_svg_dom_get_intrinsic_size(const cskia_svg_dom_t* dom, float* width, float* height);
/// getRoot()->getViewBox(): false when the root <svg> has none.
bool cskia_svg_dom_get_view_box(const cskia_svg_dom_t* dom, float* x, float* y, float* width, float* height);
/// SkSVGDOM::setContainerSize — the viewport `render` fills.
void cskia_svg_dom_set_container_size(cskia_svg_dom_t* dom, float width, float height);
/// SkSVGDOM::render into `canvas`.
void cskia_svg_dom_render(const cskia_svg_dom_t* dom, cskia_canvas_t* canvas);

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
