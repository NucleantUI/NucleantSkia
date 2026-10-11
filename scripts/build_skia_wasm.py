#!/usr/bin/env python3
"""Cross-compile Skia for WebAssembly (wasm32-unknown-wasip1).

The wasm counterpart of build_skia.py: the same Skia revision the other
platforms vendor (skia-python's submodule, m144), built as static archives

    Dependencies/wasm/lib/libskia.a (+ the third-party archives it needs)
    Dependencies/wasm/include/...    Skia's headers

for NucleantSkia's CSkia target to link into the app's one module.

Backend: **Graphite on WebGPU**, where the other platforms use Ganesh on
Vulkan. In the browser NucleantVulkan's Vulkan is itself WebGPU, and its
CWgpu is webgpu.h on the page's GPUDevice — so Skia draws with that device
into a texture the engine imports as the node's VkImage, the way ThorVG does
(VK_NUCLEANT_webgpu_objects). This build is WASI, not Emscripten, so:

  * Dawn's headers (its release closest to the Dawn revision Skia pins)
    stand in for `//third_party/dawn` — headers only, nothing of Dawn is
    built or linked; CWgpu provides the C functions. Graphite's native-Dawn
    code is what compiles here (its `__EMSCRIPTEN__` branches target
    Emscripten's old built-in WebGPU headers); the Dawn extensions it names
    are only used when the device reports them, which the page's does not.
    The shared core of webgpu.h is identical between Dawn's header and the
    one CWgpu is written against;
  * Skia's own wasm toolchain wants emsdk: a stand-in emsdk directory points
    its emcc/em++/emar at the clang of the Swift toolchain matching the
    installed wasm Swift SDK, with that SDK's WASI.sdk as the sysroot.

Single-threaded, as everything else in the module: the SDK's libc++ has no
threads, so — as in build_thorvg_wasm.py — a force-included header supplies
the `std::mutex` (and a `std::thread` that traps if started) Skia names, and
`thread_local` is compiled as `static`.

Fonts: FreeType with the custom empty font manager — faces are made from
files or data (NucleantUI loads its bundled Roboto through it).

Codecs: PNG, through the libpng FreeType already brings in — NucleantUI's
`RasterImage` decodes its files with SkCodec off Apple. No other codecs,
HarfBuzz or ICU yet: NucleantSkia does not use them.

    python3 scripts/build_skia_wasm.py [--clean] [--jobs N]
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PACKAGE_ROOT = SCRIPT_DIR.parent
WORK_DIR = SCRIPT_DIR / ".work"
SKIA_DIR = WORK_DIR / "skia"
OUT_DIR = SKIA_DIR / "out" / "wasm"
WASM_DIR = PACKAGE_ROOT / "Dependencies" / "wasm"

SKIA_REPO = "https://skia.googlesource.com/skia.git"
# skia-python's `skia` submodule — the revision build_skia.py builds.
SKIA_REVISION = "2708a1b1540e59b8e3407405b0c991a5c7b69523"
# Dawn's last release before the Dawn revision Skia's DEPS pins (6acf6ef, Feb
# 2026): its headers package is what Graphite's Dawn backend compiles against.
DAWN_RELEASE = "v20260219.200501"
DAWN_HEADERS_URL = ("https://github.com/google/dawn/releases/download/"
                    f"{DAWN_RELEASE}/dawn-headers-536c572abab2602db0b652eda401ebd01e046c11.tar.gz")
# The third-party checkouts the build below needs, out of Skia's DEPS.
# FreeType links libpng unconditionally in Skia's build (color bitmap
# glyphs), the PNG codec decodes through it, and libpng needs zlib.
DEPS_NEEDED = ["freetype", "libpng", "zlib"]

TRIPLE = "wasm32-wasip1"
VERSION_RE = re.compile(r"(\d+\.\d+(?:\.\d+)?)")

MUTEX_SHIM = """\
#pragma once
#ifdef __cplusplus
#include <__config>
#if !_LIBCPP_HAS_THREADS
_LIBCPP_BEGIN_NAMESPACE_STD
class mutex {
public:
    constexpr mutex() noexcept = default;
    mutex(const mutex&) = delete;
    mutex& operator=(const mutex&) = delete;
    void lock() {}
    bool try_lock() { return true; }
    void unlock() {}
};
// Declared so SkExecutor's thread pool compiles. Starting one traps: there
// is no second thread to run it on, and nothing in this build starts one.
class thread {
public:
    thread() noexcept = default;
    template <class F, class... Args>
    explicit thread(F&&, Args&&...) { __builtin_trap(); }
    bool joinable() const noexcept { return false; }
    void join() {}
    void detach() {}
    static unsigned hardware_concurrency() noexcept { return 1; }
};
_LIBCPP_END_NAMESPACE_STD
#endif
#endif
"""

# //third_party/dawn, headers only: Dawn's headers, and nothing to build or
# link (CWgpu provides the C functions when the app links).
DAWN_BUILD_GN = """\
# Replaced by NucleantSkia's scripts/build_skia_wasm.py: webgpu.h and
# webgpu_cpp.h from Dawn's headers package, implemented at link time by
# NucleantVulkan's CWgpu (webgpu.h on the browser's WebGPU).
config("dawn_api_config") {
  include_dirs = [ "@DAWN_INCLUDE@" ]
}

