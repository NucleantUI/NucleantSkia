//
//  SkiaShader.swift
//  NucleantSkia
//
import CSkia

/// SkShader — what a paint fills with instead of a flat color.
public protocol SkiaShader {
    var base: OpaquePointer { get }
}

/// SkGradientShader. `colors` are (r, g, b, a) 0…1; `positions` 0…1, one
/// per color, or `nil` for evenly spaced.
public enum SkGradientShader {

    public static func makeLinear(
        from p0: SIMD2<Float>, to p1: SIMD2<Float>,
        colors: [SIMD4<Float>], positions: [Float]? = nil,
        mode: SkTileMode = .clamp
    ) -> SkShader? {
        make(colors, positions) { c, p, n in
            cskia_shader_make_linear_gradient(p0.x, p0.y, p1.x, p1.y, c, p, n, mode.rawValue)
        }
    }

    public static func makeRadial(
        center: SIMD2<Float>, radius: Float,
        colors: [SIMD4<Float>], positions: [Float]? = nil,
        mode: SkTileMode = .clamp
    ) -> SkShader? {
        make(colors, positions) { c, p, n in
            cskia_shader_make_radial_gradient(center.x, center.y, radius, c, p, n, mode.rawValue)
        }
    }

    public static func makeTwoPointConical(
        start: SIMD2<Float>, startRadius: Float,
        end: SIMD2<Float>, endRadius: Float,
        colors: [SIMD4<Float>], positions: [Float]? = nil,
        mode: SkTileMode = .clamp
    ) -> SkShader? {
        make(colors, positions) { c, p, n in
            cskia_shader_make_two_point_conical_gradient(start.x, start.y, startRadius, end.x, end.y, endRadius, c, p, n, mode.rawValue)
        }
    }

    /// Angles in degrees, clockwise from +x.
    public static func makeSweep(
        center: SIMD2<Float>, startAngle: Float = 0, endAngle: Float = 360,
        colors: [SIMD4<Float>], positions: [Float]? = nil,
        mode: SkTileMode = .clamp
    ) -> SkShader? {
        make(colors, positions) { c, p, n in
            cskia_shader_make_sweep_gradient(center.x, center.y, startAngle, endAngle, c, p, n, mode.rawValue)
        }
    }

    private static func make(
        _ colors: [SIMD4<Float>], _ positions: [Float]?,
        _ body: (UnsafePointer<Float>, UnsafePointer<Float>?, Int32) -> OpaquePointer?
    ) -> SkShader? {
        guard !colors.isEmpty, positions.map({ $0.count == colors.count }) ?? true else { return nil }
        let flat = flatten(colors)
        let made = flat.withUnsafeBufferPointer { c in
            if let positions {
                return positions.withUnsafeBufferPointer { p in body(c.baseAddress!, p.baseAddress, Int32(colors.count)) }
            }
            return body(c.baseAddress!, nil, Int32(colors.count))
        }
        return made.map(SkShader.init(adopting:))
    }
}

/// SkShaders
public enum SkShaders {
    /// (r, g, b, a), 0…1.
    public static func color(_ color: SIMD4<Float>) -> SkShader? {
        cskia_shader_make_color(color.x, color.y, color.z, color.w).map(SkShader.init(adopting:))
    }
}
