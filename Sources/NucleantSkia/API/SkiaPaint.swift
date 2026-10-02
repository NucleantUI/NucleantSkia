//
//  SkiaPaint.swift
//  NucleantSkia
//
import CSkia

/// SkPaint — how a draw call fills or strokes: color, style, stroke
/// geometry, shader, path effect, blend mode, mask filter.
public protocol SkiaPaint {
    var base: OpaquePointer { get }
}

public extension SkiaPaint {

    func reset() { cskia_paint_reset(base) }

    // anti-alias / dither
    func setAntiAlias(_ aa: Bool) { cskia_paint_set_anti_alias(base, aa) }
    func isAntiAlias() -> Bool { cskia_paint_is_anti_alias(base) }
    func setDither(_ dither: Bool) { cskia_paint_set_dither(base, dither) }
    func isDither() -> Bool { cskia_paint_is_dither(base) }

    // color
    /// SkColor, 0xAARRGGBB.
    func setColor(_ argb: UInt32) { cskia_paint_set_color(base, argb) }
    /// (r, g, b, a), 0…255.
    func setColor(_ color: SIMD4<UInt8>) { cskia_paint_set_color(base, color.argb) }
    func setARGB(a: UInt8, r: UInt8, g: UInt8, b: UInt8) { cskia_paint_set_color(base, SIMD4(r, g, b, a).argb) }
    /// (r, g, b, a), 0…255.
    func getColor() -> SIMD4<UInt8> { SIMD4(argb: cskia_paint_get_color(base)) }

    /// (r, g, b, a), 0…1.
    func setColor4f(_ color: SIMD4<Float>) { cskia_paint_set_color4f(base, color.x, color.y, color.z, color.w) }
    func setColor4f<F: BinaryFloatingPoint & SIMDScalar>(_ color: SIMD4<F>) { setColor4f(SIMD4<Float>(color)) }
    func setColor4f(r: Float, g: Float, b: Float, a: Float = 1) { cskia_paint_set_color4f(base, r, g, b, a) }
    func getColor4f() -> SIMD4<Float> {
        var rgba = SIMD4<Float>()
        withUnsafeMutableBytes(of: &rgba) { cskia_paint_get_color4f(base, $0.baseAddress!.assumingMemoryBound(to: Float.self)) }
        return rgba
    }

    func setAlphaf(_ alpha: Float) { cskia_paint_set_alphaf(base, alpha) }
    func setAlphaf<F: BinaryFloatingPoint>(_ alpha: F) { cskia_paint_set_alphaf(base, .init(alpha)) }
    func getAlphaf() -> Float { cskia_paint_get_alphaf(base) }

    // style
    func setStyle(_ style: SkPaintStyle) { cskia_paint_set_style(base, style.rawValue) }
    func getStyle() -> SkPaintStyle { SkPaintStyle(rawValue: cskia_paint_get_style(base)) ?? .fill }
    /// `true` strokes, `false` fills — SkPaint::setStroke.
    func setStroke(_ stroke: Bool) { setStyle(stroke ? .stroke : .fill) }

    // stroke geometry
    func setStrokeWidth(_ width: Float) { cskia_paint_set_stroke_width(base, width) }
    func setStrokeWidth<F: BinaryFloatingPoint>(_ width: F) { cskia_paint_set_stroke_width(base, .init(width)) }
    func getStrokeWidth() -> Float { cskia_paint_get_stroke_width(base) }

    func setStrokeMiter(_ miter: Float) { cskia_paint_set_stroke_miter(base, miter) }
    func setStrokeMiter<F: BinaryFloatingPoint>(_ miter: F) { cskia_paint_set_stroke_miter(base, .init(miter)) }
    func getStrokeMiter() -> Float { cskia_paint_get_stroke_miter(base) }

    func setStrokeCap(_ cap: SkStrokeCap) { cskia_paint_set_stroke_cap(base, cap.rawValue) }
    func getStrokeCap() -> SkStrokeCap { SkStrokeCap(rawValue: cskia_paint_get_stroke_cap(base)) ?? .butt }

    func setStrokeJoin(_ join: SkStrokeJoin) { cskia_paint_set_stroke_join(base, join.rawValue) }
    func getStrokeJoin() -> SkStrokeJoin { SkStrokeJoin(rawValue: cskia_paint_get_stroke_join(base)) ?? .miter }

    // shader / path effect / blend / mask filter
    /// The paint keeps its own reference to `shader`.
    func setShader<S: SkiaShader>(_ shader: S) { cskia_paint_set_shader(base, shader.base) }
    /// SkPaint::setShader(nullptr)
    func clearShader() { cskia_paint_set_shader(base, nil) }

    /// The paint keeps its own reference to `effect`.
    func setPathEffect<E: SkiaPathEffect>(_ effect: E) { cskia_paint_set_path_effect(base, effect.base) }
    /// SkPaint::setPathEffect(nullptr)
    func clearPathEffect() { cskia_paint_set_path_effect(base, nil) }

    func setBlendMode(_ mode: SkBlendMode) { cskia_paint_set_blend_mode(base, mode.rawValue) }
    func getBlendMode() -> SkBlendMode { SkBlendMode(rawValue: cskia_paint_get_blend_mode(base)) ?? .srcOver }

    /// SkPaint::setMaskFilter(SkMaskFilter::MakeBlur(style, sigma)).
    func setMaskFilterBlur(_ style: SkBlurStyle = .normal, sigma: Float) {
        cskia_paint_set_mask_filter_blur(base, style.rawValue, sigma)
    }
    /// SkPaint::setMaskFilter(nullptr)
    func clearMaskFilter() { cskia_paint_set_mask_filter_blur(base, 0, 0) }
}
