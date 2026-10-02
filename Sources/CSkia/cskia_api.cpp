//
//  cskia_api.cpp
//  CSkia — implementation of cskia_api.h against Skia's C++ API (m132).
//
#include "cskia_api.h"

#include "include/core/SkCanvas.h"
#include "include/core/SkBlurTypes.h"
#include "include/core/SkColor.h"
#include "include/core/SkData.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMetrics.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkImage.h"
#include "include/core/SkImageInfo.h"
#include "include/core/SkMaskFilter.h"
#include "include/core/SkMatrix.h"
#include "include/core/SkPaint.h"
#include "include/core/SkPath.h"
#include "include/core/SkPathEffect.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkRRect.h"
#include "include/core/SkRect.h"
#include "include/core/SkSamplingOptions.h"
#include "include/core/SkShader.h"
#include "include/core/SkString.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "include/effects/SkCornerPathEffect.h"
#include "include/effects/SkDashPathEffect.h"
#include "include/effects/SkGradientShader.h"
#if defined(__APPLE__)
#include "include/ports/SkFontMgr_mac_ct.h"
#elif defined(__ANDROID__)
#include "include/ports/SkFontMgr_android.h"
#include "include/ports/SkFontScanner_FreeType.h"
#else
#include "include/ports/SkFontMgr_fontconfig.h"
#include "include/ports/SkFontScanner_FreeType.h"
#endif

#include <algorithm>
#include <cstring>
#include <vector>

// MARK: - Handle casts
//
// The C handles are the Skia objects themselves; only the raster surface
// carries a wrapper (it has to hold the sk_sp).

struct cskia_raster_surface_t {
    sk_sp<SkSurface> surface;
};

static SkCanvas*           as_canvas(cskia_canvas_t* c)              { return reinterpret_cast<SkCanvas*>(c); }
static SkPaint*            as_paint(cskia_paint_t* p)                { return reinterpret_cast<SkPaint*>(p); }
static const SkPaint*      as_paint(const cskia_paint_t* p)          { return reinterpret_cast<const SkPaint*>(p); }
static SkPath*             as_path(cskia_path_t* p)                  { return reinterpret_cast<SkPath*>(p); }
static const SkPath*       as_path(const cskia_path_t* p)            { return reinterpret_cast<const SkPath*>(p); }
static SkFont*             as_font(cskia_font_t* f)                  { return reinterpret_cast<SkFont*>(f); }
static const SkFont*       as_font(const cskia_font_t* f)            { return reinterpret_cast<const SkFont*>(f); }
static SkTypeface*         as_typeface(cskia_typeface_t* t)          { return reinterpret_cast<SkTypeface*>(t); }
static const SkTypeface*   as_typeface(const cskia_typeface_t* t)    { return reinterpret_cast<const SkTypeface*>(t); }
static SkShader*           as_shader(cskia_shader_t* s)              { return reinterpret_cast<SkShader*>(s); }
static SkPathEffect*       as_effect(cskia_path_effect_t* e)         { return reinterpret_cast<SkPathEffect*>(e); }
static const SkImage*      as_image(const cskia_image_t* i)          { return reinterpret_cast<const SkImage*>(i); }
static SkImage*            as_image(cskia_image_t* i)                { return reinterpret_cast<SkImage*>(i); }

/// Hand one reference out across the C boundary.
template <typename T, typename H>
static H* release_to(sk_sp<T> object) { return reinterpret_cast<H*>(object.release()); }

/// A borrowed handle as an sk_sp holding its own new reference.
template <typename T>
static sk_sp<T> retain(T* object) { return sk_ref_sp(object); }

template <typename E>
static E clamp_enum(int32_t value, int32_t last) {
    return static_cast<E>(std::clamp<int32_t>(value, 0, last));
}

static SkRect xywh(float x, float y, float w, float h) { return SkRect::MakeXYWH(x, y, w, h); }

static void write_rect(const SkRect& r, cskia_rect* out) {
    if (out) { *out = cskia_rect{r.x(), r.y(), r.width(), r.height()}; }
}

static SkMatrix to_matrix(const cskia_matrix* m) {
    return SkMatrix::MakeAll(m->scale_x, m->skew_x,  m->trans_x,
                             m->skew_y,  m->scale_y, m->trans_y,
                             m->persp_0, m->persp_1, m->persp_2);
}

