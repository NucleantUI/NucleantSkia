//
//  SkiaImage.swift
//  NucleantSkia
//
import CSkia

/// SkImage — immutable pixels that can be drawn.
public protocol SkiaImage {
    var base: OpaquePointer { get }
}

public extension SkiaImage {
    func width() -> Int32 { cskia_image_get_width(base) }
    func height() -> Int32 { cskia_image_get_height(base) }
    func size() -> SIMD2<Int32> { SIMD2(width(), height()) }
}

/// SkImages
public enum SkImages {

    /// SkImages::RasterFromPixmapCopy — 4 bytes a pixel in `colorType`
    /// order, `rowBytes` per row (`size.x * 4` when nil). The pixels are copied.
    public static func rasterFromPixmapCopy(
        _ pixels: [UInt8],
        size: SIMD2<Int32>,
        rowBytes: Int? = nil,
        colorType: SkColorType = .rgba8888,
        alphaType: SkAlphaType = .premul
    ) -> SkImage? {
        let rowBytes = rowBytes ?? Int(size.x) * 4
        guard size.x > 0, size.y > 0, pixels.count >= rowBytes * Int(size.y) else { return nil }
        return pixels.withUnsafeBytes {
            cskia_image_make_raster_copy($0.baseAddress, size.x, size.y, rowBytes, colorType.rawValue, alphaType.rawValue)
        }.map(SkImage.init(adopting:))
    }

    /// The same from 32-bit pixels, one `UInt32` each — e.g. premultiplied
    /// ARGB in native (little-endian) order is `.bgra8888`.
    public static func rasterFromPixmapCopy(
        _ pixels: [UInt32],
        size: SIMD2<Int32>,
        colorType: SkColorType = .bgra8888,
        alphaType: SkAlphaType = .premul
    ) -> SkImage? {
        guard size.x > 0, size.y > 0, pixels.count >= Int(size.x) * Int(size.y) else { return nil }
        return pixels.withUnsafeBytes {
            cskia_image_make_raster_copy($0.baseAddress, size.x, size.y, Int(size.x) * 4, colorType.rawValue, alphaType.rawValue)
        }.map(SkImage.init(adopting:))
    }
}
