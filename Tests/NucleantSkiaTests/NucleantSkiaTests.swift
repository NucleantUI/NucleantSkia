import Foundation
import Testing
@testable import NucleantSkia

// Everything draws into a CPU raster surface and reads the pixels back, so
// these run without a GPU or a window.

private let white = SIMD4<Float>(1, 1, 1, 1)
private let red   = SIMD4<Float>(1, 0, 0, 1)
private let blue  = SIMD4<Float>(0, 0, 1, 1)

private func makeSurface(_ width: Int32 = 64, _ height: Int32 = 64) throws -> SkRasterSurface {
    let surface = try #require(SkSurfaces.raster(width: width, height: height))
    surface.getCanvas().clear(white)
    return surface
}

private func isClose(_ a: SIMD4<UInt8>?, _ b: SIMD4<UInt8>, tolerance: Int = 2) -> Bool {
    guard let a else { return false }
    return (0..<4).allSatisfy { abs(Int(a[$0]) - Int(b[$0])) <= tolerance }
}

private func roboto() throws -> SkTypeface {
    let url = try #require(Bundle.module.url(forResource: "Roboto-Regular", withExtension: "ttf", subdirectory: "Resources"))
    let bytes = try [UInt8](Data(contentsOf: url))
    return try #require(SkFontMgr.makeFromData(bytes))
}

// MARK: - Surface + canvas

@Test func rasterSurfaceHasItsSizeAndClears() throws {
    let surface = try makeSurface(40, 30)
    #expect(surface.width() == 40)
    #expect(surface.height() == 30)
    #expect(surface.readPixels().count == 40 * 30 * 4)
    #expect(surface.readPixel(x: 0, y: 0) == SIMD4(255, 255, 255, 255))
    #expect(surface.readPixel(x: 40, y: 0) == nil)
}

@Test func drawRectFillsOnlyItsRect() throws {
    let surface = try makeSurface()
    surface.getCanvas().drawRect(pos: SIMD2(10, 10), size: SIMD2(20, 20), paint: SkPaint(color: red))
    #expect(surface.readPixel(x: 15, y: 15) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 5, y: 5) == SIMD4(255, 255, 255, 255))
    #expect(surface.readPixel(x: 35, y: 35) == SIMD4(255, 255, 255, 255))
}

@Test func genericSIMDOverloadsDrawTheSame() throws {
    let surface = try makeSurface()
    surface.getCanvas().drawRect(pos: SIMD2<Double>(10, 10), size: SIMD2<Double>(20, 20), paint: SkPaint(color: blue))
    #expect(surface.readPixel(x: 15, y: 15) == SIMD4(0, 0, 255, 255))
}

@Test func circleOvalRRectAndLine() throws {
    let surface = try makeSurface()
    let canvas = surface.getCanvas()
    canvas.drawCircle(center: SIMD2(16, 16), radius: 8, paint: SkPaint(color: red))
    canvas.drawOval(pos: SIMD2(40, 8), size: SIMD2(16, 16), paint: SkPaint(color: blue))
    canvas.drawRRect(pos: SIMD2(8, 40), size: SIMD2(16, 16), radius: SIMD2(4, 4), paint: SkPaint(color: red))
    let stroke = SkPaint(color: blue)
    stroke.setStroke(true)
    stroke.setStrokeWidth(4)
    canvas.drawLine(from: SIMD2(40, 48), to: SIMD2(60, 48), paint: stroke)

    #expect(surface.readPixel(x: 16, y: 16) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 9, y: 9) == SIMD4(255, 255, 255, 255))   // outside the circle, inside its box
    #expect(surface.readPixel(x: 48, y: 16) == SIMD4(0, 0, 255, 255))
    #expect(surface.readPixel(x: 16, y: 48) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 8, y: 40) == SIMD4(255, 255, 255, 255))  // the rounded-off corner
    #expect(surface.readPixel(x: 50, y: 48) == SIMD4(0, 0, 255, 255))
    #expect(surface.readPixel(x: 50, y: 44) == SIMD4(255, 255, 255, 255))
}

