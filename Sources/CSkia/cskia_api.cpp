//
//  cskia_api.cpp
//  CSkia — implementation of cskia_api.h against Skia's C++ API (m132).
//
#include "cskia_api.h"

#include "include/codec/SkCodec.h"
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
#include "include/core/SkPathMeasure.h"
#include "include/core/SkPixmap.h"
#include "include/core/SkRRect.h"
#include "include/core/SkRect.h"
#include "include/core/SkSamplingOptions.h"
#include "include/core/SkShader.h"
#include "include/core/SkString.h"
#include "include/core/SkSurface.h"
#include "include/core/SkStream.h"
#include "include/core/SkTextBlob.h"
#include "include/core/SkTypeface.h"
#include "include/effects/SkCornerPathEffect.h"
#include "include/effects/SkDashPathEffect.h"
#include "include/effects/SkGradientShader.h"
#include "include/encode/SkJpegEncoder.h"
#include "include/encode/SkPngEncoder.h"
#include "include/encode/SkWebpEncoder.h"
#include "include/pathops/SkPathOps.h"
#include "include/utils/SkParsePath.h"
#if defined(__APPLE__)
#include "include/ports/SkFontMgr_mac_ct.h"
#elif defined(__ANDROID__)
#include "include/ports/SkFontMgr_android.h"
#include "include/ports/SkFontScanner_FreeType.h"
#elif defined(__wasm__)
// The browser: no system fonts, faces only from files and data.
#include "include/ports/SkFontMgr_empty.h"
#elif defined(_WIN32)
#include "include/ports/SkTypeface_win.h"
#else
#include "include/ports/SkFontMgr_fontconfig.h"
#include "include/ports/SkFontScanner_FreeType.h"
#endif

#if defined(CSKIA_SVG)
// Skia's SVG module. Its headers reach four of Skia's private ones, which
// the Skia builds don't ship; they are in Sources/CSkia/skia (m144).
#include "include/core/SkStream.h"
#include "modules/svg/include/SkSVGDOM.h"
#include "modules/svg/include/SkSVGRenderContext.h"
#include "modules/svg/include/SkSVGSVG.h"
#endif

#include <algorithm>
#include <cstring>
#include <memory>
#include <vector>

// MARK: - Handle casts
//
// The C handles are the Skia objects themselves; only the raster surface,
// the codec and the path iterator carry a wrapper (they have to hold the
// sk_sp / unique_ptr / the iterator's own state).

struct cskia_raster_surface_t {
    sk_sp<SkSurface> surface;
};

struct cskia_codec_t {
    std::unique_ptr<SkCodec> codec;
};

