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
    // MARK: relative verbs — from the last point

    func rMoveTo(dx: Float, dy: Float) { cskia_path_r_move_to(base, dx, dy) }
    func rMoveTo(_ d: SIMD2<Float>) { cskia_path_r_move_to(base, d.x, d.y) }
    func rMoveTo<F: BinaryFloatingPoint & SIMDScalar>(_ d: SIMD2<F>) { rMoveTo(SIMD2<Float>(d)) }

    func rLineTo(dx: Float, dy: Float) { cskia_path_r_line_to(base, dx, dy) }
    func rLineTo(_ d: SIMD2<Float>) { cskia_path_r_line_to(base, d.x, d.y) }
    func rLineTo<F: BinaryFloatingPoint & SIMDScalar>(_ d: SIMD2<F>) { rLineTo(SIMD2<Float>(d)) }

    func rQuadTo(_ d1: SIMD2<Float>, _ d2: SIMD2<Float>) { cskia_path_r_quad_to(base, d1.x, d1.y, d2.x, d2.y) }
    func rQuadTo<F: BinaryFloatingPoint & SIMDScalar>(_ d1: SIMD2<F>, _ d2: SIMD2<F>) { rQuadTo(SIMD2<Float>(d1), SIMD2<Float>(d2)) }

    func rConicTo(_ d1: SIMD2<Float>, _ d2: SIMD2<Float>, weight: Float) { cskia_path_r_conic_to(base, d1.x, d1.y, d2.x, d2.y, weight) }
    func rConicTo<F: BinaryFloatingPoint & SIMDScalar>(_ d1: SIMD2<F>, _ d2: SIMD2<F>, weight: F) {
        rConicTo(SIMD2<Float>(d1), SIMD2<Float>(d2), weight: Float(weight))
    }

    func rCubicTo(_ d1: SIMD2<Float>, _ d2: SIMD2<Float>, _ d3: SIMD2<Float>) {
        cskia_path_r_cubic_to(base, d1.x, d1.y, d2.x, d2.y, d3.x, d3.y)
    }
    func rCubicTo<F: BinaryFloatingPoint & SIMDScalar>(_ d1: SIMD2<F>, _ d2: SIMD2<F>, _ d3: SIMD2<F>) {
        rCubicTo(SIMD2<Float>(d1), SIMD2<Float>(d2), SIMD2<Float>(d3))
    }

    // MARK: arcs

    /// An arc tangent to the line from the last point to `p1` and the line
    /// from `p1` to `p2` (SkPath::arcTo(x1, y1, x2, y2, radius)).
    func arcTo(_ p1: SIMD2<Float>, _ p2: SIMD2<Float>, radius: Float) {
        cskia_path_arc_to_tangent(base, p1.x, p1.y, p2.x, p2.y, radius)
    }
    func arcTo<F: BinaryFloatingPoint & SIMDScalar>(_ p1: SIMD2<F>, _ p2: SIMD2<F>, radius: F) {
        arcTo(SIMD2<Float>(p1), SIMD2<Float>(p2), radius: Float(radius))
    }

    /// Part of the oval in the box, angles in degrees; joined to the last
    /// point with a line unless `forceMoveTo`.
    func arcTo(pos: SIMD2<Float>, size: SIMD2<Float>, startAngle: Float, sweepAngle: Float, forceMoveTo: Bool) {
        cskia_path_arc_to_oval(base, pos.x, pos.y, size.x, size.y, startAngle, sweepAngle, forceMoveTo)
    }
    func arcTo<F: BinaryFloatingPoint & SIMDScalar>(pos: SIMD2<F>, size: SIMD2<F>, startAngle: F, sweepAngle: F, forceMoveTo: Bool) {
        arcTo(pos: SIMD2<Float>(pos), size: SIMD2<Float>(size), startAngle: Float(startAngle), sweepAngle: Float(sweepAngle), forceMoveTo: forceMoveTo)
    }

    /// SVG's elliptical arc to `end`: radii, the ellipse's rotation in
    /// degrees, which of the two arcs (`largeArc`) and which way round.
    func arcTo(radii: SIMD2<Float>, xAxisRotate: Float = 0, largeArc: Bool, sweep: SkPathDirection, end: SIMD2<Float>) {
        cskia_path_arc_to_svg(base, radii.x, radii.y, xAxisRotate, largeArc, sweep.rawValue, end.x, end.y, false)
    }
    /// `arcTo(radii:…)` with `end` relative to the last point.
    func rArcTo(radii: SIMD2<Float>, xAxisRotate: Float = 0, largeArc: Bool, sweep: SkPathDirection, end: SIMD2<Float>) {
        cskia_path_arc_to_svg(base, radii.x, radii.y, xAxisRotate, largeArc, sweep.rawValue, end.x, end.y, true)
    }

    // MARK: more shapes

    /// A rounded rect with each corner's own (x, y) radii: upper-left,
    /// upper-right, lower-right, lower-left.
    func addRRect(pos: SIMD2<Float>, size: SIMD2<Float>, cornerRadii: [SIMD2<Float>], dir: SkPathDirection = .cw) {
        precondition(cornerRadii.count == 4, "four corners: upper-left, upper-right, lower-right, lower-left")
        let radii = cornerRadii.flatMap { [$0.x, $0.y] }
        cskia_path_add_rrect_radii(base, pos.x, pos.y, size.x, size.y, radii, dir.rawValue)
    }

    func addPoly(_ points: [SIMD2<Float>], close: Bool) {
        let xy = points.flatMap { [$0.x, $0.y] }
        cskia_path_add_poly(base, xy, Int32(points.count), close)
    }
    func addPoly<F: BinaryFloatingPoint & SIMDScalar>(_ points: [SIMD2<F>], close: Bool) {
        addPoly(points.map(SIMD2<Float>.init), close: close)
    }

    /// `src` mapped by `matrix`.
    func addPath<P: SkiaPath>(_ src: P, matrix: SkMatrix, mode: SkPathAddPathMode = .append) {
        var m = matrix.c
        cskia_path_add_path_matrix(base, src.base, &m, mode.rawValue)
    }

    /// `src`'s contours, last first, each run backwards.
    func reverseAddPath<P: SkiaPath>(_ src: P) { cskia_path_reverse_add_path(base, src.base) }

    func toggleInverseFillType() { cskia_path_toggle_inverse_fill_type(base) }
    func isInverseFillType() -> Bool { cskia_path_is_inverse_fill_type(base) }

    // MARK: points

    func getPoint(_ index: Int) -> SIMD2<Float>? {
        var x: Float = 0, y: Float = 0
        return cskia_path_get_point(base, Int32(index), &x, &y) ? SIMD2(x, y) : nil
    }

    func getPoints() -> [SIMD2<Float>] {
        let count = Int(cskia_path_get_points(base, nil, 0))
        guard count > 0 else { return [] }
        var xy = [Float](repeating: 0, count: count * 2)
        _ = cskia_path_get_points(base, &xy, Int32(count))
        return (0..<count).map { SIMD2(xy[$0 * 2], xy[$0 * 2 + 1]) }
    }

    func getLastPt() -> SIMD2<Float>? {
        var x: Float = 0, y: Float = 0
        return cskia_path_get_last_pt(base, &x, &y) ? SIMD2(x, y) : nil
    }

    func setLastPt(_ point: SIMD2<Float>) { cskia_path_set_last_pt(base, point.x, point.y) }

    // MARK: what it is

    /// The rect, when the path is one.
    func isRect() -> (pos: SIMD2<Float>, size: SIMD2<Float>)? {
        var rect = cskia_rect()
        return cskia_path_is_rect(base, &rect) ? (rect.pos, rect.size) : nil
    }

    /// The oval's bounds, when the path is one.
    func isOval() -> (pos: SIMD2<Float>, size: SIMD2<Float>)? {
        var rect = cskia_rect()
        return cskia_path_is_oval(base, &rect) ? (rect.pos, rect.size) : nil
    }

    /// The two ends, when the path is one line.
    func isLine() -> (SIMD2<Float>, SIMD2<Float>)? {
        var line = [Float](repeating: 0, count: 4)
        return cskia_path_is_line(base, &line) ? (SIMD2(line[0], line[1]), SIMD2(line[2], line[3])) : nil
    }

    func isConvex() -> Bool { cskia_path_is_convex(base) }
    func isFinite() -> Bool { cskia_path_is_finite(base) }
    func isLastContourClosed() -> Bool { cskia_path_is_last_contour_closed(base) }

    /// True only when the rect is surely inside (false can still be inside).
    func conservativelyContainsRect(pos: SIMD2<Float>, size: SIMD2<Float>) -> Bool {
        cskia_path_conservatively_contains_rect(base, pos.x, pos.y, size.x, size.y)
    }

    // MARK: interpolation

    func isInterpolatable<P: SkiaPath>(_ other: P) -> Bool { cskia_path_is_interpolatable(base, other.base) }

    /// self × weight + `ending` × (1 − weight); nil when the two aren't
    /// interpolatable.
    func interpolate<P: SkiaPath>(_ ending: P, weight: Float) -> SkPath? {
        let out = SkPath()
        return cskia_path_interpolate(base, ending.base, weight, out.base) ? out : nil
    }

    // MARK: SVG and bytes

    /// SkParsePath::ToSVGString — the path as an SVG `d`.
    func toSVGString(relative: Bool = false) -> String {
        let length = cskia_path_to_svg_string(base, relative, nil, 0)
        var buffer = [CChar](repeating: 0, count: length + 1)
        _ = cskia_path_to_svg_string(base, relative, &buffer, buffer.count)
        return String(decoding: buffer.prefix(length).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    /// SkPath::writeToMemory — what `SkPath(serialized:)` reads back.
    func serialize() -> [UInt8] {
        let size = cskia_path_write_to_memory(base, nil)
        var bytes = [UInt8](repeating: 0, count: size)
        _ = bytes.withUnsafeMutableBytes { cskia_path_write_to_memory(base, $0.baseAddress) }
        return bytes
    }

    // MARK: iteration

    /// The path's verbs with their points (SkPath::Iter). `forceClose`
    /// closes every contour with a line back to its start.
    func elements(forceClose: Bool = false) -> [SkPathElement] {
        Array(SkPathIter(self, forceClose: forceClose))
    }

    // MARK: PathOps

    /// The two paths combined by `op`; nil when it can't be computed.
    func op<P: SkiaPath>(_ other: P, _ op: SkPathOp) -> SkPath? {
        let out = SkPath()
        return cskia_path_op(base, other.base, op.rawValue, out.base) ? out : nil
    }

    /// The same area with no overlapping contours.
    func simplify() -> SkPath? {
        let out = SkPath()
        return cskia_path_simplify(base, out.base) ? out : nil
    }

    /// The same area with a winding fill type.
    func asWinding() -> SkPath? {
        let out = SkPath()
        return cskia_path_as_winding(base, out.base) ? out : nil
    }
}

/// SkPath::Iter — a path's verbs with their points, in order. Iterates a
/// copy of the path, so the path can change or go meanwhile.
public final class SkPathIter: IteratorProtocol, Sequence {
    private let path: OpaquePointer
    private let iter: OpaquePointer

    public init<P: SkiaPath>(_ path: P, forceClose: Bool = false) {
        self.path = cskia_path_copy(path.base)
        iter = cskia_path_iter_new(self.path, forceClose)
    }

    deinit {
        cskia_path_iter_delete(iter)
        cskia_path_delete(path)
    }

    public func next() -> SkPathElement? {
        var xy = [Float](repeating: 0, count: 8)
        var weight: Float = 1
        let verb = cskia_path_iter_next(iter, &xy, &weight)
        let p = (0..<4).map { SIMD2(xy[$0 * 2], xy[$0 * 2 + 1]) }
        switch verb {
        case 0: return .move(p[0])
        case 1: return .line(p[0], p[1])
        case 2: return .quad(p[0], p[1], p[2])
        case 3: return .conic(p[0], p[1], p[2], weight: weight)
        case 4: return .cubic(p[0], p[1], p[2], p[3])
        case 5: return .close
        default: return nil
        }
    }
}

/// SkPathMeasure — lengths, positions and pieces along a path, one contour
/// at a time from the first. Measures a copy of the path.
public final class SkPathMeasure {
    private let base: OpaquePointer

    /// `forceClosed` measures each contour as if closed; `resScale` > 1
    /// measures curves more finely (for paths drawn scaled up).
    public init<P: SkiaPath>(_ path: P, forceClosed: Bool = false, resScale: Float = 1) {
        base = cskia_path_measure_new(path.base, forceClosed, resScale)
    }

    deinit { cskia_path_measure_delete(base) }

    /// Length of the current contour.
    public func getLength() -> Float { cskia_path_measure_get_length(base) }

    /// Position and unit tangent at `distance` (pinned to the contour).
    public func getPosTan(_ distance: Float) -> (position: SIMD2<Float>, tangent: SIMD2<Float>)? {
        var position = [Float](repeating: 0, count: 2)
        var tangent = [Float](repeating: 0, count: 2)
        guard cskia_path_measure_get_pos_tan(base, distance, &position, &tangent) else { return nil }
        return (SIMD2(position[0], position[1]), SIMD2(tangent[0], tangent[1]))
    }

    /// The piece from `start` to `stop`, appended to `dst`.
    @discardableResult
    public func getSegment<P: SkiaPath>(start: Float, stop: Float, into dst: P, startWithMoveTo: Bool = true) -> Bool {
        cskia_path_measure_get_segment(base, start, stop, dst.base, startWithMoveTo)
    }

    /// The piece from `start` to `stop` as a path of its own.
    public func getSegment(start: Float, stop: Float, startWithMoveTo: Bool = true) -> SkPath? {
        let out = SkPath()
        return getSegment(start: start, stop: stop, into: out, startWithMoveTo: startWithMoveTo) ? out : nil
    }

    public func isClosed() -> Bool { cskia_path_measure_is_closed(base) }

    /// On to the next contour; false when there is none.
    public func nextContour() -> Bool { cskia_path_measure_next_contour(base) }
}

/// SkOpBuilder — any number of paths, each with its op, resolved at once
/// (faster than chaining `op`).
public final class SkOpBuilder {
    private let base: OpaquePointer

    public init() { base = cskia_op_builder_new() }

    deinit { cskia_op_builder_delete(base) }

    public func add<P: SkiaPath>(_ path: P, _ op: SkPathOp) { cskia_op_builder_add(base, path.base, op.rawValue) }

    public func resolve() -> SkPath? {
        let out = SkPath()
        return cskia_op_builder_resolve(base, out.base) ? out : nil
    }
}
