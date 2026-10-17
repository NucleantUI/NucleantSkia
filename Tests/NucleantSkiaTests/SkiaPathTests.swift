import Testing
@testable import NucleantSkia

// SkPath beyond the basics: relative verbs, arcs, shape queries, SVG,
// iteration, PathOps and SkPathMeasure.

@Test func relativeVerbsAndPoints() {
    let path = SkPath()
    path.moveTo(x: 10, y: 10)
    path.rLineTo(dx: 20, dy: 0)
    path.rLineTo(SIMD2<Float>(0, 20))
    #expect(path.getPoints() == [SIMD2(10, 10), SIMD2(30, 10), SIMD2(30, 30)])
    #expect(path.getPoint(1) == SIMD2(30, 10))
    #expect(path.getPoint(3) == nil)
    #expect(path.getLastPt() == SIMD2(30, 30))
    path.setLastPt(SIMD2(40, 40))
    #expect(path.getLastPt() == SIMD2(40, 40))
    #expect(SkPath().getLastPt() == nil)

    let curves = SkPath()
    curves.moveTo(x: 0, y: 0)
    curves.rQuadTo(SIMD2<Float>(10, 10), SIMD2<Float>(20, 0))
    curves.rConicTo(SIMD2<Float>(10, 10), SIMD2<Float>(20, 0), weight: 0.5)
    curves.rCubicTo(SIMD2<Float>(5, 5), SIMD2<Float>(15, 5), SIMD2<Float>(20, 0))
    #expect(curves.getLastPt() == SIMD2(60, 0))
    curves.rMoveTo(SIMD2<Float>(0, 10))
    #expect(curves.getLastPt() == SIMD2(60, 10))
}

@Test func arcsGoWhereTheyShould() {
    // SVG's arc: half a circle of radius 10 from (0, 10) to (20, 10), over the top.
    let svgArc = SkPath()
    svgArc.moveTo(x: 0, y: 10)
    svgArc.arcTo(radii: SIMD2(10, 10), largeArc: false, sweep: .cw, end: SIMD2(20, 10))
    let bounds = svgArc.computeTightBounds()
    #expect(abs(bounds.pos.y - 0) < 0.01 && abs(bounds.size.y - 10) < 0.01)
    #expect(svgArc.getLastPt() == SIMD2(20, 10))

    let relative = SkPath()
    relative.moveTo(x: 0, y: 10)
    relative.rArcTo(radii: SIMD2(10, 10), largeArc: false, sweep: .cw, end: SIMD2(20, 0))
    #expect(relative.getLastPt() == SIMD2(20, 10))

    // A quarter of the oval in (0, 0, 20, 20), from 0° to 90°.
    let oval = SkPath()
    oval.arcTo(pos: SIMD2<Float>(0, 0), size: SIMD2<Float>(20, 20), startAngle: 0, sweepAngle: 90, forceMoveTo: true)
    #expect(oval.getPoint(0) == SIMD2(20, 10))
    #expect(oval.getLastPt().map { abs($0.x - 10) < 0.01 && abs($0.y - 20) < 0.01 } == true)

    // Rounding the corner at (20, 0) of the line (0, 0) → (20, 0) → (20, 20).
    let tangent = SkPath()
    tangent.moveTo(x: 0, y: 0)
    tangent.arcTo(SIMD2<Float>(20, 0), SIMD2<Float>(20, 20), radius: 5)
    #expect(tangent.getLastPt().map { abs($0.x - 20) < 0.01 && abs($0.y - 5) < 0.01 } == true)
}

@Test func perCornerRoundedRect() {
    // Only the upper-right corner is round.
    let path = SkPath()
    path.addRRect(pos: SIMD2(0, 0), size: SIMD2(40, 40),
                  cornerRadii: [SIMD2(0, 0), SIMD2(20, 20), SIMD2(0, 0), SIMD2(0, 0)])
    #expect(path.contains(x: 1, y: 1))
    #expect(path.contains(x: 39, y: 39))
    #expect(!path.contains(x: 39, y: 1))
}

