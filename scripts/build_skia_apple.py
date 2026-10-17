#!/usr/bin/env python3
"""Build Skia for Apple's platforms (Ganesh on Vulkan, through MoltenVK) and
package it as one Skia.xcframework.zip — the Apple counterpart of
build_skia.py + make_artifactbundle.py.

From nucleant_dev/skia-build's build_skia_macos.py and build_skia_ios.py:
the same Skia branch, GN arguments and build steps, for every configuration
— macos-arm64, macos-x64, ios-arm64, ios-sim-arm64, ios-sim-x64 — on one Mac,
then packaged:

    python3 scripts/build_skia_apple.py build --out out [--config ...]
    python3 scripts/build_skia_apple.py package --inputs out/* --output dist

`build` leaves <out>/<config>/lib/*.a (libskia.a and the module archives)
and <out>/<config>/include (Skia's headers). `package` makes the xcframework's three
slices — macOS (arm64 + x86_64), iOS, iOS simulator (arm64 + x86_64), each
`lipo`'d across its configurations — merges every archive of a slice into one
libSkia.a, since a binary target links one library, and writes
<output>/Skia.xcframework.zip.

The Vulkan backend links no Vulkan library: Skia resolves every entry point
through the vkGetInstanceProcAddr the app hands it (MoltenVK, via CVulkan).

Run with a real python3, not Xcode's bundled one — see
_require_safe_interpreter.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
SKIA_DIR = os.path.join(ROOT, ".work", "skia-apple")
SKIA_REPO = "https://skia.googlesource.com/skia.git"

# Built as their own targets next to libskia.a; all merged into libSkia.a.
MODULE_LIBS = [
    "libsvg.a",
    "libskparagraph.a",
    "libskshaper.a",
    "libskunicode_icu.a",
    "libskunicode_core.a",
    "libskresources.a",
]

# name -> (target_os, gn target_cpu, iOS simulator)
CONFIGS = {
    "macos-arm64": ("mac", "arm64", False),
    "macos-x64": ("mac", "x64", False),
    "ios-arm64": ("ios", "arm64", False),
    "ios-sim-arm64": ("ios", "arm64", True),
    "ios-sim-x64": ("ios", "x64", True),
}

# The xcframework's slices, by configuration-name prefix (most specific first).
SLICES = ["macos", "ios-sim", "ios"]


def _require_safe_interpreter():
    """Refuse to run under Xcode's bundled python3.

    That interpreter (macOS's `/usr/bin/python3`, which resolves into
    `Xcode.app/.../Python3.framework`) reliably corrupted the first few cc1
    invocations `subprocess.run` spawns to drive ninja — reproduced as a
    deterministic "ZLIB_VERNUM != PNG_ZLIB_VERNUM" from pngpriv.h. Launching
    a modern python3 directly clears it; re-exec'ing from inside Xcode's does
    not. So: fail loudly and tell the invoker to run a different python3.
    """
    if "Xcode" not in sys.executable and "CommandLineTools" not in sys.executable:
        return
    raise SystemExit(
        f"refusing to run under {sys.executable} (Xcode's bundled python3 — "
        f"corrupts this script's subprocess calls). Rerun with a different "
        f"python3 directly."
    )


def run(cmd, cwd=None, env=None):
    print(f"+ {' '.join(cmd)}  (cwd={cwd or os.getcwd()})", flush=True)
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def run_retry(cmd, cwd, attempts):
    """Like `run`, but retries on failure — ninja is incremental, so a retry
    only recompiles whatever the previous attempt left missing. A handful of
    libpng TUs intermittently fail with a spurious "ZLIB_VERNUM !=
    PNG_ZLIB_VERNUM" in large parallel runs; a retry has always finished."""
    for attempt in range(1, attempts + 1):
        try:
            run(cmd, cwd=cwd)
            return
        except subprocess.CalledProcessError:
            if attempt == attempts:
                raise
            print(f"! build attempt {attempt}/{attempts} failed, retrying (ninja will only redo the missing objects)", flush=True)


def clone_or_update(branch):
    if not os.path.isdir(os.path.join(SKIA_DIR, ".git")):
        run(["git", "clone", "--depth", "1", "--branch", branch, SKIA_REPO, SKIA_DIR])
    else:
        run(["git", "fetch", "--depth", "1", "origin", branch], cwd=SKIA_DIR)
        run(["git", "checkout", "FETCH_HEAD"], cwd=SKIA_DIR)


def sync_deps():
    run([sys.executable, os.path.join("tools", "git-sync-deps")], cwd=SKIA_DIR)
    run([os.path.join("bin", "fetch-gn")], cwd=SKIA_DIR)


