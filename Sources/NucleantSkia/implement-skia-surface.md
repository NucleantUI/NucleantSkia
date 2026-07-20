

# build skia macos framework

make build script for skia for macos with vulkan support
https://skia.org/docs/user/build/
https://skia.org/docs/user/special/vulkan/



# SkiaCore

i assume there going to be the need to make CSkia target also
but i just prepared where i want most Skia handling atm..


# PyNucleantUI - SkiaShaderNode / SkiaCanvasBase
SulphurXcodeDemo/packages/PyNucleantUI/Sources/PyNucleantUI/RenderEngine/Nodes/SkiaShaderNode.swift
SulphurXcodeDemo/packages/PyNucleantUI/Sources/PyNucleantUI/PyApi/Canvas/SkiaCanvasBase.swift

# SkiaCore + PySwiftKit

just wrap what is needed for SkiaSurfaceCanvasBase to work with it...
maybe some wrap of the Text render part in skia..

# skia-python

like in thorvg-cython maybe allow something that passes SkiaSurface by PyCapsule
to skia-python, and i guess we need to fork it and just make our own modification for now
