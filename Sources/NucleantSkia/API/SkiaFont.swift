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

    func fontStyle() -> SkFontStyle {
        var weight: Int32 = 0, width: Int32 = 0, slant: Int32 = 0
        cskia_typeface_get_style(base, &weight, &width, &slant)
        return SkFontStyle(weight: weight, width: width, slant: SkFontStyle.Slant(rawValue: slant) ?? .upright)
    }

    func isBold() -> Bool { cskia_typeface_is_bold(base) }
    func isItalic() -> Bool { cskia_typeface_is_italic(base) }
    func isFixedPitch() -> Bool { cskia_typeface_is_fixed_pitch(base) }
    func getUnitsPerEm() -> Int32 { cskia_typeface_get_units_per_em(base) }

    /// 0 when the face has no glyph for it.
    func unicharToGlyph(_ unichar: Unicode.Scalar) -> UInt16 {
        cskia_typeface_unichar_to_glyph(base, Int32(unichar.value))
    }

    /// The sfnt tables' tags ('head', 'cmap', … as big-endian four-char codes).
    func getTableTags() -> [UInt32] {
        let count = cskia_typeface_get_table_tags(base, nil, 0)
        guard count > 0 else { return [] }
        var tags = [UInt32](repeating: 0, count: Int(count))
        _ = cskia_typeface_get_table_tags(base, &tags, count)
        return tags
    }

    /// One table's bytes; nil when the face has no such table.
    func getTableData(_ tag: UInt32) -> [UInt8]? {
        let size = cskia_typeface_get_table_data(base, tag, 0, 0, nil)
        guard size > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        let copied = bytes.withUnsafeMutableBytes { cskia_typeface_get_table_data(base, tag, 0, size, $0.baseAddress) }
        return Array(bytes.prefix(copied))
    }
}

