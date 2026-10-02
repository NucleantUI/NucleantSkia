//
//  SkiaTypes.swift
//  NucleantSkia
//
//  Skia's enums and small value types, named as in Skia. Raw values are
//  Skia's own, which is what the C layer passes straight through.
//
import CSkia

/// SkPaint::Style
public enum SkPaintStyle: Int32 {
    case fill, stroke, strokeAndFill
}

/// SkPaint::Cap
public enum SkStrokeCap: Int32 {
    case butt, round, square
}

/// SkPaint::Join
public enum SkStrokeJoin: Int32 {
    case miter, round, bevel
}

/// SkPathFillType
public enum SkPathFillType: Int32 {
    case winding, evenOdd, inverseWinding, inverseEvenOdd
}

/// SkPathDirection
public enum SkPathDirection: Int32 {
    case cw, ccw
}

/// SkClipOp
public enum SkClipOp: Int32 {
    case difference, intersect
}

/// SkTileMode
public enum SkTileMode: Int32 {
    case clamp, `repeat`, mirror, decal
}

/// SkBlurStyle
public enum SkBlurStyle: Int32 {
    case normal, solid, outer, inner
}

/// SkBlendMode
public enum SkBlendMode: Int32 {
    case clear, src, dst, srcOver, dstOver, srcIn, dstIn, srcOut, dstOut
    case srcATop, dstATop, xor, plus, modulate, screen
    case overlay, darken, lighten, colorDodge, colorBurn, hardLight, softLight
    case difference, exclusion, multiply
    case hue, saturation, color, luminosity
}

/// SkFont::Edging
public enum SkFontEdging: Int32 {
    case alias, antiAlias, subpixelAntiAlias
}

/// SkFontHinting
public enum SkFontHinting: Int32 {
    case none, slight, normal, full
}

/// SkColorType — the two 8-bit orders a VkImage / bitmap comes in.
public enum SkColorType: Int32 {
    case rgba8888, bgra8888
}

/// SkAlphaType
public enum SkAlphaType: Int32 {
    case opaque = 1, premul, unpremul
}

/// SkFontStyle
public struct SkFontStyle: Hashable, Sendable {
    /// SkFontStyle::Slant
    public enum Slant: Int32, Sendable {
        case upright, italic, oblique
    }

    /// 100…1000; 400 normal, 700 bold.
    public var weight: Int32
    /// 1…9; 5 normal.
    public var width: Int32
    public var slant: Slant

    public init(weight: Int32 = 400, width: Int32 = 5, slant: Slant = .upright) {
        self.weight = weight
        self.width = width
        self.slant = slant
    }

    public static let normal = SkFontStyle()
    public static let bold = SkFontStyle(weight: 700)
    public static let italic = SkFontStyle(slant: .italic)
    public static let boldItalic = SkFontStyle(weight: 700, slant: .italic)
}

/// SkMatrix — 3×3, in SkMatrix's own order.
public struct SkMatrix: Hashable, Sendable {
    public var scaleX: Float, skewX: Float, transX: Float
    public var skewY: Float, scaleY: Float, transY: Float
    public var persp0: Float, persp1: Float, persp2: Float

    public init(
        scaleX: Float = 1, skewX: Float = 0, transX: Float = 0,
        skewY: Float = 0, scaleY: Float = 1, transY: Float = 0,
        persp0: Float = 0, persp1: Float = 0, persp2: Float = 1
    ) {
        self.scaleX = scaleX; self.skewX = skewX; self.transX = transX
        self.skewY = skewY; self.scaleY = scaleY; self.transY = transY
        self.persp0 = persp0; self.persp1 = persp1; self.persp2 = persp2
    }

    public static let identity = SkMatrix()

    /// SkMatrix::Translate
    public static func translate(_ d: SIMD2<Float>) -> SkMatrix { SkMatrix(transX: d.x, transY: d.y) }
    /// SkMatrix::Scale
    public static func scale(_ s: SIMD2<Float>) -> SkMatrix { SkMatrix(scaleX: s.x, scaleY: s.y) }

    init(_ m: cskia_matrix) {
        self.init(
            scaleX: m.scale_x, skewX: m.skew_x, transX: m.trans_x,
            skewY: m.skew_y, scaleY: m.scale_y, transY: m.trans_y,
            persp0: m.persp_0, persp1: m.persp_1, persp2: m.persp_2
        )
    }

    var c: cskia_matrix {
        cskia_matrix(
            scale_x: scaleX, skew_x: skewX, trans_x: transX,
            skew_y: skewY, scale_y: scaleY, trans_y: transY,
            persp_0: persp0, persp_1: persp1, persp_2: persp2
        )
    }
}

/// SkFontMetrics
public struct SkFontMetrics: Hashable, Sendable {
    public var flags: UInt32
    /// Greatest extent above the baseline of any glyph — typically negative.
    public var top: Float
    /// Distance to reserve above the baseline — typically negative.
    public var ascent: Float
    /// Distance to reserve below the baseline — typically positive.
    public var descent: Float
    public var bottom: Float
    public var leading: Float
    public var avgCharWidth: Float
    public var maxCharWidth: Float
    public var xMin: Float
    public var xMax: Float
    public var xHeight: Float
    public var capHeight: Float
    public var underlineThickness: Float
    public var underlinePosition: Float
    public var strikeoutThickness: Float
    public var strikeoutPosition: Float

    init(_ m: cskia_font_metrics) {
        flags = m.flags
        top = m.top; ascent = m.ascent; descent = m.descent; bottom = m.bottom; leading = m.leading
        avgCharWidth = m.avg_char_width; maxCharWidth = m.max_char_width
        xMin = m.x_min; xMax = m.x_max; xHeight = m.x_height; capHeight = m.cap_height
        underlineThickness = m.underline_thickness; underlinePosition = m.underline_position
        strikeoutThickness = m.strikeout_thickness; strikeoutPosition = m.strikeout_position
    }
}

// MARK: - Internal helpers

extension SIMD4 where Scalar == UInt8 {
    /// (r, g, b, a) → SkColor's 0xAARRGGBB.
    var argb: UInt32 {
        UInt32(w) << 24 | UInt32(x) << 16 | UInt32(y) << 8 | UInt32(z)
    }

    /// SkColor's 0xAARRGGBB → (r, g, b, a).
    init(argb: UInt32) {
        self.init(UInt8(truncatingIfNeeded: argb >> 16), UInt8(truncatingIfNeeded: argb >> 8),
                  UInt8(truncatingIfNeeded: argb), UInt8(truncatingIfNeeded: argb >> 24))
    }
}

extension cskia_rect {
    init(pos: SIMD2<Float>, size: SIMD2<Float>) {
        self.init(x: pos.x, y: pos.y, w: size.x, h: size.y)
    }

    var pos: SIMD2<Float> { SIMD2(x, y) }
    var size: SIMD2<Float> { SIMD2(w, h) }
}

/// `count` × RGBA floats, flat — what the gradient makers take.
func flatten(_ colors: [SIMD4<Float>]) -> [Float] {
    colors.flatMap { [$0.x, $0.y, $0.z, $0.w] }
}
