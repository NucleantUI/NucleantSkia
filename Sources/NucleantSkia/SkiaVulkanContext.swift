//
//  SkiaVulkanContext.swift
//  SkiaCore
//
import CSkia


public enum SkiaCoreError: Error {
    case contextCreationFailed
    case surfaceCreationFailed
}


/// One Ganesh Vulkan context over an existing VkDevice/VkQueue — wraps
/// the raw `cskia_context_t` handle. A class, not a struct: this is a
/// reference to one live Skia GPU context whose lifetime and identity
/// must never be duplicated by value-copy.
///
/// The Vulkan handles are opaque here on purpose: SkiaCore knows nothing
/// about CVulkan — callers pass the engine's `VkInstance` etc. straight
/// through (they import as `OpaquePointer` on both sides).
public final class SkiaVulkanContext {

    public let base: OpaquePointer

    /// `instanceExtensions`/`deviceExtensions` must name exactly what was
    /// enabled at instance/device creation — Skia's caps read them (most
    /// importantly VK_KHR_portability_subset, which keeps it inside
    /// MoltenVK's feature set).
    public init(
        instance:           OpaquePointer,
        physicalDevice:     OpaquePointer,
        device:             OpaquePointer,
        queue:              OpaquePointer,
        queueFamilyIndex:   UInt32,
        instanceExtensions: [String],
        deviceExtensions:   [String]
    ) throws {
        let created = withCStringArray(instanceExtensions) { instPtr, instCount in
            withCStringArray(deviceExtensions) { devPtr, devCount in
                cskia_context_create(
                    UnsafeMutableRawPointer(instance),
                    UnsafeMutableRawPointer(physicalDevice),
                    UnsafeMutableRawPointer(device),
                    UnsafeMutableRawPointer(queue),
                    queueFamilyIndex,
                    instPtr,
                    instCount,
                    devPtr,
                    devCount
                )
            }
        }
        guard let created else {
            throw SkiaCoreError.contextCreationFailed
        }
        self.base = created
    }

    deinit {
        cskia_context_destroy(base)
    }
}


/// Call `body` with a C array of NULL-terminated C strings, valid for
/// the duration of the call.
func withCStringArray<R>(
    _ strings: [String],
    _ body: (UnsafePointer<UnsafePointer<CChar>?>?, UInt32) -> R
) -> R {
    func recurse(_ index: Int, _ acc: [UnsafePointer<CChar>?]) -> R {
        if index == strings.count {
            return acc.withUnsafeBufferPointer { buf in
                body(buf.baseAddress, UInt32(strings.count))
            }
        }
        return strings[index].withCString { cString in
            recurse(index + 1, acc + [cString])
        }
    }
    return recurse(0, [])
}
