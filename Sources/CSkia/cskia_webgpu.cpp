//
//  cskia_webgpu.cpp
//  CSkia — cskia.h in the browser: Skia's Graphite on the page's WebGPU.
//
//  Every other platform implements cskia.h with Ganesh on Vulkan
//  (cskia.cpp). In the browser, Vulkan is NucleantVulkan's own
//  implementation on WebGPU, and Skia's backend for WebGPU is Graphite's
//  Dawn one — built against webgpu.h, which CWgpu (NucleantVulkan)
//  implements on that same GPUDevice. So the context is Graphite on the
//  page's device, and a surface wraps the WebGPU texture the engine's VkImage
//  is (vkExportWebGPUObjectsNUCLEANT): Skia draws into the image itself, no
//  copy, and what it submits reaches the one GPUQueue ahead of the engine's
//  frame.
//
//  WebGPU has no image layouts, so there is nothing for notify_layout to
//  record, and a flush's final layout is already the case. Graphite runs
//  here as a "non-yielding" context (no tick: the module cannot spin while
//  the page settles a promise), so a flush never waits for the GPU — the
//  queue orders the work, which is all the engine's frame needs.
//
#if defined(__wasm__)

// Dawn's webgpu.h first: Skia was built against it (scripts/build_skia_wasm.py)
// and it shares its include guard with CWgpu's, which this target also sees
// through NucleantVulkan. The two agree on everything Skia calls.
#include "dawn/webgpu.h"
#include "webgpu/webgpu_cpp.h"

// CVulkan: VkDevice, VkImage and VK_NUCLEANT_webgpu_objects.
#include "shim.h"

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
#include "include/gpu/graphite/BackendTexture.h"
#include "include/gpu/graphite/Context.h"
#include "include/gpu/graphite/ContextOptions.h"
#include "include/gpu/graphite/GraphiteTypes.h"
#include "include/gpu/graphite/Image.h"
#include "include/gpu/graphite/ImageProvider.h"
#include "include/gpu/graphite/Recorder.h"
#include "include/gpu/graphite/Recording.h"
#include "include/gpu/graphite/Surface.h"
#include "include/gpu/graphite/dawn/DawnBackendContext.h"
#include "include/gpu/graphite/dawn/DawnGraphiteTypes.h"
#include "include/ports/SkFontMgr_empty.h"

#include <cstdio>
#include <cstring>
#include <list>
#include <memory>
#include <unordered_map>
#include <utility>

namespace graphite = skgpu::graphite;

struct cskia_context_t {
    VkDevice                             device = VK_NULL_HANDLE;
    wgpu::Queue                          queue;
    std::unique_ptr<graphite::Context>   context;
    std::unique_ptr<graphite::Recorder>  recorder;
};

struct cskia_surface_t {
    sk_sp<SkSurface>  surface;
    cskia_context_t*  ctx    = nullptr;
    int32_t           width  = 0;
    int32_t           height = 0;
};

// MARK: - The page's adapter, and Dawn's two own calls

// The instance, adapter and device are the page's (CWgpu answers every
// request with them, before the call returns).
static WGPUInstance page_instance;
static WGPUAdapter  page_adapter;

extern "C" {

// Graphite calls these two Dawn additions to webgpu.h; CWgpu implements the
// standard header only, so here they are on its calls.
WGPUAdapter wgpuDeviceGetAdapter(WGPUDevice device) {
    (void)device;
    if (page_adapter) {
        wgpuAdapterAddRef(page_adapter);
    }
    return page_adapter;
}

void wgpuDeviceTick(WGPUDevice device) {
    (void)device;
    wgpuInstanceProcessEvents(page_instance);
}

}  // extern "C"

static bool acquire_page_device(WGPUDevice* out) {
    if (!page_instance) {
        page_instance = wgpuCreateInstance(nullptr);
    }
    if (!page_adapter && page_instance) {
        WGPURequestAdapterCallbackInfo info = {};
        info.mode = WGPUCallbackMode_AllowSpontaneous;
        info.callback = [](WGPURequestAdapterStatus status, WGPUAdapter adapter, WGPUStringView, void* userdata, void*) {
            if (status == WGPURequestAdapterStatus_Success) {
                *static_cast<WGPUAdapter*>(userdata) = adapter;
            }
        };
        info.userdata1 = &page_adapter;
        wgpuInstanceRequestAdapter(page_instance, nullptr, info);
    }
    if (!page_adapter) {
        return false;
    }
    WGPUDevice device = nullptr;
    WGPURequestDeviceCallbackInfo info = {};
    info.mode = WGPUCallbackMode_AllowSpontaneous;
    info.callback = [](WGPURequestDeviceStatus status, WGPUDevice device, WGPUStringView, void* userdata, void*) {
        if (status == WGPURequestDeviceStatus_Success) {
            *static_cast<WGPUDevice*>(userdata) = device;
        }
    };
    info.userdata1 = &device;
    wgpuAdapterRequestDevice(page_adapter, nullptr, info);
    *out = device;
    return device != nullptr;
}

