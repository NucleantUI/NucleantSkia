#!/usr/bin/env python3
"""Build Skia for Linux (Ganesh/Vulkan + fontconfig) and vendor it into
Dependencies/linux/, the same way Dependencies/apple/Skia.xcframework is a
vendored, committed binary rather than resolved from the system.

Wraps skia-python (https://github.com/NucleantUI/skia-python, expected as a
sibling checkout next to this repo, same convention as
NucleantThorVG/scripts/build_thorvg.py + thorvg-cython): initializes its
depot_tools/skia git submodules, applies its Linux patch set, runs
`gn gen` + `ninja` with the same GN args as skia-python's own
scripts/build_Linux.sh (skia_use_vulkan=true), then copies the resulting
static libraries and public headers here.

Prerequisites (not installed by this script):
    sudo apt install libfontconfig1-dev
    # depot_tools' `gn` wrapper shells out to `python` (not `python3`) —
    # either `sudo apt install python-is-python3`, or this script stages a
    # local python -> python3 symlink on PATH as a fallback.

Usage
-----
    python3 scripts/build_skia.py
    python3 scripts/build_skia.py --clean   # wipe skia/out and re-configure
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PACKAGE_ROOT = SCRIPT_DIR.parent
DEV_ROOT = PACKAGE_ROOT.parent

SKIA_PYTHON_DIR = DEV_ROOT / "skia-python"
SKIA_PYTHON_REPO = "https://github.com/NucleantUI/skia-python.git"
DEPOT_TOOLS_DIR = SKIA_PYTHON_DIR / "depot_tools"
SKIA_DIR = SKIA_PYTHON_DIR / "skia"
PATCH_DIR = SKIA_PYTHON_DIR / "patch"
OUT_DIR = SKIA_DIR / "out" / "Release"

NUCLEANT_LINUX_DIR = PACKAGE_ROOT / "Dependencies" / "linux"

LINUX_PATCHES = [
    ("0001-Make-SkPath-immutable-on-GN-build.patch", "-R"),
    ("0001-Disable-legacy-PNG-encoding-decoding-in-SkPicture.patch", "-R"),
    ("skia-m144-minimize-download.patch", None),
    ("skia-m132-colrv1-freetype.diff", None),
    ("skia-m132-egl-runtime.diff", None),
]

# Shared by every platform — same sources, same feature set. Only the bits
# that genuinely differ per OS live in the tails below.
GN_ARGS_COMMON = """
is_official_build=true
skia_enable_svg=true
skia_use_vulkan=true
skia_use_gl=false
skia_use_system_libjpeg_turbo=false
skia_use_system_libwebp=false
skia_use_system_libpng=false
skia_use_system_icu=false
skia_use_system_harfbuzz=false
skia_use_system_freetype2=false
extra_cflags_cc=["-frtti"]
"""

# -lrt: on Linux clock_gettime etc. live in librt; on Android they are in libc
# and there is no librt to link.
GN_ARGS_LINUX = """
extra_ldflags=["-lrt"]
"""

GN_ARGS = GN_ARGS_COMMON + GN_ARGS_LINUX

NUCLEANT_ANDROID_DIR = PACKAGE_ROOT / "Dependencies" / "android"

# Android ABI -> Skia's GN target_cpu name.
ANDROID_ABIS = {
    "arm64-v8a": "arm64",
    "x86_64": "x64",
    "armeabi-v7a": "arm",
}

# Matches [tool.kivy-school.android] min_api / the Swift Android SDK floor.
ANDROID_API_DEFAULT = 28


def _android_gn_args(ndk: Path, target_cpu: str, api: int) -> str:
    """GN args for one Android ABI: the common set plus Android's own.

    skia_use_fontconfig=false — Android has no fontconfig; Skia uses its own
    Android font manager, which is also why the Swift target links no
    fontconfig there.

    skia_use_system_expat=false — that arg defaults to is_official_build (true
    here), so Skia would look for a *system* expat. Linux has one; Android does
    not, and SkFontMgr_android_parser needs it to read /system/etc/fonts.xml.
    Building the vendored third_party/externals/expat instead keeps the Android
    font manager working. Left alone on Linux, where the system copy is real.
    """
    return GN_ARGS_COMMON + f'''
target_os="android"
target_cpu="{target_cpu}"
ndk="{ndk}"
ndk_api={api}
skia_use_fontconfig=false
skia_use_system_expat=false
'''



def _find_ndk(explicit: Path | None) -> Path:
    """Locate an Android NDK — nothing hardcoded, same resolution order as
    NucleantVulkan/scripts/build_wgpu.py."""
    if explicit is not None:
        return explicit.resolve()
    # Env first: this is what ksproject exports when *it* drives the build.
    for var in ("ANDROID_NDK_HOME", "ANDROID_NDK_ROOT", "NDK_HOME"):
        value = os.environ.get(var)
        if value:
            return Path(value).resolve()
    sys.exit(
        "error: no Android NDK given.\n"
        "  Pass --ndk <path>, or set ANDROID_NDK_HOME — ksproject exports it\n"
        "  when it drives the build; resolve it yourself with\n"
        "  `uv run ksproject android get-path ndk`."
    )


def log(message: str) -> None:
    print(f"\033[1;34m[build_skia]\033[0m {message}", flush=True)


def _run(cmd: list[str], *, cwd: Path | None = None, env: dict | None = None) -> None:
    log(f"$ {' '.join(str(c) for c in cmd)}" + (f"   (cwd={cwd})" if cwd else ""))
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def _ensure_skia_python() -> None:
    if not SKIA_PYTHON_DIR.is_dir():
        log(f"cloning skia-python into {SKIA_PYTHON_DIR} ...")
        _run(["git", "clone", SKIA_PYTHON_REPO, str(SKIA_PYTHON_DIR)])
    if not (DEPOT_TOOLS_DIR / "gn").exists():
        log("initializing depot_tools submodule (git submodule update --init --depth 1 depot_tools)")
        _run(["git", "submodule", "update", "--init", "--depth", "1", "depot_tools"], cwd=SKIA_PYTHON_DIR)
    if not (SKIA_DIR / "BUILD.gn").exists():
        log("initializing skia submodule (git submodule update --init --depth 1 skia) — this fetches skia's own history, expect it to take a while")
        _run(["git", "submodule", "update", "--init", "--depth", "1", "skia"], cwd=SKIA_PYTHON_DIR)


def _ensure_python_shim(bin_dir: Path) -> None:
    """depot_tools' `gn` wrapper shells out to a bare `python`, which
    Ubuntu/Debian don't provide by default (no python-is-python3 without
    sudo). Stage a local python -> python3 symlink and hand back a dir to
    prepend to PATH, rather than assuming the system already has one."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    py = bin_dir / "python"
    if not py.exists():
        py.symlink_to(sys.executable)