struct cskia_path_iter_t {
    SkPath::Iter iter;
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
static const SkTextBlob*   as_blob(const cskia_text_blob_t* b)       { return reinterpret_cast<const SkTextBlob*>(b); }
static SkTextBlob*         as_blob(cskia_text_blob_t* b)             { return reinterpret_cast<SkTextBlob*>(b); }
static SkTextBlobBuilder*  as_blob_builder(cskia_text_blob_builder_t* b) { return reinterpret_cast<SkTextBlobBuilder*>(b); }
static SkPathMeasure*      as_measure(cskia_path_measure_t* m)       { return reinterpret_cast<SkPathMeasure*>(m); }
static const SkData*       as_data(const cskia_data_t* d)            { return reinterpret_cast<const SkData*>(d); }
static SkData*             as_data(cskia_data_t* d)                  { return reinterpret_cast<SkData*>(d); }
static SkFontStyleSet*     as_style_set(cskia_font_style_set_t* s)   { return reinterpret_cast<SkFontStyleSet*>(s); }

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

static SkSamplingOptions sampling(const cskia_sampling* s) {
    if (!s) { return linear_sampling(); }
    if (s->cubic) { return SkSamplingOptions(SkCubicResampler{s->cubic_b, s->cubic_c}); }
    return SkSamplingOptions(clamp_enum<SkFilterMode>(s->filter, 1), clamp_enum<SkMipmapMode>(s->mipmap, 2));
}

/// The C color types: 0 RGBA_8888, 1 BGRA_8888.
static SkColorType color_type(int32_t v) { return v == 1 ? kBGRA_8888_SkColorType : kRGBA_8888_SkColorType; }

static SkAlphaType alpha_type(int32_t v) {
    SkAlphaType at = clamp_enum<SkAlphaType>(v, kLastEnum_SkAlphaType);
    return at == kUnknown_SkAlphaType ? kPremul_SkAlphaType : at;
}

static SkFontStyle font_style(int32_t weight, int32_t width, int32_t slant) {
    return SkFontStyle(weight, width, clamp_enum<SkFontStyle::Slant>(slant, 2));
}

static void write_style(const SkFontStyle& style, int32_t* weight, int32_t* width, int32_t* slant) {
    if (weight) { *weight = style.weight(); }
    if (width) { *width = style.width(); }
    if (slant) { *slant = static_cast<int32_t>(style.slant()); }
}

/// `string` into `buffer` (NUL-terminated, truncated to `capacity`); its
/// full length.
static size_t copy_string(const SkString& string, char* buffer, size_t capacity) {
    if (buffer && capacity > 0) {
        size_t n = std::min(string.size(), capacity - 1);
        std::memcpy(buffer, string.c_str(), n);
        buffer[n] = '\0';
    }
    return string.size();
}

static SkSpan<const SkPoint> points(const float* xy, int32_t count) {
    return {reinterpret_cast<const SkPoint*>(xy), static_cast<size_t>(std::max(count, 0))};
}

static SkSpan<const SkGlyphID> glyph_span(const uint16_t* glyphs, int32_t count) {
    return {glyphs, static_cast<size_t>(std::max(count, 0))};
}

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
#elif defined(__wasm__)
        return SkFontMgr_New_Custom_Empty();
#elif defined(_WIN32)
        return SkFontMgr_New_DirectWrite();
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

void cskia_canvas_draw_image_rect_src(cskia_canvas_t* canvas, const cskia_image_t* image, const cskia_rect* src, const cskia_rect* dst, const cskia_sampling* s, const cskia_paint_t* paint, int32_t constraint) {
    if (!image || !src || !dst) { return; }
    as_canvas(canvas)->drawImageRect(as_image(image), xywh(src->x, src->y, src->w, src->h), xywh(dst->x, dst->y, dst->w, dst->h),
                                     sampling(s), as_paint(paint),
                                     constraint == 1 ? SkCanvas::kFast_SrcRectConstraint : SkCanvas::kStrict_SrcRectConstraint);
}
void cskia_canvas_draw_image_nine(cskia_canvas_t* canvas, const cskia_image_t* image, int32_t cx, int32_t cy, int32_t cw, int32_t ch, const cskia_rect* dst, int32_t filter, const cskia_paint_t* paint) {
    if (!image || !dst) { return; }
    as_canvas(canvas)->drawImageNine(as_image(image), SkIRect::MakeXYWH(cx, cy, cw, ch), xywh(dst->x, dst->y, dst->w, dst->h),
                                     clamp_enum<SkFilterMode>(filter, 1), as_paint(paint));
}
void cskia_canvas_draw_text_blob(cskia_canvas_t* canvas, const cskia_text_blob_t* blob, float x, float y, const cskia_paint_t* paint) {
    if (!blob) { return; }
    as_canvas(canvas)->drawTextBlob(as_blob(blob), x, y, *as_paint(paint));
}
void cskia_canvas_draw_glyphs(cskia_canvas_t* canvas, const uint16_t* glyphs, const float* positions, int32_t count, float origin_x, float origin_y, const cskia_font_t* font, const cskia_paint_t* paint) {
    if (!glyphs || !positions || count <= 0) { return; }
    as_canvas(canvas)->drawGlyphs(glyph_span(glyphs, count), points(positions, count), {origin_x, origin_y}, *as_font(font), *as_paint(paint));
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

void cskia_path_r_move_to(cskia_path_t* path, float dx, float dy) { as_path(path)->rMoveTo(dx, dy); }
void cskia_path_r_line_to(cskia_path_t* path, float dx, float dy) { as_path(path)->rLineTo(dx, dy); }
void cskia_path_r_quad_to(cskia_path_t* path, float dx1, float dy1, float dx2, float dy2) { as_path(path)->rQuadTo(dx1, dy1, dx2, dy2); }
void cskia_path_r_conic_to(cskia_path_t* path, float dx1, float dy1, float dx2, float dy2, float weight) { as_path(path)->rConicTo(dx1, dy1, dx2, dy2, weight); }
void cskia_path_r_cubic_to(cskia_path_t* path, float dx1, float dy1, float dx2, float dy2, float dx3, float dy3) {
    as_path(path)->rCubicTo(dx1, dy1, dx2, dy2, dx3, dy3);
}

void cskia_path_arc_to_tangent(cskia_path_t* path, float x1, float y1, float x2, float y2, float radius) {
    as_path(path)->arcTo(x1, y1, x2, y2, radius);
}
void cskia_path_arc_to_oval(cskia_path_t* path, float x, float y, float w, float h, float start_angle, float sweep_angle, bool force_move_to) {
    as_path(path)->arcTo(xywh(x, y, w, h), start_angle, sweep_angle, force_move_to);
}
void cskia_path_arc_to_svg(cskia_path_t* path, float rx, float ry, float x_axis_rotate, bool large_arc, int32_t dir, float x, float y, bool relative) {
    SkPath::ArcSize size = large_arc ? SkPath::kLarge_ArcSize : SkPath::kSmall_ArcSize;
    if (relative) {
        as_path(path)->rArcTo(rx, ry, x_axis_rotate, size, direction(dir), x, y);
    } else {
        as_path(path)->arcTo(rx, ry, x_axis_rotate, size, direction(dir), x, y);
    }
}

void cskia_path_add_rrect_radii(cskia_path_t* path, float x, float y, float w, float h, const float* radii, int32_t dir) {
    if (!radii) { return; }
    SkRRect rrect;
    rrect.setRectRadii(xywh(x, y, w, h), reinterpret_cast<const SkVector*>(radii));
    as_path(path)->addRRect(rrect, direction(dir));
}
void cskia_path_add_poly(cskia_path_t* path, const float* xy, int32_t count, bool close) {
    if (!xy || count <= 0) { return; }
    as_path(path)->addPoly(points(xy, count), close);
}
void cskia_path_add_path_matrix(cskia_path_t* path, const cskia_path_t* src, const cskia_matrix* matrix, int32_t mode) {
    SkPath::AddPathMode m = mode == 1 ? SkPath::kExtend_AddPathMode : SkPath::kAppend_AddPathMode;
    as_path(path)->addPath(*as_path(src), matrix ? to_matrix(matrix) : SkMatrix::I(), m);
}
void cskia_path_reverse_add_path(cskia_path_t* path, const cskia_path_t* src) { as_path(path)->reverseAddPath(*as_path(src)); }

void cskia_path_toggle_inverse_fill_type(cskia_path_t* path) { as_path(path)->toggleInverseFillType(); }
bool cskia_path_is_inverse_fill_type(const cskia_path_t* path) { return as_path(path)->isInverseFillType(); }

bool cskia_path_get_point(const cskia_path_t* path, int32_t index, float* x, float* y) {
    if (index < 0 || index >= as_path(path)->countPoints()) { return false; }
    SkPoint p = as_path(path)->getPoint(index);
    if (x) { *x = p.fX; }
    if (y) { *y = p.fY; }
    return true;
}
int32_t cskia_path_get_points(const cskia_path_t* path, float* xy, int32_t max_points) {
    if (xy && max_points > 0) {
        as_path(path)->getPoints({reinterpret_cast<SkPoint*>(xy), static_cast<size_t>(max_points)});
    }
    return as_path(path)->countPoints();
}
bool cskia_path_get_last_pt(const cskia_path_t* path, float* x, float* y) {
    std::optional<SkPoint> last = as_path(path)->getLastPt();
    if (!last) { return false; }
    if (x) { *x = last->fX; }
    if (y) { *y = last->fY; }
    return true;
}
void cskia_path_set_last_pt(cskia_path_t* path, float x, float y) { as_path(path)->setLastPt(x, y); }

bool cskia_path_is_rect(const cskia_path_t* path, cskia_rect* out) {
    SkRect rect;
    if (!as_path(path)->isRect(&rect)) { return false; }
    write_rect(rect, out);
    return true;
}
bool cskia_path_is_oval(const cskia_path_t* path, cskia_rect* out) {
    SkRect rect;
    if (!as_path(path)->isOval(&rect)) { return false; }
    write_rect(rect, out);
    return true;
}
bool cskia_path_is_line(const cskia_path_t* path, float* line) {
    SkPoint pts[2];
    if (!as_path(path)->isLine(pts)) { return false; }
    if (line) {
        line[0] = pts[0].fX; line[1] = pts[0].fY;
        line[2] = pts[1].fX; line[3] = pts[1].fY;
    }
    return true;
}
bool cskia_path_is_convex(const cskia_path_t* path) { return as_path(path)->isConvex(); }
bool cskia_path_is_finite(const cskia_path_t* path) { return as_path(path)->isFinite(); }
bool cskia_path_is_last_contour_closed(const cskia_path_t* path) { return as_path(path)->isLastContourClosed(); }
bool cskia_path_conservatively_contains_rect(const cskia_path_t* path, float x, float y, float w, float h) {
    return as_path(path)->conservativelyContainsRect(xywh(x, y, w, h));
}

bool cskia_path_is_interpolatable(const cskia_path_t* path, const cskia_path_t* other) {
    return as_path(path)->isInterpolatable(*as_path(other));
}
bool cskia_path_interpolate(const cskia_path_t* path, const cskia_path_t* ending, float weight, cskia_path_t* out) {
    return as_path(path)->interpolate(*as_path(ending), weight, as_path(out));
}

size_t cskia_path_write_to_memory(const cskia_path_t* path, void* buffer) { return as_path(path)->writeToMemory(buffer); }
cskia_path_t* cskia_path_read_from_memory(const void* buffer, size_t length) {
    if (!buffer || length == 0) { return nullptr; }
    std::optional<SkPath> read = SkPath::ReadFromMemory(buffer, length);
    return read ? reinterpret_cast<cskia_path_t*>(new SkPath(std::move(*read))) : nullptr;
}

cskia_path_t* cskia_path_make_from_svg_string(const char* svg) {
    if (!svg) { return nullptr; }
    std::optional<SkPath> parsed = SkParsePath::FromSVGString(svg);
    return parsed ? reinterpret_cast<cskia_path_t*>(new SkPath(std::move(*parsed))) : nullptr;
}
size_t cskia_path_to_svg_string(const cskia_path_t* path, bool relative, char* buffer, size_t capacity) {
    SkString svg = SkParsePath::ToSVGString(*as_path(path), relative ? SkParsePath::PathEncoding::Relative
                                                                     : SkParsePath::PathEncoding::Absolute);
    return copy_string(svg, buffer, capacity);
}

// MARK: - SkPath::Iter

cskia_path_iter_t* cskia_path_iter_new(const cskia_path_t* path, bool force_close) {
    return new cskia_path_iter_t{SkPath::Iter(*as_path(path), force_close)};
}
void cskia_path_iter_delete(cskia_path_iter_t* iter) { delete iter; }

int32_t cskia_path_iter_next(cskia_path_iter_t* iter, float* xy, float* conic_weight) {
    SkPoint pts[4];
    SkPath::Verb verb = iter->iter.next(pts);
    int count = 0;
    switch (verb) {
        case SkPath::kMove_Verb:  count = 1; break;
        case SkPath::kLine_Verb:  count = 2; break;
        case SkPath::kQuad_Verb:
        case SkPath::kConic_Verb: count = 3; break;
        case SkPath::kCubic_Verb: count = 4; break;
        default: break;
    }
    if (xy) {
        for (int i = 0; i < count; ++i) {
            xy[i * 2] = pts[i].fX;
            xy[i * 2 + 1] = pts[i].fY;
        }
    }
    if (conic_weight) { *conic_weight = verb == SkPath::kConic_Verb ? iter->iter.conicWeight() : 1; }
    return static_cast<int32_t>(verb);
}

// MARK: - PathOps

static SkPathOp path_op(int32_t v) { return clamp_enum<SkPathOp>(v, static_cast<int32_t>(kReverseDifference_SkPathOp)); }

bool cskia_path_op(const cskia_path_t* one, const cskia_path_t* two, int32_t op, cskia_path_t* out) {
    std::optional<SkPath> result = Op(*as_path(one), *as_path(two), path_op(op));
    if (!result) { return false; }
    *as_path(out) = std::move(*result);
    return true;
}
bool cskia_path_simplify(const cskia_path_t* path, cskia_path_t* out) {
    std::optional<SkPath> result = Simplify(*as_path(path));
    if (!result) { return false; }
    *as_path(out) = std::move(*result);
    return true;
}
bool cskia_path_as_winding(const cskia_path_t* path, cskia_path_t* out) {
    std::optional<SkPath> result = AsWinding(*as_path(path));
    if (!result) { return false; }
    *as_path(out) = std::move(*result);
    return true;
}

cskia_op_builder_t* cskia_op_builder_new(void) { return reinterpret_cast<cskia_op_builder_t*>(new SkOpBuilder()); }
void cskia_op_builder_delete(cskia_op_builder_t* builder) { delete reinterpret_cast<SkOpBuilder*>(builder); }
void cskia_op_builder_add(cskia_op_builder_t* builder, const cskia_path_t* path, int32_t op) {
    reinterpret_cast<SkOpBuilder*>(builder)->add(*as_path(path), path_op(op));
}
bool cskia_op_builder_resolve(cskia_op_builder_t* builder, cskia_path_t* out) {
    return reinterpret_cast<SkOpBuilder*>(builder)->resolve(as_path(out));
}

// MARK: - SkPathMeasure

cskia_path_measure_t* cskia_path_measure_new(const cskia_path_t* path, bool force_closed, float res_scale) {
    return reinterpret_cast<cskia_path_measure_t*>(new SkPathMeasure(*as_path(path), force_closed, res_scale));
}
void  cskia_path_measure_delete(cskia_path_measure_t* measure) { delete as_measure(measure); }
float cskia_path_measure_get_length(cskia_path_measure_t* measure) { return as_measure(measure)->getLength(); }
bool  cskia_path_measure_get_pos_tan(cskia_path_measure_t* measure, float distance, float* position, float* tangent) {
    SkPoint pos;
    SkVector tan;
    if (!as_measure(measure)->getPosTan(distance, &pos, &tan)) { return false; }
    if (position) { position[0] = pos.fX; position[1] = pos.fY; }
    if (tangent) { tangent[0] = tan.fX; tangent[1] = tan.fY; }
    return true;
}
bool cskia_path_measure_get_segment(cskia_path_measure_t* measure, float start, float stop, cskia_path_t* dst, bool start_with_move_to) {
    return as_measure(measure)->getSegment(start, stop, as_path(dst), start_with_move_to);
}
bool cskia_path_measure_is_closed(cskia_path_measure_t* measure) { return as_measure(measure)->isClosed(); }
bool cskia_path_measure_next_contour(cskia_path_measure_t* measure) { return as_measure(measure)->nextContour(); }

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

cskia_shader_t* cskia_shader_make_image(const cskia_image_t* image, int32_t tile_x, int32_t tile_y, const cskia_sampling* s, const cskia_matrix* matrix) {
    if (!image) { return nullptr; }
    SkMatrix local = matrix ? to_matrix(matrix) : SkMatrix::I();
    return release_to<SkShader, cskia_shader_t>(
        as_image(image)->makeShader(tile_mode(tile_x), tile_mode(tile_y), sampling(s), &local));
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

void cskia_typeface_get_style(const cskia_typeface_t* typeface, int32_t* weight, int32_t* width, int32_t* slant) {
    write_style(as_typeface(typeface)->fontStyle(), weight, width, slant);
}
bool cskia_typeface_is_bold(const cskia_typeface_t* typeface) { return as_typeface(typeface)->isBold(); }
bool cskia_typeface_is_italic(const cskia_typeface_t* typeface) { return as_typeface(typeface)->isItalic(); }
bool cskia_typeface_is_fixed_pitch(const cskia_typeface_t* typeface) { return as_typeface(typeface)->isFixedPitch(); }
int32_t cskia_typeface_get_units_per_em(const cskia_typeface_t* typeface) { return as_typeface(typeface)->getUnitsPerEm(); }
uint16_t cskia_typeface_unichar_to_glyph(const cskia_typeface_t* typeface, int32_t unichar) {
    return as_typeface(typeface)->unicharToGlyph(unichar);
}
int32_t cskia_typeface_get_table_tags(const cskia_typeface_t* typeface, uint32_t* tags, int32_t max_tags) {
    int count = as_typeface(typeface)->countTables();
    if (tags && max_tags > 0) {
        std::vector<SkFontTableTag> all(count);
        as_typeface(typeface)->readTableTags({all.data(), all.size()});
        std::copy_n(all.begin(), std::min(count, max_tags), tags);
    }
    return count;
}
size_t cskia_typeface_get_table_data(const cskia_typeface_t* typeface, uint32_t tag, size_t offset, size_t length, void* data) {
    if (!data) { return as_typeface(typeface)->getTableSize(tag); }
    return as_typeface(typeface)->getTableData(tag, offset, length, data);
}

void cskia_typeface_ref(cskia_typeface_t* typeface) { SkSafeRef(as_typeface(typeface)); }
void cskia_typeface_unref(cskia_typeface_t* typeface) { SkSafeUnref(as_typeface(typeface)); }

// MARK: - SkFontMgr

int32_t cskia_font_mgr_count_families(void) {
    sk_sp<SkFontMgr> mgr = font_mgr();
    return mgr ? mgr->countFamilies() : 0;
}
size_t cskia_font_mgr_get_family_name(int32_t index, char* buffer, size_t capacity) {
    sk_sp<SkFontMgr> mgr = font_mgr();
    if (!mgr || index < 0 || index >= mgr->countFamilies()) { return copy_string(SkString(), buffer, capacity); }
    SkString name;
    mgr->getFamilyName(index, &name);
    return copy_string(name, buffer, capacity);
}
cskia_font_style_set_t* cskia_font_mgr_match_family(const char* family) {
    sk_sp<SkFontMgr> mgr = font_mgr();
    sk_sp<SkFontStyleSet> set = mgr ? mgr->matchFamily(family) : nullptr;
    if (!set) { set = SkFontStyleSet::CreateEmpty(); }
    return release_to<SkFontStyleSet, cskia_font_style_set_t>(std::move(set));
}
cskia_typeface_t* cskia_font_mgr_match_family_style_character(const char* family, int32_t weight, int32_t width, int32_t slant, const char* const* bcp47, int32_t bcp47_count, int32_t unichar) {
    sk_sp<SkFontMgr> mgr = font_mgr();
    if (!mgr) { return nullptr; }
    return release_to<SkTypeface, cskia_typeface_t>(mgr->matchFamilyStyleCharacter(
        family, font_style(weight, width, slant), const_cast<const char**>(bcp47), std::max(bcp47_count, 0), unichar));
}

// MARK: - SkFontStyleSet

int32_t cskia_font_style_set_count(cskia_font_style_set_t* set) { return as_style_set(set)->count(); }
size_t cskia_font_style_set_get_style(cskia_font_style_set_t* set, int32_t index, int32_t* weight, int32_t* width, int32_t* slant, char* name, size_t capacity) {
    SkFontStyle style;
    SkString styleName;
    if (index >= 0 && index < as_style_set(set)->count()) {
        as_style_set(set)->getStyle(index, &style, &styleName);
    }
    write_style(style, weight, width, slant);
    return copy_string(styleName, name, capacity);
}
cskia_typeface_t* cskia_font_style_set_create_typeface(cskia_font_style_set_t* set, int32_t index) {
    if (index < 0 || index >= as_style_set(set)->count()) { return nullptr; }
    return release_to<SkTypeface, cskia_typeface_t>(as_style_set(set)->createTypeface(index));
}
cskia_typeface_t* cskia_font_style_set_match_style(cskia_font_style_set_t* set, int32_t weight, int32_t width, int32_t slant) {
    return release_to<SkTypeface, cskia_typeface_t>(as_style_set(set)->matchStyle(font_style(weight, width, slant)));
}
void cskia_font_style_set_unref(cskia_font_style_set_t* set) { SkSafeUnref(as_style_set(set)); }

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

bool    cskia_font_is_embolden(const cskia_font_t* font) { return as_font(font)->isEmbolden(); }
bool    cskia_font_is_subpixel(const cskia_font_t* font) { return as_font(font)->isSubpixel(); }
bool    cskia_font_is_linear_metrics(const cskia_font_t* font) { return as_font(font)->isLinearMetrics(); }
bool    cskia_font_is_baseline_snap(const cskia_font_t* font) { return as_font(font)->isBaselineSnap(); }
void    cskia_font_set_force_auto_hinting(cskia_font_t* font, bool force) { as_font(font)->setForceAutoHinting(force); }
bool    cskia_font_is_force_auto_hinting(const cskia_font_t* font) { return as_font(font)->isForceAutoHinting(); }
void    cskia_font_set_embedded_bitmaps(cskia_font_t* font, bool embedded) { as_font(font)->setEmbeddedBitmaps(embedded); }
bool    cskia_font_is_embedded_bitmaps(const cskia_font_t* font) { return as_font(font)->isEmbeddedBitmaps(); }
int32_t cskia_font_get_edging(const cskia_font_t* font) { return static_cast<int32_t>(as_font(font)->getEdging()); }
int32_t cskia_font_get_hinting(const cskia_font_t* font) { return static_cast<int32_t>(as_font(font)->getHinting()); }

uint16_t cskia_font_unichar_to_glyph(const cskia_font_t* font, int32_t unichar) { return as_font(font)->unicharToGlyph(unichar); }
void cskia_font_unichars_to_glyphs(const cskia_font_t* font, const int32_t* unichars, int32_t count, uint16_t* glyphs) {
    if (!unichars || !glyphs || count <= 0) { return; }
    as_font(font)->unicharsToGlyphs({unichars, static_cast<size_t>(count)}, {glyphs, static_cast<size_t>(count)});
}
void cskia_font_get_widths_bounds(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float* widths, cskia_rect* bounds, const cskia_paint_t* paint) {
    if (!glyphs || count <= 0) { return; }
    std::vector<SkRect> rects(bounds ? count : 0);
    as_font(font)->getWidthsBounds(glyph_span(glyphs, count),
                                   widths ? SkSpan<SkScalar>(widths, count) : SkSpan<SkScalar>(),
                                   SkSpan<SkRect>(rects.data(), rects.size()),
                                   as_paint(paint));
    for (size_t i = 0; i < rects.size(); ++i) { write_rect(rects[i], &bounds[i]); }
}
void cskia_font_get_pos(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float origin_x, float origin_y, float* positions) {
    if (!glyphs || !positions || count <= 0) { return; }
    as_font(font)->getPos(glyph_span(glyphs, count), {reinterpret_cast<SkPoint*>(positions), static_cast<size_t>(count)}, {origin_x, origin_y});
}
void cskia_font_get_x_pos(const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float origin, float* xpos) {
    if (!glyphs || !xpos || count <= 0) { return; }
    as_font(font)->getXPos(glyph_span(glyphs, count), {xpos, static_cast<size_t>(count)}, origin);
}
bool cskia_font_get_path(const cskia_font_t* font, uint16_t glyph, cskia_path_t* out) {
    std::optional<SkPath> path = as_font(font)->getPath(glyph);
    if (!path) { return false; }
    *as_path(out) = std::move(*path);
    return true;
}

// MARK: - SkTextBlob

cskia_text_blob_t* cskia_text_blob_make_from_text(const char* utf8, size_t byte_length, const cskia_font_t* font) {
    if (!utf8 || byte_length == 0) { return nullptr; }
    return release_to<SkTextBlob, cskia_text_blob_t>(SkTextBlob::MakeFromText(utf8, byte_length, *as_font(font), SkTextEncoding::kUTF8));
}
cskia_text_blob_t* cskia_text_blob_make_from_pos_glyphs(const uint16_t* glyphs, const float* positions, int32_t count, const cskia_font_t* font) {
    if (!glyphs || !positions || count <= 0) { return nullptr; }
    return release_to<SkTextBlob, cskia_text_blob_t>(SkTextBlob::MakeFromPosGlyphs(glyph_span(glyphs, count), points(positions, count), *as_font(font)));
}
cskia_text_blob_t* cskia_text_blob_make_from_pos_h_glyphs(const uint16_t* glyphs, const float* xpos, int32_t count, float y, const cskia_font_t* font) {
    if (!glyphs || !xpos || count <= 0) { return nullptr; }
    return release_to<SkTextBlob, cskia_text_blob_t>(SkTextBlob::MakeFromPosHGlyphs(glyph_span(glyphs, count), {xpos, static_cast<size_t>(count)}, y, *as_font(font)));
}
void cskia_text_blob_get_bounds(const cskia_text_blob_t* blob, cskia_rect* out) { write_rect(as_blob(blob)->bounds(), out); }
int32_t cskia_text_blob_get_intercepts(const cskia_text_blob_t* blob, float upper, float lower, float* intervals, int32_t max, const cskia_paint_t* paint) {
    const SkScalar band[2] = {upper, lower};
    int count = as_blob(blob)->getIntercepts(band, nullptr, as_paint(paint));
    if (intervals && max >= count) { as_blob(blob)->getIntercepts(band, intervals, as_paint(paint)); }
    return count;
}
void cskia_text_blob_ref(cskia_text_blob_t* blob) { SkSafeRef(as_blob(blob)); }
void cskia_text_blob_unref(cskia_text_blob_t* blob) { SkSafeUnref(as_blob(blob)); }

// MARK: - SkTextBlobBuilder

cskia_text_blob_builder_t* cskia_text_blob_builder_new(void) { return reinterpret_cast<cskia_text_blob_builder_t*>(new SkTextBlobBuilder()); }
void cskia_text_blob_builder_delete(cskia_text_blob_builder_t* builder) { delete as_blob_builder(builder); }
void cskia_text_blob_builder_add_run(cskia_text_blob_builder_t* builder, const cskia_font_t* font, const uint16_t* glyphs, int32_t count, float x, float y) {
    if (!glyphs || count <= 0) { return; }
    const auto& run = as_blob_builder(builder)->allocRun(*as_font(font), count, x, y);
    std::copy_n(glyphs, count, run.glyphs);
}
void cskia_text_blob_builder_add_run_pos_h(cskia_text_blob_builder_t* builder, const cskia_font_t* font, const uint16_t* glyphs, const float* xpos, int32_t count, float y) {
    if (!glyphs || !xpos || count <= 0) { return; }
    const auto& run = as_blob_builder(builder)->allocRunPosH(*as_font(font), count, y);
    std::copy_n(glyphs, count, run.glyphs);
    std::copy_n(xpos, count, run.pos);
}
void cskia_text_blob_builder_add_run_pos(cskia_text_blob_builder_t* builder, const cskia_font_t* font, const uint16_t* glyphs, const float* positions, int32_t count) {
    if (!glyphs || !positions || count <= 0) { return; }
    const auto& run = as_blob_builder(builder)->allocRunPos(*as_font(font), count);
    std::copy_n(glyphs, count, run.glyphs);
    std::copy_n(positions, count * 2, run.pos);
}
cskia_text_blob_t* cskia_text_blob_builder_make(cskia_text_blob_builder_t* builder) {
    return release_to<SkTextBlob, cskia_text_blob_t>(as_blob_builder(builder)->make());
}

// MARK: - SkData

const void* cskia_data_get_bytes(const cskia_data_t* data) { return as_data(data)->data(); }
size_t cskia_data_get_size(const cskia_data_t* data) { return as_data(data)->size(); }
void cskia_data_unref(cskia_data_t* data) { SkSafeUnref(as_data(data)); }

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
cskia_image_t* cskia_image_make_from_encoded(const void* data, size_t size) {
    if (!data || size == 0) { return nullptr; }
    return release_to<SkImage, cskia_image_t>(SkImages::DeferredFromEncodedData(SkData::MakeWithCopy(data, size)));
}
int32_t cskia_image_get_color_type(const cskia_image_t* image) {
    switch (as_image(image)->colorType()) {
        case kRGBA_8888_SkColorType: return 0;
        case kBGRA_8888_SkColorType: return 1;
        default: return -1;
    }
}
int32_t cskia_image_get_alpha_type(const cskia_image_t* image) { return static_cast<int32_t>(as_image(image)->alphaType()); }
bool cskia_image_is_opaque(const cskia_image_t* image) { return as_image(image)->isOpaque(); }
bool cskia_image_read_pixels(const cskia_image_t* image, void* pixels, size_t row_bytes, int32_t width, int32_t height, int32_t ct, int32_t at, int32_t src_x, int32_t src_y) {
    if (!pixels || width <= 0 || height <= 0) { return false; }
    SkImageInfo info = SkImageInfo::Make(width, height, color_type(ct), alpha_type(at));
    return as_image(image)->readPixels(nullptr, info, pixels, row_bytes, src_x, src_y);
}
bool cskia_image_peek_pixels(const cskia_image_t* image, const void** pixels, size_t* row_bytes) {
    SkPixmap pixmap;
    if (!as_image(image)->peekPixels(&pixmap)) { return false; }
    if (pixels) { *pixels = pixmap.addr(); }
    if (row_bytes) { *row_bytes = pixmap.rowBytes(); }
    return true;
}
cskia_image_t* cskia_image_make_subset(const cskia_image_t* image, int32_t x, int32_t y, int32_t w, int32_t h) {
    SkIRect subset = SkIRect::MakeXYWH(x, y, w, h);
    if (w <= 0 || h <= 0 || !SkIRect::MakeWH(as_image(image)->width(), as_image(image)->height()).contains(subset)) { return nullptr; }
    return release_to<SkImage, cskia_image_t>(as_image(image)->makeSubset(nullptr, subset, {}));
}
cskia_image_t* cskia_image_make_raster_image(const cskia_image_t* image) {
    return release_to<SkImage, cskia_image_t>(as_image(image)->makeRasterImage());
}

cskia_data_t* cskia_image_encode(const cskia_image_t* image, int32_t format, int32_t quality) {
    // The encoders read a pixmap: a lazy image is decoded for them first.
    sk_sp<SkImage> raster = as_image(image)->makeRasterImage();
    SkPixmap pixmap;
    if (!raster || !raster->peekPixels(&pixmap)) { return nullptr; }
    quality = std::clamp(quality, 0, 100);
    sk_sp<SkData> data;
    switch (format) {
        case 0: data = SkPngEncoder::Encode(pixmap, {}); break;
        case 1: {
            SkJpegEncoder::Options options;
            options.fQuality = quality;
            data = SkJpegEncoder::Encode(pixmap, options);
            break;
        }
        case 2: {
            SkWebpEncoder::Options options;
            options.fCompression = quality >= 100 ? SkWebpEncoder::Compression::kLossless : SkWebpEncoder::Compression::kLossy;
            options.fQuality = static_cast<float>(quality);
            data = SkWebpEncoder::Encode(pixmap, options);
            break;
        }
        default: break;
    }
    return release_to<SkData, cskia_data_t>(std::move(data));
}

void cskia_image_ref(cskia_image_t* image) { SkSafeRef(as_image(image)); }
void cskia_image_unref(cskia_image_t* image) { SkSafeUnref(as_image(image)); }

// MARK: - SkCodec

cskia_codec_t* cskia_codec_make_from_data(const void* data, size_t size) {
    if (!data || size == 0) { return nullptr; }
    // The overload without a decoder list takes the build's own — whichever
    // SK_CODEC_DECODES_* libskia was compiled with — so this links on every
    // platform, whatever codecs its Skia has.
    std::unique_ptr<SkCodec> codec = SkCodec::MakeFromData(SkData::MakeWithCopy(data, size));
    if (!codec) { return nullptr; }
    auto* wrapper = new cskia_codec_t();
    wrapper->codec = std::move(codec);
    return wrapper;
}

void cskia_codec_delete(cskia_codec_t* codec) { delete codec; }

int32_t cskia_codec_get_width(const cskia_codec_t* codec) { return codec->codec->dimensions().width(); }
int32_t cskia_codec_get_height(const cskia_codec_t* codec) { return codec->codec->dimensions().height(); }

bool cskia_codec_get_pixels(cskia_codec_t* codec, void* pixels, size_t row_bytes, int32_t color_type, int32_t alpha_type) {
    if (!pixels) { return false; }
    SkColorType ct = color_type == 1 ? kBGRA_8888_SkColorType : kRGBA_8888_SkColorType;
    SkAlphaType at = clamp_enum<SkAlphaType>(alpha_type, kLastEnum_SkAlphaType);
    if (at == kUnknown_SkAlphaType) { at = kPremul_SkAlphaType; }
    SkImageInfo info = codec->codec->getInfo().makeColorType(ct).makeAlphaType(at);
    return codec->codec->getPixels(info, pixels, row_bytes) == SkCodec::kSuccess;
}

// MARK: - SkSVGDOM

#if defined(CSKIA_SVG)

static SkSVGDOM*       as_svg(cskia_svg_dom_t* d)       { return reinterpret_cast<SkSVGDOM*>(d); }
static const SkSVGDOM* as_svg(const cskia_svg_dom_t* d) { return reinterpret_cast<const SkSVGDOM*>(d); }

cskia_svg_dom_t* cskia_svg_dom_make_from_data(const void* data, size_t size) {
    if (!data || size == 0) { return nullptr; }
    SkMemoryStream stream(SkData::MakeWithCopy(data, size));
    sk_sp<SkSVGDOM> dom = SkSVGDOM::Builder().setFontManager(font_mgr()).make(stream);
    if (!dom || !dom->getRoot()) { return nullptr; }
    return release_to<SkSVGDOM, cskia_svg_dom_t>(std::move(dom));
}

void cskia_svg_dom_unref(cskia_svg_dom_t* dom) { SkSafeUnref(as_svg(dom)); }

void cskia_svg_dom_get_intrinsic_size(const cskia_svg_dom_t* dom, float* width, float* height) {
    SkSize size = as_svg(dom)->getRoot()->intrinsicSize(SkSVGLengthContext(SkSize::Make(0, 0)));
    if (width) { *width = size.width(); }
    if (height) { *height = size.height(); }
}

bool cskia_svg_dom_get_view_box(const cskia_svg_dom_t* dom, float* x, float* y, float* width, float* height) {
    const auto& box = as_svg(dom)->getRoot()->getViewBox();
    if (!box.has_value()) { return false; }
    if (x) { *x = box->x(); }
    if (y) { *y = box->y(); }
    if (width) { *width = box->width(); }
    if (height) { *height = box->height(); }
    return true;
}

void cskia_svg_dom_set_container_size(cskia_svg_dom_t* dom, float width, float height) {
    as_svg(dom)->setContainerSize(SkSize::Make(width, height));
}

void cskia_svg_dom_render(const cskia_svg_dom_t* dom, cskia_canvas_t* canvas) {
    if (!canvas) { return; }
    as_svg(dom)->render(as_canvas(canvas));
}

#else

// No SVG module in this Skia build: nothing parses, so there is never a DOM
// for the rest to be called on.
cskia_svg_dom_t* cskia_svg_dom_make_from_data(const void*, size_t) { return nullptr; }
void cskia_svg_dom_unref(cskia_svg_dom_t*) {}
void cskia_svg_dom_get_intrinsic_size(const cskia_svg_dom_t*, float* width, float* height) {
    if (width) { *width = 0; }
    if (height) { *height = 0; }
}
bool cskia_svg_dom_get_view_box(const cskia_svg_dom_t*, float*, float*, float*, float*) { return false; }
void cskia_svg_dom_set_container_size(cskia_svg_dom_t*, float, float) {}
void cskia_svg_dom_render(const cskia_svg_dom_t*, cskia_canvas_t*) {}

#endif

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