group("dawn") {
  public_configs = [ ":dawn_api_config" ]
}

group("tint") {
}
"""

GN_ARGS = """
target_os="wasm"
target_cpu="wasm"
is_official_build=true
is_debug=false
skia_emsdk_dir="{emsdk}"
skia_enable_ganesh=false
skia_enable_graphite=true
skia_use_dawn=true
skia_use_webgpu=true
skia_use_webgl=false
skia_use_gl=false
skia_use_vulkan=false
skia_use_metal=false
skia_enable_pdf=false
skia_enable_svg=false
skia_enable_skottie=false
skia_enable_tools=false
skia_use_freetype=true
skia_use_system_freetype2=false
skia_use_freetype_woff2=false
skia_use_freetype_zlib=false
skia_use_freetype_svg=false
skia_enable_fontmgr_custom_empty=true
skia_enable_fontmgr_custom_directory=false
skia_enable_fontmgr_custom_embedded=false
skia_use_fontconfig=false
skia_use_harfbuzz=false
skia_use_icu=false
skia_use_expat=false
skia_use_zlib=true
skia_use_system_zlib=false
skia_use_wuffs=false
skia_use_libpng_decode=true
skia_use_libpng_encode=false
skia_use_libjpeg_turbo_decode=false
skia_use_libjpeg_turbo_encode=false
skia_use_libwebp_decode=false
skia_use_libwebp_encode=false
skia_use_dng_sdk=false
skia_use_piex=false
skia_use_lua=false
skia_canvaskit_enable_webgpu=false
extra_cflags={extra_cflags}
extra_cflags_cc=["-frtti"]
"""


def log(message: str) -> None:
    print(f"[build_skia_wasm] {message}", flush=True)


def run(cmd: list[str], cwd: Path | None = None, env: dict | None = None) -> None:
    log("$ " + " ".join(str(c) for c in cmd))
    subprocess.check_call(cmd, cwd=cwd, env=env)


def find_sysroot() -> Path:
    """The WASI.sdk sysroot inside the installed wasm Swift SDK bundle."""
    for root in (Path.home() / "Library" / "org.swift.swiftpm" / "swift-sdks", Path.home() / ".swiftpm" / "swift-sdks"):
        for sysroot in sorted(root.glob("*_wasm.artifactbundle/*/wasm32-unknown-wasip1/WASI.sdk"), reverse=True):
            return sysroot
    sys.exit("error: no wasm Swift SDK found (https://www.swift.org/documentation/articles/wasm-getting-started.html)")


def find_toolchain_bin(sysroot: Path) -> Path:
    """usr/bin of the Swift toolchain whose version matches the SDK."""
    match = VERSION_RE.search(str(sysroot))
    version = match.group(1) if match else None
    for base in (Path.home() / "Library" / "Developer" / "Toolchains", Path("/Library/Developer/Toolchains")):
        candidate = base / f"swift-{version}-RELEASE.xctoolchain" / "usr" / "bin"
        if (candidate / "clang").is_file() and (candidate / "llvm-ar").is_file():
            return candidate
    sys.exit(f"error: no Swift {version} toolchain with clang found; install it with `swiftly install {version}`")


def sync_skia() -> None:
    if not (SKIA_DIR / ".git").is_dir():
        WORK_DIR.mkdir(parents=True, exist_ok=True)
        run(["git", "init", "-q", str(SKIA_DIR)])
        run(["git", "remote", "add", "origin", SKIA_REPO], cwd=SKIA_DIR)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=SKIA_DIR, capture_output=True, text=True).stdout.strip()
    if head != SKIA_REVISION:
        run(["git", "fetch", "-q", "--depth", "1", "origin", SKIA_REVISION], cwd=SKIA_DIR)
        run(["git", "checkout", "-q", "--force", "FETCH_HEAD"], cwd=SKIA_DIR)
    if not (SKIA_DIR / "bin" / "gn").is_file():
        run([sys.executable, "bin/fetch-gn"], cwd=SKIA_DIR)


def sync_deps() -> None:
    """Only the DEPS entries this build uses, shallow, at Skia's pins."""
    deps = (SKIA_DIR / "DEPS").read_text()
    for name in DEPS_NEEDED:
        match = re.search(rf'"third_party/externals/{re.escape(name)}"\s*:\s*"([^"@]+)@([0-9a-f]+)"', deps)
        if not match:
            sys.exit(f"error: {name} not in Skia's DEPS")
        url, revision = match.groups()
        target = SKIA_DIR / "third_party" / "externals" / name
        if (target / ".git").is_dir():
            head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=target, capture_output=True, text=True).stdout.strip()
            if head == revision:
                continue
        else:
            target.mkdir(parents=True, exist_ok=True)
            run(["git", "init", "-q"], cwd=target)
            run(["git", "remote", "add", "origin", url], cwd=target)
        run(["git", "fetch", "-q", "--depth", "1", "origin", revision], cwd=target)
        run(["git", "checkout", "-q", "--force", "FETCH_HEAD"], cwd=target)