def _apply_patches() -> None:
    marker = SKIA_DIR / ".nucleant_linux_patches_applied"
    if marker.exists():
        log("patches already applied (found .nucleant_linux_patches_applied) — skipping")
        return
    for name, flag in LINUX_PATCHES:
        cmd = ["patch"]
        if flag:
            cmd.append(flag)
        cmd += ["-p1", "-i", str(PATCH_DIR / name)]
        # --dry-run first: the marker is an untracked file, so anything that
        # cleans the skia checkout loses it while the tree stays patched, and a
        # blind re-apply then fails the whole build. Ask patch what it would do
        # and treat "already applied" as success.
        probe = subprocess.run(
            cmd + ["--dry-run", "--forward"],
            cwd=SKIA_DIR, capture_output=True, text=True,
        )
        combined = probe.stdout + probe.stderr
        if any(k in combined for k in
               ("previously applied", "Unreversed patch", "Reversed (or previously")):
            log(f"patch already applied, skipping: {name}")
            continue
        if probe.returncode != 0:
            sys.exit(f"ERROR: patch would not apply cleanly: {name}\n{combined}")
        _run(cmd, cwd=SKIA_DIR)
    marker.write_text("applied by scripts/build_skia.py\n")


def _sync_deps(env: dict) -> None:
    _run([sys.executable, "tools/git-sync-deps"], cwd=SKIA_DIR, env=env)


def _gn_gen(env: dict) -> None:
    _run(["gn", "gen", str(OUT_DIR), f"--args={GN_ARGS}"], cwd=SKIA_DIR, env=env)


def _ninja_build_dir(out_dir: Path, env: dict, jobs: int | None) -> None:
    cmd = ["ninja", "-C", str(out_dir)]
    if jobs:
        cmd += ["-j", str(jobs)]
    _run(cmd, cwd=SKIA_DIR, env=env)


def _ninja_build(env: dict, jobs: int | None) -> None:
    cmd = ["ninja", "-C", str(OUT_DIR)]
    if jobs:
        cmd += ["-j", str(jobs)]
    _run(cmd, cwd=SKIA_DIR, env=env)


