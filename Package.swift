// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// Build against the sibling `../NucleantVulkan` checkout or against its
/// `master` on GitHub — decided the same way in every Nucleant package:
/// `NUCLEANT_LOCAL_DEV=1|0` in the environment wins; otherwise local when the
/// sibling checkout exists next to this package. (A package fetched by
/// revision may not have path dependencies, so a clone SwiftPM made under
/// `.build/checkouts` has to take the GitHub one.)
let devMode: Bool = {
    if let flag = ProcessInfo.processInfo.environment["NUCLEANT_LOCAL_DEV"] {
        return ["1", "true", "yes"].contains(flag.lowercased())
    }
    let siblings = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return FileManager.default.fileExists(atPath: siblings.appendingPathComponent("NucleantVulkan").path)
}()

func getPlatformTarget() -> PackageDescription.Platform {
    // Package.swift is compiled by the *host* toolchain even when
    // cross-compiling, so `#if os(...)` only ever describes the host. Building
    // for Android from this Linux box would otherwise resolve to `.linux` and
    // link the Linux Skia. Android is always a cross-compile, so it is an
    // explicit env-var opt-in — SWIFT_ANDROID_HOME, matching NucleantVulkan,
    // CPython, PySwiftKit and PyNucleantUI.
    let env = ProcessInfo.processInfo.environment
    if env["SWIFT_ANDROID_HOME"] != nil || env["ANDROID_BUILD"] != nil {
        return .android
    }
    // WebAssembly (`swift build --swift-sdk <version>_wasm`) is a
    // cross-compile too, opted into the same way as in NucleantVulkan.
    if env["WASM_BUILD"] == "1" {
        return .wasi
    }
#if os(Linux)
    return .linux
#else
    return .macOS
#endif
}

let platformTarget = getPlatformTarget()

/// Vendored Android artifacts for the ABI currently being built. Android
/// builds one architecture per `swift build`, so unlike Linux there is no
/// single lib directory. Mirrors NucleantVulkan's helper of the same name.
func androidABI() -> String {
    let env = ProcessInfo.processInfo.environment
    if let abi = env["SWIFT_ANDROID_ABI"], !abi.isEmpty {
        return abi
    }
    switch (env["SWIFT_TRIPLE"] ?? "").split(separator: "-").first.map(String.init) ?? "" {
    case "aarch64": return "arm64-v8a"
    case "x86_64":  return "x86_64"
    case "armv7":   return "armeabi-v7a"
    default:        return "arm64-v8a"
    }
}

/// Skia prebuilt as one archive per platform: `Skia.xcframework.zip` on
/// Apple's platforms, a static-library artifact bundle (SE-0482) on the
/// others — see scripts/make_artifactbundle.py. This is its file name, the
/// same on a GitHub release and under Artifacts/.
func prebuiltSkiaArchive() -> String {
    switch platformTarget {
    case .wasi:
        return "skia-wasm32.artifactbundle.zip"
    case .android:
        return "skia-android-\(androidABI()).artifactbundle.zip"
    case .linux:
        // Linux builds are native, so the host's architecture is the target's.
#if arch(arm64)
        return "skia-linux-aarch64.artifactbundle.zip"
#else
        return "skia-linux-x86_64.artifactbundle.zip"
#endif
    default:
        return "Skia.xcframework.zip"
    }
}

/// Each prebuilt archive on this release's GitHub release, by file name: its
/// URL and checksum. Written here by .github/workflows/release.yml on the
/// release commit — in this file, not one it reads, because SwiftPM caches a
/// manifest's evaluation by its text (and environment), not by the files it
/// looks at. Empty on master.
let releasedSkia: [String: (url: String, checksum: String)] = [:]

/// The prebuilt Skia, when there is one, as the "Skia" binary target:
///   * on a release commit, the archive from the GitHub release — SwiftPM
///     downloads only the one declared here;
///   * with NUCLEANT_SKIA_ARTIFACTS=1, Artifacts/<archive>: the archives
///     .github/workflows/build-deps.yml builds, put there to build and test
///     against;
/// nil: neither, so Skia comes from the vendored Dependencies/.
func prebuiltSkiaTarget() -> Target? {
    let archive = prebuiltSkiaArchive()
    if let release = releasedSkia[archive] {
        return .binaryTarget(name: "Skia", url: release.url, checksum: release.checksum)
    }
    if ProcessInfo.processInfo.environment["NUCLEANT_SKIA_ARTIFACTS"] == "1" {
        return .binaryTarget(name: "Skia", path: "Artifacts/\(archive)")
    }
    return nil
}