def fetch_dawn_headers() -> Path:
    """include/ of Dawn's headers package (webgpu/, dawn/)."""
    root = WORK_DIR / "dawn-headers"
    include = root / "dawn-headers" / "include"
    if not (include / "dawn" / "webgpu_cpp.h").is_file():
        archive = WORK_DIR / f"dawn-headers-{DAWN_RELEASE}.tar.gz"
        if not archive.is_file():
            log(f"downloading {DAWN_HEADERS_URL}")
            urllib.request.urlretrieve(DAWN_HEADERS_URL, archive)
        if root.exists():
            shutil.rmtree(root)
        root.mkdir(parents=True)
        with tarfile.open(archive) as tf:
            tf.extractall(root)
    return include


def make_emsdk(bin_dir: Path, sysroot: Path, shims: Path) -> Path:
    """A directory shaped like an activated emsdk, for Skia's wasm toolchain:
    its emcc/em++/emar run the Swift toolchain's clang for wasm32-wasip1."""
    emsdk = WORK_DIR / "emsdk-wasi"
    emscripten = emsdk / "upstream" / "emscripten"
    (emscripten / "cache").mkdir(parents=True, exist_ok=True)
    link = emscripten / "cache" / "sysroot"
    if link.is_symlink() or link.exists():
        link.unlink()
    link.symlink_to(sysroot)
    # setjmp/longjmp (libpng's and FreeType's error handling) exist on WASI
    # only through wasm exception handling: -mllvm -wasm-enable-sjlj here,
    # libsetjmp when the app links. Every browser with WebGPU has it.
    common = (f'--target={TRIPLE} --sysroot="{sysroot}" -I"{shims}" -mllvm -wasm-enable-sjlj')
    scripts = {
        "emcc": f'exec "{bin_dir / "clang"}" {common} "$@"',
        "em++": f'exec "{bin_dir / "clang++"}" {common} -include "{shims / "wasi_single_thread_mutex.h"}" "$@"',
        "emar": f'exec "{bin_dir / "llvm-ar"}" "$@"',
    }
    for name, body in scripts.items():
        path = emscripten / name
        path.write_text("#!/bin/sh\n" + body + "\n")
        path.chmod(0o755)
    return emsdk


