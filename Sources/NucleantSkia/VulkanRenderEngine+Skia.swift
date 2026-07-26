//
//  VulkanRenderEngine+Skia.swift
//  PyNucleantUI
//
//  The Skia side of the engine: a Ganesh Vulkan context sharing the
//  engine's device/queue, widget nodes whose VkImage Skia renders into
//  directly, and the per-frame update the node dispatch routes `.skia`
//  slots to. Everything lives in this file so the engine core stays
//  Skia-free.
//
import NucleantVulkan
import VulkanCore
import CVulkan
//import SulphurCore
import CSkia


// MARK: - Node factory

extension VulkanRenderEngine {

    /// Build a Ganesh Vulkan context over this engine's instance/device/
    /// queue. One context per canvas is fine for now — contexts don't
    /// share GPU caches, but ownership stays trivially scoped: the canvas
    /// drops surface + context before the engine (and its VkDevice) go.
    ///
    /// The extension lists are re-derived with the same availability
    /// checks the engine's init runs, so they name exactly what was
    /// enabled — Skia's caps need the truth (portability_subset above
    /// all, which keeps it inside MoltenVK's feature set).
    public func makeSkiaContext() throws -> SkiaVulkanContext {
        var instanceExtensions = ["VK_KHR_surface", "VK_EXT_metal_surface"]
        let availableInstance = enumerateSkiaInstanceExtensions()
        if availableInstance.contains("VK_KHR_get_physical_device_properties2") {
            instanceExtensions.append("VK_KHR_get_physical_device_properties2")
        }
        if availableInstance.contains("VK_KHR_portability_enumeration") {
            instanceExtensions.append("VK_KHR_portability_enumeration")
        }
        var deviceExtensions = ["VK_KHR_swapchain"]
        let availableDevice = enumerateSkiaDeviceExtensions(physicalDevice)
        if availableDevice.contains("VK_KHR_portability_subset") {
            deviceExtensions.append("VK_KHR_portability_subset")
        }
        if availableDevice.contains("VK_EXT_metal_objects") {
            deviceExtensions.append("VK_EXT_metal_objects")
        }
        return try SkiaVulkanContext(
            instance:           instance,
            physicalDevice:     physicalDevice,
            device:             device,
            queue:              graphicsQueue,
            queueFamilyIndex:   queueFamilyIndex,
            instanceExtensions: instanceExtensions,
            deviceExtensions:   deviceExtensions
        )
    }

    /// Build the engine-owned VkImage (same shape as the thor node's
    /// owned-image path) and the `SkiaSurface` wrapping it — the part node
    /// creation (`makeSkiaWidgetNode`) and in-place resize (`resizeSkiaNode`)
    /// share. Returns nil (freeing any partial allocation) on failure.
    func makeSkiaImageAndSurface(
        context: SkiaVulkanContext,
        width:   Int,
        height:  Int
    ) -> (image: VkImage, view: VkImageView, memory: VkDeviceMemory?, surface: SkiaSurface)? {
        // GrVkGpu::onWrapBackendRenderTarget (check_image_info) unconditionally
        // requires BOTH transfer bits on any VkImage Ganesh wraps — without
        // TRANSFER_SRC_BIT it silently rejects the wrap (WrapBackendRenderTarget
        // returns null, no error surfaced anywhere in the public API).
        let usage = VkImageUsageFlags(
            VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue |
            VK_IMAGE_USAGE_SAMPLED_BIT.rawValue |
            VK_IMAGE_USAGE_STORAGE_BIT.rawValue |
            VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue |
            VK_IMAGE_USAGE_TRANSFER_DST_BIT.rawValue
        )

        var image: VkImage?
        var imageInfo = VkImageCreateInfo()
        imageInfo.sType         = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
        imageInfo.imageType     = VK_IMAGE_TYPE_2D
        imageInfo.format        = VK_FORMAT_R8G8B8A8_UNORM
        imageInfo.extent        = VkExtent3D(width: UInt32(width), height: UInt32(height), depth: 1)
        imageInfo.mipLevels     = 1
        imageInfo.arrayLayers   = 1
        imageInfo.samples       = VK_SAMPLE_COUNT_1_BIT
        imageInfo.tiling        = VK_IMAGE_TILING_OPTIMAL
        imageInfo.usage         = usage
        imageInfo.sharingMode   = VK_SHARING_MODE_EXCLUSIVE
        imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED
        guard vkCreateImage(device, &imageInfo, nil, &image) == VK_SUCCESS, let image else {
            print("VulkanRenderEngine: skia node image creation failed")
            return nil
        }

        var requirements = VkMemoryRequirements()
        vkGetImageMemoryRequirements(device, image, &requirements)
        var memory: VkDeviceMemory?
        var allocInfo = VkMemoryAllocateInfo()
        allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
        allocInfo.allocationSize = requirements.size
        allocInfo.memoryTypeIndex = findMemoryType(
            typeFilter: requirements.memoryTypeBits,
            properties: VkMemoryPropertyFlags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT.rawValue)
        )
        guard vkAllocateMemory(device, &allocInfo, nil, &memory) == VK_SUCCESS else {
            vkDestroyImage(device, image, nil)
            print("VulkanRenderEngine: skia node memory allocation failed")
            return nil
        }
        vkBindImageMemory(device, image, memory, 0)