static void write_matrix(const SkMatrix& m, cskia_matrix* out) {
    float v[9];
    m.get9(v);
    *out = cskia_matrix{v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8]};
}

static SkClipOp       clip_op(int32_t v)      { return clamp_enum<SkClipOp>(v, 1); }
static SkBlendMode    blend_mode(int32_t v)   { return clamp_enum<SkBlendMode>(v, static_cast<int32_t>(SkBlendMode::kLastMode)); }
static SkPathDirection direction(int32_t v)   { return clamp_enum<SkPathDirection>(v, 1); }
static SkTileMode     tile_mode(int32_t v)    { return clamp_enum<SkTileMode>(v, static_cast<int32_t>(SkTileMode::kLastTileMode)); }

static SkSamplingOptions linear_sampling() { return SkSamplingOptions(SkFilterMode::kLinear); }

/// `count` × RGBA floats as SkColor4f.
static std::vector<SkColor4f> colors4f(const float* rgba, int32_t count) {
    std::vector<SkColor4f> out(count > 0 ? count : 0);
    for (int32_t i = 0; i < count; ++i) {
        out[i] = SkColor4f{rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2], rgba[i * 4 + 3]};
    }
    return out;
}

/// The platform font manager, made once. Typefaces made from data or files
/// go through it, so they rasterize with the same scaler as system faces.
static sk_sp<SkFontMgr> font_mgr() {
    static sk_sp<SkFontMgr> mgr = [] {
#if defined(__APPLE__)
        return SkFontMgr_New_CoreText(nullptr);
#elif defined(__ANDROID__)
        return SkFontMgr_New_Android(nullptr, SkFontScanner_Make_FreeType());
#else
        return SkFontMgr_New_FontConfig(nullptr, SkFontScanner_Make_FreeType());
#endif
    }();
    return mgr;
}

extern "C" {

// MARK: - SkCanvas

int32_t cskia_canvas_save(cskia_canvas_t* canvas) { return as_canvas(canvas)->save(); }

int32_t cskia_canvas_save_layer(cskia_canvas_t* canvas, const cskia_rect* bounds, const cskia_paint_t* paint) {
    SkRect rect;
    if (bounds) { rect = xywh(bounds->x, bounds->y, bounds->w, bounds->h); }
    return as_canvas(canvas)->saveLayer(bounds ? &rect : nullptr, as_paint(paint));
}

int32_t cskia_canvas_save_layer_alphaf(cskia_canvas_t* canvas, const cskia_rect* bounds, float alpha) {
    SkRect rect;
    if (bounds) { rect = xywh(bounds->x, bounds->y, bounds->w, bounds->h); }
    return as_canvas(canvas)->saveLayerAlphaf(bounds ? &rect : nullptr, alpha);
}

void    cskia_canvas_restore(cskia_canvas_t* canvas) { as_canvas(canvas)->restore(); }
void    cskia_canvas_restore_to_count(cskia_canvas_t* canvas, int32_t count) { as_canvas(canvas)->restoreToCount(count); }
int32_t cskia_canvas_get_save_count(cskia_canvas_t* canvas) { return as_canvas(canvas)->getSaveCount(); }

void cskia_canvas_translate(cskia_canvas_t* canvas, float dx, float dy) { as_canvas(canvas)->translate(dx, dy); }
void cskia_canvas_scale(cskia_canvas_t* canvas, float sx, float sy) { as_canvas(canvas)->scale(sx, sy); }
void cskia_canvas_rotate(cskia_canvas_t* canvas, float degrees) { as_canvas(canvas)->rotate(degrees); }
void cskia_canvas_rotate_about(cskia_canvas_t* canvas, float degrees, float px, float py) { as_canvas(canvas)->rotate(degrees, px, py); }
void cskia_canvas_skew(cskia_canvas_t* canvas, float sx, float sy) { as_canvas(canvas)->skew(sx, sy); }
void cskia_canvas_concat(cskia_canvas_t* canvas, const cskia_matrix* matrix) { as_canvas(canvas)->concat(to_matrix(matrix)); }
void cskia_canvas_set_matrix(cskia_canvas_t* canvas, const cskia_matrix* matrix) { as_canvas(canvas)->setMatrix(to_matrix(matrix)); }
void cskia_canvas_reset_matrix(cskia_canvas_t* canvas) { as_canvas(canvas)->resetMatrix(); }
void cskia_canvas_get_total_matrix(cskia_canvas_t* canvas, cskia_matrix* out) { write_matrix(as_canvas(canvas)->getTotalMatrix(), out); }

void cskia_canvas_clip_rect(cskia_canvas_t* canvas, float x, float y, float w, float h, int32_t op, bool anti_alias) {
    as_canvas(canvas)->clipRect(xywh(x, y, w, h), clip_op(op), anti_alias);
}

void cskia_canvas_clip_rrect(cskia_canvas_t* canvas, float x, float y, float w, float h, float rx, float ry, int32_t op, bool anti_alias) {
    as_canvas(canvas)->clipRRect(SkRRect::MakeRectXY(xywh(x, y, w, h), rx, ry), clip_op(op), anti_alias);
}

void cskia_canvas_clip_path(cskia_canvas_t* canvas, const cskia_path_t* path, int32_t op, bool anti_alias) {
    as_canvas(canvas)->clipPath(*as_path(path), clip_op(op), anti_alias);
}

void cskia_canvas_clear_color4f(cskia_canvas_t* canvas, float r, float g, float b, float a) {
    as_canvas(canvas)->clear(SkColor4f{r, g, b, a});
}

void cskia_canvas_draw_color4f(cskia_canvas_t* canvas, float r, float g, float b, float a, int32_t mode) {
    as_canvas(canvas)->drawColor(SkColor4f{r, g, b, a}, blend_mode(mode));
}

void cskia_canvas_draw_paint(cskia_canvas_t* canvas, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawPaint(*as_paint(paint));
}

void cskia_canvas_draw_rect_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawRect(xywh(x, y, w, h), *as_paint(paint));
}

