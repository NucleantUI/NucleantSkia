//
//  SkiaWin32Tests.swift
//  NucleantSkiaTests
//
//  Skia on Windows: Ganesh on the engine's own Vulkan device, drawing into
//  the node's VkImage, which the engine then samples — the engine on a Win32
//  window, as an app's is. Shapes, paths, text through DirectWrite from a
//  font file, and images Skia uploads itself, read back through Vulkan.
//
//  Needs a Vulkan driver. CI's Windows machines have no GPU, so the workflow
//  registers Mesa's software one (lavapipe); on a desktop it is the
//  machine's own.
//
#if os(Windows)
import Foundation
import Testing
import WinSDK
import CVulkan
import NucleantVulkan
@testable import NucleantSkia

/// Where `flush` leaves the image, as a Swift API value (Int32 on Windows).
private let attachmentLayout = UInt32(VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue)

/// On the main actor, the thread that owns the window, as in an app.
@MainActor
@Suite(.serialized)
struct SkiaWin32Tests {

    let window: TestWindow

    init() throws {
        window = try TestWindow(width: 64, height: 48)
    }

    func makeEngine() throws -> VulkanRenderEngine<SkiaSlot> {
        let window = window
        return try VulkanRenderEngine<SkiaSlot>(
            win32Instance: window.instance,
            win32Window: window.hwnd,
            getExtent: { window.extent }
        )
    }

    @Test func widgetNodeHoldsWhatSkiaDrew() throws {
        let engine = try makeEngine()
        let context = try engine.renderDevice.makeSkiaContext()
        let node = try #require(engine.renderDevice.makeSkiaWidgetNode(context: context, width: 32, height: 16))
        defer { node.destroyResources(engine.renderDevice) }
        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)

        canvas.clear(SIMD4<Float>(0, 0, 1, 1))
        canvas.drawRect(x: 0, y: 0, w: 16, h: 16, paint: SkPaint(color: SIMD4(1, 0, 0, 1)))
        #expect(surface.flush(finalLayout: attachmentLayout, syncCpu: false))

        // RGBA bytes: red on the left half, the blue clear on the right.
        let pixels = readPixels(engine, node)
        expectPixel(pixels, 32, 4, 8, [255, 0, 0, 255])
        expectPixel(pixels, 32, 15, 0, [255, 0, 0, 255])
        expectPixel(pixels, 32, 24, 8, [0, 0, 255, 255])
    }

    @Test func pathsAndAntialiasedShapes() throws {
        let engine = try makeEngine()
        let context = try engine.renderDevice.makeSkiaContext()
        let node = try #require(engine.renderDevice.makeSkiaWidgetNode(context: context, width: 64, height: 64))
        defer { node.destroyResources(engine.renderDevice) }
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
        #expect(surface.flush(finalLayout: attachmentLayout, syncCpu: false))

        let pixels = readPixels(engine, node)
        expectPixel(pixels, 64, 10, 10, [255, 0, 0, 255])
        expectPixel(pixels, 64, 48, 48, [0, 0, 255, 255])
        expectPixel(pixels, 64, 40, 30, [255, 255, 255, 255])
        // The circle's edge is antialiased: around it, pixels part blue.
        let around = (36..<62).flatMap { y in (36..<62).map { x in pixel(pixels, 64, x, y) } }
        #expect(around.contains { $0[0] > 20 && $0[0] < 235 })
    }

    @Test func textFromAFontFileAndAnUploadedImage() throws {
        let engine = try makeEngine()
        let context = try engine.renderDevice.makeSkiaContext()
        let node = try #require(engine.renderDevice.makeSkiaWidgetNode(context: context, width: 120, height: 40))
        defer { node.destroyResources(engine.renderDevice) }
        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)

        // A face from a file, through DirectWrite.
        let url = try #require(Bundle.module.url(forResource: "Roboto-Regular", withExtension: "ttf", subdirectory: "Resources"))
        let path = url.withUnsafeFileSystemRepresentation { String(cString: $0!) }
        let typeface = try #require(SkFontMgr.makeFromFile(path))
        #expect(typeface.getFamilyName() == "Roboto")
        // A raster image is uploaded by Skia when drawn.
        let green: [UInt8] = Array(repeating: [0, 255, 0, 255], count: 4).flatMap { $0 }
        let image = try #require(SkImages.rasterFromPixmapCopy(green, size: SIMD2(2, 2)))

        canvas.clear(SIMD4<Float>(1, 1, 1, 1))
        canvas.drawString("Hi", pos: SIMD2(4, 30), font: SkFont(typeface, size: 24), paint: SkPaint(color: SIMD4(0, 0, 0, 1)))
        canvas.drawImageRect(image, pos: SIMD2(80, 10), size: SIMD2(20, 20))
        #expect(surface.flush(finalLayout: attachmentLayout, syncCpu: false))

        let pixels = readPixels(engine, node)
        let inked = (0..<40).flatMap { y in (0..<60).map { x in pixel(pixels, 120, x, y) } }.filter { $0[0] < 128 }.count
        #expect(inked > 20)
        expectPixel(pixels, 120, 90, 20, [0, 255, 0, 255])
        expectPixel(pixels, 120, 115, 35, [255, 255, 255, 255])
    }

    @Test func redrawAfterAFlushReplacesTheContent() throws {
        let engine = try makeEngine()
        let context = try engine.renderDevice.makeSkiaContext()
        let node = try #require(engine.renderDevice.makeSkiaWidgetNode(context: context, width: 16, height: 16))
        defer { node.destroyResources(engine.renderDevice) }
        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)

        for (color, bytes) in [(SIMD4<Float>(1, 0, 0, 1), [UInt8](arrayLiteral: 255, 0, 0, 255)),
                               (SIMD4<Float>(0, 1, 0, 1), [0, 255, 0, 255])] {
            canvas.clear(color)
            #expect(surface.flush(finalLayout: attachmentLayout, syncCpu: false))
            expectPixel(readPixels(engine, node), 16, 8, 8, bytes)
        }
    }

    @Test func resizedNodeDrawsAtTheNewSize() throws {
        let engine = try makeEngine()
        let context = try engine.renderDevice.makeSkiaContext()
        let node = try #require(engine.renderDevice.makeSkiaWidgetNode(context: context, width: 8, height: 8))
        defer { node.destroyResources(engine.renderDevice) }
        let oldImage = node.image

        #expect(engine.renderDevice.resizeSkiaNode(node, id: 1, width: 24, height: 12))
        #expect(node.width == 24)
        #expect(node.height == 12)
        #expect(node.image != oldImage)

        let surface = try #require(node.canvas.surface)
        let canvas = try #require(surface.canvas)
        canvas.clear(SIMD4<Float>(0, 0, 0, 0))
        canvas.drawRect(x: 12, y: 0, w: 12, h: 12, paint: SkPaint(color: SIMD4(0, 1, 0, 1)))
        #expect(surface.flush(finalLayout: attachmentLayout, syncCpu: false))
        let pixels = readPixels(engine, node)
        expectPixel(pixels, 24, 4, 6, [0, 0, 0, 0])
        expectPixel(pixels, 24, 20, 6, [0, 255, 0, 255])
    }

    @Test func engineCompositesASkiaNode() throws {
        let engine = try makeEngine()
        let context = try engine.renderDevice.makeSkiaContext()
        let node = try #require(engine.renderDevice.makeSkiaWidgetNode(context: context, width: 32, height: 24))
        let canvas = try #require(node.canvas.surface?.canvas)
        canvas.clear(SIMD4<Float>(1, 0.5, 0, 1))

        engine.append(SkiaSlot(id: 1, context: .skia(node)))
        // The node's update flushes Skia's drawing, then the frame samples it.
        engine.drawFrame(1.0 / 60.0)
        engine.waitForPreviousFrame()
        #expect(engine.renderDevice.readable.contains(1))
        let pixels = readPixels(engine, node)
        expectPixel(pixels, 32, 16, 12, [255, 128, 0, 255])
        // The window only shows the node; its maker frees it (and its surface).
        engine.remove(id: 1)
        node.destroyResources(engine.renderDevice)
    }
}

