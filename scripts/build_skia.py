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

GN_ARGS = """
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
extra_ldflags=["-lrt"]
"""


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
        _run(cmd, cwd=SKIA_DIR)
    marker.write_text("applied by scripts/build_skia.py\n")


def _sync_deps(env: dict) -> None:
    _run([sys.executable, "tools/git-sync-deps"], cwd=SKIA_DIR, env=env)


def _gn_gen(env: dict) -> None:
    _run(["gn", "gen", str(OUT_DIR), f"--args={GN_ARGS}"], cwd=SKIA_DIR, env=env)


def _ninja_build(env: dict, jobs: int | None) -> None:
    cmd = ["ninja", "-C", str(OUT_DIR)]
    if jobs:
        cmd += ["-j", str(jobs)]
    _run(cmd, cwd=SKIA_DIR, env=env)


def _repackage() -> None:
    """Copy the built static libraries + public headers into
    Dependencies/linux/, vendored/committed the same way
    Dependencies/apple/Skia.xcframework is."""
    archives = sorted(OUT_DIR.glob("*.a"))
    if not archives:
        sys.exit(f"ERROR: no .a files found in {OUT_DIR} — did the ninja build finish?")

    lib_dir = NUCLEANT_LINUX_DIR / "lib"
    include_dir = NUCLEANT_LINUX_DIR / "include"
    if include_dir.exists():
        shutil.rmtree(include_dir)
    lib_dir.mkdir(parents=True, exist_ok=True)
    include_dir.mkdir(parents=True, exist_ok=True)

    for a in archives:
        shutil.copy2(str(a), str(lib_dir / a.name))
    log(f"libs -> {lib_dir} ({', '.join(a.name for a in archives)})")

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
    args = parser.parse_args()

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


if __name__ == "__main__":
    sys.exit(main())