void cskia_canvas_draw_rrect_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, float rx, float ry, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawRRect(SkRRect::MakeRectXY(xywh(x, y, w, h), rx, ry), *as_paint(paint));
}

void cskia_canvas_draw_oval_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawOval(xywh(x, y, w, h), *as_paint(paint));
}

void cskia_canvas_draw_circle_at(cskia_canvas_t* canvas, float cx, float cy, float radius, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawCircle(cx, cy, radius, *as_paint(paint));
}

void cskia_canvas_draw_arc_xywh(cskia_canvas_t* canvas, float x, float y, float w, float h, float start_angle, float sweep_angle, bool use_center, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawArc(xywh(x, y, w, h), start_angle, sweep_angle, use_center, *as_paint(paint));
}

void cskia_canvas_draw_line_points(cskia_canvas_t* canvas, float x0, float y0, float x1, float y1, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawLine(x0, y0, x1, y1, *as_paint(paint));
}

void cskia_canvas_draw_point(cskia_canvas_t* canvas, float x, float y, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawPoint(x, y, *as_paint(paint));
}

void cskia_canvas_draw_path(cskia_canvas_t* canvas, const cskia_path_t* path, const cskia_paint_t* paint) {
    as_canvas(canvas)->drawPath(*as_path(path), *as_paint(paint));
}

void cskia_canvas_draw_image(cskia_canvas_t* canvas, const cskia_image_t* image, float x, float y, const cskia_paint_t* paint) {
    if (!image) { return; }
    as_canvas(canvas)->drawImage(as_image(image), x, y, linear_sampling(), as_paint(paint));
}

void cskia_canvas_draw_image_rect(cskia_canvas_t* canvas, const cskia_image_t* image, float x, float y, float w, float h, const cskia_paint_t* paint) {
    if (!image) { return; }
    as_canvas(canvas)->drawImageRect(as_image(image), xywh(x, y, w, h), linear_sampling(), as_paint(paint));
}

void cskia_canvas_draw_simple_text(cskia_canvas_t* canvas, const char* utf8, size_t byte_length, float x, float y, const cskia_font_t* font, const cskia_paint_t* paint) {
    if (!utf8 || byte_length == 0) { return; }
    as_canvas(canvas)->drawSimpleText(utf8, byte_length, SkTextEncoding::kUTF8, x, y, *as_font(font), *as_paint(paint));
}

// MARK: - SkPaint

cskia_paint_t* cskia_paint_new(void) { return reinterpret_cast<cskia_paint_t*>(new SkPaint()); }
cskia_paint_t* cskia_paint_copy(const cskia_paint_t* paint) { return reinterpret_cast<cskia_paint_t*>(new SkPaint(*as_paint(paint))); }
void cskia_paint_delete(cskia_paint_t* paint) { delete as_paint(paint); }
void cskia_paint_reset(cskia_paint_t* paint) { as_paint(paint)->reset(); }