// MARK: - Helpers

/// `node`'s texels through a host-visible buffer on the engine's device. A
/// real GPU keeps a color attachment in its own (compressed) form, so the
/// image goes to TRANSFER_SRC for the copy and back to the layout the node
/// tracks, after whatever Skia or the frame submitted before it.
private func readPixels(_ engine: VulkanRenderEngine<SkiaSlot>, _ node: SkiaShaderNode<SkiaSlot>) -> [UInt8] {
    let width = Int(node.width), height = Int(node.height)
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
    let wanted = VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT.rawValue)
        | VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_HOST_COHERENT_BIT.rawValue)
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

    let image = node.image
    let layout = node.currentLayout
    let anyAccess = VkAccessFlags(VK_ACCESS_MEMORY_READ_BIT.rawValue) | VkAccessFlags(VK_ACCESS_MEMORY_WRITE_BIT.rawValue)
    engine.renderDevice.oneTimeSubmit { cmd in
        engineImageBarrier(
            cmd, image: image,
            srcLayout: layout, srcAccess: anyAccess, srcStage: VK_PIPELINE_STAGE_ALL_COMMANDS_BIT,
            dstLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            dstAccess: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue), dstStage: VK_PIPELINE_STAGE_TRANSFER_BIT
        )
        var region = VkBufferImageCopy()
        region.imageSubresource = VkImageSubresourceLayers(
            aspectMask: VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue), mipLevel: 0, baseArrayLayer: 0, layerCount: 1)
        region.imageExtent = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        vkCmdCopyImageToBuffer(cmd, image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buffer, 1, &region)
        engineImageBarrier(
            cmd, image: image,
            srcLayout: VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
            srcAccess: VkAccessFlags(VK_ACCESS_TRANSFER_READ_BIT.rawValue), srcStage: VK_PIPELINE_STAGE_TRANSFER_BIT,
            dstLayout: layout, dstAccess: anyAccess, dstStage: VK_PIPELINE_STAGE_ALL_COMMANDS_BIT
        )
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

/// A top-level window of the system STATIC class (nothing to register), never
/// shown — a surface needs a window, not a visible one.
final class TestWindow {
    let instance: HINSTANCE
    let hwnd: HWND

    init(width: Int32, height: Int32) throws {
        let module = try #require(GetModuleHandleW(nil))
        let window = "STATIC".withCString(encodedAs: UTF16.self) { className in
            "NucleantSkiaTests".withCString(encodedAs: UTF16.self) { title in
                CreateWindowExW(0, className, title, 0, 0, 0, width, height, nil, nil, module, nil)
            }
        }
        instance = module
        hwnd = try #require(window)
    }

    /// The client area, in pixels.
    var extent: VkExtent2D {
        var rect = RECT()
        GetClientRect(hwnd, &rect)
        return VkExtent2D(width: UInt32(max(rect.right - rect.left, 0)),
                          height: UInt32(max(rect.bottom - rect.top, 0)))
    }

    deinit {
        DestroyWindow(hwnd)
    }
}
#endif
