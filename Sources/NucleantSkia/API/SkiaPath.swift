//
//  SkiaPath.swift
//  NucleantSkia
//
import CSkia

/// SkPath — lines and curves, plus whole rects / rounded rects / ovals /
/// circles / arcs, with a fill type.
public protocol SkiaPath {
    var base: OpaquePointer { get }
}

public extension SkiaPath {

    func reset() { cskia_path_reset(base) }
    func rewind() { cskia_path_rewind(base) }

    // moveTo
    func moveTo(x: Float, y: Float) { cskia_path_move_to(base, x, y) }
    func moveTo<F: BinaryFloatingPoint>(x: F, y: F) { cskia_path_move_to(base, .init(x), .init(y)) }
    func moveTo(_ pos: SIMD2<Float>) { cskia_path_move_to(base, pos.x, pos.y) }
    func moveTo<F: BinaryFloatingPoint & SIMDScalar>(_ pos: SIMD2<F>) { moveTo(SIMD2<Float>(pos)) }

    // lineTo
    func lineTo(x: Float, y: Float) { cskia_path_line_to(base, x, y) }
    func lineTo<F: BinaryFloatingPoint>(x: F, y: F) { cskia_path_line_to(base, .init(x), .init(y)) }
    func lineTo(_ pos: SIMD2<Float>) { cskia_path_line_to(base, pos.x, pos.y) }
    func lineTo<F: BinaryFloatingPoint & SIMDScalar>(_ pos: SIMD2<F>) { lineTo(SIMD2<Float>(pos)) }

    // quadTo
    func quadTo(x1: Float, y1: Float, x2: Float, y2: Float) { cskia_path_quad_to(base, x1, y1, x2, y2) }
    func quadTo(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>) { cskia_path_quad_to(base, p1.x, p1.y, p2.x, p2.y) }
    func quadTo<F: BinaryFloatingPoint & SIMDScalar>(_ p1: SIMD2<F>, _ p2: SIMD2<F>) { quadTo(SIMD2<Float>(p1), SIMD2<Float>(p2)) }

    // conicTo
    func conicTo(x1: Float, y1: Float, x2: Float, y2: Float, weight: Float) { cskia_path_conic_to(base, x1, y1, x2, y2, weight) }
    func conicTo(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, weight: Float) { cskia_path_conic_to(base, p1.x, p1.y, p2.x, p2.y, weight) }
    func conicTo<F: BinaryFloatingPoint & SIMDScalar>(_ p1: SIMD2<F>, _ p2: SIMD2<F>, weight: F) {
        conicTo(SIMD2<Float>(p1), SIMD2<Float>(p2), weight: Float(weight))
    }

    // cubicTo
    func cubicTo(x1: Float, y1: Float, x2: Float, y2: Float, x3: Float, y3: Float) { cskia_path_cubic_to(base, x1, y1, x2, y2, x3, y3) }
    func cubicTo<F: BinaryFloatingPoint>(x1: F, y1: F, x2: F, y2: F, x3: F, y3: F) {
        cskia_path_cubic_to(base, .init(x1), .init(y1), .init(x2), .init(y2), .init(x3), .init(y3))
    }
    func cubicTo(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, _ p3: SIMD2<Float>) { cskia_path_cubic_to(base, p1.x, p1.y, p2.x, p2.y, p3.x, p3.y) }
    func cubicTo<F: BinaryFloatingPoint & SIMDScalar>(_ p1: SIMD2<F>, _ p2: SIMD2<F>, _ p3: SIMD2<F>) {
        cubicTo(SIMD2<Float>(p1), SIMD2<Float>(p2), SIMD2<Float>(p3))
    }

    func close() { cskia_path_close(base) }

