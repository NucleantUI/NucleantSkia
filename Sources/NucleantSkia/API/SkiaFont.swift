//
//  SkiaFont.swift
//  NucleantSkia
//
import CSkia

/// SkTypeface — one loaded face.
public protocol SkiaTypeface {
    var base: OpaquePointer { get }
}

public extension SkiaTypeface {
    func getFamilyName() -> String {
        let length = cskia_typeface_get_family_name(base, nil, 0)
        var buffer = [CChar](repeating: 0, count: length + 1)
        _ = cskia_typeface_get_family_name(base, &buffer, buffer.count)
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    func countGlyphs() -> Int32 { cskia_typeface_count_glyphs(base) }
}

/// SkFontMgr — the platform's font manager (CoreText on Apple, fontconfig
/// on Linux, the system font set on Android). Faces made here rasterize
/// through the same scaler as the system's own.
public enum SkFontMgr {

    public static func makeFromData(_ bytes: [UInt8], ttcIndex: Int32 = 0) -> SkTypeface? {
        bytes.withUnsafeBytes {
            cskia_typeface_make_from_data($0.baseAddress, $0.count, ttcIndex)
        }.map(SkTypeface.init(adopting:))
    }

    public static func makeFromFile(_ path: String, ttcIndex: Int32 = 0) -> SkTypeface? {
        cskia_typeface_make_from_file(path, ttcIndex).map(SkTypeface.init(adopting:))
    }

    /// `family == nil` is the platform default face.
    public static func matchFamilyStyle(_ family: String?, style: SkFontStyle = .normal) -> SkTypeface? {
        let made: OpaquePointer?
        if let family {
            made = cskia_typeface_match_family_style(family, style.weight, style.width, style.slant.rawValue)
        } else {
            made = cskia_typeface_match_family_style(nil, style.weight, style.width, style.slant.rawValue)
        }
        return made.map(SkTypeface.init(adopting:))
    }
}

/// SkFont — a typeface at a size, with the knobs that change how glyphs
/// are measured and rasterized.
public protocol SkiaFont {
    var base: OpaquePointer { get }
}

public extension SkiaFont {

    /// The font keeps its own reference to `typeface`.
    func setTypeface<T: SkiaTypeface>(_ typeface: T) { cskia_font_set_typeface(base, typeface.base) }
    func refTypeface() -> SkTypeface? { cskia_font_ref_typeface(base).map(SkTypeface.init(adopting:)) }

    func setSize(_ size: Float) { cskia_font_set_size(base, size) }
    func setSize<F: BinaryFloatingPoint>(_ size: F) { cskia_font_set_size(base, .init(size)) }
    func getSize() -> Float { cskia_font_get_size(base) }

    func setScaleX(_ scale: Float) { cskia_font_set_scale_x(base, scale) }
    func getScaleX() -> Float { cskia_font_get_scale_x(base) }
    /// Synthetic italic: negative leans right (Skia uses -1/4).
    func setSkewX(_ skew: Float) { cskia_font_set_skew_x(base, skew) }
    func getSkewX() -> Float { cskia_font_get_skew_x(base) }

    func setEmbolden(_ embolden: Bool) { cskia_font_set_embolden(base, embolden) }
    func setSubpixel(_ subpixel: Bool) { cskia_font_set_subpixel(base, subpixel) }
    func setLinearMetrics(_ linear: Bool) { cskia_font_set_linear_metrics(base, linear) }
    func setBaselineSnap(_ snap: Bool) { cskia_font_set_baseline_snap(base, snap) }
    func setEdging(_ edging: SkFontEdging) { cskia_font_set_edging(base, edging.rawValue) }
    func setHinting(_ hinting: SkFontHinting) { cskia_font_set_hinting(base, hinting.rawValue) }

    /// Advance width of `text`.
    func measureText(_ text: String) -> Float {
        var text = text
        return text.withUTF8 { utf8 in
            utf8.withMemoryRebound(to: CChar.self) { cskia_font_measure_text(base, $0.baseAddress, $0.count, nil) }
        }
    }

    /// Advance width of `text`, and its ink box.
    func measureText(_ text: String, bounds: inout (pos: SIMD2<Float>, size: SIMD2<Float>)) -> Float {
        var text = text
        var rect = cskia_rect()
        let advance = text.withUTF8 { utf8 in
            utf8.withMemoryRebound(to: CChar.self) { cskia_font_measure_text(base, $0.baseAddress, $0.count, &rect) }
        }
        bounds = (rect.pos, rect.size)
        return advance
    }

    func textToGlyphs(_ text: String) -> [UInt16] {
        var text = text
        return text.withUTF8 { utf8 in
            utf8.withMemoryRebound(to: CChar.self) { chars -> [UInt16] in
                let count = cskia_font_text_to_glyphs(base, chars.baseAddress, chars.count, nil, 0)
                guard count > 0 else { return [] }
                var glyphs = [UInt16](repeating: 0, count: Int(count))
                _ = cskia_font_text_to_glyphs(base, chars.baseAddress, chars.count, &glyphs, count)
                return glyphs
            }
        }
    }

    /// Advance width of each glyph.
    func getWidths(_ glyphs: [UInt16]) -> [Float] {
        guard !glyphs.isEmpty else { return [] }
        var widths = [Float](repeating: 0, count: glyphs.count)
        cskia_font_get_widths(base, glyphs, Int32(glyphs.count), &widths)
        return widths
    }

    func getMetrics() -> SkFontMetrics {
        var metrics = cskia_font_metrics()
        _ = cskia_font_get_metrics(base, &metrics)
        return SkFontMetrics(metrics)
    }

    /// Recommended line spacing: descent − ascent + leading.
    func getSpacing() -> Float { cskia_font_get_spacing(base) }
}
