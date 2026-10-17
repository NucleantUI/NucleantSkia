import Testing
@testable import NucleantSkia

// Typeface and font queries, glyph positions and outlines, text blobs, and
// the platform font manager. Roboto Regular is the known face.

@Test func typefaceKnowsItsStyleAndTables() throws {
    let typeface = try roboto()
    #expect(typeface.fontStyle() == SkFontStyle(weight: 400, width: 5, slant: .upright))
    #expect(!typeface.isBold())
    #expect(!typeface.isItalic())
    #expect(!typeface.isFixedPitch())
    #expect(typeface.getUnitsPerEm() == 2048)
    #expect(typeface.unicharToGlyph("A") != 0)
    #expect(typeface.unicharToGlyph("\u{10FFFD}") == 0)

    let head = SkSetFourByteTag("head")
    #expect(typeface.getTableTags().contains(head))
    // The 'head' table is 54 bytes, its magic number at 12.
    let table = try #require(typeface.getTableData(head))
    #expect(table.count == 54)
    #expect(Array(table[12..<16]) == [0x5F, 0x0F, 0x3C, 0xF5])
    #expect(typeface.getTableData(SkSetFourByteTag("none")) == nil)
}

@Test func fontFlagsRoundTrip() throws {
    let font = SkFont(try roboto(), size: 20)
    font.setEmbolden(true)
    font.setSubpixel(true)
    font.setLinearMetrics(true)
    font.setBaselineSnap(false)
    font.setForceAutoHinting(true)
    font.setEmbeddedBitmaps(true)
    font.setEdging(.alias)
    font.setHinting(.full)
    #expect(font.isEmbolden() && font.isSubpixel() && font.isLinearMetrics())
    #expect(!font.isBaselineSnap())
    #expect(font.isForceAutoHinting() && font.isEmbeddedBitmaps())
    #expect(font.getEdging() == .alias)
    #expect(font.getHinting() == .full)
}

@Test func glyphsPositionsAndBounds() throws {
    let font = SkFont(try roboto(), size: 20)
    let glyphs = font.textToGlyphs("Hello")
    #expect(font.unicharsToGlyphs(Array("Hello".unicodeScalars)) == glyphs)
    #expect(font.unicharToGlyph("H") == glyphs[0])

    // Each origin is the previous plus its advance.
    let widths = font.getWidths(glyphs)
    let xpos = font.getXPos(glyphs, origin: 10)
    #expect(xpos[0] == 10)
    for i in 1..<glyphs.count {
        #expect(abs(xpos[i] - (xpos[i - 1] + widths[i - 1])) < 0.001)
    }
    let pos = font.getPos(glyphs, origin: SIMD2(10, 30))
    #expect(pos.map(\.x) == xpos)
    #expect(pos.allSatisfy { $0.y == 30 })

    let measured = font.getWidthsBounds(glyphs)
    #expect(measured.map(\.width) == widths)
    // 'H' has ink, above the baseline.
    let h = font.getBounds(glyphs)[0]
    #expect(h.size.x > 0 && h.size.y > 0 && h.pos.y < 0)
}

@Test func glyphOutline() throws {
    let font = SkFont(try roboto(), size: 100)
    let o = try #require(font.getPath(font.unicharToGlyph("O")))
    #expect(!o.isEmpty())
    let bounds = o.getBounds()
    // An 'O': its middle is the hole, its left edge is ink.
    let middle = bounds.pos + bounds.size / 2
    #expect(!o.contains(middle))
    #expect(o.contains(SIMD2(bounds.pos.x + 3, middle.y)))
}

@Test func textBlobDrawsWhereStringWould() throws {
    let font = SkFont(try roboto(), size: 24)
    let blob = try #require(SkTextBlob(text: "Hi", font: font))
    let bounds = blob.bounds()
    #expect(bounds.size.x > 10 && bounds.pos.y < 0)
    #expect(SkTextBlob(text: "", font: font) == nil)

    let viaBlob = try makeSurface(120, 40)
    viaBlob.getCanvas().drawTextBlob(blob, pos: SIMD2(4, 30), paint: SkPaint(color: SIMD4(0, 0, 0, 1)))
    let viaString = try makeSurface(120, 40)
    viaString.getCanvas().drawString("Hi", x: 4, y: 30, font: font, paint: SkPaint(color: SIMD4(0, 0, 0, 1)))
    #expect(viaBlob.readPixels() == viaString.readPixels())
}