        var view: VkImageView?
        var viewInfo = VkImageViewCreateInfo()
        viewInfo.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
        viewInfo.image    = image
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D
        viewInfo.format   = VK_FORMAT_R8G8B8A8_UNORM
        viewInfo.subresourceRange = VkImageSubresourceRange(
            aspectMask:     VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
            baseMipLevel:   0, levelCount: 1,
            baseArrayLayer: 0, layerCount: 1
        )
        guard vkCreateImageView(device, &viewInfo, nil, &view) == VK_SUCCESS, let view else {
            vkDestroyImage(device, image, nil)
            vkFreeMemory(device, memory, nil)
            print("VulkanRenderEngine: skia node image view creation failed")
            return nil
        }

        // Start where the per-frame choreography expects a drawn image to
        // sit — Skia is told the same layout when it wraps the image.
        oneTimeSubmit { cmd in
            skiaEngineImageBarrier(
                cmd,
                image:     image,
                srcLayout: VK_IMAGE_LAYOUT_UNDEFINED,
                srcAccess: 0,
                srcStage:  VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
                dstLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                dstAccess: VkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue),
                dstStage:  VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT
            )
        }

        guard let surface = try? SkiaSurface(
            context:          context,
            vkImage:          image,
            width:            width,
            height:           height,
            format:           VK_FORMAT_R8G8B8A8_UNORM.rawValue,
            layout:           VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue,
            usageFlags:       usage,
            queueFamilyIndex: queueFamilyIndex
        ) else {
            vkDestroyImageView(device, view, nil)
            vkDestroyImage(device, image, nil)
            vkFreeMemory(device, memory, nil)
            print("VulkanRenderEngine: skia surface wrap failed")
            return nil
        }

        return (image, view, memory, surface)
    }

    /// Build a whole self-contained Skia render target: an engine-owned
    /// VkImage and a `SkiaSurface` wrapping it, packed into a node. Callers
    /// append the returned node into `nodes` themselves; this only builds it.
    public func makeSkiaWidgetNode(
        context: SkiaVulkanContext,
        width:   Int,
        height:  Int
    ) -> SkiaShaderNode<RenderNode>? {
        guard let built = makeSkiaImageAndSurface(context: context, width: width, height: height) else {
            return nil
        }
        return SkiaShaderNode(
            canvas: SkiaVulkanCanvas(
                context: context,
                surface: built.surface
            ),
            width:     UInt32(width),
            height:    UInt32(height),
            image:     built.image,
            imageView: built.view,
            memory:    built.memory
        )
    }

    /// Resize an existing Skia node **in place** — the Skia counterpart of
    /// `resizeThorNode`. Mints a fresh engine-owned VkImage + `SkiaSurface` at
    /// the new size (reusing the node's own `SkiaVulkanContext`), waits for the
    /// device to idle, then swaps the new backing into the *same*
    /// `SkiaShaderNode` so its identity — id, composite slot, z-order,
    /// Observation registration — is preserved and nothing above needs
    /// rebinding. A resize must not remake the node (that's for widget
    /// add/remove or a canvas swap). The old image/view/memory and surface are
    /// freed once the swap lands and the device is idle. Returns false — node
    /// untouched, still at the old size — on any failure, so the widget stays
    /// visible instead of going dark.
    ///
    /// `id` is the node's composite slot id: the engine caches a sampler
    /// descriptor per slot on the assumption a node's imageView never changes,
    /// so that cache is dropped here (`invalidateComposite`) to force a rebuild
    /// from the new view.
    @discardableResult
    public func resizeSkiaNode(
        _ node: SkiaShaderNode<RenderNode>,
        id:     Int,
        width:  Int,
        height: Int
    ) -> Bool {
        guard width > 0, height > 0,
              node.width != UInt32(width) || node.height != UInt32(height)
        else { return true }   // already that size — nothing to do

        // Build the new backing through the same factory the node was created
        // with, on its own context so Ganesh's device/queue stay shared. Built
        // before the old one is touched, so a failure here leaves the node
        // drawing at the old size. `fresh` is a throwaway carrier: we move its
        // image/view/memory/surface into `node` and discard it without
        // `destroyResources`, so nothing frees what we just handed over.
        guard let fresh = makeSkiaWidgetNode(
            context: node.canvas.context,
            width:   width,
            height:  height
        ), let freshSurface = fresh.canvas.surface else {
            print("VulkanRenderEngine: skia node resize backing creation failed")
            return false
        }

        // Hold the old handles; free them only after the device is idle so no
        // in-flight command buffer still samples them.
        let oldImage  = node.image
        let oldView   = node.imageView
        let oldMemory = node.memory

        vkDeviceWaitIdle(device)

        // Swap the new backing into the existing node and canvas.
        node.image         = fresh.image
        node.imageView     = fresh.imageView
        node.memory        = fresh.memory
        node.width         = UInt32(width)
        node.height        = UInt32(height)
        // makeSkiaWidgetNode leaves the fresh image in COLOR_ATTACHMENT_OPTIMAL.
        node.currentLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        node.canvas.replaceSurface(freshSurface)
        node.dirty         = true

        // Old backing: safe to free now the node points elsewhere and the
        // device is idle.
        vkDestroyImageView(device, oldView, nil)
        vkDestroyImage(device, oldImage, nil)
        if let oldMemory { vkFreeMemory(device, oldMemory, nil) }

        // Cached sampler descriptor still points at the freed view — drop it so
        // the next frame rebuilds from the new one.
        invalidateComposite(id: id)
        return true
    }

    // destroyResources moved onto the node itself — SkiaShaderNode conforms
    // to VulkanRenderNode.destroyResources(_:), which drops the surface then
    // frees image/view/memory. The engine no longer needs a per-node-kind
    // teardown method here.
}


