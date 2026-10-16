//
//  SkiaSVG.swift
//  NucleantSkia
//
import CSkia

/// SkSVGDOM — an SVG document parsed by Skia's SVG module, drawn into any
/// canvas. Ref-counted in Skia; this holds one reference.
///
/// The browser's Skia has no SVG module: `make` is always `nil` there.
public final class SkSVGDOM {
    let base: OpaquePointer

    init(adopting base: OpaquePointer) { self.base = base }

    deinit { cskia_svg_dom_unref(base) }

    /// SkSVGDOM::Builder().make — `nil` when `bytes` isn't an SVG document.
    /// <text> is laid out with the platform's fonts. The bytes are copied.
    public static func make(_ bytes: UnsafeRawBufferPointer) -> SkSVGDOM? {
        cskia_svg_dom_make_from_data(bytes.baseAddress, bytes.count).map(SkSVGDOM.init(adopting:))
    }

    /// The root <svg>'s width and height in pixels; 0 for one given in
    /// percent (the default), when the `viewBox` says the size.
    public func intrinsicSize() -> SIMD2<Float> {
        var width: Float = 0, height: Float = 0
        cskia_svg_dom_get_intrinsic_size(base, &width, &height)
        return SIMD2(width, height)
    }

    /// The root <svg>'s viewBox, `nil` when it has none.
    public func viewBox() -> (pos: SIMD2<Float>, size: SIMD2<Float>)? {
        var x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0
        guard cskia_svg_dom_get_view_box(base, &x, &y, &width, &height) else { return nil }
        return (SIMD2(x, y), SIMD2(width, height))
    }

    /// The viewport `render` fills, from the canvas's origin.
    public func setContainerSize(_ size: SIMD2<Float>) {
        cskia_svg_dom_set_container_size(base, size.x, size.y)
    }

    public func render<C: SkiaCanvas>(_ canvas: C) {
        cskia_svg_dom_render(base, canvas.base)
    }
}