@Test func clipRectKeepsDrawingInside() throws {
    let surface = try makeSurface()
    let canvas = surface.getCanvas()
    canvas.save()
    canvas.clipRect(pos: SIMD2(0, 0), size: SIMD2(32, 64))
    canvas.drawPaint(SkPaint(color: red))
    canvas.restore()
    #expect(surface.readPixel(x: 10, y: 10) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 50, y: 10) == SIMD4(255, 255, 255, 255))
}

@Test func clipDifferenceCutsAHole() throws {
    let surface = try makeSurface()
    let canvas = surface.getCanvas()
    canvas.save()
    canvas.clipRRect(pos: SIMD2(16, 16), size: SIMD2(32, 32), radius: SIMD2(0, 0), op: .difference, doAntiAlias: false)
    canvas.drawPaint(SkPaint(color: red))
    canvas.restore()
    #expect(surface.readPixel(x: 32, y: 32) == SIMD4(255, 255, 255, 255))
    #expect(surface.readPixel(x: 4, y: 4) == SIMD4(255, 0, 0, 255))
}

@Test func saveRestoreAndMatrix() throws {
    let surface = try makeSurface()
    let canvas = surface.getCanvas()
    #expect(canvas.getSaveCount() == 1)
    let count = canvas.save()
    #expect(count == 1)
    canvas.translate(SIMD2(5, 7))
    canvas.scale(2)
    let m = canvas.getTotalMatrix()
    #expect(m.transX == 5 && m.transY == 7 && m.scaleX == 2 && m.scaleY == 2)
    canvas.restoreToCount(count)
    #expect(canvas.getTotalMatrix() == .identity)

    canvas.setMatrix(.translate(SIMD2(20, 20)))
    canvas.drawRect(pos: SIMD2(0, 0), size: SIMD2(4, 4), paint: SkPaint(color: red))
    canvas.resetMatrix()
    #expect(surface.readPixel(x: 22, y: 22) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 2, y: 2) == SIMD4(255, 255, 255, 255))
}

@Test func saveLayerAlphaBlendsTheLayer() throws {
    let surface = try makeSurface()
    let canvas = surface.getCanvas()
    canvas.saveLayerAlphaf(0.5)
    canvas.drawPaint(SkPaint(color: red))
    canvas.restore()
    #expect(isClose(surface.readPixel(x: 10, y: 10), SIMD4(255, 127, 127, 255)))
}

// MARK: - Paint

@Test func paintRoundTrips() {
    let paint = SkPaint()
    #expect(paint.isAntiAlias())
    paint.setColor(SIMD4<UInt8>(10, 20, 30, 40))
    #expect(paint.getColor() == SIMD4(10, 20, 30, 40))
    paint.setARGB(a: 255, r: 1, g: 2, b: 3)
    #expect(paint.getColor() == SIMD4(1, 2, 3, 255))
    paint.setColor4f(SIMD4<Float>(0.25, 0.5, 0.75, 1))
    #expect(paint.getColor4f() == SIMD4(0.25, 0.5, 0.75, 1))
    paint.setAlphaf(0.5)
    #expect(paint.getAlphaf() == 0.5)

    paint.setStyle(.strokeAndFill)
    #expect(paint.getStyle() == .strokeAndFill)
    paint.setStrokeWidth(3)
    paint.setStrokeMiter(6)
    paint.setStrokeCap(.round)
    paint.setStrokeJoin(.bevel)
    #expect(paint.getStrokeWidth() == 3)
    #expect(paint.getStrokeMiter() == 6)
    #expect(paint.getStrokeCap() == .round)
    #expect(paint.getStrokeJoin() == .bevel)
    paint.setBlendMode(.multiply)
    #expect(paint.getBlendMode() == .multiply)

    let copy = paint.copy()
    copy.setStrokeWidth(9)
    #expect(paint.getStrokeWidth() == 3)
    #expect(copy.getStrokeCap() == .round)

    paint.reset()
    #expect(paint.getStyle() == .fill)
    #expect(!paint.isAntiAlias())
}