// MARK: - Per-frame update

extension VulkanRenderEngine {

    /// The Skia counterpart of the thor update, dispatched from the
    /// engine's per-slot switch. Skia flushes its recorded drawing on the
    /// engine's own queue (submission order alone serialises it against
    /// the engine's command buffer), is told to leave the image in
    /// COLOR_ATTACHMENT_OPTIMAL, and the same barrier choreography as the
    /// thor node publishes it — optionally through the compute post
    /// shader — into SHADER_READ_ONLY for the composite pass.
    
}


// MARK: - File-private helpers

/// Layout-transition barrier — same shape as the engine core's, duplicated
/// here because that one is file-private to VulkanRenderEngine.swift.
func skiaEngineImageBarrier(
    _ cmd:     VkCommandBuffer,
    image:     VkImage,
    srcLayout: VkImageLayout,
    srcAccess: VkAccessFlags,
    srcStage:  VkPipelineStageFlagBits,
    dstLayout: VkImageLayout,
    dstAccess: VkAccessFlags,
    dstStage:  VkPipelineStageFlagBits
) {
    var barrier = VkImageMemoryBarrier()
    barrier.sType               = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
    barrier.srcAccessMask       = srcAccess
    barrier.dstAccessMask       = dstAccess
    barrier.oldLayout           = srcLayout
    barrier.newLayout           = dstLayout
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
    barrier.image               = image
    barrier.subresourceRange    = VkImageSubresourceRange(
        aspectMask:     VkImageAspectFlags(VK_IMAGE_ASPECT_COLOR_BIT.rawValue),
        baseMipLevel:   0, levelCount: 1,
        baseArrayLayer: 0, layerCount: 1
    )
    vkCmdPipelineBarrier(
        cmd,
        VkPipelineStageFlags(srcStage.rawValue),
        VkPipelineStageFlags(dstStage.rawValue),
        0, 0, nil, 0, nil, 1, &barrier
    )
}

/// Extension enumeration — duplicated from the engine core's file-private
/// helpers; used to re-derive the exact lists the engine enabled.
private func enumerateSkiaInstanceExtensions() -> Set<String> {
    var count: UInt32 = 0
    vkEnumerateInstanceExtensionProperties(nil, &count, nil)
    guard count > 0 else { return [] }
    var props = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(count))
    vkEnumerateInstanceExtensionProperties(nil, &count, &props)
    return Set(props.map(skiaExtensionName))
}

private func enumerateSkiaDeviceExtensions(_ gpu: VkPhysicalDevice) -> Set<String> {
    var count: UInt32 = 0
    vkEnumerateDeviceExtensionProperties(gpu, nil, &count, nil)
    guard count > 0 else { return [] }
    var props = [VkExtensionProperties](repeating: VkExtensionProperties(), count: Int(count))
    vkEnumerateDeviceExtensionProperties(gpu, nil, &count, &props)
    return Set(props.map(skiaExtensionName))
}

private func skiaExtensionName(_ prop: VkExtensionProperties) -> String {
    var name = prop.extensionName
    return withUnsafeBytes(of: &name) { raw in
        String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
    }
}
