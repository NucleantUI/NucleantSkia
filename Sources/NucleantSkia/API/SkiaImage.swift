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

    /// nil for a color type other than RGBA_8888 / BGRA_8888.
    func colorType() -> SkColorType? { SkColorType(rawValue: cskia_image_get_color_type(base)) }
    func alphaType() -> SkAlphaType? { SkAlphaType(rawValue: cskia_image_get_alpha_type(base)) }
    func isOpaque() -> Bool { cskia_image_is_opaque(base) }

    /// The pixels of (`origin`, `size`) — the whole image by default — 4
    /// bytes each in `colorType` order, row after row. nil when they can't
    /// be read.
    func readPixels(
        colorType: SkColorType = .rgba8888, alphaType: SkAlphaType = .premul,
        origin: SIMD2<Int32> = .zero, size: SIMD2<Int32>? = nil
    ) -> [UInt8]? {
        let size = size ?? self.size() &- origin
        guard size.x > 0, size.y > 0 else { return nil }
        let rowBytes = Int(size.x) * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * Int(size.y))
        let ok = pixels.withUnsafeMutableBytes {
            cskia_image_read_pixels(base, $0.baseAddress, rowBytes, size.x, size.y, colorType.rawValue, alphaType.rawValue, origin.x, origin.y)
        }
        return ok ? pixels : nil
    }

    /// The pixels in place, for an image already in memory (nil otherwise):
    /// `body` gets them and the bytes per row, valid only inside it.
    func withPeekedPixels<R>(_ body: (UnsafeRawPointer, Int) throws -> R) rethrows -> R? {
        var pixels: UnsafeRawPointer?
        var rowBytes = 0
        guard cskia_image_peek_pixels(base, &pixels, &rowBytes), let pixels else { return nil }
        return try body(pixels, rowBytes)
    }

    /// The pixels of (`origin`, `size`) as an image of their own; nil for a
    /// rect not inside this one.
    func makeSubset(origin: SIMD2<Int32>, size: SIMD2<Int32>) -> SkImage? {
        cskia_image_make_subset(base, origin.x, origin.y, size.x, size.y).map(SkImage.init(adopting:))
    }

    /// Decoded into memory now (an image made from encoded data decodes
    /// when first drawn).
    func makeRasterImage() -> SkImage? {
        cskia_image_make_raster_image(base).map(SkImage.init(adopting:))
    }

    /// Encoded as `format`; `quality` 0…100 for JPEG and WebP (WebP 100 is
    /// lossless). nil when it can't be — always in the browser, whose Skia
    /// has no encoders.
    func encode(_ format: SkEncodedImageFormat = .png, quality: Int32 = 100) -> [UInt8]? {
        guard let data = cskia_image_encode(base, format.rawValue, quality) else { return nil }
        defer { cskia_data_unref(data) }
        let bytes = UnsafeRawBufferPointer(start: cskia_data_get_bytes(data), count: cskia_data_get_size(data))
        return Array(bytes)
    }

    /// A shader repeating, mirroring, clamping or leaving out the image
    /// past its edges, `matrix` placing it.
    func makeShader(
        tileX: SkTileMode = .clamp, tileY: SkTileMode = .clamp,
        sampling: SkSamplingOptions = .linear, matrix: SkMatrix = .identity
    ) -> SkShader? {
        var options = sampling.c
        var m = matrix.c
        return cskia_shader_make_image(base, tileX.rawValue, tileY.rawValue, &options, &m).map(SkShader.init(adopting:))
    }
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