@Test func positionedGlyphsAndBuilder() throws {
    let font = SkFont(try roboto(), size: 24)
    let glyphs = font.textToGlyphs("ab")
    let positions = font.getPos(glyphs, origin: SIMD2(4, 30))

    let viaGlyphs = try makeSurface(120, 40)
    viaGlyphs.getCanvas().drawGlyphs(glyphs, positions: positions, font: font, paint: SkPaint(color: SIMD4(0, 0, 0, 1)))
    let viaString = try makeSurface(120, 40)
    viaString.getCanvas().drawString("ab", x: 4, y: 30, font: font, paint: SkPaint(color: SIMD4(0, 0, 0, 1)))
    #expect(viaGlyphs.readPixels() == viaString.readPixels())

    let posBlob = try #require(SkTextBlob(glyphs: glyphs, positions: positions, font: font))
    let hBlob = try #require(SkTextBlob(glyphs: glyphs, xpos: positions.map(\.x), y: 30, font: font))
    #expect(posBlob.bounds().size.x > 0 && hBlob.bounds().size.x > 0)

    // Two runs, two sizes, one blob.
    let builder = SkTextBlobBuilder()
    builder.addRun(glyphs, font: font, origin: SIMD2(0, 30))
    builder.addRun(glyphs, font: SkFont(try roboto(), size: 12), xpos: [60, 70], y: 30)
    builder.addRun(glyphs, font: font, positions: [SIMD2(90, 30), SIMD2(100, 30)])
    let blob = try #require(builder.make())
    #expect(blob.bounds().pos.x + blob.bounds().size.x > 100)
    // The builder is empty again.
    #expect(builder.make() == nil)
}

@Test func interceptsFollowDescenders() throws {
    let font = SkFont(try roboto(), size: 40)
    // An underline band below the baseline crosses 'g''s descender, not 'o'.
    let descender = try #require(SkTextBlob(text: "g", font: font))
    #expect(!descender.getIntercepts(upper: 4, lower: 6).isEmpty)
    let none = try #require(SkTextBlob(text: "o", font: font))
    #expect(none.getIntercepts(upper: 4, lower: 6).isEmpty)
}

#if os(WASI)
@Test func theBrowserHasNoSystemFaces() {
    // Its font manager is Skia's empty one: at most a placeholder face
    // with no glyphs.
    for family in SkFontMgr.familyNames() {
        let set = SkFontMgr.matchFamily(family)
        for index in 0..<set.count() {
            #expect(set.createTypeface(index).map { $0.countGlyphs() } ?? 0 == 0)
        }
    }
    #expect(SkFontMgr.matchFamily("Roboto").count() == 0)
    #expect(SkFontMgr.matchFamilyStyleCharacter(nil, character: "A") == nil)
}
#else
@Test func platformFamiliesAndFallback() throws {
    #expect(SkFontMgr.countFamilies() > 0)
    let families = SkFontMgr.familyNames()
    let family = try #require(families.first { !$0.isEmpty && !$0.hasPrefix(".") })

    let set = SkFontMgr.matchFamily(family)
    #expect(set.count() > 0)
    let (style, _) = set.getStyle(0)
    #expect(style.weight >= 100 && style.weight <= 1000)
    let face = try #require(set.createTypeface(0))
    #expect(face.getFamilyName() == family)
    #expect(set.matchStyle(.normal) != nil)
    #expect(SkFontMgr.matchFamily("No Such Family 1234").count() == 0)

    // Some face on the system has 'A'.
    let fallback = try #require(SkFontMgr.matchFamilyStyleCharacter(nil, character: "A"))
    #expect(fallback.unicharToGlyph("A") != 0)
}
#endif