def patch_skia(dawn_include: Path) -> None:
    """Point //third_party/dawn at Dawn's headers; no musttail on wasm."""
    (SKIA_DIR / "third_party" / "dawn" / "BUILD.gn").write_text(
        DAWN_BUILD_GN.replace("@DAWN_INCLUDE@", dawn_include.as_posix()))
    # [[clang::musttail]] in the raster pipeline needs wasm's tail-call
    # feature; Skia already leaves it out for Emscripten — likewise here.
    patch_once("src/core/SkRasterPipeline.h",
               "!defined(__EMSCRIPTEN__) && !defined(SK_CPU_ARM32)",
               "!defined(__EMSCRIPTEN__) && !defined(__wasm__) && !defined(SK_CPU_ARM32)")
    # SkPath's edit methods (moveTo, lineTo, …), which CSkia's API is built
    # on: build_skia.py keeps them on the other platforms by reverting
    # skia-python's "Make SkPath immutable on GN build" patch — the same
    # define, dropped here.
    patch_once("BUILD.gn",
               '    # TODO(kjlubick,fmalita) Remove when clients updated and APIs deleted.\n'
               '    "SK_HIDE_PATH_EDIT_METHODS",\n',
               '    # wasm (build_skia_wasm.py): SkPath edit methods kept, as on every platform.\n')
    # POSIX semaphores need threads, which wasm32-wasip1 has none of: with
    # one thread a semaphore is a count, and a wait on an empty one could
    # never end.
    patch_once("src/base/SkSemaphore.cpp",
               "#else\n    // It's important we test for Mach before this.",
               "#elif defined(__wasi__)\n"
               "    #include \"include/private/base/SkAssert.h\"\n"
               "    struct SkSemaphore::OSSemaphore {\n"
               "        int fCount = 0;\n"
               "\n"
               "        void signal(int n) { fCount += n; }\n"
               "        void wait() {\n"
               "            if (fCount == 0) { SK_ABORT(\"SkSemaphore: wait with no other thread to signal (wasm)\"); }\n"
               "            fCount--;\n"
               "        }\n"
               "    };\n"
               "#else\n    // It's important we test for Mach before this.")
    # Two Dawn-native features whose names moved between Dawn's last header
    # release and Skia's Dawn pin. Neither exists in the browser, so the
    # code paths that use them go the way Emscripten's do.
    graphite = "src/gpu/graphite/dawn/"
    patch_once(graphite + "DawnCaps.cpp",
               "if (!device.HasFeature(wgpu::FeatureName::R8UnormStorage)) {",
               "if (true) {  // wasm: no R8UnormStorage in the browser")
    patch_once(graphite + "DawnCommandBuffer.cpp",
               "    wgpu::DawnRenderPassColorAttachmentRenderToSingleSampled mssaRenderToSingleSampledDesc;\n",
               "#if !defined(__wasm__)\n"
               "    wgpu::DawnRenderPassColorAttachmentRenderToSingleSampled mssaRenderToSingleSampledDesc;\n"
               "#endif\n")
    patch_once(graphite + "DawnCommandBuffer.cpp",
               "#if defined(__EMSCRIPTEN__)\n            SkASSERT(!isMSAAToSingleSampled);",
               "#if defined(__EMSCRIPTEN__) || defined(__wasm__)\n            SkASSERT(!isMSAAToSingleSampled);")


