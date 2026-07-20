//
//  cskia.cpp
//  CSkia — implementation of the C shim against Skia's C++ API (m132).
//
#include "cskia.h"

#include "include/core/SkCanvas.h"
#include "include/core/SkColorSpace.h"
#include "include/core/SkFont.h"
#include "include/core/SkFontMgr.h"
#include "include/core/SkFontStyle.h"
#include "include/core/SkPaint.h"
#include "include/core/SkRRect.h"
#include "include/core/SkRect.h"
#include "include/core/SkSurface.h"
#include "include/core/SkTypeface.h"
#include "include/gpu/MutableTextureState.h"
#include "include/gpu/ganesh/GrBackendSurface.h"
#include "include/gpu/ganesh/GrDirectContext.h"
#include "include/gpu/ganesh/SkSurfaceGanesh.h"
#include "include/gpu/ganesh/vk/GrVkBackendSurface.h"
#include "include/gpu/ganesh/vk/GrVkDirectContext.h"
#include "include/gpu/ganesh/vk/GrVkTypes.h"
#include "include/gpu/vk/VulkanBackendContext.h"
#include "include/gpu/vk/VulkanExtensions.h"
#include "include/gpu/vk/VulkanMutableTextureState.h"
#include "include/ports/SkFontMgr_mac_ct.h"

#include <cstring>

// Resolved at final app link from MoltenVK (linked by CVulkan). The
// bundled Vulkan headers declare the prototype unless VK_NO_PROTOTYPES
// is in effect, in which case this redeclaration stands alone.
#if defined(VK_NO_PROTOTYPES)
extern "C" PFN_vkVoidFunction vkGetInstanceProcAddr(VkInstance instance, const char* pName);
#endif

struct cskia_context_t {
    sk_sp<GrDirectContext>  gr;
    skgpu::VulkanExtensions extensions;
};

struct cskia_surface_t {
    sk_sp<SkSurface>       surface;
    GrBackendRenderTarget  renderTarget;
    // Kept so destroy() can drain the GPU work referencing the wrapped
    // image before the caller destroys that VkImage.
    sk_sp<GrDirectContext> gr;
    int32_t                width  = 0;
    int32_t                height = 0;
};

static SkCanvas* canvas_of(cskia_surface_t* s) {
    return (s && s->surface) ? s->surface->getCanvas() : nullptr;
}

static SkPaint fill_paint(float r, float g, float b, float a) {
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor4f(SkColor4f{r, g, b, a});
    return paint;
}

