// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let devMode = true

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

func getDependencies() -> [Package.Dependency] {
    if devMode {
        return [
            .package(path: "../NucleantVulkan")
        ]
    }
    return [
        .package(url: "https://github.com/NucleantUI/NucleantVulkan", branch: "master"),
    ]
}

func skiaTargets() -> [Target] {
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
                sources: ["cskia.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    .define("SK_GANESH"),
                    .define("SK_VULKAN"),
                    .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
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
                sources: ["cskia.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [
                    .headerSearchPath("."),
                    .define("SK_GANESH"),
                    .define("SK_VULKAN"),
                    .define("SK_USE_INTERNAL_VULKAN_HEADERS"),
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
        // Plain-C shim over Skia's C++ API: Vulkan GrDirectContext,
        // VkImage-wrapping SkSurface, flush, basic draw + text.
        .target(
            name: "CSkia",
            dependencies: [
                "Skia"
            ],
            cxxSettings: [
                .define("SK_GANESH"),
                .define("SK_VULKAN"),
                .define("SK_USE_INTERNAL_VULKAN_HEADERS")
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
            dependencies: ["NucleantSkia"]
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
