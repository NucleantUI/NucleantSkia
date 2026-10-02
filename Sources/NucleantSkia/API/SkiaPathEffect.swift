//
//  SkiaPathEffect.swift
//  NucleantSkia
//
import CSkia

/// SkPathEffect — reshapes the geometry a paint strokes (dashes, rounded
/// corners).
public protocol SkiaPathEffect {
    var base: OpaquePointer { get }
}

/// SkDashPathEffect
public enum SkDashPathEffect {
    /// `intervals` alternate on / off lengths — an even count of at least two.
    public static func make(intervals: [Float], phase: Float = 0) -> SkPathEffect? {
        intervals.withUnsafeBufferPointer {
            cskia_path_effect_make_dash($0.baseAddress, Int32(intervals.count), phase)
        }.map(SkPathEffect.init(adopting:))
    }
}

/// SkCornerPathEffect
public enum SkCornerPathEffect {
    public static func make(radius: Float) -> SkPathEffect? {
        cskia_path_effect_make_corner(radius).map(SkPathEffect.init(adopting:))
    }
}
