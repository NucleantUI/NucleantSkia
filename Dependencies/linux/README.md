# Linux dependencies

Skia is vendored here (`lib/*.a`, `include/`), committed into the repo, the
same way `Dependencies/apple/` vendors the macOS/iOS Skia.xcframework —
built via [skia-python](https://github.com/NucleantUI/skia-python) with the
Ganesh Vulkan backend (`skia_use_vulkan=true`, matching `CSkia`'s
`SK_GANESH`/`SK_VULKAN` defines on every platform) and a fontconfig-based
font manager (Skia's `SkFontMgr_New_CoreText` used on Apple has no Linux
equivalent — `Sources/CSkia/cskia.cpp` picks `SkFontMgr_New_FontConfig`
there instead, `#ifdef __APPLE__`-gated).

`CSkia`'s Linux target links `Dependencies/linux/lib` directly (`-L` + one
`-l` per vendored `.a`, plus an `-rpath` back to that directory) instead of
going through pkg-config — deliberately not `.systemLibrary`: nothing to
resolve ambiguously off the machine, just what got built here. That only
works because this stays the *root* package build (SwiftPM rejects
`unsafeFlags` — what the direct link needs — in any target belonging to a
package used as someone else's dependency).

## 1. System prerequisites

```
sudo apt install libfontconfig1-dev
```

depot_tools' `gn` wrapper also shells out to a bare `python` (not
`python3`), which Ubuntu/Debian don't provide by default — either
`sudo apt install python-is-python3`, or let `scripts/build_skia.py` stage
its own local `python -> python3` symlink (it does this automatically,
no action needed).

## 2. Build + vendor Skia

```
python3 scripts/build_skia.py
```

This is a **big** build — expect it to take a while and to need several GB
of disk the first time:

1. Clones `skia-python` next to this repo if missing, and initializes its
   `depot_tools`/`skia` git submodules (skia's own history, several hundred
   MB even shallow).
2. `python3 tools/git-sync-deps` — fetches skia's third-party dependencies
   (~8GB: freetype, harfbuzz, icu, libjpeg-turbo, vulkan headers, etc.,
   all bundled/statically compiled rather than resolved from the system —
   `skia_use_system_*=false` for everything except fontconfig).
3. Applies skia-python's Linux patch set (idempotent — tracked via a
   `.nucleant_linux_patches_applied` marker in the skia checkout).
4. `gn gen` + `ninja` with the same args as skia-python's own
   `scripts/build_Linux.sh` (`skia_use_vulkan=true`).
5. Copies every `.a` produced (Skia's GN build splits into several —
   `libskia.a` plus bundled third-party pieces) into
   `Dependencies/linux/lib/`, and `skia/{include,modules}` (headers only,
   no `.cpp`/`BUILD.*`) into `Dependencies/linux/include/`.

Re-running is incremental (ninja/gn gen only re-run when needed). Pass
`--jobs N` to cap parallelism if the build machine is memory-constrained —
Skia's C++ compile units can be heavy. `--clean` wipes `skia/out/Release`
and reconfigures from scratch. `--skip-build` just re-runs the repackage
step against whatever's already in `skia/out/Release` (e.g. after tweaking
which files `_repackage()` copies).

## Building the package

```
swift build
```

No `PKG_CONFIG_PATH`, no `LD_LIBRARY_PATH` — `Package.swift` detects Linux
automatically (`#if os(Linux)`) and links `CSkia` straight against the
vendored archives, with an `-rpath` baked in (though since everything here
is a static `.a`, nothing is actually loaded at runtime from that path —
it's there in case a future change introduces a shared object).