def patch_skia_sources():
    """Drop `SK_HIDE_PATH_EDIT_METHODS` from Skia's public config so SkPath's
    edit methods keep their definitions in libskia.a (m144 compiles out every
    SkPath mutator with it). Doesn't change SkPath's layout. Idempotent."""
    build_gn = os.path.join(SKIA_DIR, "BUILD.gn")
    with open(build_gn) as f:
        lines = f.readlines()
    drop = {
        '"SK_HIDE_PATH_EDIT_METHODS",',
        "# TODO(kjlubick,fmalita) Remove when clients updated and APIs deleted.",
    }
    kept = [ln for ln in lines if ln.strip() not in drop]
    if len(kept) != len(lines):
        with open(build_gn, "w") as f:
            f.writelines(kept)
        print(f"patched {build_gn}: removed SK_HIDE_PATH_EDIT_METHODS", flush=True)


def gn_args(target_os, cpu, simulator, min_macos, min_ios):
    args = [
        'is_official_build=true',
        'is_debug=false',
        f'target_os="{target_os}"',
        f'target_cpu="{cpu}"',
    ]
    if target_os == "ios":
        args += [
            f'ios_use_simulator={"true" if simulator else "false"}',
            f'ios_min_target="{min_ios}"',
        ]
    args += [
        # Vulkan-only GPU surface — Metal/GL/ANGLE/Dawn permanently off.
        'skia_use_vulkan=true',
        'skia_use_metal=false',
        'skia_use_gl=false',
        'skia_use_dawn=false',
        'skia_use_angle=false',
        'skia_enable_ganesh=true',
        'skia_enable_graphite=false',

        # Full text + vector stack: SVG, freetype, ICU + harfbuzz shaping,
        # skparagraph.
        'skia_enable_svg=true',
        'skia_use_expat=true',
        'skia_use_system_expat=false',
        'skia_use_freetype=true',
        'skia_use_system_freetype2=false',
        'skia_enable_fontmgr_custom_empty=true',
        'skia_use_icu=true',
        'skia_use_system_icu=false',
        'skia_use_harfbuzz=true',
        'skia_use_system_harfbuzz=false',

        'skia_enable_pdf=true',

        # Codecs. is_official_build flips skia_use_system_* to true by
        # default — force the bundled copies so the archives are
        # self-contained.
        'skia_use_zlib=true',
        'skia_use_system_zlib=false',
        'skia_use_libpng_decode=true',
        'skia_use_libpng_encode=true',
        'skia_use_system_libpng=false',
        'skia_use_libjpeg_turbo_decode=true',
        'skia_use_libjpeg_turbo_encode=true',
        'skia_use_system_libjpeg_turbo=false',
        'skia_use_libwebp_decode=true',
        'skia_use_libwebp_encode=true',
        'skia_use_system_libwebp=false',

        'skia_use_piex=false',
        'skia_use_lua=false',
        'skia_enable_tools=false',

        'extra_cflags_cc=["-frtti"]',
    ]
    if target_os == "mac":
        args.append(f'extra_cflags=["-mmacosx-version-min={min_macos}"]')
    return " ".join(args)


def _lib_targets(ninja, out_rel):
    """libskia.a plus whichever MODULE_LIBS this gn config defines (queried
    from the ninja graph, so no test executables get built)."""
    wanted = ["libskia.a"] + MODULE_LIBS
    try:
        res = subprocess.run(
            [ninja, "-C", out_rel, "-t", "targets", "all"],
            cwd=SKIA_DIR, capture_output=True, text=True, check=True,
        )
    except subprocess.CalledProcessError:
        return ["skia"]
    available = {os.path.basename(line.split(":", 1)[0].strip()) for line in res.stdout.splitlines()}
    targets = [n for n in wanted if n in available]
    if "libskia.a" not in targets:
        targets = ["libskia.a"] + targets
    return targets


def _copy_module_headers(staging, mod, whole=False):
    """A module's public headers into staging/modules/<mod>, keeping Skia's
    layout so `#include "modules/<mod>/include/..."` resolves."""
    src = os.path.join(SKIA_DIR, "modules", mod)
    if not os.path.isdir(src):
        return
    if whole:
        # skcms.h includes "src/skcms_public.h", so keep the whole thing.
        shutil.copytree(
            src, os.path.join(staging, "modules", mod),
            ignore=shutil.ignore_patterns("*.cc", "*.cpp", "*.c", "BUILD.*", "*.gn", "*.gni", "tests"),
        )
        return
    inc = os.path.join(src, "include")
    if os.path.isdir(inc):
        shutil.copytree(inc, os.path.join(staging, "modules", mod, "include"))


def build(ns):
    """Each configuration in turn, out of one checkout, into <out>/<config>."""
    if not ns.skip_sync:
        clone_or_update(ns.branch)
        sync_deps()
    patch_skia_sources()
    for config in ns.config:
        build_config(ns, config)