void cskia_paint_set_anti_alias(cskia_paint_t* paint, bool aa) { as_paint(paint)->setAntiAlias(aa); }
bool cskia_paint_is_anti_alias(const cskia_paint_t* paint) { return as_paint(paint)->isAntiAlias(); }
void cskia_paint_set_dither(cskia_paint_t* paint, bool dither) { as_paint(paint)->setDither(dither); }
bool cskia_paint_is_dither(const cskia_paint_t* paint) { return as_paint(paint)->isDither(); }

void     cskia_paint_set_color(cskia_paint_t* paint, uint32_t argb) { as_paint(paint)->setColor(argb); }
uint32_t cskia_paint_get_color(const cskia_paint_t* paint) { return as_paint(paint)->getColor(); }
void     cskia_paint_set_color4f(cskia_paint_t* paint, float r, float g, float b, float a) { as_paint(paint)->setColor4f(SkColor4f{r, g, b, a}); }
void     cskia_paint_get_color4f(const cskia_paint_t* paint, float* rgba) {
    SkColor4f c = as_paint(paint)->getColor4f();
    rgba[0] = c.fR; rgba[1] = c.fG; rgba[2] = c.fB; rgba[3] = c.fA;
}
void  cskia_paint_set_alphaf(cskia_paint_t* paint, float alpha) { as_paint(paint)->setAlphaf(alpha); }
float cskia_paint_get_alphaf(const cskia_paint_t* paint) { return as_paint(paint)->getAlphaf(); }

void    cskia_paint_set_style(cskia_paint_t* paint, int32_t style) { as_paint(paint)->setStyle(clamp_enum<SkPaint::Style>(style, 2)); }
int32_t cskia_paint_get_style(const cskia_paint_t* paint) { return static_cast<int32_t>(as_paint(paint)->getStyle()); }
void    cskia_paint_set_stroke_width(cskia_paint_t* paint, float width) { as_paint(paint)->setStrokeWidth(width); }
float   cskia_paint_get_stroke_width(const cskia_paint_t* paint) { return as_paint(paint)->getStrokeWidth(); }
void    cskia_paint_set_stroke_miter(cskia_paint_t* paint, float miter) { as_paint(paint)->setStrokeMiter(miter); }
float   cskia_paint_get_stroke_miter(const cskia_paint_t* paint) { return as_paint(paint)->getStrokeMiter(); }
void    cskia_paint_set_stroke_cap(cskia_paint_t* paint, int32_t cap) { as_paint(paint)->setStrokeCap(clamp_enum<SkPaint::Cap>(cap, SkPaint::kLast_Cap)); }
int32_t cskia_paint_get_stroke_cap(const cskia_paint_t* paint) { return static_cast<int32_t>(as_paint(paint)->getStrokeCap()); }
void    cskia_paint_set_stroke_join(cskia_paint_t* paint, int32_t join) { as_paint(paint)->setStrokeJoin(clamp_enum<SkPaint::Join>(join, SkPaint::kLast_Join)); }
int32_t cskia_paint_get_stroke_join(const cskia_paint_t* paint) { return static_cast<int32_t>(as_paint(paint)->getStrokeJoin()); }

void cskia_paint_set_shader(cskia_paint_t* paint, cskia_shader_t* shader) {
    as_paint(paint)->setShader(shader ? retain(as_shader(shader)) : nullptr);
}

void cskia_paint_set_path_effect(cskia_paint_t* paint, cskia_path_effect_t* effect) {
    as_paint(paint)->setPathEffect(effect ? retain(as_effect(effect)) : nullptr);
}

void    cskia_paint_set_blend_mode(cskia_paint_t* paint, int32_t mode) { as_paint(paint)->setBlendMode(blend_mode(mode)); }
int32_t cskia_paint_get_blend_mode(const cskia_paint_t* paint) {
    return static_cast<int32_t>(as_paint(paint)->getBlendMode_or(SkBlendMode::kSrcOver));
}

