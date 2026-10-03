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
- [ ] drawImageRect with source rect / sampling options
- [ ] drawImageNine / drawImageLattice
- [ ] drawAtlas
- [ ] drawVertices / drawPatch
- [x] drawSimpleText / drawString (UTF-8)
- [ ] drawTextBlob / drawGlyphs
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
- [ ] rMoveTo / rLineTo / rQuadTo / rConicTo / rCubicTo
- [ ] arcTo (all three forms)
- [x] addRect (direction)
- [x] addRRect (uniform radius)
- [ ] addRRect with per-corner radii
- [x] addOval
- [x] addCircle
- [x] addArc
- [ ] addPoly
- [x] addPath (offset)
- [ ] addPath with matrix / AddPathMode / reverseAddPath
- [x] setFillType / getFillType
- [ ] toggleInverseFillType / isInverseFillType
- [x] getBounds / computeTightBounds
- [x] contains
- [x] isEmpty
- [x] countPoints / countVerbs
- [ ] getPoint / getPoints / getVerbs / getLastPt / setLastPt
- [ ] Iter / RawIter
- [ ] isRect / isOval / isRRect / isLine / isConvex / isFinite
- [ ] conservativelyContainsRect
- [ ] interpolate / isInterpolatable
- [x] offset
- [x] transform (SkMatrix)
- [ ] serialize / readFromMemory
- [ ] SkParsePath — FromSVGString / ToSVGString
- [ ] PathOps — Op (union / intersect / difference / xor), Simplify, AsWinding, SkOpBuilder
- [ ] SkPathBuilder
- [ ] SkPathMeasure (length, getPosTan, getSegment)

## SkShader
- [x] SkGradientShader::MakeLinear
- [x] SkGradientShader::MakeRadial
- [x] SkGradientShader::MakeTwoPointConical
- [x] SkGradientShader::MakeSweep
- [ ] gradient flags (interpolate in premul), color space, local matrix
- [x] SkShaders::Color
- [ ] SkShaders::Empty / Blend
- [ ] SkShaders::MakeFractalNoise / MakeTurbulence
- [ ] SkImage::makeShader (image shader, tile modes)
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
- [ ] SkFontMgr::matchFamilyStyleCharacter (fallback for a character)
- [ ] SkFontMgr::countFamilies / getFamilyName / matchFamily (enumeration)
- [x] SkTypeface::getFamilyName
- [x] SkTypeface::countGlyphs
- [ ] fontStyle / isBold / isItalic / isFixedPitch
- [ ] unicharToGlyph / unicharsToGlyphs
- [ ] getUnitsPerEm
- [ ] makeClone (variable-font axes) / getVariationDesignPosition
- [ ] countTables / getTableData

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
- [ ] setForceAutoHinting / setEmbeddedBitmaps
- [ ] getters for the flags (isEmbolden, isSubpixel, getEdging, getHinting, …)
- [x] measureText (advance, ink bounds)
- [x] textToGlyphs
- [x] getWidths
- [ ] getWidthsBounds / getBounds
- [ ] getPos / getXPos
- [ ] getPath / getPaths (glyph outlines)
- [ ] unicharToGlyph
- [ ] getIntercepts
- [x] getMetrics (SkFontMetrics)
- [x] getSpacing

## Text layout
- [ ] SkTextBlob / SkTextBlobBuilder
- [ ] SkShaper (libskshaper is linked)
- [ ] skparagraph — ParagraphBuilder / Paragraph (libskparagraph is linked)
- [ ] SkUnicode (libskunicode is linked)

## SkImage (SkImages)
- [x] SkImages::RasterFromPixmapCopy (RGBA/BGRA bytes, 32-bit pixels)
- [x] width / height
- [ ] RasterFromData / RasterFromPixmap (no copy, release proc)
- [ ] DeferredFromEncodedData (PNG decode is linked)
- [ ] colorType / alphaType / isOpaque
- [ ] readPixels / peekPixels
- [ ] makeSubset / makeRasterImage
- [ ] SkPngEncoder / encode (PNG encode is linked)
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
- [ ] SkSVGDOM (libsvg is linked)
- [ ] SkDocument / SkPDF
- [ ] SkRuntimeEffect (SkSL color filters / blenders)

## Swift-side additions (not in Skia)
- [x] `SkPaint()` starts anti-aliased (Skia's default is off)
- [x] `SkPaint(color:)`
- [x] `clearShader()` / `clearPathEffect()` / `clearMaskFilter()` stand in for `set…(nullptr)`
- [x] `SkRasterSurface.readPixel(x:y:)`
- [x] `SkiaSurface.canvas` — the GPU surface's canvas as an `SkCanvas`