/// CSkia over the prebuilt Skia. No unsafeFlags anywhere — SwiftPM refuses
/// them in a package depended on by version — so the binary target gives the
/// header search paths and the library, and the rest are plain settings.
func prebuiltSkiaTargets(_ skia: Target) -> [Target] {
    switch platformTarget {
    case .wasi:
        return [
            skia,
            .target(
                name: "CSkia",
                dependencies: [
                    "Skia",
                    .product(name: "NucleantVulkan", package: "NucleantVulkan"),
                ],
                path: "Sources/CSkia",
                // cskia_noexcept.cpp: Skia is built without exceptions, as
                // -fno-exceptions would build CSkia; it stands in for the
                // exception runtime the SDK's libc++abi lacks.
                sources: ["cskia_webgpu.cpp", "cskia_api.cpp", "cskia_noexcept.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    // The defines Skia's GN build gives its own clients, and
                    // the ones build_skia_wasm.py adds for the WASI target.
                    .define("NDEBUG"),
                    .define("SK_GRAPHITE"),
                    .define("SK_DAWN"),
                    .define("SK_ENABLE_PRECOMPILE"),
                    .define("SKNX_NO_SIMD"),
                    .define("SK_FORCE_8_BYTE_ALIGNMENT"),
                    .define("SK_DISABLE_TRACING"),
                    .define("SK_GAMMA_APPLY_TO_A8"),
                    .define("SK_TYPEFACE_FACTORY_FREETYPE"),
                    .define("SK_FONTMGR_FREETYPE_EMPTY_AVAILABLE"),
                    .define("SK_BUILD_FOR_UNIX"),
                    .define("SK_DISABLE_LEGACY_NONCONST_SERIAL_PROCS"),
                    .define("SK_SUPPORT_PDF"),
                    .define("SK_XML"),
                    .define("SK_ENABLE_SVG"),
                    .define("SK_SHAPER_HARFBUZZ_AVAILABLE"),
                    .define("SK_SHAPER_PRIMITIVE_AVAILABLE"),
                    .define("SK_SHAPER_UNICODE_AVAILABLE"),
                    .define("SK_UNICODE_AVAILABLE"),
                    .define("SK_UNICODE_ICU_IMPLEMENTATION"),
                    .define("SK_HAS_WUFFS_LIBRARY"),
                    .define("_WASI_EMULATED_MMAN"),
                    .define("thread_local", to: ""),
                    .define("CSKIA_SVG"),
                    .headerSearchPath("skia"),
                ],
                linkerSettings: [
                    .linkedLibrary("c++"),
                    .linkedLibrary("c++abi"),
                    .linkedLibrary("setjmp"),
                ]
            ),
        ]
    case .android:
        return [
            skia,
            .target(
                name: "CSkia",
                dependencies: ["Skia"],
                path: "Sources/CSkia",
                sources: ["cskia.cpp", "cskia_api.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    .define("SK_GANESH"),
                    .define("SK_VULKAN"),
                    .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
                    .define("CSKIA_SVG"),
                    .headerSearchPath("skia"),
                ],
                linkerSettings: [
                    .linkedLibrary("c++_shared"),
                    .linkedLibrary("m"),
                    .linkedLibrary("z"),
                    .linkedLibrary("log"),
                ]
            ),
        ]
    case .linux:
        return [
            skia,
            .target(
                name: "CSkia",
                dependencies: ["Skia"],
                path: "Sources/CSkia",
                sources: ["cskia.cpp", "cskia_api.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    .define("SK_GANESH"),
                    .define("SK_VULKAN"),
                    .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
                    .define("CSKIA_SVG"),
                    .headerSearchPath("skia"),
                ],
                linkerSettings: [
                    .linkedLibrary("fontconfig"),
                    // Linux's Skia takes the system's expat (SVG's XML
                    // parser), as it does zlib.
                    .linkedLibrary("expat"),
                    .linkedLibrary("pthread"),
                    .linkedLibrary("dl"),
                    .linkedLibrary("rt"),
                    .linkedLibrary("m"),
                    .linkedLibrary("z"),
                ]
            ),
        ]
    default:
        return [
            skia,
            .target(
                name: "CSkia",
                dependencies: ["Skia"],
                cxxSettings: [
                    .define("SK_GANESH"),
                    .define("SK_VULKAN"),
                    .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
                    .define("CSKIA_SVG"),
                    .headerSearchPath("skia"),
                ],
                linkerSettings: [
                    .linkedLibrary("c++"),
                    .linkedFramework("CoreFoundation"),
                    .linkedFramework("CoreGraphics"),
                    .linkedFramework("CoreText"),
                    .linkedFramework("ImageIO")
                ]
            ),
        ]
    }
}