extern "C" {

cskia_context_t* cskia_context_create(
    void*              vk_instance,
    void*              vk_physical_device,
    void*              vk_device,
    void*              vk_queue,
    uint32_t           queue_family_index,
    const char* const* instance_extensions,
    uint32_t           instance_extension_count,
    const char* const* device_extensions,
    uint32_t           device_extension_count)
{
    VkInstance       instance       = static_cast<VkInstance>(vk_instance);
    VkPhysicalDevice physicalDevice = static_cast<VkPhysicalDevice>(vk_physical_device);
    VkDevice         device         = static_cast<VkDevice>(vk_device);
    VkQueue          queue          = static_cast<VkQueue>(vk_queue);
    if (!instance || !physicalDevice || !device || !queue) {
        return nullptr;
    }

    auto getDeviceProc = reinterpret_cast<PFN_vkGetDeviceProcAddr>(
        vkGetInstanceProcAddr(instance, "vkGetDeviceProcAddr"));
    if (!getDeviceProc) {
        return nullptr;
    }

    skgpu::VulkanGetProc getProc =
        [getDeviceProc](const char* name, VkInstance inst, VkDevice dev) -> PFN_vkVoidFunction {
            if (dev != VK_NULL_HANDLE) {
                return getDeviceProc(dev, name);
            }
            return vkGetInstanceProcAddr(inst, name);
        };

    auto* ctx = new cskia_context_t();
    ctx->extensions.init(
        getProc,
        instance,
        physicalDevice,
        instance_extension_count,
        instance_extensions,
        device_extension_count,
        device_extensions);

    skgpu::VulkanBackendContext backend;
    backend.fInstance           = instance;
    backend.fPhysicalDevice     = physicalDevice;
    backend.fDevice             = device;
    backend.fQueue              = queue;
    backend.fGraphicsQueueIndex = queue_family_index;
    // 1.1 keeps Skia off 1.2-core paths MoltenVK's portability subset may
    // not fully back; everything else it needs is extension-gated.
    backend.fMaxAPIVersion      = VK_API_VERSION_1_1;
    backend.fVkExtensions       = &ctx->extensions;
    backend.fGetProc            = getProc;
    // No fDeviceFeatures/fDeviceFeatures2 on purpose: the engine creates
    // its VkDevice with no enabled features, and null-null means exactly
    // "assume no features are enabled".

    ctx->gr = GrDirectContexts::MakeVulkan(backend);
    if (!ctx->gr) {
        delete ctx;
        return nullptr;
    }
    fprintf(stderr, "cskia: context created — colorTypeSupportedAsSurface(RGBA_8888)=%d "
                    "maxSurfaceSampleCount(RGBA_8888)=%d defaultBackendFormat(RGBA_8888,renderable).isValid=%d\n",
            ctx->gr->colorTypeSupportedAsSurface(kRGBA_8888_SkColorType),
            ctx->gr->maxSurfaceSampleCountForColorType(kRGBA_8888_SkColorType),
            ctx->gr->defaultBackendFormat(kRGBA_8888_SkColorType, GrRenderable::kYes).isValid());
    return ctx;
}

void cskia_context_destroy(cskia_context_t* ctx) {
    if (!ctx) {
        return;
    }
    if (ctx->gr) {
        ctx->gr->flushAndSubmit(GrSyncCpu::kYes);
        ctx->gr->releaseResourcesAndAbandonContext();
    }
    delete ctx;
}

cskia_surface_t* cskia_surface_wrap_vk_image(
    cskia_context_t* ctx,
    void*            vk_image,
    int32_t          width,
    int32_t          height,
    uint32_t         vk_format,
    uint32_t         vk_image_layout,
    uint32_t         vk_usage_flags,
    uint32_t         vk_queue_family_index)
{
    if (!ctx || !ctx->gr || !vk_image || width <= 0 || height <= 0) {
        return nullptr;
    }

    GrVkImageInfo info;
    info.fImage              = static_cast<VkImage>(vk_image);
    info.fImageTiling        = VK_IMAGE_TILING_OPTIMAL;
    info.fImageLayout        = static_cast<VkImageLayout>(vk_image_layout);
    info.fFormat             = static_cast<VkFormat>(vk_format);
    info.fImageUsageFlags    = vk_usage_flags;
    info.fSampleCount        = 1;
    info.fLevelCount         = 1;
    // VK_QUEUE_FAMILY_IGNORED is only valid alongside VK_SHARING_MODE_CONCURRENT —
    // for EXCLUSIVE (what the engine creates this image with), Ganesh needs the
    // real owning queue family to reason about ownership-transfer barriers, and
    // silently rejects the wrap otherwise.
    info.fCurrentQueueFamily = vk_queue_family_index;
    info.fSharingMode        = VK_SHARING_MODE_EXCLUSIVE;

    SkColorType colorType;
    switch (info.fFormat) {
        case VK_FORMAT_R8G8B8A8_UNORM: colorType = kRGBA_8888_SkColorType; break;
        case VK_FORMAT_B8G8R8A8_UNORM: colorType = kBGRA_8888_SkColorType; break;
        default:
            fprintf(stderr, "cskia: wrap_vk_image: unsupported VkFormat %d\n", (int)info.fFormat);
            return nullptr;
    }

    auto* wrapper = new cskia_surface_t();
    wrapper->renderTarget = GrBackendRenderTargets::MakeVk(width, height, info);

    GrBackendFormat rtFormat = wrapper->renderTarget.getBackendFormat();
    VkFormat extractedFormat = VK_FORMAT_UNDEFINED;
    bool gotFormat = GrBackendFormats::AsVkFormat(rtFormat, &extractedFormat);
    fprintf(stderr, "cskia: wrap_vk_image: rt.sampleCnt=%d rtFormat.isValid=%d "
                    "AsVkFormat.ok=%d extractedFormat=%d (expected %d)\n",
            wrapper->renderTarget.sampleCnt(), rtFormat.isValid(), gotFormat,
            (int)extractedFormat, (int)info.fFormat);

    fprintf(stderr, "cskia: wrap_vk_image: gr=%p renderTarget.isValid=%d width=%d height=%d usage=0x%x layout=%d\n",
            (void*)ctx->gr.get(), wrapper->renderTarget.isValid(), width, height,
            (unsigned)vk_usage_flags, (int)vk_image_layout);

    SkSurfaceProps props;
    wrapper->surface = SkSurfaces::WrapBackendRenderTarget(
        ctx->gr.get(),
        wrapper->renderTarget,
        kTopLeft_GrSurfaceOrigin,
        colorType,
        nullptr,
        &props);
    if (!wrapper->surface) {
        fprintf(stderr, "cskia: wrap_vk_image: SkSurfaces::WrapBackendRenderTarget returned null\n");
        delete wrapper;
        return nullptr;
    }
    wrapper->gr     = ctx->gr;
    wrapper->width  = width;
    wrapper->height = height;
    return wrapper;
}

void cskia_surface_destroy(cskia_surface_t* surface) {
    if (!surface) {
        return;
    }
    sk_sp<GrDirectContext> gr = surface->gr;
    surface->surface.reset();
    if (gr) {
        // The wrapped image's internal views/framebuffers die with the
        // surface's last GPU reference — force that reference count down
        // now so the caller may destroy the VkImage right after.
        gr->flushAndSubmit(GrSyncCpu::kYes);
        gr->performDeferredCleanup(std::chrono::milliseconds(0));
    }
    delete surface;
}

void* cskia_surface_sk_surface(cskia_surface_t* surface) {
    return (surface && surface->surface) ? surface->surface.get() : nullptr;
}

void* cskia_surface_sk_canvas(cskia_surface_t* surface) {
    return canvas_of(surface);
}

void cskia_surface_notify_layout(
    cskia_surface_t* surface,
    uint32_t         vk_image_layout)
{
    if (!surface) {
        return;
    }
    GrBackendRenderTargets::SetVkImageLayout(
        &surface->renderTarget,
        static_cast<VkImageLayout>(vk_image_layout));
}

bool cskia_context_flush(
    cskia_context_t* ctx,
    cskia_surface_t* surface,
    uint32_t         final_layout,
    bool             sync_cpu)
{
    if (!ctx || !ctx->gr || !surface || !surface->surface) {
        return false;
    }
    skgpu::MutableTextureState newState = skgpu::MutableTextureStates::MakeVulkan(
        static_cast<VkImageLayout>(final_layout),
        VK_QUEUE_FAMILY_IGNORED);
    ctx->gr->flush(surface->surface.get(), GrFlushInfo(), &newState);
    return ctx->gr->submit(sync_cpu ? GrSyncCpu::kYes : GrSyncCpu::kNo);
}

// MARK: - Basic draw

void cskia_canvas_clear(
    cskia_surface_t* surface,
    float r, float g, float b, float a)
{
    if (SkCanvas* canvas = canvas_of(surface)) {
        canvas->clear(SkColor4f{r, g, b, a});
    }
}

void cskia_canvas_draw_rect(
    cskia_surface_t* surface,
    float x, float y, float w, float h,
    float r, float g, float b, float a)
{
    if (SkCanvas* canvas = canvas_of(surface)) {
        canvas->drawRect(SkRect::MakeXYWH(x, y, w, h), fill_paint(r, g, b, a));
    }
}

void cskia_canvas_draw_round_rect(
    cskia_surface_t* surface,
    float x, float y, float w, float h,
    float radius,
    float r, float g, float b, float a)
{
    if (SkCanvas* canvas = canvas_of(surface)) {
        canvas->drawRRect(
            SkRRect::MakeRectXY(SkRect::MakeXYWH(x, y, w, h), radius, radius),
            fill_paint(r, g, b, a));
    }
}

void cskia_canvas_draw_circle(
    cskia_surface_t* surface,
    float cx, float cy, float radius,
    float r, float g, float b, float a)
{
    if (SkCanvas* canvas = canvas_of(surface)) {
        canvas->drawCircle(cx, cy, radius, fill_paint(r, g, b, a));
    }
}

void cskia_canvas_draw_line(
    cskia_surface_t* surface,
    float x0, float y0, float x1, float y1,
    float stroke_width,
    float r, float g, float b, float a)
{
    if (SkCanvas* canvas = canvas_of(surface)) {
        SkPaint paint = fill_paint(r, g, b, a);
        paint.setStroke(true);
        paint.setStrokeWidth(stroke_width);
        canvas->drawLine(x0, y0, x1, y1, paint);
    }
}

// MARK: - Text

static sk_sp<SkTypeface> default_typeface() {
    static sk_sp<SkTypeface> typeface = [] {
        sk_sp<SkFontMgr> mgr = SkFontMgr_New_CoreText(nullptr);
        if (!mgr) {
            return sk_sp<SkTypeface>();
        }
        sk_sp<SkTypeface> match = mgr->matchFamilyStyle(nullptr, SkFontStyle());
        if (!match) {
            match = mgr->legacyMakeTypeface(nullptr, SkFontStyle());
        }
        return match;
    }();
    return typeface;
}

void cskia_canvas_draw_text(
    cskia_surface_t* surface,
    const char*      utf8,
    float x, float y,
    float size,
    float r, float g, float b, float a)
{
    SkCanvas* canvas = canvas_of(surface);
    if (!canvas || !utf8) {
        return;
    }
    sk_sp<SkTypeface> typeface = default_typeface();
    if (!typeface) {
        return;
    }
    SkFont font(typeface, size);
    font.setEdging(SkFont::Edging::kAntiAlias);
    font.setSubpixel(true);
    canvas->drawString(utf8, x, y, font, fill_paint(r, g, b, a));
}

float cskia_text_width(
    const char* utf8,
    float       size)
{
    if (!utf8) {
        return 0.0f;
    }
    sk_sp<SkTypeface> typeface = default_typeface();
    if (!typeface) {
        return 0.0f;
    }
    SkFont font(typeface, size);
    return font.measureText(utf8, std::strlen(utf8), SkTextEncoding::kUTF8);
}

} // extern "C"
