# Progress of Api compared to Skia (m132)

How it's laid out (same shape as NucleantThorVG):

- `Sources/CSkia/include/cskia_api.h` + `cskia_api.cpp`: the plain-C shim,
  one handle per Skia class.
- `Sources/NucleantSkia/API/`: one protocol per Skia class (`SkiaCanvas`,
  `SkiaPaint`, `SkiaPath`, `SkiaFont`, `SkiaTypeface`, `SkiaShader`,
  `SkiaPathEffect`, `SkiaImage`). Each holds `var base: OpaquePointer`, and
  the API lives in its default extension. Anything else can conform and get
  the API.
- Owning types are named as in Skia: `SkPaint`, `SkPath`, `SkFont`,
  `SkTypeface`, `SkShader`, `SkPathEffect`, `SkImage`, `SkCanvas`
  (borrowed), `SkRasterSurface`. Skia's factory namespaces are enums:
  `SkGradientShader`, `SkShaders`, `SkDashPathEffect`, `SkCornerPathEffect`,
  `SkFontMgr`, `SkImages`, `SkSurfaces`.
- Method names follow Skia's (`drawRect`, `moveTo`, `setStrokeWidth`, …).
  Positions and sizes are `SIMD2<Float>` (`pos:` / `size:`), with generic
  `SIMD2<F: BinaryFloatingPoint>` overloads. Colors are `SIMD4<Float>` 0…1
  (`color4f`) or `SIMD4<UInt8>` 0…255, in (r, g, b, a) order.
- Tests: `Tests/NucleantSkiaTests` draw into a raster surface and read the
  pixels back.

`[x]` = wrapped and tested. `[ ]` = remaining.

## SkCanvas
- [x] save / restore / restoreToCount / getSaveCount
- [x] saveLayer (bounds, paint)
- [x] saveLayerAlphaf
- [ ] saveLayer(SaveLayerRec) — backdrop filter, flags
- [x] translate / scale / rotate / rotate about point / skew
- [x] concat / setMatrix / resetMatrix / getTotalMatrix (SkMatrix)
- [ ] concat / getLocalToDevice (SkM44)
- [x] clipRect (op, anti-alias)
- [x] clipRRect (uniform radius)
- [x] clipPath
- [ ] clipRRect with per-corner radii
- [ ] clipShader / clipRegion
- [ ] getLocalClipBounds / getDeviceClipBounds / isClipEmpty / isClipRect / quickReject
- [x] clear
- [x] drawColor (blend mode)
- [x] drawPaint
- [x] drawRect
- [x] drawRRect (uniform radius) — SkCanvas::drawRoundRect
- [ ] drawRRect with per-corner radii / drawDRRect
- [x] drawOval
- [x] drawCircle
- [x] drawArc
- [x] drawLine
- [x] drawPoint
- [ ] drawPoints (points / lines / polygon mode)
- [x] drawPath
- [x] drawImage (optional paint, linear sampling)
- [x] drawImageRect (whole image into rect)
- [x] drawImageRect with source rect / sampling options
- [x] drawImageNine
- [ ] drawImageLattice
- [ ] drawAtlas
- [ ] drawVertices / drawPatch
- [x] drawSimpleText / drawString (UTF-8)
- [x] drawTextBlob / drawGlyphs
- [ ] drawPicture / drawDrawable
- [ ] drawRegion
- [ ] drawAnnotation
- [ ] readPixels / writePixels / imageInfo / getBaseLayerSize
- [ ] makeSurface / getSurface

## SkPaint
- [x] new / copy / reset
- [x] setAntiAlias / isAntiAlias
- [x] setDither / isDither
- [x] setColor (SkColor ARGB, SIMD4<UInt8>) / getColor
- [x] setARGB
- [x] setColor4f / getColor4f
- [x] setAlphaf / getAlphaf
- [ ] setAlpha / getAlpha (UInt8)
- [x] setStyle / getStyle / setStroke
- [x] setStrokeWidth / getStrokeWidth
- [x] setStrokeMiter / getStrokeMiter
- [x] setStrokeCap / getStrokeCap
- [x] setStrokeJoin / getStrokeJoin
- [x] setShader (and clear)
- [ ] getShader / refShader
- [x] setPathEffect (and clear)
- [ ] getPathEffect
- [x] setBlendMode / getBlendMode
- [ ] setBlender
- [x] setMaskFilter — blur (SkMaskFilter::MakeBlur) and clear
- [ ] setMaskFilter — other mask filters
- [ ] setColorFilter
- [ ] setImageFilter
- [ ] nothingToDraw / canComputeFastBounds / computeFastBounds

