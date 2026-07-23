// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let devMode = false

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

let package = Package(
    name: "NucleantSkia",
    platforms: [
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
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .binaryTarget(
            name: "Skia",
            path: "Dependencies/Skia.xcframework"
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
    ],
    cxxLanguageStandard: .cxx17
)