void cskia_paint_set_mask_filter_blur(cskia_paint_t* paint, int32_t blur_style, float sigma) {
    if (sigma <= 0) {
        as_paint(paint)->setMaskFilter(nullptr);
        return;
    }
    as_paint(paint)->setMaskFilter(SkMaskFilter::MakeBlur(clamp_enum<SkBlurStyle>(blur_style, kLastEnum_SkBlurStyle), sigma));
}

// MARK: - SkPath

cskia_path_t* cskia_path_new(void) { return reinterpret_cast<cskia_path_t*>(new SkPath()); }
cskia_path_t* cskia_path_copy(const cskia_path_t* path) { return reinterpret_cast<cskia_path_t*>(new SkPath(*as_path(path))); }
void cskia_path_delete(cskia_path_t* path) { delete as_path(path); }
void cskia_path_reset(cskia_path_t* path) { as_path(path)->reset(); }
void cskia_path_rewind(cskia_path_t* path) { as_path(path)->rewind(); }

void cskia_path_move_to(cskia_path_t* path, float x, float y) { as_path(path)->moveTo(x, y); }
void cskia_path_line_to(cskia_path_t* path, float x, float y) { as_path(path)->lineTo(x, y); }
void cskia_path_quad_to(cskia_path_t* path, float x1, float y1, float x2, float y2) { as_path(path)->quadTo(x1, y1, x2, y2); }
void cskia_path_conic_to(cskia_path_t* path, float x1, float y1, float x2, float y2, float weight) { as_path(path)->conicTo(x1, y1, x2, y2, weight); }
void cskia_path_cubic_to(cskia_path_t* path, float x1, float y1, float x2, float y2, float x3, float y3) { as_path(path)->cubicTo(x1, y1, x2, y2, x3, y3); }
void cskia_path_close(cskia_path_t* path) { as_path(path)->close(); }

void cskia_path_add_rect(cskia_path_t* path, float x, float y, float w, float h, int32_t dir) {
    as_path(path)->addRect(xywh(x, y, w, h), direction(dir));
}
void cskia_path_add_rrect(cskia_path_t* path, float x, float y, float w, float h, float rx, float ry, int32_t dir) {
    as_path(path)->addRRect(SkRRect::MakeRectXY(xywh(x, y, w, h), rx, ry), direction(dir));
}
void cskia_path_add_oval(cskia_path_t* path, float x, float y, float w, float h, int32_t dir) {
    as_path(path)->addOval(xywh(x, y, w, h), direction(dir));
}
void cskia_path_add_circle(cskia_path_t* path, float cx, float cy, float radius, int32_t dir) {
    as_path(path)->addCircle(cx, cy, radius, direction(dir));
}
void cskia_path_add_arc(cskia_path_t* path, float x, float y, float w, float h, float start_angle, float sweep_angle) {
    as_path(path)->addArc(xywh(x, y, w, h), start_angle, sweep_angle);
}
void cskia_path_add_path(cskia_path_t* path, const cskia_path_t* src, float dx, float dy) {
    as_path(path)->addPath(*as_path(src), dx, dy);
}

void    cskia_path_set_fill_type(cskia_path_t* path, int32_t fill_type) { as_path(path)->setFillType(clamp_enum<SkPathFillType>(fill_type, 3)); }
int32_t cskia_path_get_fill_type(const cskia_path_t* path) { return static_cast<int32_t>(as_path(path)->getFillType()); }
void    cskia_path_get_bounds(const cskia_path_t* path, cskia_rect* out) { write_rect(as_path(path)->getBounds(), out); }
void    cskia_path_compute_tight_bounds(const cskia_path_t* path, cskia_rect* out) { write_rect(as_path(path)->computeTightBounds(), out); }
bool    cskia_path_contains(const cskia_path_t* path, float x, float y) { return as_path(path)->contains(x, y); }
bool    cskia_path_is_empty(const cskia_path_t* path) { return as_path(path)->isEmpty(); }
int32_t cskia_path_count_points(const cskia_path_t* path) { return as_path(path)->countPoints(); }
int32_t cskia_path_count_verbs(const cskia_path_t* path) { return as_path(path)->countVerbs(); }
void    cskia_path_offset(cskia_path_t* path, float dx, float dy) { as_path(path)->offset(dx, dy); }
void    cskia_path_transform(cskia_path_t* path, const cskia_matrix* matrix) { as_path(path)->transform(to_matrix(matrix)); }

// MARK: - SkShader