    // addRect
    func addRect(x: Float, y: Float, w: Float, h: Float, dir: SkPathDirection = .cw) { cskia_path_add_rect(base, x, y, w, h, dir.rawValue) }
    func addRect(pos: SIMD2<Float>, size: SIMD2<Float>, dir: SkPathDirection = .cw) { cskia_path_add_rect(base, pos.x, pos.y, size.x, size.y, dir.rawValue) }
    func addRect<F: BinaryFloatingPoint & SIMDScalar>(pos: SIMD2<F>, size: SIMD2<F>, dir: SkPathDirection = .cw) {
        addRect(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), dir: dir)
    }

    // addRRect
    func addRRect(pos: SIMD2<Float>, size: SIMD2<Float>, radius: SIMD2<Float>, dir: SkPathDirection = .cw) {
        cskia_path_add_rrect(base, pos.x, pos.y, size.x, size.y, radius.x, radius.y, dir.rawValue)
    }
    func addRRect<F: BinaryFloatingPoint & SIMDScalar>(pos: SIMD2<F>, size: SIMD2<F>, radius: SIMD2<F>, dir: SkPathDirection = .cw) {
        addRRect(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), radius: SIMD2<Float>(radius), dir: dir)
    }

    // addOval
    func addOval(pos: SIMD2<Float>, size: SIMD2<Float>, dir: SkPathDirection = .cw) { cskia_path_add_oval(base, pos.x, pos.y, size.x, size.y, dir.rawValue) }
    func addOval<F: BinaryFloatingPoint & SIMDScalar>(pos: SIMD2<F>, size: SIMD2<F>, dir: SkPathDirection = .cw) {
        addOval(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), dir: dir)
    }

    // addCircle
    func addCircle(x: Float, y: Float, radius: Float, dir: SkPathDirection = .cw) { cskia_path_add_circle(base, x, y, radius, dir.rawValue) }
    func addCircle(center: SIMD2<Float>, radius: Float, dir: SkPathDirection = .cw) { cskia_path_add_circle(base, center.x, center.y, radius, dir.rawValue) }
    func addCircle<F: BinaryFloatingPoint & SIMDScalar>(center: SIMD2<F>, radius: F, dir: SkPathDirection = .cw) {
        addCircle(center: SIMD2<Float>(center), radius: Float(radius), dir: dir)
    }

    // addArc — the oval's box, angles in degrees.
    func addArc(pos: SIMD2<Float>, size: SIMD2<Float>, startAngle: Float, sweepAngle: Float) {
        cskia_path_add_arc(base, pos.x, pos.y, size.x, size.y, startAngle, sweepAngle)
    }
    func addArc<F: BinaryFloatingPoint & SIMDScalar>(pos: SIMD2<F>, size: SIMD2<F>, startAngle: F, sweepAngle: F) {
        addArc(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), startAngle: Float(startAngle), sweepAngle: Float(sweepAngle))
    }

    // addPath
    func addPath<P: SkiaPath>(_ src: P, offset: SIMD2<Float> = .zero) { cskia_path_add_path(base, src.base, offset.x, offset.y) }

    // fill type
    func setFillType(_ type: SkPathFillType) { cskia_path_set_fill_type(base, type.rawValue) }
    func getFillType() -> SkPathFillType { SkPathFillType(rawValue: cskia_path_get_fill_type(base)) ?? .winding }

    // queries
    func getBounds() -> (pos: SIMD2<Float>, size: SIMD2<Float>) {
        var rect = cskia_rect()
        cskia_path_get_bounds(base, &rect)
        return (rect.pos, rect.size)
    }
    func computeTightBounds() -> (pos: SIMD2<Float>, size: SIMD2<Float>) {
        var rect = cskia_rect()
        cskia_path_compute_tight_bounds(base, &rect)
        return (rect.pos, rect.size)
    }
    func contains(x: Float, y: Float) -> Bool { cskia_path_contains(base, x, y) }
    func contains(_ point: SIMD2<Float>) -> Bool { cskia_path_contains(base, point.x, point.y) }
    func isEmpty() -> Bool { cskia_path_is_empty(base) }
    func countPoints() -> Int32 { cskia_path_count_points(base) }
    func countVerbs() -> Int32 { cskia_path_count_verbs(base) }

    // in-place transforms
    func offset(dx: Float, dy: Float) { cskia_path_offset(base, dx, dy) }
    func offset(_ d: SIMD2<Float>) { cskia_path_offset(base, d.x, d.y) }
    func transform(_ matrix: SkMatrix) {
        var m = matrix.c
        cskia_path_transform(base, &m)
    }
}
