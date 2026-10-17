//
//  cskia_noexcept.cpp
//  CSkia — the browser's C++ exception entry points, for a CSkia built with
//  exceptions on.
//
//  The wasm Swift SDK's libc++abi has no exception runtime, and Skia is built
//  with -fno-exceptions, where a throw in libc++ aborts. Over the prebuilt
//  Skia, CSkia is built without unsafeFlags, so without -fno-exceptions: its
//  inline libc++ code then calls these two to throw. Each aborts, as the
//  -fno-exceptions build does. Weak, so a module that does have the runtime
//  keeps its own.
//
#if defined(__wasm__)

#include <cstddef>
#include <cstdlib>

extern "C" __attribute__((weak)) void *__cxa_allocate_exception(std::size_t) {
    std::abort();
}

extern "C" __attribute__((weak)) void __cxa_throw(void *, void *, void (*)(void *)) {
    std::abort();
}

#endif