cskia_shader_t* cskia_shader_make_linear_gradient(float x0, float y0, float x1, float y1, const float* colors, const float* positions, int32_t count, int32_t mode) {
    if (!colors || count < 1) { return nullptr; }
    const SkPoint pts[2] = {{x0, y0}, {x1, y1}};
    auto c = colors4f(colors, count);
    return release_to<SkShader, cskia_shader_t>(
        SkGradientShader::MakeLinear(pts, c.data(), nullptr, positions, count, tile_mode(mode)));
}

cskia_shader_t* cskia_shader_make_radial_gradient(float cx, float cy, float radius, const float* colors, const float* positions, int32_t count, int32_t mode) {
    if (!colors || count < 1) { return nullptr; }
    auto c = colors4f(colors, count);
    return release_to<SkShader, cskia_shader_t>(
        SkGradientShader::MakeRadial({cx, cy}, radius, c.data(), nullptr, positions, count, tile_mode(mode)));
}

cskia_shader_t* cskia_shader_make_two_point_conical_gradient(float sx, float sy, float start_radius, float ex, float ey, float end_radius, const float* colors, const float* positions, int32_t count, int32_t mode) {
    if (!colors || count < 1) { return nullptr; }
    auto c = colors4f(colors, count);
    return release_to<SkShader, cskia_shader_t>(
        SkGradientShader::MakeTwoPointConical({sx, sy}, start_radius, {ex, ey}, end_radius,
                                              c.data(), nullptr, positions, count, tile_mode(mode)));
}

cskia_shader_t* cskia_shader_make_sweep_gradient(float cx, float cy, float start_angle, float end_angle, const float* colors, const float* positions, int32_t count, int32_t mode) {
    if (!colors || count < 1) { return nullptr; }
    auto c = colors4f(colors, count);
    return release_to<SkShader, cskia_shader_t>(
        SkGradientShader::MakeSweep(cx, cy, c.data(), nullptr, positions, count, tile_mode(mode),
                                    start_angle, end_angle, 0, nullptr));
}

cskia_shader_t* cskia_shader_make_color(float r, float g, float b, float a) {
    return release_to<SkShader, cskia_shader_t>(SkShaders::Color(SkColor4f{r, g, b, a}, nullptr));
}

void cskia_shader_ref(cskia_shader_t* shader) { SkSafeRef(as_shader(shader)); }
void cskia_shader_unref(cskia_shader_t* shader) { SkSafeUnref(as_shader(shader)); }

// MARK: - SkPathEffect

cskia_path_effect_t* cskia_path_effect_make_dash(const float* intervals, int32_t count, float phase) {
    // Skia wants an even count of at least two.
    if (!intervals || count < 2 || count % 2 != 0) { return nullptr; }
    return release_to<SkPathEffect, cskia_path_effect_t>(SkDashPathEffect::Make({intervals, static_cast<size_t>(count)}, phase));
}

cskia_path_effect_t* cskia_path_effect_make_corner(float radius) {
    return release_to<SkPathEffect, cskia_path_effect_t>(SkCornerPathEffect::Make(radius));
}

void cskia_path_effect_ref(cskia_path_effect_t* effect) { SkSafeRef(as_effect(effect)); }
void cskia_path_effect_unref(cskia_path_effect_t* effect) { SkSafeUnref(as_effect(effect)); }

// MARK: - SkTypeface

cskia_typeface_t* cskia_typeface_make_from_data(const void* bytes, size_t length, int32_t ttc_index) {
    sk_sp<SkFontMgr> mgr = font_mgr();
    if (!mgr || !bytes || length == 0) { return nullptr; }
    return release_to<SkTypeface, cskia_typeface_t>(mgr->makeFromData(SkData::MakeWithCopy(bytes, length), ttc_index));
}

cskia_typeface_t* cskia_typeface_make_from_file(const char* path, int32_t ttc_index) {
    sk_sp<SkFontMgr> mgr = font_mgr();
    if (!mgr || !path) { return nullptr; }
    return release_to<SkTypeface, cskia_typeface_t>(mgr->makeFromFile(path, ttc_index));
}

cskia_typeface_t* cskia_typeface_match_family_style(const char* family, int32_t weight, int32_t width, int32_t slant) {
    sk_sp<SkFontMgr> mgr = font_mgr();
    if (!mgr) { return nullptr; }
    SkFontStyle style(weight, width, clamp_enum<SkFontStyle::Slant>(slant, 2));
    sk_sp<SkTypeface> match = mgr->matchFamilyStyle(family, style);
    if (!match) { match = mgr->legacyMakeTypeface(family, style); }
    return release_to<SkTypeface, cskia_typeface_t>(std::move(match));
}

