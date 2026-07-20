//
//  SkiaShaderNode.swift
//  PyNucleantUI
//
import NucleantVulkan
import CVulkan
import Observation


/// The Skia counterpart of `ThorShaderNode`: a Ganesh Vulkan surface
/// rendering into an engine-owned VkImage, plus the optional compute
/// shader post-process every node kind carries. Conforms to
/// `VulkanSkiaRenderNode`, so it is the concrete payload of
/// `RenderNode.Context.skia`.
///
/// Unlike the thor node there is no external backing: Skia records and
/// submits on the engine's own VkDevice/VkQueue, straight into this
/// image — no Metal import, no cross-queue wait.
///
/// `@Observable` for the same reason as the thor node: the owning
/// `RenderNode` slot tracks the mutable render-affecting state (`dirty`,
/// the compute trio) and flips `needsRender` on its own.
@Observable
public final class SkiaShaderNode: VulkanSkiaRenderNode {

    public var canvas: SkiaVulkanCanvas
    public let width:  UInt32
    public let height: UInt32

    public let image:                VkImage
    public let imageView:            VkImageView
    /// The allocation backing `image` — same contract as the thor node:
    /// the engine binds but never frees it on its own; whoever tears the
    /// node down (resize, detach) goes through `destroyResources(of:)`.
    public let memory:               VkDeviceMemory?
    public var computePipeline:      VkPipeline?
    public var computeLayout:        VkPipelineLayout?
    public var computeDescriptorSet: VkDescriptorSet?
    public var dirty:                Bool = true

    /// Always true here: the image is engine-created with STORAGE usage,
    /// so a canvas post shader may bind it as its compute output.
    public let storageCapable: Bool

    /// The image's actual current Vulkan-tracked layout, updated after
    /// every barrier the engine records — and mirrored into Skia via
    /// `notifyLayout` before each flush, so Skia never records a
    /// transition from a stale layout.
    var currentLayout: VkImageLayout

    public init(
        canvas:               SkiaVulkanCanvas,
        width:                UInt32,
        height:               UInt32,
        image:                VkImage,
        imageView:            VkImageView,
        memory:               VkDeviceMemory?   = nil,
        storageCapable:       Bool              = true,
        computePipeline:      VkPipeline?       = nil,
        computeLayout:        VkPipelineLayout? = nil,
        computeDescriptorSet: VkDescriptorSet?  = nil
    ) {
        self.canvas               = canvas
        self.width                = width
        self.height               = height
        self.image                = image
        self.imageView            = imageView
        self.memory               = memory
        self.storageCapable       = storageCapable
        self.currentLayout        = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        self.computePipeline      = computePipeline
        self.computeLayout        = computeLayout
        self.computeDescriptorSet = computeDescriptorSet
    }
}
