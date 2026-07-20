//
//  VulkanSkiaRenderNode.swift
//  NucleantSkia
//
import NucleantVulkan


public protocol VulkanSkiaRenderNode: VulkanRenderNode {
    associatedtype CanvasSurface: SkiaGPUCanvas
    var canvas: CanvasSurface { get }
    var width:  UInt32        { get }
    var height: UInt32        { get }
}