@Test func blurMaskFilterSpreadsPastTheShape() throws {
    let surface = try makeSurface()
    let paint = SkPaint(color: red)
    paint.setMaskFilterBlur(.normal, sigma: 4)
    surface.getCanvas().drawRect(pos: SIMD2(24, 24), size: SIMD2(16, 16), paint: paint)
    // Just outside the rect: no longer pure white.
    let outside = try #require(surface.readPixel(x: 22, y: 32))
    #expect(outside.y < 250)

    paint.clearMaskFilter()
    let sharp = try makeSurface()
    sharp.getCanvas().drawRect(pos: SIMD2(24, 24), size: SIMD2(16, 16), paint: paint)
    #expect(sharp.readPixel(x: 22, y: 32) == SIMD4(255, 255, 255, 255))
}

// MARK: - Shaders / path effects

@Test func linearGradientRunsFromStartToEnd() throws {
    let surface = try makeSurface(100, 10)
    let shader = try #require(SkGradientShader.makeLinear(from: SIMD2(0, 0), to: SIMD2(100, 0), colors: [red, blue]))
    let paint = SkPaint()
    paint.setShader(shader)
    surface.getCanvas().drawPaint(paint)
    let left = try #require(surface.readPixel(x: 1, y: 5))
    let right = try #require(surface.readPixel(x: 98, y: 5))
    #expect(left.x > 240 && left.z < 15)
    #expect(right.z > 240 && right.x < 15)

    // A mismatched positions array is refused rather than read past.
    #expect(SkGradientShader.makeLinear(from: .zero, to: SIMD2(1, 0), colors: [red, blue], positions: [0]) == nil)
    #expect(SkGradientShader.makeLinear(from: .zero, to: SIMD2(1, 0), colors: []) == nil)
}