func getDependencies() -> [Package.Dependency] {
    if devMode {
        return [
            .package(path: "../NucleantVulkan")
        ]
    }
    return [
        .package(url: "https://github.com/NucleantUI/NucleantVulkan.git", branch: "master"),
    ]
}

func skiaTargets() -> [Target] {
    if let skia = prebuiltSkiaTarget() {
        return prebuiltSkiaTargets(skia)
    }
    if platformTarget == .wasi {
        // The browser: Skia's Graphite with its Dawn (WebGPU) backend, built
        // for wasm32-wasip1 by scripts/build_skia_wasm.py into
        // Dependencies/wasm (lib/ + include/, Dawn's webgpu.h under
        // include/dawn-headers). Its webgpu.h calls resolve against
        // NucleantVulkan's CWgpu — webgpu.h on the page's WebGPU device, the
        // one the Vulkan implementation runs on — so cskia_webgpu.cpp gives
        // the same cskia.h as cskia.cpp does with Ganesh on Vulkan elsewhere,
        // drawing straight into the engine's VkImage. NucleantVulkan is a
        // dependency here for CVulkan's header (VK_NUCLEANT_webgpu_objects).
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let wasmRoot = packageRoot.appendingPathComponent("Dependencies/wasm")
        let wasmLibDir = wasmRoot.appendingPathComponent("lib").path
        let wasmIncludeDir = wasmRoot.appendingPathComponent("include").path
        // Every archive the build made — Skia, its modules (svg, skshaper,
        // skunicode, …) and the third-party libraries — as on Linux. wasm-ld
        // resolves between archives in any order, so no group is needed.
        let archiveNames: [String] = (try? FileManager.default.contentsOfDirectory(atPath: wasmLibDir))?
            .filter { $0.hasSuffix(".a") }
            .map { String($0.dropFirst(3).dropLast(2)) } // libFoo.a -> Foo
            .sorted() ?? []
        return [
            .target(
                name: "CSkia",
                dependencies: [
                    .product(name: "NucleantVulkan", package: "NucleantVulkan"),
                ],
                path: "Sources/CSkia",
                sources: ["cskia_webgpu.cpp", "cskia_api.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    // The defines Skia's GN build gives its own clients
                    // (skia_public), and the ones build_skia_wasm.py adds
                    // for the WASI target, so headers read as they were built.
                    .define("NDEBUG"),
                    .define("SK_GRAPHITE"),
                    .define("SK_DAWN"),
                    .define("SK_ENABLE_PRECOMPILE"),
                    .define("SKNX_NO_SIMD"),
                    .define("SK_FORCE_8_BYTE_ALIGNMENT"),
                    .define("SK_DISABLE_TRACING"),
                    .define("SK_GAMMA_APPLY_TO_A8"),
                    .define("SK_TYPEFACE_FACTORY_FREETYPE"),
                    .define("SK_FONTMGR_FREETYPE_EMPTY_AVAILABLE"),
                    .define("SK_BUILD_FOR_UNIX"),
                    .define("SK_DISABLE_LEGACY_NONCONST_SERIAL_PROCS"),
                    .define("SK_SUPPORT_PDF"),
                    .define("SK_XML"),
                    .define("SK_ENABLE_SVG"),
                    .define("SK_SHAPER_HARFBUZZ_AVAILABLE"),
                    .define("SK_SHAPER_PRIMITIVE_AVAILABLE"),
                    .define("SK_SHAPER_UNICODE_AVAILABLE"),
                    .define("SK_UNICODE_AVAILABLE"),
                    .define("SK_UNICODE_ICU_IMPLEMENTATION"),
                    .define("SK_HAS_WUFFS_LIBRARY"),
                    .define("_WASI_EMULATED_MMAN"),
                    // No thread-local storage on wasm32-wasip1; the build
                    // is single-threaded throughout.
                    .define("thread_local", to: ""),
                    // Skia's SVG module, and the four private Skia headers
                    // its own headers reach — as on every platform.
                    .define("CSKIA_SVG"),
                    .headerSearchPath("skia"),
                    .unsafeFlags([
                        "-I\(wasmIncludeDir)",
                        "-I\(wasmIncludeDir)/dawn-headers",
                        "-Wno-keyword-macro",
                        // As Skia is built: the SDK's libc++abi has no
                        // exception runtime (__cxa_throw).
                        "-fno-exceptions",
                    ]),
                ],
                linkerSettings: archiveNames.map { .linkedLibrary($0) } + [
                    .linkedLibrary("c++"),
                    .linkedLibrary("c++abi"),
                    // libpng's error handling longjmps (wasm's setjmp
                    // runtime, from the SDK's sysroot).
                    .linkedLibrary("setjmp"),
                    .unsafeFlags(["-L\(wasmLibDir)"]),
                ]
            ),
        ]
    }
    if platformTarget == .android {
        // Same vendored-static-archive shape as Linux below, but per-ABI:
        // Dependencies/android/<abi>/lib holds the Skia archives built for
        // that architecture. Differences from Linux are all Android's:
        //   * no fontconfig — Android has none; Skia is built against its own
        //     font manager, so that library is simply absent here.
        //   * no -rpath — the loader resolves out of the app's native library
        //     directory, and a host path baked at build time is meaningless
        //     on device.
        //   * libc++ is explicit — the NDK does not link a C++ runtime by
        //     default the way the Linux C++ driver pulls in libstdc++.
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let androidRoot = packageRoot.appendingPathComponent("Dependencies/android")
        let androidLibDir = androidRoot.appendingPathComponent("\(androidABI())/lib").path
        let androidIncludeDir = androidRoot.appendingPathComponent("include").path

        let archiveNames: [String] = (try? FileManager.default.contentsOfDirectory(atPath: androidLibDir))?
            .filter { $0.hasSuffix(".a") }
            .map { String($0.dropFirst(3).dropLast(2)) } // libFoo.a -> Foo
            .sorted() ?? []

        // Same circular-archive problem as Linux: lld makes one pass, so the
        // Skia archives need --start-group/--end-group regardless of order.
        var linkerFlags = ["-L\(androidLibDir)"]
        linkerFlags += ["-Xlinker", "--start-group"]
        linkerFlags += archiveNames.flatMap { ["-Xlinker", "-l\($0)"] }
        linkerFlags += ["-Xlinker", "--end-group"]

        return [
            .target(
                name: "CSkia",
                path: "Sources/CSkia",
                sources: ["cskia.cpp", "cskia_api.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    .define("SK_GANESH"),
                    .define("SK_VULKAN"),
                    .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
                    // Skia's SVG module (libsvg, with skshaper and
                    // skunicode, among the archives linked below), and the
                    // four private Skia headers its own headers reach.
                    .define("CSKIA_SVG"),
                    .headerSearchPath("skia"),
                    .unsafeFlags(["-I\(androidIncludeDir)"]),
                ],
                linkerSettings: [
                    .linkedLibrary("c++_shared"),
                    .linkedLibrary("m"),
                    .linkedLibrary("z"),
                    // liblog: Skia's Android backend logs through it.
                    .linkedLibrary("log"),
                    .unsafeFlags(linkerFlags),
                ]
            ),
        ]
    }
    if platformTarget == .linux {
        // Vendored Skia static libs (Dependencies/linux/lib) built with the
        // Ganesh Vulkan backend + fontconfig, the same role
        // Dependencies/apple/Skia.xcframework plays below — built via
        // scripts/build_skia.py (wraps skia-python). Linked directly
        // (unsafeFlags -L/-l, one -l per vendored .a) rather than through
        // pkg-config/.systemLibrary: nothing to resolve ambiguously off the
        // machine, this is exactly what was built here. Only works because
        // this stays the root package build — see
        // Dependencies/linux/README.md.
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let linuxLibDir = packageRoot.appendingPathComponent("Dependencies/linux/lib").path
        let linuxIncludeDir = packageRoot.appendingPathComponent("Dependencies/linux/include").path

        let archiveNames: [String] = (try? FileManager.default.contentsOfDirectory(atPath: linuxLibDir))?
            .filter { $0.hasSuffix(".a") }
            .map { String($0.dropFirst(3).dropLast(2)) } // libFoo.a -> Foo
            .sorted() ?? []

        // Skia's GN build splits into multiple static archives with
        // circular references between them (e.g. skia <-> skunicode) — GNU
        // ld only makes one left-to-right pass over archives, so circular
        // undefined symbols need --start-group/--end-group to be resolved
        // regardless of link order. System libs stay outside the group.
        var linkerFlags = ["-L\(linuxLibDir)", "-Xlinker", "-rpath", "-Xlinker", linuxLibDir]
        linkerFlags += ["-Xlinker", "--start-group"]
        linkerFlags += archiveNames.flatMap { ["-Xlinker", "-l\($0)"] }
        linkerFlags += ["-Xlinker", "--end-group"]

        return [
            .target(
                name: "CSkia",
                path: "Sources/CSkia",
                sources: ["cskia.cpp", "cskia_api.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    .define("SK_GANESH"),
                    .define("SK_VULKAN"),
                    .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
                    // Skia's SVG module (libsvg, with skshaper and
                    // skunicode, among the archives linked below), and the
                    // four private Skia headers its own headers reach.
                    .define("CSKIA_SVG"),
                    .headerSearchPath("skia"),
                    // cskia.cpp does `#include "include/core/SkCanvas.h"` —
                    // relative to the skia repo root (include/ and modules/
                    // as siblings), matching Dependencies/linux/include/'s
                    // own layout (see scripts/build_skia.py's _repackage()).
                    .unsafeFlags(["-I\(linuxIncludeDir)"]),
                ],
                linkerSettings: [
                    // No -lc++ here (unlike the Apple branch below): Linux
                    // links libstdc++ automatically via the C++ driver,
                    // and there's no libc++ installed by default anyway.
                    .linkedLibrary("fontconfig"),
                    .linkedLibrary("pthread"),
                    .linkedLibrary("dl"),
                    .linkedLibrary("rt"),
                    .linkedLibrary("m"),
                    // zlib: Skia links the system zlib rather than
                    // bundling it (freetype's gzip support, dng_sdk).
                    .linkedLibrary("z"),
                    .unsafeFlags(linkerFlags),
                ]
            ),
        ]
    }
    return [
        .binaryTarget(
            name: "Skia",
            path: "Dependencies/apple/Skia.xcframework"
        ),
        // Skia's SVG module and what it links: <text> is shaped through
        // skshaper, which takes ICU from skunicode (ICU itself is inside
        // libskunicode_icu). Built with the same Skia as libskia; each its
        // own xcframework, since one links one library.
        .binaryTarget(
            name: "SkiaSVG",
            path: "Dependencies/apple/SkiaSVG.xcframework"
        ),
        .binaryTarget(
            name: "SkiaShaper",
            path: "Dependencies/apple/SkiaShaper.xcframework"
        ),
        .binaryTarget(
            name: "SkiaUnicodeICU",
            path: "Dependencies/apple/SkiaUnicodeICU.xcframework"
        ),
        .binaryTarget(
            name: "SkiaUnicodeCore",
            path: "Dependencies/apple/SkiaUnicodeCore.xcframework"
        ),
        // Plain-C shim over Skia's C++ API: Vulkan GrDirectContext,
        // VkImage-wrapping SkSurface, flush, basic draw + text, SVG.
        .target(
            name: "CSkia",
            dependencies: [
                "Skia",
                "SkiaSVG",
                "SkiaShaper",
                "SkiaUnicodeICU",
                "SkiaUnicodeCore",
            ],
            cxxSettings: [
                .define("SK_GANESH"),
                .define("SK_VULKAN"),
                .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
                // The four private Skia headers the SVG module's headers
                // reach, which the xcframework doesn't ship.
                .define("CSKIA_SVG"),
                .headerSearchPath("skia"),
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("ImageIO")
            ]
        ),
    ]
}

func mainTargets() -> [Target] {
    [
        .target(
            name: "NucleantSkia",
            dependencies: [
                "CSkia",
                .product(name: "NucleantVulkan", package: "NucleantVulkan")
            ],
            exclude: [
                "implement-skia-surface.md"
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "NucleantSkiaTests",
            dependencies: ["NucleantSkia"],
            // Roboto, for the font tests — a known face on every platform.
            resources: [.copy("Resources")]
        ),
    ]
}

func getTargets() -> [Target] {
    var targets = mainTargets()
    targets.append(contentsOf: skiaTargets())
    return targets
}

let package = Package(
    name: "NucleantSkia",
    platforms: [
        // iOS 17 to match the graph's Observation-framework floor (macOS 14).
        // (Full iOS build also needs an iOS slice of Skia.xcframework.)
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "NucleantSkia",
            targets: ["NucleantSkia"]
        ),
    ],
    dependencies: getDependencies(),
    targets: getTargets(),
    cxxLanguageStandard: .cxx17
)
