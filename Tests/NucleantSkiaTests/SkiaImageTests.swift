import Foundation
import Testing
@testable import NucleantSkia

// SkImage: decoding, reading pixels back, subsets, encoding, drawing parts
// of an image and as a shader.

/// A 2x1 PNG: opaque red, then blue at half alpha.
private let twoPixelPNG = [UInt8](Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAADklEQVR4nGP4z8AAQg0AD3oDfnfpf5cAAAAASUVORK5CYII=")!)

/// An image of `colors` (r, g, b, a bytes), `width` wide.
private func image(_ colors: [SIMD4<UInt8>], width: Int32) throws -> SkImage {
    let bytes = colors.flatMap { [$0.x, $0.y, $0.z, $0.w] }
    return try #require(SkImages.rasterFromPixmapCopy(bytes, size: SIMD2(width, Int32(colors.count) / width), alphaType: .unpremul))
}

private let r = SIMD4<UInt8>(255, 0, 0, 255), g = SIMD4<UInt8>(0, 255, 0, 255), b = SIMD4<UInt8>(0, 0, 255, 255)

@Test func encodedImageDecodesWhenRead() throws {
    let png = try #require(SkImage(encoded: twoPixelPNG))
    #expect(png.size() == SIMD2(2, 1))
    // Lazy: not in memory until decoded.
    #expect(png.withPeekedPixels { _, _ in true } == nil)
    #expect(png.readPixels(colorType: .rgba8888, alphaType: .unpremul) == [255, 0, 0, 255, 0, 0, 255, 128])

    let decoded = try #require(png.makeRasterImage())
    #expect(decoded.withPeekedPixels { _, rowBytes in rowBytes } == 8)
    #expect(SkImage(encoded: [1, 2, 3]) == nil)
}

@Test func colorAndAlphaTypes() throws {
    let opaque = try image([r, g], width: 2)
    #expect(opaque.colorType() == .rgba8888)
    #expect(opaque.alphaType() == .unpremul)
    #expect(!opaque.isOpaque())
    let bgra = try #require(SkImages.rasterFromPixmapCopy([UInt32](repeating: 0xFF00FF00, count: 4), size: SIMD2(2, 2)))
    #expect(bgra.colorType() == .bgra8888)
}

@Test func readPixelsOfAPart() throws {
    let img = try image([r, g, b, r], width: 2)
    // The right column — green, red — as BGRA bytes.
    let column = try #require(img.readPixels(colorType: .bgra8888, alphaType: .unpremul, origin: SIMD2(1, 0), size: SIMD2(1, 2)))
    #expect(column == [0, 255, 0, 255, 0, 0, 255, 255])
}

@Test func subsetIsThePartAlone() throws {
    let img = try image([r, g, b, r], width: 2)
    let bottom = try #require(img.makeSubset(origin: SIMD2(0, 1), size: SIMD2(2, 1)))
    #expect(bottom.size() == SIMD2(2, 1))
    #expect(bottom.readPixels(alphaType: .unpremul) == [0, 0, 255, 255, 255, 0, 0, 255])
    #expect(img.makeSubset(origin: SIMD2(1, 1), size: SIMD2(2, 2)) == nil)
}

@Test func encodeAndDecodeAgain() throws {
    let surface = try makeSurface(8, 8)
    surface.getCanvas().drawRect(pos: SIMD2(0, 0), size: SIMD2(4, 8), paint: SkPaint(color: red))
    let snapshot = try #require(surface.makeImageSnapshot())

    let png = try #require(snapshot.encode(.png))
    #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    let again = try #require(SkImage(encoded: png))
    #expect(again.readPixels(alphaType: .unpremul) == snapshot.readPixels(alphaType: .unpremul))

    let jpeg = try #require(snapshot.encode(.jpeg, quality: 90))
    #expect(Array(jpeg.prefix(2)) == [0xFF, 0xD8])
    let webp = try #require(snapshot.encode(.webp, quality: 100))
    #expect(Array(webp[8..<12]) == Array("WEBP".utf8))
    // Lossless WebP keeps the pixels exactly.
    #expect(SkImage(encoded: webp)?.readPixels(alphaType: .unpremul) == snapshot.readPixels(alphaType: .unpremul))
}

@Test func drawPartOfAnImageWithSampling() throws {
    // Red | blue; the right half fills the whole destination.
    let img = try image([r, b], width: 2)
    let surface = try makeSurface(20, 20)
    surface.getCanvas().drawImageRect(img, src: (SIMD2(1, 0), SIMD2(1, 1)), dst: (SIMD2(0, 0), SIMD2(20, 20)), sampling: .nearest)
    #expect(surface.readPixel(x: 1, y: 1) == SIMD4(0, 0, 255, 255))
    #expect(surface.readPixel(x: 18, y: 18) == SIMD4(0, 0, 255, 255))

    // Cubic sampling stays inside the source with `strict`.
    let cubic = try makeSurface(20, 20)
    cubic.getCanvas().drawImageRect(img, src: (SIMD2(0, 0), SIMD2(1, 1)), dst: (SIMD2(0, 0), SIMD2(20, 20)),
                                    sampling: .mitchell, paint: SkPaint(), constraint: .strict)
    #expect(isClose(cubic.readPixel(x: 18, y: 10), SIMD4(255, 0, 0, 255)))
}

@Test func nineDrawsCornersAtTheirSize() throws {
    // 3x3: red corners, green edges, blue center.
    let img = try image([r, g, r, g, b, g, r, g, r], width: 3)
    let surface = try makeSurface(30, 30)
    surface.getCanvas().drawImageNine(img, center: (SIMD2(1, 1), SIMD2(1, 1)), dst: (SIMD2(0, 0), SIMD2(30, 30)), filter: .nearest)
    #expect(surface.readPixel(x: 0, y: 0) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 29, y: 29) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 15, y: 0) == SIMD4(0, 255, 0, 255))
    #expect(surface.readPixel(x: 15, y: 15) == SIMD4(0, 0, 255, 255))
}

@Test func imageShaderRepeats() throws {
    // A 2x2 checker repeated over the surface.
    let tile = try image([r, b, b, r], width: 2)
    let shader = try #require(tile.makeShader(tileX: .repeat, tileY: .repeat, sampling: .nearest))
    let paint = SkPaint()
    paint.setShader(shader)
    let surface = try makeSurface(10, 10)
    surface.getCanvas().drawPaint(paint)
    #expect(surface.readPixel(x: 0, y: 0) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 1, y: 0) == SIMD4(0, 0, 255, 255))
    #expect(surface.readPixel(x: 8, y: 6) == SIMD4(255, 0, 0, 255))
    #expect(surface.readPixel(x: 9, y: 6) == SIMD4(0, 0, 255, 255))

    // The matrix places it: shifted by one pixel, the colors swap.
    let shifted = try #require(tile.makeShader(tileX: .repeat, tileY: .repeat, sampling: .nearest, matrix: .translate(SIMD2(1, 0))))
    paint.setShader(shifted)
    let moved = try makeSurface(10, 10)
    moved.getCanvas().drawPaint(paint)
    #expect(moved.readPixel(x: 0, y: 0) == SIMD4(0, 0, 255, 255))
}
