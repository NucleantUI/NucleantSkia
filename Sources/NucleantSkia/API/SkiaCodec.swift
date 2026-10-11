//
//  SkiaCodec.swift
//  NucleantSkia
//
import CSkia

/// SkCodec — an encoded image (PNG, …) with the decoder that reads it.
/// Uniquely owned, as in Skia.
public final class SkCodec {
    let base: OpaquePointer

    init(base: OpaquePointer) { self.base = base }

    deinit { cskia_codec_delete(base) }

    /// SkCodec::MakeFromData — `nil` when none of the decoders this Skia
    /// build has reads `bytes`. The bytes are copied.
    public static func makeFromData(_ bytes: UnsafeRawBufferPointer) -> SkCodec? {
        cskia_codec_make_from_data(bytes.baseAddress, bytes.count).map(SkCodec.init(base:))
    }

    public func width() -> Int32 { cskia_codec_get_width(base) }
    public func height() -> Int32 { cskia_codec_get_height(base) }
    public func size() -> SIMD2<Int32> { SIMD2(width(), height()) }

    /// SkCodec::getPixels — the whole image, one `UInt32` a pixel, row after
    /// row. Premultiplied `.bgra8888` is ARGB in native (little-endian) order.
    /// `nil` unless every row decoded.
    public func getPixels(colorType: SkColorType = .bgra8888, alphaType: SkAlphaType = .premul) -> [UInt32]? {
        let width = Int(width()), height = Int(height())
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0, count: width * height)
        let decoded = pixels.withUnsafeMutableBytes {
            cskia_codec_get_pixels(base, $0.baseAddress, width * 4, colorType.rawValue, alphaType.rawValue)
        }
        return decoded ? pixels : nil
    }
}