/// A table tag from its four characters ("head", "cmap", …).
public func SkSetFourByteTag(_ tag: String) -> UInt32 {
    tag.utf8.prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
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

    public static func countFamilies() -> Int32 { cskia_font_mgr_count_families() }

    public static func getFamilyName(_ index: Int32) -> String {
        let length = cskia_font_mgr_get_family_name(index, nil, 0)
        var buffer = [CChar](repeating: 0, count: length + 1)
        _ = cskia_font_mgr_get_family_name(index, &buffer, buffer.count)
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    /// Every family the platform has.
    public static func familyNames() -> [String] {
        (0..<countFamilies()).map(getFamilyName)
    }

    /// The family's faces; empty when there's no such family.
    public static func matchFamily(_ family: String) -> SkFontStyleSet {
        SkFontStyleSet(adopting: cskia_font_mgr_match_family(family))
    }

    /// A face near `style` with a glyph for `character` — fallback for text
    /// the face in use can't show. `bcp47` are language tags, most preferred
    /// last. nil when no face has it.
    public static func matchFamilyStyleCharacter(
        _ family: String?, style: SkFontStyle = .normal, bcp47: [String] = [], character: Unicode.Scalar
    ) -> SkTypeface? {
        let made: OpaquePointer? = withCStringArray(bcp47) { tags, count in
            if let family {
                return cskia_font_mgr_match_family_style_character(family, style.weight, style.width, style.slant.rawValue,
                                                                   tags, Int32(count), Int32(character.value))
            }
            return cskia_font_mgr_match_family_style_character(nil, style.weight, style.width, style.slant.rawValue,
                                                               tags, Int32(count), Int32(character.value))
        }
        return made.map(SkTypeface.init(adopting:))
    }
}

/// SkFontStyleSet — the faces of one family.
public final class SkFontStyleSet {
    let base: OpaquePointer

    init(adopting base: OpaquePointer) { self.base = base }

    deinit { cskia_font_style_set_unref(base) }

    public func count() -> Int32 { cskia_font_style_set_count(base) }

    /// Face `index`'s style and its style name ("Bold Italic", …).
    public func getStyle(_ index: Int32) -> (style: SkFontStyle, name: String) {
        var weight: Int32 = 0, width: Int32 = 0, slant: Int32 = 0
        let length = cskia_font_style_set_get_style(base, index, &weight, &width, &slant, nil, 0)
        var buffer = [CChar](repeating: 0, count: length + 1)
        _ = cskia_font_style_set_get_style(base, index, &weight, &width, &slant, &buffer, buffer.count)
        let style = SkFontStyle(weight: weight, width: width, slant: SkFontStyle.Slant(rawValue: slant) ?? .upright)
        return (style, String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)), as: UTF8.self))
    }

    public func createTypeface(_ index: Int32) -> SkTypeface? {
        cskia_font_style_set_create_typeface(base, index).map(SkTypeface.init(adopting:))
    }

    /// The face closest to `style`.
    public func matchStyle(_ style: SkFontStyle) -> SkTypeface? {
        cskia_font_style_set_match_style(base, style.weight, style.width, style.slant.rawValue).map(SkTypeface.init(adopting:))
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

    // MARK: flags

    func isEmbolden() -> Bool { cskia_font_is_embolden(base) }
    func isSubpixel() -> Bool { cskia_font_is_subpixel(base) }
    func isLinearMetrics() -> Bool { cskia_font_is_linear_metrics(base) }
    func isBaselineSnap() -> Bool { cskia_font_is_baseline_snap(base) }
    func setForceAutoHinting(_ force: Bool) { cskia_font_set_force_auto_hinting(base, force) }
    func isForceAutoHinting() -> Bool { cskia_font_is_force_auto_hinting(base) }
    func setEmbeddedBitmaps(_ embedded: Bool) { cskia_font_set_embedded_bitmaps(base, embedded) }
    func isEmbeddedBitmaps() -> Bool { cskia_font_is_embedded_bitmaps(base) }
    func getEdging() -> SkFontEdging { SkFontEdging(rawValue: cskia_font_get_edging(base)) ?? .antiAlias }
    func getHinting() -> SkFontHinting { SkFontHinting(rawValue: cskia_font_get_hinting(base)) ?? .normal }

    // MARK: glyphs

    /// 0 when the typeface has no glyph for it.
    func unicharToGlyph(_ unichar: Unicode.Scalar) -> UInt16 { cskia_font_unichar_to_glyph(base, Int32(unichar.value)) }

    func unicharsToGlyphs(_ unichars: [Unicode.Scalar]) -> [UInt16] {
        guard !unichars.isEmpty else { return [] }
        let values = unichars.map { Int32($0.value) }
        var glyphs = [UInt16](repeating: 0, count: values.count)
        cskia_font_unichars_to_glyphs(base, values, Int32(values.count), &glyphs)
        return glyphs
    }

    /// Each glyph's advance and ink box (as `paint` would draw it, if given).
    func getWidthsBounds<P: SkiaPaint>(_ glyphs: [UInt16], paint: P) -> [(width: Float, bounds: (pos: SIMD2<Float>, size: SIMD2<Float>))] {
        widthsBounds(glyphs, paint: paint.base)
    }
    func getWidthsBounds(_ glyphs: [UInt16]) -> [(width: Float, bounds: (pos: SIMD2<Float>, size: SIMD2<Float>))] {
        widthsBounds(glyphs, paint: nil)
    }

    private func widthsBounds(_ glyphs: [UInt16], paint: OpaquePointer?) -> [(width: Float, bounds: (pos: SIMD2<Float>, size: SIMD2<Float>))] {
        guard !glyphs.isEmpty else { return [] }
        var widths = [Float](repeating: 0, count: glyphs.count)
        var bounds = [cskia_rect](repeating: cskia_rect(), count: glyphs.count)
        cskia_font_get_widths_bounds(base, glyphs, Int32(glyphs.count), &widths, &bounds, paint)
        return zip(widths, bounds).map { ($0, ($1.pos, $1.size)) }
    }

    /// Each glyph's ink box.
    func getBounds(_ glyphs: [UInt16]) -> [(pos: SIMD2<Float>, size: SIMD2<Float>)] {
        getWidthsBounds(glyphs).map(\.bounds)
    }

    /// Where each glyph's origin falls, laid one after another from `origin`.
    func getPos(_ glyphs: [UInt16], origin: SIMD2<Float> = .zero) -> [SIMD2<Float>] {
        guard !glyphs.isEmpty else { return [] }
        var xy = [Float](repeating: 0, count: glyphs.count * 2)
        cskia_font_get_pos(base, glyphs, Int32(glyphs.count), origin.x, origin.y, &xy)
        return (0..<glyphs.count).map { SIMD2(xy[$0 * 2], xy[$0 * 2 + 1]) }
    }

    /// The same, x only.
    func getXPos(_ glyphs: [UInt16], origin: Float = 0) -> [Float] {
        guard !glyphs.isEmpty else { return [] }
        var xpos = [Float](repeating: 0, count: glyphs.count)
        cskia_font_get_x_pos(base, glyphs, Int32(glyphs.count), origin, &xpos)
        return xpos
    }

    /// The glyph's outline, origin at its baseline start; nil for a glyph
    /// with none (a bitmap glyph).
    func getPath(_ glyph: UInt16) -> SkPath? {
        let path = SkPath()
        return cskia_font_get_path(base, glyph, path.base) ? path : nil
    }
}