@Test func whatAPathIs() {
    let rect = SkPath()
    rect.addRect(pos: SIMD2(1, 2), size: SIMD2(3, 4))
    #expect(rect.isRect().map { $0.pos == SIMD2(1, 2) && $0.size == SIMD2(3, 4) } == true)
    #expect(rect.isOval() == nil)
    #expect(rect.isConvex())
    #expect(rect.isFinite())
    #expect(rect.conservativelyContainsRect(pos: SIMD2(2, 3), size: SIMD2(1, 1)))
    #expect(!rect.conservativelyContainsRect(pos: SIMD2(0, 0), size: SIMD2(10, 10)))

    let oval = SkPath()
    oval.addOval(pos: SIMD2(0, 0), size: SIMD2(10, 20))
    #expect(oval.isOval().map { $0.size == SIMD2(10, 20) } == true)

    let line = SkPath()
    line.moveTo(x: 1, y: 1)
    line.lineTo(x: 5, y: 9)
    #expect(line.isLine().map { $0.0 == SIMD2(1, 1) && $0.1 == SIMD2(5, 9) } == true)
    #expect(!line.isLastContourClosed())

    let star = SkPath()
    star.addPoly([SIMD2(10, 0), SIMD2(13, 20), SIMD2(0, 7), SIMD2(20, 7), SIMD2(7, 20)], close: true)
    #expect(!star.isConvex())
    #expect(star.isLastContourClosed())
    #expect(star.countPoints() == 5)

    star.toggleInverseFillType()
    #expect(star.isInverseFillType())
    #expect(star.getFillType() == .inverseWinding)
}

@Test func addPathWithAMatrixAndReversed() {
    let src = SkPath()
    src.moveTo(x: 0, y: 0)
    src.lineTo(x: 10, y: 0)

    let moved = SkPath()
    moved.addPath(src, matrix: .translate(SIMD2(5, 5)))
    #expect(moved.getPoints() == [SIMD2(5, 5), SIMD2(15, 5)])

    let reversed = SkPath()
    reversed.reverseAddPath(src)
    #expect(reversed.getPoints() == [SIMD2(10, 0), SIMD2(0, 0)])

    // Extend joins the added path to the last contour: no second moveTo.
    let extended = SkPath()
    extended.moveTo(x: 0, y: 10)
    extended.addPath(src, matrix: .identity, mode: .extend)
    #expect(extended.elements().filter { if case .move = $0 { return true } else { return false } }.count == 1)
}

@Test func interpolateBetweenTwoPaths() throws {
    let start = SkPath()
    start.moveTo(x: 0, y: 0)
    start.lineTo(x: 10, y: 0)
    let end = SkPath()
    end.moveTo(x: 0, y: 20)
    end.lineTo(x: 30, y: 20)
    #expect(start.isInterpolatable(end))

    let middle = try #require(start.interpolate(end, weight: 0.5))
    #expect(middle.getPoints() == [SIMD2(0, 10), SIMD2(20, 10)])

    let other = SkPath()
    other.addCircle(x: 0, y: 0, radius: 5)
    #expect(!start.isInterpolatable(other))
    #expect(start.interpolate(other, weight: 0.5) == nil)
}

@Test func svgPathStringsRoundTrip() throws {
    let path = try #require(SkPath(svg: "M0 0 L10 0 L10 10 Z"))
    #expect(path.countVerbs() == 4)
    #expect(path.getPoints() == [SIMD2(0, 0), SIMD2(10, 0), SIMD2(10, 10)])
    let absolute = path.toSVGString()
    #expect(absolute.hasPrefix("M0 0L10 0L10 10"))
    #expect(absolute.hasSuffix("Z"))
    // Read back, it is the same closed triangle.
    let again = try #require(SkPath(svg: absolute))
    #expect(again.computeTightBounds() == path.computeTightBounds())
    #expect(again.isLastContourClosed())
    #expect(again.contains(x: 8, y: 2) && !again.contains(x: 2, y: 8))
    #expect(path.toSVGString(relative: true).contains("l"))
    #expect(SkPath(svg: "not a path") == nil)
}

@Test func serializeRoundTrips() throws {
    let path = SkPath()
    path.addCircle(x: 10, y: 10, radius: 5)
    path.setFillType(.evenOdd)
    let bytes = path.serialize()
    #expect(!bytes.isEmpty)
    let read = try #require(SkPath(serialized: bytes))
    #expect(read.getPoints() == path.getPoints())
    #expect(read.getFillType() == .evenOdd)
    #expect(SkPath(serialized: [1, 2, 3]) == nil)
}