// MARK: - Images

/// Raster images drawn on a Graphite canvas become textures here: Graphite
/// draws only images already on the GPU, where Ganesh (cskia.cpp) uploads a
/// raster image itself. One upload per image — its unique ID, so a changed
/// image is a new one — keeping the most recently drawn kCapacity.
class UploadingImageProvider final : public graphite::ImageProvider {
public:
    sk_sp<SkImage> findOrCreate(graphite::Recorder* recorder,
                                const SkImage* image,
                                SkImage::RequiredProperties required) override {
        // A mipmapped upload serves either request.
        if (sk_sp<SkImage> found = this->find(key(image, true))) {
            return found;
        }
        if (!required.fMipmapped) {
            if (sk_sp<SkImage> found = this->find(key(image, false))) {
                return found;
            }
        }
        sk_sp<SkImage> made = SkImages::TextureFromImage(recorder, image, required);
        if (made) {
            this->insert(key(image, required.fMipmapped), made);
        }
        return made;
    }

private:
    static constexpr size_t kCapacity = 256;
    using Key = uint64_t;
    using Entry = std::pair<Key, sk_sp<SkImage>>;

    static Key key(const SkImage* image, bool mipmapped) {
        return (static_cast<uint64_t>(image->uniqueID()) << 1) | (mipmapped ? 1 : 0);
    }

    sk_sp<SkImage> find(Key key) {
        auto found = fIndex.find(key);
        if (found == fIndex.end()) {
            return nullptr;
        }
        fOrder.splice(fOrder.begin(), fOrder, found->second);
        return found->second->second;
    }

    void insert(Key key, sk_sp<SkImage> image) {
        fOrder.emplace_front(key, std::move(image));
        fIndex[key] = fOrder.begin();
        if (fOrder.size() > kCapacity) {
            fIndex.erase(fOrder.back().first);
            fOrder.pop_back();
        }
    }

    std::list<Entry> fOrder;  // most recently drawn first
    std::unordered_map<Key, std::list<Entry>::iterator> fIndex;
};

// MARK: - Helpers

static SkCanvas* canvas_of(cskia_surface_t* s) {
    return (s && s->surface) ? s->surface->getCanvas() : nullptr;
}

static SkPaint fill_paint(float r, float g, float b, float a) {
    SkPaint paint;
    paint.setAntiAlias(true);
    paint.setColor4f(SkColor4f{r, g, b, a});
    return paint;
}

/// Snaps what the recorder holds and submits it, without waiting.
static bool submit_recording(cskia_context_t* ctx) {
    std::unique_ptr<graphite::Recording> recording = ctx->recorder->snap();
    if (recording) {
        graphite::InsertRecordingInfo info;
        info.fRecording = recording.get();
        if (ctx->context->insertRecording(info) != graphite::InsertStatus::kSuccess) {
            return false;
        }
    }
    return ctx->context->submit(graphite::SyncToCpu::kNo);
}

/// Waits until the GPU has finished everything Graphite submitted, which a
/// non-yielding Context must have done before it is destroyed. The wait is
/// webgpu.h's WaitAny, which blocks only where the page can (JSPI); false
/// where it cannot.
static bool wait_for_gpu(cskia_context_t* ctx) {
    while (ctx->context->hasUnfinishedGpuWork()) {
        WGPUQueueWorkDoneCallbackInfo done = {};
        done.mode = WGPUCallbackMode_WaitAnyOnly;
        WGPUFutureWaitInfo wait = {};
        wait.future = wgpuQueueOnSubmittedWorkDone(ctx->queue.Get(), done);
        if (wgpuInstanceWaitAny(page_instance, 1, &wait, UINT64_MAX) != WGPUWaitStatus_Success) {
            return false;
        }
        ctx->context->checkAsyncWorkCompletion();
    }
    return true;
}

extern "C" {

// MARK: - Context

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
    // The Vulkan objects only name the device: the one under them is the
    // page's GPUDevice, which webgpu.h reaches directly.
    (void)vk_instance;
    (void)vk_physical_device;
    (void)vk_queue;
    (void)queue_family_index;
    (void)instance_extensions;
    (void)instance_extension_count;
    (void)device_extensions;
    (void)device_extension_count;
    if (!vk_device) {
        return nullptr;
    }
    WGPUDevice device = nullptr;
    if (!acquire_page_device(&device)) {
        fprintf(stderr, "cskia: the page's WebGPU device is not available\n");
        return nullptr;
    }

    graphite::DawnBackendContext backend;
    backend.fInstance = wgpu::Instance(page_instance);
    backend.fDevice   = wgpu::Device::Acquire(device);
    backend.fQueue    = backend.fDevice.GetQueue();
    // Non-yielding (see the top of the file).
    backend.fTick     = nullptr;

    auto* ctx = new cskia_context_t();
    ctx->device  = static_cast<VkDevice>(vk_device);
    ctx->queue   = backend.fQueue;
    ctx->context = graphite::ContextFactory::MakeDawn(backend, graphite::ContextOptions());
    if (ctx->context) {
        graphite::RecorderOptions options;
        options.fImageProvider = sk_make_sp<UploadingImageProvider>();
        ctx->recorder = ctx->context->makeRecorder(options);
    }
    if (!ctx->context || !ctx->recorder) {
        fprintf(stderr, "cskia: Graphite could not start on the page's WebGPU device\n");
        delete ctx;
        return nullptr;
    }
    return ctx;
}

