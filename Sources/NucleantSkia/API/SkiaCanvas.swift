//
//  SkiaCanvas.swift
//  NucleantSkia
//
import CSkia

/// SkCanvas — the draw calls, the save/restore stack, the matrix and the
/// clip. Borrowed from a surface; it lives as long as that surface.
public protocol SkiaCanvas {
    var base: OpaquePointer { get }
}

public extension SkiaCanvas {

    // MARK: save / restore

    @discardableResult func save() -> Int32 { cskia_canvas_save(base) }

    @discardableResult func saveLayer() -> Int32 { cskia_canvas_save_layer(base, nil, nil) }
    @discardableResult func saveLayer<P: SkiaPaint>(paint: P) -> Int32 { cskia_canvas_save_layer(base, nil, paint.base) }
    @discardableResult func saveLayer<P: SkiaPaint>(pos: SIMD2<Float>, size: SIMD2<Float>, paint: P) -> Int32 {
        var bounds = cskia_rect(pos: pos, size: size)
        return cskia_canvas_save_layer(base, &bounds, paint.base)
    }

    @discardableResult func saveLayerAlphaf(_ alpha: Float) -> Int32 { cskia_canvas_save_layer_alphaf(base, nil, alpha) }
    @discardableResult func saveLayerAlphaf(pos: SIMD2<Float>, size: SIMD2<Float>, alpha: Float) -> Int32 {
        var bounds = cskia_rect(pos: pos, size: size)
        return cskia_canvas_save_layer_alphaf(base, &bounds, alpha)
    }

    func restore() { cskia_canvas_restore(base) }
    func restoreToCount(_ count: Int32) { cskia_canvas_restore_to_count(base, count) }
    func getSaveCount() -> Int32 { cskia_canvas_get_save_count(base) }

    // MARK: matrix

    func translate(dx: Float, dy: Float) { cskia_canvas_translate(base, dx, dy) }
    func translate<F: BinaryFloatingPoint>(dx: F, dy: F) { cskia_canvas_translate(base, .init(dx), .init(dy)) }
    func translate(_ d: SIMD2<Float>) { cskia_canvas_translate(base, d.x, d.y) }
    func translate<F: BinaryFloatingPoint & SIMDScalar>(_ d: SIMD2<F>) { translate(SIMD2<Float>(d)) }

    func scale(sx: Float, sy: Float) { cskia_canvas_scale(base, sx, sy) }
    func scale(_ factor: Float) { cskia_canvas_scale(base, factor, factor) }
    func scale(_ s: SIMD2<Float>) { cskia_canvas_scale(base, s.x, s.y) }
    func scale<F: BinaryFloatingPoint & SIMDScalar>(_ s: SIMD2<F>) { scale(SIMD2<Float>(s)) }

    /// Degrees, about the origin.
    func rotate(_ degrees: Float) { cskia_canvas_rotate(base, degrees) }
    func rotate<F: BinaryFloatingPoint>(_ degrees: F) { cskia_canvas_rotate(base, .init(degrees)) }
    /// Degrees, about `point`.
    func rotate(_ degrees: Float, about point: SIMD2<Float>) { cskia_canvas_rotate_about(base, degrees, point.x, point.y) }

    func skew(sx: Float, sy: Float) { cskia_canvas_skew(base, sx, sy) }
    func skew(_ s: SIMD2<Float>) { cskia_canvas_skew(base, s.x, s.y) }

    func concat(_ matrix: SkMatrix) {
        var m = matrix.c
        cskia_canvas_concat(base, &m)
    }
    func setMatrix(_ matrix: SkMatrix) {
        var m = matrix.c
        cskia_canvas_set_matrix(base, &m)
    }
    func resetMatrix() { cskia_canvas_reset_matrix(base) }
    func getTotalMatrix() -> SkMatrix {
        var m = cskia_matrix()
        cskia_canvas_get_total_matrix(base, &m)
        return SkMatrix(m)
    }

    // MARK: clip

