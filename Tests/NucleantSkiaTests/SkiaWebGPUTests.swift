//
//  SkiaWebGPUTests.swift
//  NucleantSkiaTests
//
//  Skia in the browser: Graphite on the page's WebGPU, drawing into the
//  texture the engine's VkImage is (VK_NUCLEANT_webgpu_objects) — so what
//  Skia drew is read back through Vulkan with no copy in between. Shapes,
//  paths, text from a font file, and images Skia uploads itself. Run with
//  scripts/run_wasm_tests.py (headless Chrome).
//
#if os(WASI)
import Foundation
import Testing
import CVulkan
import NucleantVulkan
@testable import NucleantSkia

@Suite(.serialized)
struct SkiaWebGPUTests {

    @Test func widgetNodeHoldsWhatSkiaDrew() throws {
        let engine = try VulkanRenderEngine<SkiaSlot>(canvasSelector: "#test-canvas", getSize: { (64, 48) })
        let context = try engine.makeSkiaContext()
        let node = try #require(engine.makeSkiaWidgetNode(context: context, width: 32, height: 16))
        defer { node.destroyResources(engine) }
        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)

        canvas.clear(SIMD4<Float>(0, 0, 1, 1))
        canvas.drawRect(x: 0, y: 0, w: 16, h: 16, paint: SkPaint(color: SIMD4(1, 0, 0, 1)))
        #expect(surface.flush(finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue, syncCpu: false))

        // RGBA bytes: red on the left half, the blue clear on the right.
        let pixels = readPixels(engine, node.image, width: 32, height: 16)
        expectPixel(pixels, 32, 4, 8, [255, 0, 0, 255])
        expectPixel(pixels, 32, 15, 0, [255, 0, 0, 255])
        expectPixel(pixels, 32, 24, 8, [0, 0, 255, 255])
    }

    @Test func pathsAndAntialiasedShapes() throws {
        let engine = try VulkanRenderEngine<SkiaSlot>(canvasSelector: "#test-canvas", getSize: { (64, 48) })
        let context = try engine.makeSkiaContext()
        let node = try #require(engine.makeSkiaWidgetNode(context: context, width: 64, height: 64))
        defer { node.destroyResources(engine) }
        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)

        canvas.clear(SIMD4<Float>(1, 1, 1, 1))
        let triangle = SkPath()
        triangle.moveTo(x: 0, y: 0)
        triangle.lineTo(x: 60, y: 0)
        triangle.lineTo(x: 0, y: 60)
        triangle.close()
        canvas.drawPath(triangle, paint: SkPaint(color: SIMD4(1, 0, 0, 1)))
        canvas.drawCircle(cx: 48, cy: 48, radius: 10, paint: SkPaint(color: SIMD4(0, 0, 1, 1)))
        #expect(surface.flush(finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue, syncCpu: false))

        let pixels = readPixels(engine, node.image, width: 64, height: 64)
        expectPixel(pixels, 64, 10, 10, [255, 0, 0, 255])
        expectPixel(pixels, 64, 48, 48, [0, 0, 255, 255])
        expectPixel(pixels, 64, 40, 30, [255, 255, 255, 255])
        // The circle's edge is antialiased: around it, pixels part blue.
        let around = (36..<62).flatMap { y in (36..<62).map { x in pixel(pixels, 64, x, y) } }
        #expect(around.contains { $0[0] > 20 && $0[0] < 235 })
    }

    @Test func textFromAFontFileAndAnUploadedImage() throws {
        let engine = try VulkanRenderEngine<SkiaSlot>(canvasSelector: "#test-canvas", getSize: { (64, 48) })
        let context = try engine.makeSkiaContext()
        let node = try #require(engine.makeSkiaWidgetNode(context: context, width: 120, height: 40))
        defer { node.destroyResources(engine) }
        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)

        // Fonts come from files in the browser (the page's mounted ones).
        let url = try #require(Bundle.module.url(forResource: "Roboto-Regular", withExtension: "ttf", subdirectory: "Resources"))
        let typeface = try #require(SkFontMgr.makeFromFile(url.path))
        #expect(typeface.getFamilyName() == "Roboto")
        // A raster image is uploaded by Skia when drawn.
        let green: [UInt8] = Array(repeating: [0, 255, 0, 255], count: 4).flatMap { $0 }
        let image = try #require(SkImages.rasterFromPixmapCopy(green, size: SIMD2(2, 2)))

        canvas.clear(SIMD4<Float>(1, 1, 1, 1))
        canvas.drawString("Hi", pos: SIMD2(4, 30), font: SkFont(typeface, size: 24), paint: SkPaint(color: SIMD4(0, 0, 0, 1)))
        canvas.drawImageRect(image, pos: SIMD2(80, 10), size: SIMD2(20, 20))
        #expect(surface.flush(finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue, syncCpu: false))

        let pixels = readPixels(engine, node.image, width: 120, height: 40)
        let inked = (0..<40).flatMap { y in (0..<60).map { x in pixel(pixels, 120, x, y) } }.filter { $0[0] < 128 }.count
        #expect(inked > 20)
        expectPixel(pixels, 120, 90, 20, [0, 255, 0, 255])
        expectPixel(pixels, 120, 115, 35, [255, 255, 255, 255])
    }

    @Test func redrawAfterAFlushReplacesTheContent() throws {
        let engine = try VulkanRenderEngine<SkiaSlot>(canvasSelector: "#test-canvas", getSize: { (64, 48) })
        let context = try engine.makeSkiaContext()
        let node = try #require(engine.makeSkiaWidgetNode(context: context, width: 16, height: 16))
        defer { node.destroyResources(engine) }
        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)

        for (color, bytes) in [(SIMD4<Float>(1, 0, 0, 1), [UInt8](arrayLiteral: 255, 0, 0, 255)),
                               (SIMD4<Float>(0, 1, 0, 1), [0, 255, 0, 255])] {
            canvas.clear(color)
            #expect(surface.flush(finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue, syncCpu: false))
            expectPixel(readPixels(engine, node.image, width: 16, height: 16), 16, 8, 8, bytes)
        }
    }

    @Test func resizedNodeDrawsAtTheNewSize() throws {
        let engine = try VulkanRenderEngine<SkiaSlot>(canvasSelector: "#test-canvas", getSize: { (64, 48) })
        let context = try engine.makeSkiaContext()
        let node = try #require(engine.makeSkiaWidgetNode(context: context, width: 8, height: 8))
        defer { node.destroyResources(engine) }
        let oldImage = node.image

        #expect(engine.resizeSkiaNode(node, id: 1, width: 24, height: 12))
        #expect(node.width == 24)
        #expect(node.height == 12)
        #expect(node.image != oldImage)

        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)
        canvas.clear(SIMD4<Float>(0, 0, 0, 0))
        canvas.drawRect(x: 12, y: 0, w: 12, h: 12, paint: SkPaint(color: SIMD4(0, 1, 0, 1)))
        #expect(surface.flush(finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue, syncCpu: false))
        let pixels = readPixels(engine, node.image, width: 24, height: 12)
        expectPixel(pixels, 24, 4, 6, [0, 0, 0, 0])
        expectPixel(pixels, 24, 20, 6, [0, 255, 0, 255])
    }

    @Test func engineCompositesASkiaNode() throws {
        let engine = try VulkanRenderEngine<SkiaSlot>(canvasSelector: "#test-canvas", getSize: { (64, 48) })
        let context = try engine.makeSkiaContext()
        let node = try #require(engine.makeSkiaWidgetNode(context: context, width: 32, height: 24))
        let canvas = try #require(node.canvas.surface?.canvas)
        canvas.clear(SIMD4<Float>(1, 0.5, 0, 1))

        engine.append(SkiaSlot(id: 1, context: .skia(node)))
        // The node's update flushes Skia's drawing, then the frame samples it.
        engine.drawFrame(1.0 / 60.0)
        engine.waitForPreviousFrame()
        #expect(engine.readable.contains(1))
        let pixels = readPixels(engine, node.image, width: 32, height: 24)
        expectPixel(pixels, 32, 16, 12, [255, 128, 0, 255])
        // The slot frees the node (and its surface) on removal.
        engine.remove(id: 1)
    }
}

