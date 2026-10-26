//
//  SkiaTestSupport.swift
//  NucleantSkiaTests
//
//  What the GPU suites share — SkiaWebGPUTests (the browser) and
//  SkiaWin32Tests (Windows): a composite slot for one Skia node, and pixel
//  checks on what was read back.
//
#if os(WASI) || os(Windows)
import Testing
import Observation
import CVulkan
import NucleantVulkan
@testable import NucleantSkia

func pixel(_ pixels: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> [UInt8] {
    let i = (y * width + x) * 4
    return Array(pixels[i..<i + 4])
}

func expectPixel(
    _ pixels: [UInt8], _ width: Int, _ x: Int, _ y: Int, _ expected: [UInt8], sourceLocation: SourceLocation = #_sourceLocation
) {
    let actual = pixel(pixels, width, x, y)
    let close = zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 1 }
    #expect(close, "pixel \(x),\(y): \(actual), expected \(expected)", sourceLocation: sourceLocation)
}

/// The smallest composite slot the engine can drive: one Skia node.
@Observable
final class SkiaSlot: RenderContainerNode, @unchecked Sendable {
    enum Context: RenderNodeContext {
        case skia(SkiaShaderNode<SkiaSlot>)
    }

    let id: Int
    let context: Context
    var needsRender = true

    init(id: Int, context: Context) {
        self.id = id
        self.context = context
    }

    func observeContext() {
        if case .skia(let node) = context { observe(node) }
    }

    func update(engine: Engine, cmd: VkCommandBuffer) {
        if case .skia(let node) = context { node.update(engine, slot: self, cmd: cmd) }
    }

    func destroyResources(engine: Engine) {
        if case .skia(let node) = context { node.destroyResources(engine) }
    }

    func getImageView() -> VkImageView? {
        if case .skia(let node) = context { return node.imageView }
        return nil
    }
}
#endif