@Test func otherGradientsAndColorShaderBuild() throws {
    let colors = [red, blue]
    #expect(SkGradientShader.makeRadial(center: SIMD2(5, 5), radius: 5, colors: colors) != nil)
    #expect(SkGradientShader.makeTwoPointConical(start: SIMD2(5, 5), startRadius: 0, end: SIMD2(5, 5), endRadius: 5, colors: colors) != nil)
    #expect(SkGradientShader.makeSweep(center: SIMD2(5, 5), colors: colors, positions: [0, 1], mode: .repeat) != nil)

    let surface = try makeSurface()
    let paint = SkPaint()
    paint.setShader(try #require(SkShaders.color(blue)))
    surface.getCanvas().drawPaint(paint)
    #expect(surface.readPixel(x: 3, y: 3) == SIMD4(0, 0, 255, 255))

    paint.clearShader()
    paint.setColor4f(red)
    surface.getCanvas().drawPaint(paint)
    #expect(surface.readPixel(x: 3, y: 3) == SIMD4(255, 0, 0, 255))
}

@Test func dashPathEffectLeavesGaps() throws {
    #expect(SkDashPathEffect.make(intervals: [4]) == nil)
    #expect(SkDashPathEffect.make(intervals: [4, 4, 4]) == nil)
    #expect(SkCornerPathEffect.make(radius: 4) != nil)

    let surface = try makeSurface()
    let paint = SkPaint(color: red)
    paint.setAntiAlias(false)
    paint.setStroke(true)
    paint.setStrokeWidth(2)
    paint.setPathEffect(try #require(SkDashPathEffect.make(intervals: [10, 10])))
    surface.getCanvas().drawLine(from: SIMD2(0, 10), to: SIMD2(60, 10), paint: paint)
    #expect(surface.readPixel(x: 5, y: 10) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 15, y: 10) == SIMD4(255, 255, 255, 255))
    #expect(surface.readPixel(x: 25, y: 10) == SIMD4(255, 0, 0, 255))
}

// MARK: - Path

@Test func pathBuildsAndAnswers() {
    let path = SkPath()
    #expect(path.isEmpty())
    path.addRect(pos: SIMD2(10, 20), size: SIMD2(30, 40))
    let bounds = path.getBounds()
    #expect(bounds.pos == SIMD2(10, 20))
    #expect(bounds.size == SIMD2(30, 40))
    #expect(path.contains(SIMD2(20, 30)))
    #expect(!path.contains(x: 5, y: 5))
    #expect(path.countPoints() == 4)

    path.offset(SIMD2(5, 5))
    #expect(path.getBounds().pos == SIMD2(15, 25))
    path.transform(.scale(SIMD2(2, 2)))
    #expect(path.getBounds().pos == SIMD2(30, 50))

    path.setFillType(.evenOdd)
    #expect(path.getFillType() == .evenOdd)

    let copy = path.copy()
    path.reset()
    #expect(path.isEmpty())
    #expect(!copy.isEmpty())

    let curve = SkPath()
    curve.moveTo(SIMD2(0, 0))
    curve.cubicTo(SIMD2(0, 10), SIMD2(10, 10), SIMD2(10, 0))
    curve.quadTo(SIMD2(15, -5), SIMD2(20, 0))
    curve.conicTo(SIMD2(25, 5), SIMD2(30, 0), weight: 0.7)
    curve.close()
    #expect(curve.countVerbs() == 5)
    let tight = curve.computeTightBounds()
    #expect(tight.size.x == 30)
}

@Test func filledTriangleAndEvenOddHole() throws {
    let surface = try makeSurface()
    let triangle = SkPath()
    triangle.moveTo(x: 0, y: 0)
    triangle.lineTo(x: 60, y: 0)
    triangle.lineTo(x: 0, y: 60)
    triangle.close()
    surface.getCanvas().drawPath(triangle, paint: SkPaint(color: red))
    #expect(surface.readPixel(x: 10, y: 10) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 50, y: 50) == SIMD4(255, 255, 255, 255))

    let ring = SkPath()
    ring.addCircle(center: SIMD2(32, 32), radius: 30)
    ring.addCircle(center: SIMD2(32, 32), radius: 10)
    ring.setFillType(.evenOdd)
    let other = try makeSurface()
    other.getCanvas().drawPath(ring, paint: SkPaint(color: blue))
    #expect(other.readPixel(x: 32, y: 32) == SIMD4(255, 255, 255, 255))
    #expect(other.readPixel(x: 32, y: 10) == SIMD4(0, 0, 255, 255))

    let clip = SkPath()
    clip.addOval(pos: SIMD2(0, 0), size: SIMD2(64, 64))
    let clipped = try makeSurface()
    clipped.getCanvas().clipPath(clip)
    clipped.getCanvas().drawPaint(SkPaint(color: red))
    #expect(clipped.readPixel(x: 32, y: 32) == SIMD4(255, 0, 0, 255))
    #expect(clipped.readPixel(x: 1, y: 1) == SIMD4(255, 255, 255, 255))
}

// MARK: - Images

@Test func imageFromPixelsDrawsScaled() throws {
    // 2×2 opaque green, RGBA bytes.
    let green: [UInt8] = Array(repeating: [0, 255, 0, 255], count: 4).flatMap { $0 }
    let image = try #require(SkImages.rasterFromPixmapCopy(green, size: SIMD2(2, 2)))
    #expect(image.size() == SIMD2(2, 2))
    #expect(SkImages.rasterFromPixmapCopy([0, 0, 0], size: SIMD2(2, 2)) == nil)

    let surface = try makeSurface()
    surface.getCanvas().drawImageRect(image, pos: SIMD2(10, 10), size: SIMD2(20, 20))
    #expect(surface.readPixel(x: 20, y: 20) == SIMD4(0, 255, 0, 255))
    #expect(surface.readPixel(x: 5, y: 5) == SIMD4(255, 255, 255, 255))

    // ARGB UInt32 (native little-endian = BGRA bytes): opaque red.
    let argb = try #require(SkImages.rasterFromPixmapCopy([UInt32](repeating: 0xFFFF_0000, count: 4), size: SIMD2(2, 2)))
    surface.getCanvas().drawImage(argb, pos: SIMD2(40, 40))
    #expect(surface.readPixel(x: 40, y: 40) == SIMD4(255, 0, 0, 255))
}

@Test func snapshotKeepsWhatWasDrawn() throws {
    let surface = try makeSurface(8, 8)
    surface.getCanvas().clear(red)
    let snapshot = try #require(surface.makeImageSnapshot())
    surface.getCanvas().clear(blue)
    let target = try makeSurface(8, 8)
    target.getCanvas().drawImage(snapshot, pos: .zero)
    #expect(target.readPixel(x: 4, y: 4) == SIMD4(255, 0, 0, 255))
}

// MARK: - Fonts

@Test func typefaceFromDataKnowsItsFamily() throws {
    let typeface = try roboto()
    #expect(typeface.getFamilyName() == "Roboto")
    #expect(typeface.countGlyphs() > 100)
    #expect(SkFontMgr.makeFromData([0, 1, 2, 3]) == nil)
    #expect(SkFontMgr.makeFromFile("/no/such/font.ttf") == nil)
}

@Test func platformDefaultTypefaceExists() throws {
    let typeface = try #require(SkFontMgr.matchFamilyStyle(nil))
    #expect(!typeface.getFamilyName().isEmpty)
}

@Test func fontMeasuresWithItsTypeface() throws {
    let font = SkFont(try roboto(), size: 20)
    #expect(font.getSize() == 20)
    #expect(font.refTypeface()?.getFamilyName() == "Roboto")
    font.setLinearMetrics(true)
    font.setSubpixel(true)
    font.setHinting(.none)

    let text = "Hello"
    let advance = font.measureText(text)
    #expect(advance > 30 && advance < 80)

    let glyphs = font.textToGlyphs(text)
    #expect(glyphs.count == 5)
    #expect(!glyphs.contains(0))
    let widths = font.getWidths(glyphs)
    #expect(abs(widths.reduce(0, +) - advance) < 0.01)

    var bounds: (pos: SIMD2<Float>, size: SIMD2<Float>) = (.zero, .zero)
    _ = font.measureText(text, bounds: &bounds)
    #expect(bounds.pos.y < 0)          // ink sits above the baseline
    #expect(bounds.size.x > 0)

    let metrics = font.getMetrics()
    #expect(metrics.ascent < 0 && metrics.descent > 0)
    #expect(abs(font.getSpacing() - (metrics.descent - metrics.ascent + metrics.leading)) < 0.01)

    font.setSkewX(-0.25)
    font.setScaleX(1.5)
    #expect(font.getSkewX() == -0.25)
    #expect(font.getScaleX() == 1.5)
    #expect(font.measureText(text) > advance)   // wider with scaleX

    let copy = font.copy()
    copy.setSize(40)
    #expect(font.getSize() == 20)
    #expect(font.measureText("") == 0)
}

@Test func drawStringPutsInkOnTheSurface() throws {
    let surface = try makeSurface(120, 40)
    let font = SkFont(try roboto(), size: 24)
    surface.getCanvas().drawString("Hi", pos: SIMD2(4, 30), font: font, paint: SkPaint(color: SIMD4(0, 0, 0, 1)))
    let pixels = surface.readPixels()
    let inked = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 128 }.count
    #expect(inked > 20)
    // Nothing drawn far right of a two-letter string.
    #expect(surface.readPixel(x: 110, y: 20) == SIMD4(255, 255, 255, 255))
}