def patch_once(relative: str, old: str, new: str) -> None:
    """Replace `old` with `new` in a Skia source, unless already done."""
    path = SKIA_DIR / relative
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        sys.exit(f"error: patch target not found in {relative}: {old[:60]!r}")
    path.write_text(text.replace(old, new, 1))
    log(f"patched {relative}")


def write_shims() -> Path:
    shims = WORK_DIR / "wasi-shims"
    shims.mkdir(parents=True, exist_ok=True)
    (shims / "wasi_single_thread_mutex.h").write_text(MUTEX_SHIM)
    return shims


def install(dawn_include: Path) -> None:
    """The archives into Dependencies/wasm/lib; Skia's public headers into
    Dependencies/wasm/include as build_skia.py lays them out for the other
    platforms, plus Dawn's under include/dawn-headers (Graphite's WebGPU
    headers include <webgpu/webgpu_cpp.h>)."""
    lib = WASM_DIR / "lib"
    include = WASM_DIR / "include"
    for directory in (lib, include):
        if directory.exists():
            shutil.rmtree(directory)
    lib.mkdir(parents=True)
    for archive in sorted(OUT_DIR.glob("*.a")):
        shutil.copy2(archive, lib / archive.name)
        log(f"installed {archive.name} ({archive.stat().st_size // 1024} KB)")
    ignore = shutil.ignore_patterns("*.cpp", "*.cc", "BUILD.bazel", "BUILD.gn")
    for sub in ("include", "modules"):
        shutil.copytree(SKIA_DIR / sub, include / sub, ignore=ignore)
    for sub in ("webgpu", "dawn"):
        shutil.copytree(dawn_include / sub, include / "dawn-headers" / sub)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--clean", action="store_true", help="build from scratch")
    parser.add_argument("--jobs", type=int, help="ninja parallelism")
    parser.add_argument("--no-install", action="store_true", help="build only, leave Dependencies/wasm alone")
    args = parser.parse_args()

    for tool in ("git", "ninja"):
        if shutil.which(tool) is None:
            sys.exit(f"error: required tool not found on PATH: {tool}")
    sysroot = find_sysroot()
    bin_dir = find_toolchain_bin(sysroot)
    log(f"sysroot {sysroot}")
    log(f"toolchain {bin_dir}")

    sync_skia()
    sync_deps()
    dawn_include = fetch_dawn_headers()
    patch_skia(dawn_include)
    shims = write_shims()
    emsdk = make_emsdk(bin_dir, sysroot, shims)

    if args.clean and OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    # thread_local -> static: one thread, and the SDK's thread-less libc++abi
    # has no __cxa_thread_atexit to register their destructors with.
    # SK_BUILD_FOR_UNIX: WASI's clang does not define __unix__ (Emscripten's
    # does), and Skia would otherwise take the target for a Mac.
    # SKCMS_HAS_MUSTTAIL=0: skcms's musttail needs wasm's tail-call feature
    # too (see patch_skia for the raster pipeline's).
    # _WASI_EMULATED_MMAN: SkOSFile maps files; the Swift SDK links WASI's
    # mmap emulation (libwasi-emulated-mman) into every module already.
    extra_cflags = ["-DSK_BUILD_FOR_UNIX", "-DSKCMS_HAS_MUSTTAIL=0", "-D_WASI_EMULATED_MMAN", "-Dthread_local=",
                    "-Wno-keyword-macro", "-Wno-unknown-warning-option"]
    gn_args = GN_ARGS.format(emsdk=emsdk.as_posix(), extra_cflags="[" + ",".join(f'"{f}"' for f in extra_cflags) + "]")
    run([str(SKIA_DIR / "bin" / "gn"), "gen", str(OUT_DIR), f"--args={gn_args}"], cwd=SKIA_DIR)
    ninja = ["ninja", "-C", str(OUT_DIR), "skia"]
    if args.jobs:
        ninja += ["-j", str(args.jobs)]
    run(ninja, cwd=SKIA_DIR)
    if not args.no_install:
        install(dawn_include)
        log(f"installed -> {WASM_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