## SkPath
- [x] new / copy / reset / rewind
- [x] moveTo / lineTo / quadTo / conicTo / cubicTo / close
- [x] rMoveTo / rLineTo / rQuadTo / rConicTo / rCubicTo
- [x] arcTo (all three forms: tangent, oval, SVG) / rArcTo
- [x] addRect (direction)
- [x] addRRect (uniform radius)
- [x] addRRect with per-corner radii (`cornerRadii:`)
- [x] addOval
- [x] addCircle
- [x] addArc
- [x] addPoly
- [x] addPath (offset)
- [x] addPath with matrix / AddPathMode / reverseAddPath
- [x] setFillType / getFillType
- [x] toggleInverseFillType / isInverseFillType
- [x] getBounds / computeTightBounds
- [x] contains
- [x] isEmpty
- [x] countPoints / countVerbs
- [x] getPoint / getPoints / getLastPt / setLastPt (verbs: through `elements()`)
- [x] Iter — `SkPathIter` (a Sequence of `SkPathElement`), `elements(forceClose:)`
- [x] isRect / isOval / isLine / isConvex / isFinite / isLastContourClosed
- [ ] isRRect
- [x] conservativelyContainsRect
- [x] interpolate / isInterpolatable
- [x] offset
- [x] transform (SkMatrix)
- [x] serialize / readFromMemory (`serialize()`, `SkPath(serialized:)`)
- [x] SkParsePath — FromSVGString / ToSVGString (`SkPath(svg:)`, `toSVGString(relative:)`)
- [x] PathOps — Op (`op(_:_:)`), Simplify, AsWinding, SkOpBuilder — nil in the browser, whose Skia has no PathOps
- [ ] SkPathBuilder
- [x] SkPathMeasure (length, getPosTan, getSegment, isClosed, nextContour)

## SkShader
- [x] SkGradientShader::MakeLinear
- [x] SkGradientShader::MakeRadial
- [x] SkGradientShader::MakeTwoPointConical
- [x] SkGradientShader::MakeSweep
- [ ] gradient flags (interpolate in premul), color space, local matrix
- [x] SkShaders::Color
- [ ] SkShaders::Empty / Blend
- [ ] SkShaders::MakeFractalNoise / MakeTurbulence
- [x] SkImage::makeShader (image shader, tile modes)
- [ ] makeWithLocalMatrix / makeWithColorFilter
- [ ] SkPictureShader
- [ ] SkRuntimeEffect (SkSL) shaders

## SkPathEffect
- [x] SkDashPathEffect::Make
- [x] SkCornerPathEffect::Make
- [ ] SkDiscretePathEffect
- [ ] SkPath1DPathEffect / SkPath2DPathEffect / SkLine2DPathEffect
- [ ] SkTrimPathEffect
- [ ] SkPathEffect::MakeSum / MakeCompose

## SkMaskFilter
- [x] MakeBlur (through SkPaint)
- [ ] SkShaderMaskFilter
- [ ] SkTableMaskFilter

## SkImageFilter (SkImageFilters)
- [ ] Blur
- [ ] DropShadow / DropShadowOnly
- [ ] Offset / MatrixTransform / Crop / Tile
- [ ] ColorFilter / Blend / Arithmetic
- [ ] Merge / Compose
- [ ] Image / Picture / Shader / RuntimeShader
- [ ] Dilate / Erode
- [ ] DisplacementMap / Magnifier
- [ ] Lighting (distant / point / spot)

## SkColorFilter (SkColorFilters)
- [ ] Blend
- [ ] Matrix (SkColorMatrix)
- [ ] Compose / Lerp
- [ ] LinearToSRGBGamma / SRGBToLinearGamma
- [ ] Table / Lighting
- [ ] SkLumaColorFilter

## SkTypeface / SkFontMgr
- [x] SkFontMgr::makeFromData
- [x] SkFontMgr::makeFromFile
- [x] SkFontMgr::matchFamilyStyle (nil = platform default)
- [x] SkFontMgr::matchFamilyStyleCharacter (fallback for a character)
- [x] SkFontMgr::countFamilies / getFamilyName / matchFamily (enumeration), SkFontStyleSet
- [x] SkTypeface::getFamilyName
- [x] SkTypeface::countGlyphs
- [x] fontStyle / isBold / isItalic / isFixedPitch
- [x] unicharToGlyph
- [x] getUnitsPerEm
- [ ] makeClone (variable-font axes) / getVariationDesignPosition
- [x] table tags / getTableData (`SkSetFourByteTag`)