void cskia_context_destroy(cskia_context_t* ctx) {
    if (!ctx) {
        return;
    }
    if (ctx->recorder) {
        submit_recording(ctx);
    }
    ctx->recorder.reset();
    if (ctx->context && !wait_for_gpu(ctx)) {
        // No way to wait here, and Graphite will not be destroyed with work
        // in flight: it stays, unused (its GPU objects go with the page).
        (void)ctx->context.release();
    }
    ctx->context.reset();
    delete ctx;
}

// MARK: - Surface

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
    (void)vk_image_layout;
    (void)vk_usage_flags;
    (void)vk_queue_family_index;
    if (!ctx || !ctx->recorder || !vk_image || width <= 0 || height <= 0) {
        return nullptr;
    }

    SkColorType colorType;
    switch (static_cast<VkFormat>(vk_format)) {
        case VK_FORMAT_R8G8B8A8_UNORM: colorType = kRGBA_8888_SkColorType; break;
        case VK_FORMAT_B8G8R8A8_UNORM: colorType = kBGRA_8888_SkColorType; break;
        default:
            fprintf(stderr, "cskia: wrap_vk_image: unsupported VkFormat %d\n", (int)vk_format);
            return nullptr;
    }

    // The texture the image is; this reference is Graphite's until it lets
    // go of the texture (the release proc).
    VkExportWebGPUTextureInfoNUCLEANT exportInfo = {};
    exportInfo.sType = VK_STRUCTURE_TYPE_EXPORT_WEBGPU_TEXTURE_INFO_NUCLEANT;
    exportInfo.image = static_cast<VkImage>(vk_image);
    vkExportWebGPUObjectsNUCLEANT(ctx->device, &exportInfo);
    WGPUTexture texture = static_cast<WGPUTexture>(exportInfo.texture);
    if (!texture) {
        fprintf(stderr, "cskia: wrap_vk_image: the image has no WebGPU texture of its own\n");
        return nullptr;
    }

    SkSurfaceProps props;
    sk_sp<SkSurface> surface = SkSurfaces::WrapBackendTexture(
        ctx->recorder.get(),
        graphite::BackendTextures::MakeDawn(texture),
        colorType,
        nullptr,
        &props,
        [](void* texture) { wgpuTextureRelease(static_cast<WGPUTexture>(texture)); },
        texture);
    // On failure the release proc has already run.
    if (!surface) {
        fprintf(stderr, "cskia: wrap_vk_image: SkSurfaces::WrapBackendTexture returned null\n");
        return nullptr;
    }

    auto* wrapper = new cskia_surface_t();
    wrapper->surface = std::move(surface);
    wrapper->ctx     = ctx;
    wrapper->width   = width;
    wrapper->height  = height;
    return wrapper;
}

void cskia_surface_destroy(cskia_surface_t* surface) {
    if (!surface) {
        return;
    }
    cskia_context_t* ctx = surface->ctx;
    surface->surface.reset();
    if (ctx && ctx->recorder) {
        // Whatever was drawn goes out now, so nothing recorded still names
        // the texture once the caller destroys the image (which WebGPU
        // allows while submitted work uses it).
        submit_recording(ctx);
        ctx->context->performDeferredCleanup(std::chrono::milliseconds(0));
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
    // No layouts on WebGPU.
    (void)surface;
    (void)vk_image_layout;
}

bool cskia_context_flush(
    cskia_context_t* ctx,
    cskia_surface_t* surface,
    uint32_t         final_layout,
    bool             sync_cpu)
{
    // No layouts; and no CPU wait (see the top of the file) — the engine's
    // frame is submitted after this, on the same queue.
    (void)final_layout;
    (void)sync_cpu;
    if (!ctx || !ctx->recorder || !surface || !surface->surface) {
        return false;
    }
    return submit_recording(ctx);
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

// The browser has no system fonts for Skia to find: faces come from files
// (cskia_typeface_make_from_file — the bundled fonts the page mounts) or
// data. With none given there is no default typeface, and text draws
// nothing.
static sk_sp<SkTypeface> default_typeface() {
    static sk_sp<SkTypeface> typeface = [] {
        sk_sp<SkFontMgr> mgr = SkFontMgr_New_Custom_Empty();
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

#endif // __wasm__
