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
public final class SkiaShaderNode<ContainerNode: RenderContainerNode>: VulkanSkiaRenderNode {
    
    public typealias Engine = VulkanRenderEngine<ContainerNode>
    
    public var canvas: SkiaVulkanCanvas
    public var width:  UInt32
    public var height: UInt32
    
    public var image:                VkImage
    public var imageView:            VkImageView
    /// The allocation backing `image` — same contract as the thor node:
    /// the engine binds but never frees it on its own; whoever tears the
    /// node down (resize, detach) goes through `destroyResources(of:)`.
    public var memory:               VkDeviceMemory?
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

extension SkiaShaderNode {
    public func update(_ engine: Engine, slot: ContainerNode, cmd: VkCommandBuffer) {
        let id = slot.id
        guard slot.needsRender else { return }
        guard let surface = canvas.surface else { return }
        
        // The engine's barriers moved the image since Skia's last flush —
        // hand Skia the layout the image is *really* in, then flush with
        // an explicit final state matching what the barrier below assumes.
        surface.notifyLayout(currentLayout.rawValue)
        let flushed = surface.flush(
            finalLayout: VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL.rawValue,
            syncCpu:     false
        )
        guard flushed else {
            if engine.warnedFailedNodes.insert(id).inserted {
                print("VulkanRenderEngine: skia node \(id) flush/submit failed — logged once")
            }
            return
        }
        engine.warnedFailedNodes.remove(id)
        
        let priorLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
        let priorAccess = VkAccessFlags(VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT.rawValue)
        
        if let pipeline = computePipeline,
           let layout   = computeLayout,
           let ds       = computeDescriptorSet {
            
            skiaEngineImageBarrier(
                cmd,
                image:     image,
                srcLayout: priorLayout,
                srcAccess: priorAccess,
                srcStage:  VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dstLayout: VK_IMAGE_LAYOUT_GENERAL,
                dstAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue) | VkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT.rawValue),
                dstStage:  VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT
            )
            vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline)
            var descSet: VkDescriptorSet? = ds
            vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, &descSet, 0, nil)
            vkCmdDispatch(cmd, (width + 7) / 8, (height + 7) / 8, 1)
            skiaEngineImageBarrier(
                cmd,
                image:     image,
                srcLayout: VK_IMAGE_LAYOUT_GENERAL,
                srcAccess: VkAccessFlags(VK_ACCESS_SHADER_WRITE_BIT.rawValue),
                srcStage:  VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,
                dstLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                dstAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
                dstStage:  VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
            )
        } else {
            skiaEngineImageBarrier(
                cmd,
                image:     image,
                srcLayout: priorLayout,
                srcAccess: priorAccess,
                srcStage:  VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                dstLayout: VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                dstAccess: VkAccessFlags(VK_ACCESS_SHADER_READ_BIT.rawValue),
                dstStage:  VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT
            )
        }
        currentLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        engine.readable.insert(id)
        // slot.needsRender deliberately not cleared — same steady-state as
        // the other node updates until the canvas side drives updates
        // through the Observation chain.
    }

    /// Free the GPU resources this node owns after draining the device —
    /// the Skia surface first, since it holds Ganesh's views onto the
    /// image, then the image/view/memory.
    public func destroyResources(_ engine: Engine) {
        vkDeviceWaitIdle(engine.device)
        canvas.dropSurface()
        vkDestroyImageView(engine.device, imageView, nil)
        vkDestroyImage(engine.device, image, nil)
        if let memory {
            vkFreeMemory(engine.device, memory, nil)
        }
    }
}