## SkFont
- [x] new (typeface, size) / copy
- [x] setTypeface / refTypeface
- [x] setSize / getSize
- [x] setScaleX / getScaleX
- [x] setSkewX / getSkewX
- [x] setEmbolden
- [x] setSubpixel
- [x] setLinearMetrics
- [x] setBaselineSnap
- [x] setEdging
- [x] setHinting
- [x] setForceAutoHinting / setEmbeddedBitmaps
- [x] getters for the flags (isEmbolden, isSubpixel, getEdging, getHinting, …)
- [x] measureText (advance, ink bounds)
- [x] textToGlyphs
- [x] getWidths
- [x] getWidthsBounds / getBounds
- [x] getPos / getXPos
- [x] getPath (glyph outline)
- [ ] getPaths
- [x] unicharToGlyph / unicharsToGlyphs
- [ ] getIntercepts (on the font — the blob has them)
- [x] getMetrics (SkFontMetrics)
- [x] getSpacing

## Text layout
- [x] SkTextBlob (from text, positioned glyphs, x positions; bounds, getIntercepts) / SkTextBlobBuilder (three run kinds)
- [ ] SkShaper (Apple has it as SkiaShaper.xcframework; the HarfBuzz shaper is only in the Linux build)
- [ ] skparagraph — ParagraphBuilder / Paragraph (only in the Linux build)
- [ ] SkUnicode (libskunicode is linked)

## SkImage (SkImages)
- [x] SkImages::RasterFromPixmapCopy (RGBA/BGRA bytes, 32-bit pixels)
- [x] width / height
- [ ] RasterFromData / RasterFromPixmap (no copy, release proc)
- [x] DeferredFromEncodedData (`SkImage(encoded:)`)
- [x] colorType / alphaType / isOpaque
- [x] readPixels (any rect) / peekPixels (`withPeekedPixels`)
- [x] makeSubset / makeRasterImage
- [x] encode — PNG, JPEG, WebP (`encode(_:quality:)`) — nil in the browser, whose Skia has no encoders
- [ ] SkImages::TextureFromTexture — wrap a VkImage as an image (GPU)
- [ ] makeTextureImage

## SkSurface (SkSurfaces)
- [x] SkSurfaces::Raster
- [x] getCanvas
- [x] readPixels
- [x] makeImageSnapshot
- [x] SkSurfaces::WrapBackendRenderTarget (Vulkan) — existing `SkiaSurface`
- [ ] SkSurfaces::WrapPixels (draw into caller memory)
- [ ] SkSurfaces::RenderTarget (Ganesh-owned)
- [ ] writePixels / notifyContentWillChange
- [ ] makeSurface (compatible) / draw (surface into canvas)

## SkMatrix / SkM44 / SkRRect
- [x] SkMatrix (9 values, identity, translate, scale)
- [ ] SkMatrix rotate / skew / concat / invert / mapPoints / mapRect
- [ ] SkM44
- [ ] SkRRect (per-corner radii, nine-patch, type queries)

## GPU (Ganesh / Vulkan) — existing `SkiaVulkanContext` / `SkiaSurface`
- [x] GrDirectContexts::MakeVulkan on the engine's device/queue
- [x] wrap an engine VkImage as a render target
- [x] flush with final layout / submit
- [x] notify external layout change
- [ ] freeGpuResources / purgeUnlockedResources / setResourceCacheLimit
- [ ] instance/device extension lists for Linux/Android (`makeSkiaContext` hardcodes `VK_EXT_metal_surface`)

## Other modules
- [ ] SkPicture / SkPictureRecorder
- [ ] SkDrawable
- [ ] SkRegion
- [ ] SkData / SkStream
- [ ] SkCodec (animated, frames)
- [x] SkSVGDOM — `make` (Builder, platform fonts for <text>), `intrinsicSize`, `viewBox`, `setContainerSize`, `render`. Apple: libsvg/skshaper/skunicode as their own xcframeworks (one library each), plus four private Skia headers its headers include (`Sources/CSkia/skia`); Linux/Android link them with the rest; the browser's Skia has none (`make` is nil)
- [ ] SkSVGDOM `renderNode`, `findNodeById`, resource provider (external images)
- [ ] SkDocument / SkPDF
- [ ] SkRuntimeEffect (SkSL color filters / blenders)

## Swift-side additions (not in Skia)
- [x] `SkPaint()` starts anti-aliased (Skia's default is off)
- [x] `SkPaint(color:)`
- [x] `clearShader()` / `clearPathEffect()` / `clearMaskFilter()` stand in for `set…(nullptr)`
- [x] `SkRasterSurface.readPixel(x:y:)`
- [x] `SkiaSurface.canvas` — the GPU surface's canvas as an `SkCanvas`