    func clipRect(pos: SIMD2<Float>, size: SIMD2<Float>, op: SkClipOp = .intersect, doAntiAlias: Bool = false) {
        cskia_canvas_clip_rect(base, pos.x, pos.y, size.x, size.y, op.rawValue, doAntiAlias)
    }
    func clipRect<F: BinaryFloatingPoint & SIMDScalar>(pos: SIMD2<F>, size: SIMD2<F>, op: SkClipOp = .intersect, doAntiAlias: Bool = false) {
        clipRect(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), op: op, doAntiAlias: doAntiAlias)
    }

    func clipRRect(pos: SIMD2<Float>, size: SIMD2<Float>, radius: SIMD2<Float>, op: SkClipOp = .intersect, doAntiAlias: Bool = true) {
        cskia_canvas_clip_rrect(base, pos.x, pos.y, size.x, size.y, radius.x, radius.y, op.rawValue, doAntiAlias)
    }
    func clipRRect<F: BinaryFloatingPoint & SIMDScalar>(pos: SIMD2<F>, size: SIMD2<F>, radius: SIMD2<F>, op: SkClipOp = .intersect, doAntiAlias: Bool = true) {
        clipRRect(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), radius: SIMD2<Float>(radius), op: op, doAntiAlias: doAntiAlias)
    }

    func clipPath<P: SkiaPath>(_ path: P, op: SkClipOp = .intersect, doAntiAlias: Bool = true) {
        cskia_canvas_clip_path(base, path.base, op.rawValue, doAntiAlias)
    }

    // MARK: fill everything

    /// (r, g, b, a), 0…1.
    func clear(_ color: SIMD4<Float>) { cskia_canvas_clear_color4f(base, color.x, color.y, color.z, color.w) }
    /// (r, g, b, a), 0…255.
    func clear(_ color: SIMD4<UInt8>) { clear(SIMD4<Float>(color) / 255) }

    /// (r, g, b, a), 0…1.
    func drawColor(_ color: SIMD4<Float>, mode: SkBlendMode = .srcOver) {
        cskia_canvas_draw_color4f(base, color.x, color.y, color.z, color.w, mode.rawValue)
    }

    func drawPaint<P: SkiaPaint>(_ paint: P) { cskia_canvas_draw_paint(base, paint.base) }

    // MARK: shapes

    func drawRect<P: SkiaPaint>(x: Float, y: Float, w: Float, h: Float, paint: P) { cskia_canvas_draw_rect_xywh(base, x, y, w, h, paint.base) }
    func drawRect<P: SkiaPaint>(pos: SIMD2<Float>, size: SIMD2<Float>, paint: P) { cskia_canvas_draw_rect_xywh(base, pos.x, pos.y, size.x, size.y, paint.base) }
    func drawRect<F: BinaryFloatingPoint & SIMDScalar, P: SkiaPaint>(pos: SIMD2<F>, size: SIMD2<F>, paint: P) {
        drawRect(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), paint: paint)
    }

    func drawRRect<P: SkiaPaint>(pos: SIMD2<Float>, size: SIMD2<Float>, radius: SIMD2<Float>, paint: P) {
        cskia_canvas_draw_rrect_xywh(base, pos.x, pos.y, size.x, size.y, radius.x, radius.y, paint.base)
    }
    func drawRRect<F: BinaryFloatingPoint & SIMDScalar, P: SkiaPaint>(pos: SIMD2<F>, size: SIMD2<F>, radius: SIMD2<F>, paint: P) {
        drawRRect(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), radius: SIMD2<Float>(radius), paint: paint)
    }

    func drawOval<P: SkiaPaint>(pos: SIMD2<Float>, size: SIMD2<Float>, paint: P) { cskia_canvas_draw_oval_xywh(base, pos.x, pos.y, size.x, size.y, paint.base) }
    func drawOval<F: BinaryFloatingPoint & SIMDScalar, P: SkiaPaint>(pos: SIMD2<F>, size: SIMD2<F>, paint: P) {
        drawOval(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), paint: paint)
    }

    func drawCircle<P: SkiaPaint>(cx: Float, cy: Float, radius: Float, paint: P) { cskia_canvas_draw_circle_at(base, cx, cy, radius, paint.base) }
    func drawCircle<P: SkiaPaint>(center: SIMD2<Float>, radius: Float, paint: P) { cskia_canvas_draw_circle_at(base, center.x, center.y, radius, paint.base) }
    func drawCircle<F: BinaryFloatingPoint & SIMDScalar, P: SkiaPaint>(center: SIMD2<F>, radius: F, paint: P) {
        drawCircle(center: SIMD2<Float>(center), radius: Float(radius), paint: paint)
    }

    /// The oval's box, angles in degrees.
    func drawArc<P: SkiaPaint>(pos: SIMD2<Float>, size: SIMD2<Float>, startAngle: Float, sweepAngle: Float, useCenter: Bool, paint: P) {
        cskia_canvas_draw_arc_xywh(base, pos.x, pos.y, size.x, size.y, startAngle, sweepAngle, useCenter, paint.base)
    }

    func drawLine<P: SkiaPaint>(x0: Float, y0: Float, x1: Float, y1: Float, paint: P) { cskia_canvas_draw_line_points(base, x0, y0, x1, y1, paint.base) }
    func drawLine<P: SkiaPaint>(from p0: SIMD2<Float>, to p1: SIMD2<Float>, paint: P) { cskia_canvas_draw_line_points(base, p0.x, p0.y, p1.x, p1.y, paint.base) }
    func drawLine<F: BinaryFloatingPoint & SIMDScalar, P: SkiaPaint>(from p0: SIMD2<F>, to p1: SIMD2<F>, paint: P) {
        drawLine(from: SIMD2<Float>(p0), to: SIMD2<Float>(p1), paint: paint)
    }

    func drawPoint<P: SkiaPaint>(x: Float, y: Float, paint: P) { cskia_canvas_draw_point(base, x, y, paint.base) }
    func drawPoint<P: SkiaPaint>(_ point: SIMD2<Float>, paint: P) { cskia_canvas_draw_point(base, point.x, point.y, paint.base) }

    func drawPath<Path: SkiaPath, P: SkiaPaint>(_ path: Path, paint: P) { cskia_canvas_draw_path(base, path.base, paint.base) }

    // MARK: images

    func drawImage<I: SkiaImage>(_ image: I, pos: SIMD2<Float>) { cskia_canvas_draw_image(base, image.base, pos.x, pos.y, nil) }
    func drawImage<I: SkiaImage, P: SkiaPaint>(_ image: I, pos: SIMD2<Float>, paint: P) { cskia_canvas_draw_image(base, image.base, pos.x, pos.y, paint.base) }

    /// The whole image stretched into the rect, linear filtering.
    func drawImageRect<I: SkiaImage>(_ image: I, pos: SIMD2<Float>, size: SIMD2<Float>) {
        cskia_canvas_draw_image_rect(base, image.base, pos.x, pos.y, size.x, size.y, nil)
    }
    func drawImageRect<I: SkiaImage, P: SkiaPaint>(_ image: I, pos: SIMD2<Float>, size: SIMD2<Float>, paint: P) {
        cskia_canvas_draw_image_rect(base, image.base, pos.x, pos.y, size.x, size.y, paint.base)
    }

    // MARK: text

    /// `pos` is the baseline origin.
    func drawSimpleText<Font: SkiaFont, P: SkiaPaint>(_ text: String, pos: SIMD2<Float>, font: Font, paint: P) {
        var text = text
        text.withUTF8 { utf8 in
            utf8.withMemoryRebound(to: CChar.self) {
                cskia_canvas_draw_simple_text(base, $0.baseAddress, $0.count, pos.x, pos.y, font.base, paint.base)
            }
        }
    }

    /// SkCanvas::drawString — `drawSimpleText` with UTF-8.
    func drawString<Font: SkiaFont, P: SkiaPaint>(_ text: String, x: Float, y: Float, font: Font, paint: P) {
        drawSimpleText(text, pos: SIMD2(x, y), font: font, paint: paint)
    }
    func drawString<Font: SkiaFont, P: SkiaPaint>(_ text: String, pos: SIMD2<Float>, font: Font, paint: P) {
        drawSimpleText(text, pos: pos, font: font, paint: paint)
    }
}
