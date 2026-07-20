//
//  SkiaSurface.swift
//  SkiaCore
//
import CSkia


/// One Skia GPU surface wrapping a caller-owned VkImage — wraps the raw
/// `cskia_surface_t` handle. A class, not a struct: one live render
/// target, identity never value-copied.
///
/// Destroy order matters: `destroy()` (or deinit) must run before the
/// wrapped VkImage is destroyed — Skia holds views onto it. The context
/// is retained so the surface can never outlive it.
public final class SkiaSurface {

    public private(set) var base: OpaquePointer?

    public let width:  Int
    public let height: Int

    /// Keeps the Ganesh context alive at least as long as the surface —
    /// releasing a surface schedules GPU teardown on its context.
    public let context: SkiaVulkanContext

    /// Wrap `vkImage` (borrowed, never owned). `format`, `layout` and
    /// `usageFlags` are the raw Vulkan enum/flag values of the image as
    /// it exists right now — they must match its creation exactly.
    /// `queueFamilyIndex` must be the queue family that owns the image
    /// (VK_SHARING_MODE_EXCLUSIVE only; Ganesh rejects VK_QUEUE_FAMILY_IGNORED
    /// there since that value is only meaningful under CONCURRENT sharing).
    public init(
        context:          SkiaVulkanContext,
        vkImage:          OpaquePointer,
        width:            Int,
        height:           Int,
        format:           UInt32,
        layout:           UInt32,
        usageFlags:       UInt32,
        queueFamilyIndex: UInt32
    ) throws {
        guard let created = cskia_surface_wrap_vk_image(
            context.base,
            UnsafeMutableRawPointer(vkImage),
            Int32(width),
            Int32(height),
            format,
            layout,
            usageFlags,
            queueFamilyIndex
        ) else {
            throw SkiaCoreError.surfaceCreationFailed
        }
        self.context = context
        self.base    = created
        self.width   = width
        self.height  = height
    }

    deinit {
        destroy()
    }

    /// Release the Skia side now (idempotent) — drains the GPU work that
    /// references the wrapped image, so the VkImage may be destroyed
    /// right after this returns.
    public func destroy() {
        guard let base else { return }
        cskia_surface_destroy(base)
        self.base = nil
    }

    /// The raw `SkSurface*` — this is what a PyCapsule carries over to
    /// skia-python. Borrowed pointer, no reference transferred; nil once
    /// destroyed.
    public func skSurfacePointer() -> UnsafeMutableRawPointer? {
        guard let base else { return nil }
        return cskia_surface_sk_surface(base)
    }

    /// The surface's raw `SkCanvas*` — same borrowing rules.
    public func skCanvasPointer() -> UnsafeMutableRawPointer? {
        guard let base else { return nil }
        return cskia_surface_sk_canvas(base)
    }

    /// Tell Skia the image's layout was changed externally (the engine's
    /// barriers move it every frame). Must precede the next `flush`, or
    /// Skia records its transition from a stale layout.
    public func notifyLayout(_ vkImageLayout: UInt32) {
        guard let base else { return }
        cskia_surface_notify_layout(
            base,
            vkImageLayout
        )
    }

    /// Flush all recorded drawing, leave the image in `finalLayout`, and
    /// submit to the queue. `syncCpu` blocks until the GPU finished.
    @discardableResult
    public func flush(
        finalLayout: UInt32,
        syncCpu:     Bool = false
    ) -> Bool {
        guard let base else { return false }
        return cskia_context_flush(
            context.base,
            base,
            finalLayout,
            syncCpu
        )
    }

    // MARK: - Basic draw

    public func clear(
        r: Float,
        g: Float,
        b: Float,
        a: Float
    ) {
        guard let base else { return }
        cskia_canvas_clear(base, r, g, b, a)
    }

    public func drawRect(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        r: Float,
        g: Float,
        b: Float,
        a: Float
    ) {
        guard let base else { return }
        cskia_canvas_draw_rect(base, x, y, width, height, r, g, b, a)
    }

    public func drawRoundRect(
        x: Float,
        y: Float,
        width: Float,
        height: Float,
        radius: Float,
        r: Float,
        g: Float,
        b: Float,
        a: Float
    ) {
        guard let base else { return }
        cskia_canvas_draw_round_rect(base, x, y, width, height, radius, r, g, b, a)
    }

    public func drawCircle(
        cx: Float,
        cy: Float,
        radius: Float,
        r: Float,
        g: Float,
        b: Float,
        a: Float
    ) {
        guard let base else { return }
        cskia_canvas_draw_circle(base, cx, cy, radius, r, g, b, a)
    }

    public func drawLine(
        x0: Float,
        y0: Float,
        x1: Float,
        y1: Float,
        strokeWidth: Float,
        r: Float,
        g: Float,
        b: Float,
        a: Float
    ) {
        guard let base else { return }
        cskia_canvas_draw_line(base, x0, y0, x1, y1, strokeWidth, r, g, b, a)
    }

    // MARK: - Text

    public func drawText(
        _ text: String,
        x: Float,
        y: Float,
        size: Float,
        r: Float,
        g: Float,
        b: Float,
        a: Float
    ) {
        guard let base else { return }
        text.withCString { utf8 in
            cskia_canvas_draw_text(base, utf8, x, y, size, r, g, b, a)
        }
    }
}


/// Advance width of `text` at `size` with the default (CoreText) typeface
/// — context-free, usable for layout before any surface exists.
public func skiaTextWidth(
    _ text: String,
    size: Float
) -> Float {
    text.withCString { utf8 in
        cskia_text_width(utf8, size)
    }
}