def _repackage(out_dir: Path = None, dest_dir: Path = None,
               headers: bool = True) -> None:
    """Copy the built static libraries + public headers into the vendored
    Dependencies/ tree, the same way Dependencies/apple/Skia.xcframework is a
    committed binary rather than something resolved from the system.

    Headers are architecture-independent, so an Android multi-ABI run only
    needs them written once (`headers=False` for subsequent ABIs).
    """
    out_dir = out_dir or OUT_DIR
    dest_dir = dest_dir or NUCLEANT_LINUX_DIR
    archives = sorted(out_dir.glob("*.a"))
    if not archives:
        sys.exit(f"ERROR: no .a files found in {out_dir} — did the ninja build finish?")

    lib_dir = dest_dir / "lib"
    include_dir = dest_dir / "include"
    if headers and include_dir.exists():
        shutil.rmtree(include_dir)
    lib_dir.mkdir(parents=True, exist_ok=True)
    if headers:
        include_dir.mkdir(parents=True, exist_ok=True)

    for a in archives:
        shutil.copy2(str(a), str(lib_dir / a.name))
    log(f"libs -> {lib_dir} ({', '.join(a.name for a in archives)})")

    if not headers:
        return
    for sub in ("include", "modules"):
        src = SKIA_DIR / sub
        if not src.is_dir():
            continue
        dst = include_dir / sub
        shutil.copytree(
            src, dst,
            ignore=shutil.ignore_patterns("*.cpp", "*.cc", "BUILD.bazel", "BUILD.gn"),
        )
    log(f"headers -> {include_dir}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--jobs", "-j", type=int, default=None,
                         help="ninja parallelism (default: ninja's own auto-detection)")
    parser.add_argument("--clean", action="store_true",
                         help="wipe skia/out/Release and re-run gn gen before building")
    parser.add_argument("--skip-build", action="store_true",
                         help="only repackage an already-built out/Release (for iterating on the repackage step)")
    # Android is never the host, so unlike Linux it cannot be inferred.
    parser.add_argument("--android", action="store_true",
                         help="cross-compile for Android instead of the host")
    parser.add_argument("--abis", default="arm64-v8a,x86_64",
                         help=f"Android only: comma-separated ABIs "
                              f"(choices: {','.join(ANDROID_ABIS)})")
    parser.add_argument("--ndk", type=Path, default=None,
                         help="Android only: NDK path (else ANDROID_NDK_HOME / "
                              "ANDROID_SDK_ROOT/ndk)")
    parser.add_argument("--api", type=int, default=ANDROID_API_DEFAULT,
                         help=f"Android only: API level (default: {ANDROID_API_DEFAULT})")
    args = parser.parse_args()

    if args.android:
        return _main_android(args)

    if not args.skip_build:
        _ensure_skia_python()

        shim_dir = SCRIPT_DIR / ".work" / "bin"
        _ensure_python_shim(shim_dir)
        env = {**os.environ, "PATH": f"{shim_dir}:{DEPOT_TOOLS_DIR}:{os.environ.get('PATH', '')}"}

        _apply_patches()
        _sync_deps(env)

        if args.clean and OUT_DIR.exists():
            log(f"cleaning {OUT_DIR}")
            shutil.rmtree(OUT_DIR)
        if args.clean or not (OUT_DIR / "build.ninja").exists():
            _gn_gen(env)

        _ninja_build(env, args.jobs)

    _repackage()
    log("done")
    return 0


def _main_android(args) -> int:
    """Cross-compile Skia once per ABI and vendor each into
    Dependencies/android/<abi>/lib, with headers written once alongside."""
    abis = [a.strip() for a in args.abis.split(",") if a.strip()]
    unknown = [a for a in abis if a not in ANDROID_ABIS]
    if unknown:
        sys.exit(f"error: unknown ABI(s) {unknown}; choices: {', '.join(ANDROID_ABIS)}")

    ndk = _find_ndk(args.ndk)
    log(f"using NDK {ndk} (API {args.api})")

    _ensure_skia_python()
    shim_dir = SCRIPT_DIR / ".work" / "bin"
    _ensure_python_shim(shim_dir)
    env = {**os.environ, "PATH": f"{shim_dir}:{DEPOT_TOOLS_DIR}:{os.environ.get('PATH', '')}"}

    _apply_patches()
    _sync_deps(env)

    wrote_headers = False
    for abi in abis:
        out_dir = SKIA_DIR / "out" / f"Android-{abi}"
        if args.clean and out_dir.exists():
            log(f"cleaning {out_dir}")
            shutil.rmtree(out_dir)
        if not args.skip_build:
            if args.clean or not (out_dir / "build.ninja").exists():
                gn_args = _android_gn_args(ndk, ANDROID_ABIS[abi], args.api)
                _run(["gn", "gen", str(out_dir), f"--args={gn_args}"],
                     cwd=SKIA_DIR, env=env)
            _ninja_build_dir(out_dir, env, args.jobs)
        _repackage(out_dir, NUCLEANT_ANDROID_DIR / abi, headers=not wrote_headers)
        if not wrote_headers:
            # Headers are ABI-independent; keep one copy at the android root
            # rather than duplicating the whole skia include/ tree per ABI.
            # Layout matches Dependencies/linux/include — include/ and modules/
            # as siblings, since cskia.cpp includes "include/core/SkCanvas.h"
            # relative to the skia repo root.
            root_include = NUCLEANT_ANDROID_DIR / "include"
            # shutil.move into an *existing* directory nests instead of
            # replacing, so a second ABI run would produce include/include.
            if root_include.exists():
                shutil.rmtree(root_include)
            shutil.move(str(NUCLEANT_ANDROID_DIR / abi / "include"),
                        str(root_include))
            wrote_headers = True
        log(f"{abi}: vendored -> {NUCLEANT_ANDROID_DIR / abi / 'lib'}")

    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