def build_config(ns, config):
    target_os, cpu, simulator = CONFIGS[config]
    out_rel = os.path.join("out", f"{config}-vulkan")
    run([os.path.join("bin", "gn"), "gen", out_rel,
         f"--args={gn_args(target_os, cpu, simulator, ns.min_macos, ns.min_ios)}"], cwd=SKIA_DIR)
    # A flush and a short pause after `gn gen` — racing ninja's first wave
    # against the just-created graph reliably produced the libpng error above.
    subprocess.run(["sync"])
    time.sleep(2)
    ninja = shutil.which("ninja")
    if ninja is None:
        run([os.path.join("bin", "fetch-ninja")], cwd=SKIA_DIR)
        ninja = os.path.join(SKIA_DIR, "bin", "ninja")
    # libpng/zlib/libjpeg alone first: more reliable than in the big first wave.
    run_retry([ninja, "-C", out_rel, f"-j{ns.jobs}", "zlib", "libpng", "libjpeg"], cwd=SKIA_DIR, attempts=5)
    run_retry([ninja, "-C", out_rel, f"-j{ns.jobs}", *_lib_targets(ninja, out_rel)], cwd=SKIA_DIR, attempts=5)

    out = os.path.join(os.path.abspath(ns.out), config)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(os.path.join(out, "lib"))
    for name in ["libskia.a"] + MODULE_LIBS:
        built = os.path.join(SKIA_DIR, out_rel, name)
        if os.path.isfile(built):
            shutil.copy2(built, os.path.join(out, "lib", name))
        else:
            print(f"note: {name} not produced by this build — skipping", flush=True)
    # Headers keep Skia's own layout: include/..., modules/.../include and
    # modules/skcms.
    staging = os.path.join(out, "include")
    shutil.copytree(os.path.join(SKIA_DIR, "include"), os.path.join(staging, "include"))
    _copy_module_headers(staging, "skcms", whole=True)
    for mod in ("svg", "skparagraph", "skshaper", "skunicode", "skresources"):
        _copy_module_headers(staging, mod)
    print(f"built {config} -> {out}", flush=True)


def _slice_of(config_dir):
    name = os.path.basename(os.path.normpath(config_dir))
    for prefix in SLICES:
        if name.startswith(prefix):
            return prefix
    raise SystemExit(f"error: {config_dir} is no configuration of {', '.join(CONFIGS)}")


def package(ns):
    groups = {}
    for config_dir in ns.inputs:
        groups.setdefault(_slice_of(config_dir), []).append(config_dir)
    output = os.path.abspath(ns.output)
    os.makedirs(output, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        command = ["xcodebuild", "-create-xcframework"]
        for slice_name, dirs in groups.items():
            slice_dir = os.path.join(temp, slice_name)
            os.makedirs(slice_dir)
            names = sorted(os.listdir(os.path.join(dirs[0], "lib")))
            fat = []
            for name in names:
                per_arch = [os.path.join(d, "lib", name) for d in dirs]
                missing = [p for p in per_arch if not os.path.isfile(p)]
                if missing:
                    raise SystemExit(f"error: {', '.join(missing)} missing")
                dest = os.path.join(slice_dir, name)
                run(["lipo", "-create", *per_arch, "-output", dest])
                fat.append(dest)
            merged = os.path.join(slice_dir, "merged", "libSkia.a")
            os.makedirs(os.path.dirname(merged))
            run(["libtool", "-static", "-no_warning_for_no_symbols", "-o", merged, *fat])
            command += ["-library", merged, "-headers", os.path.join(dirs[0], "include")]
        xcframework = os.path.join(temp, "Skia.xcframework")
        run(command + ["-output", xcframework])
        zip_path = os.path.join(output, "Skia.xcframework.zip")
        if os.path.exists(zip_path):
            os.remove(zip_path)
        run(["ditto", "-c", "-k", "--keepParent", xcframework, zip_path])
    print(f"wrote {zip_path}", flush=True)


def main():
    global SKIA_DIR
    _require_safe_interpreter()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    b = commands.add_parser("build", help="build configurations")
    b.add_argument("--config", nargs="+", default=list(CONFIGS), choices=list(CONFIGS),
                   help="configurations to build (default: all)")
    b.add_argument("--out", required=True, help="directory for <config>/lib and <config>/include")
    b.add_argument("--branch", default="chrome/m144")
    b.add_argument("--min-macos", default="14.0")
    b.add_argument("--min-ios", default="17.0")
    b.add_argument("--skip-sync", action="store_true")
    # Conservative, not os.cpu_count(): at -j16 the full build hit the libpng
    # error above even with a good interpreter; never at -j6/-j8.
    b.add_argument("--jobs", type=int, default=min(os.cpu_count() or 8, 8))
    b.add_argument("--workdir", default=None, help="where the skia/ checkout and its out/ live")

    p = commands.add_parser("package", help="package built configurations as Skia.xcframework.zip")
    p.add_argument("--inputs", nargs="+", required=True, help="the configurations' directories under `build --out`")
    p.add_argument("--output", required=True, help="directory Skia.xcframework.zip is written to")

    ns = parser.parse_args()
    if ns.command == "build":
        if ns.workdir:
            os.makedirs(ns.workdir, exist_ok=True)
            SKIA_DIR = os.path.join(ns.workdir, "skia")
        build(ns)
    else:
        package(ns)


if __name__ == "__main__":
    main()
