#!/usr/bin/env python3
"""Package one platform's Skia build as a SwiftPM artifact bundle (SE-0482):

    <output>/<name>.artifactbundle.zip
        Skia.artifactbundle/
            info.json                    one "staticLibrary" artifact, "Skia"
            lib/libSkia.a                every archive of the build, merged
            include/...                  Skia's headers, as the build laid them out

for a `.binaryTarget(name: "Skia", url:/path:, ...)` on Linux, Android and
WebAssembly, the way Skia.xcframework is one on Apple's platforms. The bundle
is one platform and architecture, so a package downloads only the Skia it
builds with.

One archive, because a binary target links one library: Skia's GN build
splits into several (libskia.a, its modules, the third-party libraries) with
references running both ways between them. Inside one archive the linker
resolves those by itself; across several, GNU ld needs --start-group, which
only unsafeFlags can pass.

    python3 scripts/make_artifactbundle.py \\
        --lib-dir Dependencies/linux/lib --include Dependencies/linux/include \\
        --triple x86_64-unknown-linux-gnu --name skia-linux-x86_64 --output dist

--header-path (repeatable, relative to the bundle's include/) adds a header
search path below include/ (wasm: dawn-headers). --ar names the archiver;
it must understand MRI scripts (llvm-ar, GNU ar — not macOS's ar).
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ARTIFACT = "Skia"


def log(message: str) -> None:
    print(f"[make_artifactbundle] {message}", flush=True)


def merge_archives(ar: str, archives: list[Path], output: Path) -> None:
    """All `archives` into `output`, through an MRI script (ADDLIB keeps
    every member, duplicate names included)."""
    script = [f"CREATE {output}"]
    script += [f"ADDLIB {archive}" for archive in archives]
    script += ["SAVE", "END"]
    log(f"merging {len(archives)} archives -> {output.name}")
    subprocess.run([ar, "-M"], input="\n".join(script) + "\n", text=True, check=True)
    # The symbol table the linker searches.
    subprocess.run([ar, "s", str(output)], check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lib-dir", type=Path, required=True, help="directory of the build's .a archives")
    parser.add_argument("--include", type=Path, required=True, help="the build's header tree (include/, modules/, ...)")
    parser.add_argument("--header-path", action="append", default=[],
                        help="extra header search path, relative to the bundle's include/")
    parser.add_argument("--triple", action="append", required=True, help="a target triple the library is for")
    parser.add_argument("--name", required=True, help="file name of the zip, without .artifactbundle.zip")
    parser.add_argument("--output", type=Path, required=True, help="directory the zip is written to")
    parser.add_argument("--version", default="1.0.0", help="the artifact's version in info.json")
    parser.add_argument("--ar", default=shutil.which("llvm-ar") or "ar", help="MRI-capable archiver")
    args = parser.parse_args()

    archives = sorted(args.lib_dir.glob("*.a"))
    if not archives:
        sys.exit(f"error: no .a archives in {args.lib_dir}")
    if not args.include.is_dir():
        sys.exit(f"error: no header directory {args.include}")

    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        bundle = Path(temp) / f"{ARTIFACT}.artifactbundle"
        (bundle / "lib").mkdir(parents=True)
        merge_archives(args.ar, [a.resolve() for a in archives], (bundle / "lib" / f"lib{ARTIFACT}.a").resolve())
        shutil.copytree(args.include, bundle / "include")
        info = {
            "schemaVersion": "1.0",
            "artifacts": {
                ARTIFACT: {
                    "type": "staticLibrary",
                    "version": args.version,
                    "variants": [{
                        "path": f"lib/lib{ARTIFACT}.a",
                        "supportedTriples": args.triple,
                        "staticLibraryMetadata": {
                            "headerPaths": ["include", *(f"include/{p}" for p in args.header_path)],
                        },
                    }],
                },
            },
        }
        (bundle / "info.json").write_text(json.dumps(info, indent=2) + "\n")
        zip_path = args.output / f"{args.name}.artifactbundle.zip"
        zip_path.unlink(missing_ok=True)
        shutil.make_archive(str(zip_path.with_suffix("")), "zip", root_dir=temp, base_dir=bundle.name)
    log(f"wrote {zip_path} ({zip_path.stat().st_size // (1024 * 1024)} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
