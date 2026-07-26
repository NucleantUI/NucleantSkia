//
//  VulkanSkiaRenderNode.swift
//  NucleantSkia
//
import NucleantVulkan


public protocol VulkanSkiaRenderNode: VulkanRenderNode {
    associatedtype CanvasSurface: SkiaGPUCanvas
    var canvas: CanvasSurface { get }
    // width/height are inherited from VulkanRenderNode as `{ get set }` — the
    // engine resizes a node's backing in place (see `resizeSkiaNode`), so
    // re-declaring them read-only here would illegally narrow that requirement.
}
