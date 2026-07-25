//
//  SkiaVulkanCanvas.swift
//  PyNucleantUI
//


/// Concrete Skia GPU canvas — pairs the Ganesh Vulkan context with the
/// surface wrapping one render node's VkImage. A class, not a struct:
/// this is a reference to one live Skia render target; its lifetime and
/// identity must never be duplicated by value-copy. Mirrors
/// `ThorVulkanCanvas`'s role for `ThorShaderNode`.
public final class SkiaVulkanCanvas: SkiaGPUCanvas {

    public let context: SkiaVulkanContext

    /// nil after `dropSurface()` — the node is then no longer drawable
    /// and the engine's update skips it.
    public private(set) var surface: SkiaSurface?

    public init(
        context: SkiaVulkanContext,
        surface: SkiaSurface
    ) {
        self.context = context
        self.surface = surface
    }

    /// Drop the Skia side of the render target ahead of the VkImage's
    /// destruction — Skia holds views onto the image, and those must die
    /// first. Safe to call twice.
    public func dropSurface() {
        surface?.destroy()
        surface = nil
    }

    /// Swap in a freshly-built surface (an in-place resize): the outgoing
    /// surface holds Ganesh's views onto the old image, so it's destroyed
    /// first — the caller frees that image only afterwards. Same context, new
    /// target; the node keeps its identity.
    public func replaceSurface(_ newSurface: SkiaSurface) {
        surface?.destroy()
        surface = newSurface
    }
}