@Test func elementsWalkEveryVerb() {
    let path = SkPath()
    path.moveTo(x: 0, y: 0)
    path.lineTo(x: 10, y: 0)
    path.quadTo(SIMD2<Float>(15, 5), SIMD2<Float>(10, 10))
    path.conicTo(SIMD2<Float>(5, 15), SIMD2<Float>(0, 10), weight: 0.5)
    path.cubicTo(SIMD2<Float>(-5, 8), SIMD2<Float>(-5, 2), SIMD2<Float>(0, 1))
    path.close()
    #expect(path.elements() == [
        .move(SIMD2(0, 0)),
        .line(SIMD2(0, 0), SIMD2(10, 0)),
        .quad(SIMD2(10, 0), SIMD2(15, 5), SIMD2(10, 10)),
        .conic(SIMD2(10, 10), SIMD2(5, 15), SIMD2(0, 10), weight: 0.5),
        .cubic(SIMD2(0, 10), SIMD2(-5, 8), SIMD2(-5, 2), SIMD2(0, 1)),
        .line(SIMD2(0, 1), SIMD2(0, 0)),
        .close,
    ])

    // forceClose closes an open contour with a line back to its start.
    let open = SkPath()
    open.moveTo(x: 0, y: 0)
    open.lineTo(x: 10, y: 0)
    #expect(open.elements().last == .line(SIMD2(0, 0), SIMD2(10, 0)))
    #expect(open.elements(forceClose: true).suffix(2) == [.line(SIMD2(10, 0), SIMD2(0, 0)), .close])
}

private func square(_ x: Float, _ y: Float, _ side: Float) -> SkPath {
    let path = SkPath()
    path.addRect(pos: SIMD2(x, y), size: SIMD2(side, side))
    return path
}

#if os(WASI)
@Test func pathOpsAreUnavailableInTheBrowser() {
    #expect(square(0, 0, 10).op(square(5, 5, 10), .union) == nil)
    #expect(square(0, 0, 10).simplify() == nil)
    #expect(SkOpBuilder().resolve() == nil)
}
#else
@Test func pathOpsCombineAreas() throws {
    let a = square(0, 0, 10), b = square(5, 5, 10)

    let union = try #require(a.op(b, .union))
    #expect(union.contains(x: 2, y: 2) && union.contains(x: 13, y: 13))
    #expect(!union.contains(x: 13, y: 2))

    let intersect = try #require(a.op(b, .intersect))
    #expect(intersect.isRect().map { $0.pos == SIMD2(5, 5) && $0.size == SIMD2(5, 5) } == true)

    let difference = try #require(a.op(b, .difference))
    #expect(difference.contains(x: 2, y: 2) && !difference.contains(x: 7, y: 7))

    let xor = try #require(a.op(b, .xor))
    #expect(xor.contains(x: 2, y: 2) && !xor.contains(x: 7, y: 7) && xor.contains(x: 13, y: 13))

    // Two overlapping contours in one path: simplify merges them.
    let both = square(0, 0, 10)
    both.addPath(b)
    let simple = try #require(both.simplify())
    #expect(simple.contains(x: 7, y: 7) && simple.contains(x: 13, y: 13))

    let evenOdd = square(0, 0, 10)
    evenOdd.setFillType(.evenOdd)
    let winding = try #require(evenOdd.asWinding())
    #expect(winding.getFillType() == .winding)
    #expect(winding.contains(x: 5, y: 5))

    let builder = SkOpBuilder()
    builder.add(a, .union)
    builder.add(b, .union)
    builder.add(square(4, 4, 2), .difference)
    let built = try #require(builder.resolve())
    #expect(built.contains(x: 13, y: 13) && !built.contains(x: 5, y: 5))
}
#endif

private func isNear(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Bool {
    abs(a.x - b.x) < 0.001 && abs(a.y - b.y) < 0.001
}

@Test func measureLengthsPositionsAndSegments() throws {
    let path = SkPath()
    path.moveTo(x: 0, y: 0)
    path.lineTo(x: 100, y: 0)
    path.addCircle(x: 0, y: 0, radius: 10)

    let measure = SkPathMeasure(path)
    #expect(measure.getLength() == 100)
    #expect(!measure.isClosed())
    let at = try #require(measure.getPosTan(25))
    #expect(at.position == SIMD2(25, 0))
    #expect(at.tangent == SIMD2(1, 0))

    let segment = try #require(measure.getSegment(start: 10, stop: 30))
    let ends = segment.getPoints()
    #expect(ends.count == 2)
    #expect(isNear(ends[0], SIMD2(10, 0)) && isNear(ends[1], SIMD2(30, 0)))

    #expect(measure.nextContour())
    #expect(measure.isClosed())
    // The circle is conics, measured to within a percent at resScale 1.
    #expect(abs(measure.getLength() - 2 * .pi * 10) < 0.63)
    #expect(!measure.nextContour())
}
