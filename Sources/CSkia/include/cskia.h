//
//  cskia.h
//  CSkia — plain-C surface over Skia's Ganesh Vulkan backend.
//
//  Only what SkiaCanvasBase needs: a GrDirectContext on the engine's
//  existing VkDevice/VkQueue, an SkSurface wrapping an engine-owned
//  VkImage, per-frame flush with an explicit final image layout, plus a
//  handful of draw/text calls for the Swift side. Python does its real
//  drawing through skia-python on the raw SkSurface* this hands out.
//

#ifndef CSKIA_H
#define CSKIA_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct cskia_context_t cskia_context_t;
typedef struct cskia_surface_t cskia_surface_t;

// MARK: - Context

/// Build a Ganesh Vulkan context over Vulkan objects the caller owns.
/// Entry points are resolved through vkGetInstanceProcAddr (MoltenVK,
/// linked into the host app) — no Vulkan library is linked here.
///
/// The extension lists must name exactly what the caller enabled when
/// creating the instance/device (VK_KHR_portability_subset especially:
/// Skia's caps checks read it to stay inside MoltenVK's feature set).
/// Returns NULL on failure.
cskia_context_t* cskia_context_create(
    void*              vk_instance,
    void*              vk_physical_device,
    void*              vk_device,
    void*              vk_queue,
    uint32_t           queue_family_index,
    const char* const* instance_extensions,
    uint32_t           instance_extension_count,
    const char* const* device_extensions,
    uint32_t           device_extension_count);

/// Flush + sync outstanding GPU work, then drop the context. Call while
/// the VkDevice is still alive.
void cskia_context_destroy(cskia_context_t* ctx);

// MARK: - Surface

/// Wrap an existing VkImage as a render-target SkSurface. The image is
/// borrowed, never owned — destroy order is: surface first, VkImage after.
/// `vk_format` supports VK_FORMAT_R8G8B8A8_UNORM / VK_FORMAT_B8G8R8A8_UNORM.
/// `vk_image_layout` is the layout the image is in right now;
/// `vk_usage_flags` must match the flags the image was created with.
/// Returns NULL on failure.
cskia_surface_t* cskia_surface_wrap_vk_image(
    cskia_context_t* ctx,
    void*            vk_image,
    int32_t          width,
    int32_t          height,
    uint32_t         vk_format,
    uint32_t         vk_image_layout,
    uint32_t         vk_usage_flags,
    uint32_t         vk_queue_family_index);

/// Release the SkSurface and force the context to finish + free its GPU
/// work for it. Call before destroying the wrapped VkImage.
void cskia_surface_destroy(cskia_surface_t* surface);

/// The raw SkSurface* behind this handle — what a PyCapsule carries over
/// to skia-python. Borrowed pointer, no ref transferred.
void* cskia_surface_sk_surface(cskia_surface_t* surface);

/// The surface's SkCanvas* — same borrowing rules.
void* cskia_surface_sk_canvas(cskia_surface_t* surface);

/// Tell Skia the image's layout changed behind its back (the engine's
/// own barriers move it every frame). Must be called before the next
/// flush or Skia records transitions from a stale layout.
void cskia_surface_notify_layout(
    cskia_surface_t* surface,
    uint32_t         vk_image_layout);

/// Flush all recorded drawing, transition the image to `final_layout`,
/// and submit to the queue. `sync_cpu` blocks until the GPU finished.
bool cskia_context_flush(
    cskia_context_t* ctx,
    cskia_surface_t* surface,
    uint32_t         final_layout,
    bool             sync_cpu);

// MARK: - Basic draw (Swift-side content + smoke tests)

void cskia_canvas_clear(
    cskia_surface_t* surface,
    float r, float g, float b, float a);

void cskia_canvas_draw_rect(
    cskia_surface_t* surface,
    float x, float y, float w, float h,
    float r, float g, float b, float a);

void cskia_canvas_draw_round_rect(
    cskia_surface_t* surface,
    float x, float y, float w, float h,
    float radius,
    float r, float g, float b, float a);

void cskia_canvas_draw_circle(
    cskia_surface_t* surface,
    float cx, float cy, float radius,
    float r, float g, float b, float a);

void cskia_canvas_draw_line(
    cskia_surface_t* surface,
    float x0, float y0, float x1, float y1,
    float stroke_width,
    float r, float g, float b, float a);

// MARK: - Text (CoreText font manager, default typeface)

void cskia_canvas_draw_text(
    cskia_surface_t* surface,
    const char*      utf8,
    float x, float y,
    float size,
    float r, float g, float b, float a);

/// Advance width of `utf8` at `size` with the default typeface.
float cskia_text_width(
    const char* utf8,
    float       size);

#ifdef __cplusplus
}
#endif

#endif /* CSKIA_H */