// MARK: - Helpers

/// `image`'s texels through a host-visible buffer on the engine's device.
private func readPixels(_ engine: VulkanRenderEngine<SkiaSlot>, _ image: VkImage, width: Int, height: Int) -> [UInt8] {
    let byteCount = width * height * 4
    var bufferInfo = VkBufferCreateInfo()
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
    bufferInfo.size = VkDeviceSize(byteCount)
    bufferInfo.usage = VkBufferUsageFlags(VK_BUFFER_USAGE_TRANSFER_DST_BIT.rawValue)
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE
    var buffer: VkBuffer?
    vkCreateBuffer(engine.device, &bufferInfo, nil, &buffer)
    defer { vkDestroyBuffer(engine.device, buffer, nil) }

    var requirements = VkMemoryRequirements()
    vkGetBufferMemoryRequirements(engine.device, buffer, &requirements)
    var properties = VkPhysicalDeviceMemoryProperties()
    vkGetPhysicalDeviceMemoryProperties(engine.physicalDevice, &properties)
    let wanted = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue
    let memoryType = withUnsafeBytes(of: properties.memoryTypes) { raw -> UInt32 in
        let types = raw.bindMemory(to: VkMemoryType.self)
        for index in 0..<Int(properties.memoryTypeCount)
        where requirements.memoryTypeBits & (1 << index) != 0 && types[index].propertyFlags & wanted == wanted {
            return UInt32(index)
        }
        return 0
    }
    var allocInfo = VkMemoryAllocateInfo()
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
    allocInfo.allocationSize = requirements.size
    allocInfo.memoryTypeIndex = memoryType
    var memory: VkDeviceMemory?
    vkAllocateMemory(engine.device, &allocInfo, nil, &memory)
    defer { vkFreeMemory(engine.device, memory, nil) }
    vkBindBufferMemory(engine.device, buffer, memory, 0)

    engine.oneTimeSubmit { cmd in
        var region = VkBufferImageCopy()
        region.imageSubresource = VkImageSubresourceLayers(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue), mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
        region.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        vkCmdCopyImageToBuffer(cmd, image, VK_IMAGE_LAYOUT_GENERAL, buffer, 1, &region)
    }

    var out = [UInt8](repeating: 0, count: byteCount)
    var mapped: UnsafeMutableRawPointer?
    vkMapMemory(engine.device, memory, 0, VkDeviceSize(byteCount), 0, &mapped)
    if let mapped {
        out.withUnsafeMutableBytes { $0.baseAddress?.copyMemory(from: mapped, byteCount: byteCount) }
    }
    vkUnmapMemory(engine.device, memory)
    return out
}
#endif
