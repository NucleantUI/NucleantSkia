//
//  SkiaObjects.swift
//  NucleantSkia
//
//  The owning types behind the protocols, named as in Skia. SkPaint /
//  SkPath / SkFont are values in Skia; here each owns a heap copy, and
//  `copy()` is how to get an independent one. SkTypeface / SkShader /
//  SkPathEffect / SkImage are ref-counted in Skia; each of these holds one
//  reference and gives it back on deinit.
//
import CSkia

// MARK: - Values

public final class SkPaint: SkiaPaint {
    public let base: OpaquePointer

    /// Anti-aliasing is on — Skia's default is off, which no one drawing UI
    /// wants; `setAntiAlias(false)` for the hard-edged case.
    public init() {
        base = cskia_paint_new()
        cskia_paint_set_anti_alias(base, true)
    }

    /// A filled paint of `color`, (r, g, b, a) 0…1.
    public convenience init(color: SIMD4<Float>) {
        self.init()
        setColor4f(color)
    }

    private init(base: OpaquePointer) { self.base = base }

    public func copy() -> SkPaint { SkPaint(base: cskia_paint_copy(base)) }

    deinit { cskia_paint_delete(base) }
}

public final class SkPath: SkiaPath {
    public let base: OpaquePointer

    public init() { base = cskia_path_new() }

    private init(base: OpaquePointer) { self.base = base }

    public func copy() -> SkPath { SkPath(base: cskia_path_copy(base)) }

    deinit { cskia_path_delete(base) }
}

public final class SkFont: SkiaFont {
    public let base: OpaquePointer

    /// `typeface == nil` is Skia's empty default face, which draws nothing —
    /// pass one from `SkFontMgr`.
    public init<T: SkiaTypeface>(_ typeface: T?, size: Float = 12) {
        base = cskia_font_new(typeface?.base, size)
    }

    private init(base: OpaquePointer) { self.base = base }

    public func copy() -> SkFont { SkFont(base: cskia_font_copy(base)) }

    deinit { cskia_font_delete(base) }
}

// MARK: - Ref-counted

public final class SkTypeface: SkiaTypeface {
    public let base: OpaquePointer

    /// Takes over one reference the C layer handed out.
    init(adopting base: OpaquePointer) { self.base = base }

    deinit { cskia_typeface_unref(base) }
}

public final class SkShader: SkiaShader {
    public let base: OpaquePointer

    init(adopting base: OpaquePointer) { self.base = base }

    deinit { cskia_shader_unref(base) }
}

public final class SkPathEffect: SkiaPathEffect {
    public let base: OpaquePointer

    init(adopting base: OpaquePointer) { self.base = base }

    deinit { cskia_path_effect_unref(base) }
}

public final class SkImage: SkiaImage {
    public let base: OpaquePointer

    init(adopting base: OpaquePointer) { self.base = base }

    deinit { cskia_image_unref(base) }
}

// MARK: - Canvas

/// A surface's SkCanvas, borrowed: valid for as long as the surface it came
/// from is alive and still has its Skia side.
public struct SkCanvas: SkiaCanvas {
    public let base: OpaquePointer

    public init(base: OpaquePointer) { self.base = base }
}

extension SkiaSurface {
    /// The surface's canvas — `nil` once the surface is destroyed.
    public var canvas: SkCanvas? {
        skCanvasPointer().map { SkCanvas(base: OpaquePointer($0)) }
    }
}

// MARK: - Raster surface

/// SkSurfaces
public enum SkSurfaces {
    /// SkSurfaces::Raster — CPU pixels, RGBA_8888 premul.
    public static func raster(width: Int32, height: Int32) -> SkRasterSurface? {
        cskia_raster_surface_make(width, height).map(SkRasterSurface.init(base:))
    }

    public static func raster(size: SIMD2<Int32>) -> SkRasterSurface? {
        raster(width: size.x, height: size.y)
    }
}

/// A CPU-backed SkSurface: draw through `getCanvas()`, read the result back
/// with `readPixels()` or keep it as an image with `makeImageSnapshot()`.
public final class SkRasterSurface {
    let base: OpaquePointer

    init(base: OpaquePointer) { self.base = base }

    deinit { cskia_raster_surface_delete(base) }

    /// Valid for as long as this surface.
    public func getCanvas() -> SkCanvas { SkCanvas(base: cskia_raster_surface_get_canvas(base)) }

    public func width() -> Int32 { cskia_raster_surface_get_width(base) }
    public func height() -> Int32 { cskia_raster_surface_get_height(base) }

    /// The pixels as RGBA_8888 unpremul, row after row.
    public func readPixels() -> [UInt8] {
        let rowBytes = Int(width()) * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * Int(height()))
        let ok = pixels.withUnsafeMutableBytes { cskia_raster_surface_read_pixels(base, $0.baseAddress, rowBytes) }
        return ok ? pixels : []
    }

    /// One pixel, (r, g, b, a) unpremul.
    public func readPixel(x: Int, y: Int) -> SIMD4<UInt8>? {
        guard x >= 0, y >= 0, x < Int(width()), y < Int(height()) else { return nil }
        let pixels = readPixels()
        guard !pixels.isEmpty else { return nil }
        let i = (y * Int(width()) + x) * 4
        return SIMD4(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
    }

    public func makeImageSnapshot() -> SkImage? {
        cskia_raster_surface_make_image_snapshot(base).map(SkImage.init(adopting:))
    }
}