size_t cskia_typeface_get_family_name(const cskia_typeface_t* typeface, char* buffer, size_t capacity) {
    if (!typeface) { return 0; }
    SkString name;
    as_typeface(typeface)->getFamilyName(&name);
    if (buffer && capacity > 0) {
        size_t n = std::min(name.size(), capacity - 1);
        std::memcpy(buffer, name.c_str(), n);
        buffer[n] = '\0';
    }
    return name.size();
}

int32_t cskia_typeface_count_glyphs(const cskia_typeface_t* typeface) {
    return typeface ? as_typeface(typeface)->countGlyphs() : 0;
}

void cskia_typeface_ref(cskia_typeface_t* typeface) { SkSafeRef(as_typeface(typeface)); }
void cskia_typeface_unref(cskia_typeface_t* typeface) { SkSafeUnref(as_typeface(typeface)); }

// MARK: - SkFont

cskia_font_t* cskia_font_new(cskia_typeface_t* typeface, float size) {
    return reinterpret_cast<cskia_font_t*>(new SkFont(typeface ? retain(as_typeface(typeface)) : nullptr, size));
}
cskia_font_t* cskia_font_copy(const cskia_font_t* font) { return reinterpret_cast<cskia_font_t*>(new SkFont(*as_font(font))); }
void cskia_font_delete(cskia_font_t* font) { delete as_font(font); }

void cskia_font_set_typeface(cskia_font_t* font, cskia_typeface_t* typeface) {
    as_font(font)->setTypeface(typeface ? retain(as_typeface(typeface)) : nullptr);
}
cskia_typeface_t* cskia_font_ref_typeface(const cskia_font_t* font) {
    return release_to<SkTypeface, cskia_typeface_t>(as_font(font)->refTypeface());
}
void  cskia_font_set_size(cskia_font_t* font, float size) { as_font(font)->setSize(size); }
float cskia_font_get_size(const cskia_font_t* font) { return as_font(font)->getSize(); }
void  cskia_font_set_scale_x(cskia_font_t* font, float scale) { as_font(font)->setScaleX(scale); }
float cskia_font_get_scale_x(const cskia_font_t* font) { return as_font(font)->getScaleX(); }
void  cskia_font_set_skew_x(cskia_font_t* font, float skew) { as_font(font)->setSkewX(skew); }
float cskia_font_get_skew_x(const cskia_font_t* font) { return as_font(font)->getSkewX(); }
void  cskia_font_set_embolden(cskia_font_t* font, bool embolden) { as_font(font)->setEmbolden(embolden); }
void  cskia_font_set_subpixel(cskia_font_t* font, bool subpixel) { as_font(font)->setSubpixel(subpixel); }
void  cskia_font_set_linear_metrics(cskia_font_t* font, bool linear) { as_font(font)->setLinearMetrics(linear); }
void  cskia_font_set_baseline_snap(cskia_font_t* font, bool snap) { as_font(font)->setBaselineSnap(snap); }
void  cskia_font_set_edging(cskia_font_t* font, int32_t edging) { as_font(font)->setEdging(clamp_enum<SkFont::Edging>(edging, 2)); }
void  cskia_font_set_hinting(cskia_font_t* font, int32_t hinting) { as_font(font)->setHinting(clamp_enum<SkFontHinting>(hinting, 3)); }

float cskia_font_measure_text(const cskia_font_t* font, const char* utf8, size_t byte_length, cskia_rect* bounds) {
    if (!utf8 || byte_length == 0) {
        write_rect(SkRect::MakeEmpty(), bounds);
        return 0;
    }
    SkRect ink = SkRect::MakeEmpty();
    float advance = as_font(font)->measureText(utf8, byte_length, SkTextEncoding::kUTF8, bounds ? &ink : nullptr);
    write_rect(ink, bounds);
    return advance;
}

int32_t cskia_font_text_to_glyphs(const cskia_font_t* font, const char* utf8, size_t byte_length, uint16_t* glyphs, int32_t max_glyphs) {
    if (!utf8 || byte_length == 0) { return 0; }
    // Counting pass first: the span form writes at most its size.
    const size_t total = as_font(font)->textToGlyphs(utf8, byte_length, SkTextEncoding::kUTF8, SkSpan<SkGlyphID>());
    if (glyphs && max_glyphs > 0) {
        as_font(font)->textToGlyphs(utf8, byte_length, SkTextEncoding::kUTF8,
                                    {glyphs, std::min(total, static_cast<size_t>(max_glyphs))});
    }
    return static_cast<int32_t>(total);
}

void cskia_font_get_widths(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float* widths) {
    if (!glyphs || !widths || count <= 0) { return; }
    as_font(font)->getWidths({glyphs, static_cast<size_t>(count)}, {widths, static_cast<size_t>(count)});
}

float cskia_font_get_metrics(const cskia_font_t* font, cskia_font_metrics* out) {
    SkFontMetrics m;
    float spacing = as_font(font)->getMetrics(&m);
    if (out) {
        *out = cskia_font_metrics{
            m.fFlags,
            m.fTop, m.fAscent, m.fDescent, m.fBottom, m.fLeading,
            m.fAvgCharWidth, m.fMaxCharWidth,
            m.fXMin, m.fXMax, m.fXHeight, m.fCapHeight,
            m.fUnderlineThickness, m.fUnderlinePosition,
            m.fStrikeoutThickness, m.fStrikeoutPosition,
        };
    }
    return spacing;
}

float cskia_font_get_spacing(const cskia_font_t* font) { return as_font(font)->getSpacing(); }

// MARK: - SkImage

cskia_image_t* cskia_image_make_raster_copy(const void* pixels, int32_t width, int32_t height, size_t row_bytes, int32_t color_type, int32_t alpha_type) {
    if (!pixels || width <= 0 || height <= 0) { return nullptr; }
    SkColorType ct = color_type == 1 ? kBGRA_8888_SkColorType : kRGBA_8888_SkColorType;
    SkAlphaType at = clamp_enum<SkAlphaType>(alpha_type, kLastEnum_SkAlphaType);
    if (at == kUnknown_SkAlphaType) { at = kPremul_SkAlphaType; }
    SkPixmap pixmap(SkImageInfo::Make(width, height, ct, at), pixels, row_bytes);
    return release_to<SkImage, cskia_image_t>(SkImages::RasterFromPixmapCopy(pixmap));
}

int32_t cskia_image_get_width(const cskia_image_t* image) { return image ? as_image(image)->width() : 0; }
int32_t cskia_image_get_height(const cskia_image_t* image) { return image ? as_image(image)->height() : 0; }
void cskia_image_ref(cskia_image_t* image) { SkSafeRef(as_image(image)); }
void cskia_image_unref(cskia_image_t* image) { SkSafeUnref(as_image(image)); }

// MARK: - Raster SkSurface

cskia_raster_surface_t* cskia_raster_surface_make(int32_t width, int32_t height) {
    if (width <= 0 || height <= 0) { return nullptr; }
    sk_sp<SkSurface> surface = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(width, height));
    if (!surface) { return nullptr; }
    auto* wrapper = new cskia_raster_surface_t();
    wrapper->surface = std::move(surface);
    return wrapper;
}

void cskia_raster_surface_delete(cskia_raster_surface_t* surface) { delete surface; }

cskia_canvas_t* cskia_raster_surface_get_canvas(cskia_raster_surface_t* surface) {
    return reinterpret_cast<cskia_canvas_t*>(surface->surface->getCanvas());
}

int32_t cskia_raster_surface_get_width(const cskia_raster_surface_t* surface) { return surface->surface->width(); }
int32_t cskia_raster_surface_get_height(const cskia_raster_surface_t* surface) { return surface->surface->height(); }

bool cskia_raster_surface_read_pixels(cskia_raster_surface_t* surface, void* dst, size_t row_bytes) {
    if (!dst) { return false; }
    SkImageInfo info = SkImageInfo::Make(surface->surface->width(), surface->surface->height(),
                                         kRGBA_8888_SkColorType, kUnpremul_SkAlphaType);
    return surface->surface->readPixels(info, dst, row_bytes, 0, 0);
}

cskia_image_t* cskia_raster_surface_make_image_snapshot(cskia_raster_surface_t* surface) {
    return release_to<SkImage, cskia_image_t>(surface->surface->makeImageSnapshot());
}

} // extern "C"
