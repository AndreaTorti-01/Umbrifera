# Windows Development & Architecture

This document outlines the architecture, prerequisites, and implementation details for the Windows port of Umbrifera.

## Architecture Overview

The Windows version of Umbrifera uses **Vulkan 1.3** as its graphics and compute backend, replacing the macOS Metal implementation.

### Core Components
- **Graphics API**: Vulkan 1.3
- **Windowing**: GLFW 3 (Win32 native)
- **UI**: Dear ImGui (Vulkan backend)
- **Shaders**: GLSL compiled to SPIR-V via `glslc`
- **Image Processing**: 100% GPU-accelerated via Compute Shaders

### Compute Pipeline
Image processing is handled by a suite of specialized compute shaders:
1.  `process.comp`: Main adjustment pipeline (Exposure, WB, HSL, Clarity, Vignette, etc.)
2.  `histogram.comp`: Luminance histogram computation using shared memory atomics.
3.  `resize.comp`: High-quality weighted average resampling (supports upscaling/downscaling).
4.  `rotate.comp`: Geometric rotation with inscribed rectangle calculation.
5.  `grain.comp`: Multi-layer film grain generation.

### Key Implementation Details

#### Asynchronous Histogram
To maintain 60+ FPS UI responsiveness, the histogram is computed asynchronously:
- **Non-blocking**: The UI thread submits a histogram compute job and continues rendering.
- **Fence Synchronization**: Uses `VkFence` to check if the previous frame's histogram is complete before submitting a new one.
- **Double Buffering**: Results are copied to a `m_HistogramBufferDisplay` to prevent read/write conflicts.
- **Zero Stalls**: No `vkDeviceWaitIdle` or synchronous texture readbacks are performed in the main loop.

#### Resize Engine
The resize tool has been updated to allow unlimited upscaling and downscaling. It uses a weighted-average kernel in `resize.comp` to maintain image quality across all dimensions.

#### Stability & Memory
- **Descriptor Management**: Descriptor sets for compute pipelines are cached and only re-allocated when textures are reloaded (e.g., opening a new image).
- **Resource Locking**: A `std::recursive_mutex m_VulkanResourceMutex` ensures thread safety between the UI thread and async loading threads.

---

## Prerequisites

To build Umbrifera on Windows, the following environment is required:

### 1. Compiler (MSVC)
- **Visual Studio 2022** (or newer) with C++ Desktop Development workload.
- **cl.exe** must be in your system `PATH`.
- **Current Version**: `14.50.35717` (or compatible).

### 2. Vulkan SDK
- **Vulkan SDK 1.3.x** or newer.
- **Environment Variable**: `VULKAN_SDK` must point to the installation directory (e.g., `C:\VulkanSDK\1.4.328.0`).
- **glslc**: The shader compiler must be available in the path.

### 3. Build Tools
- **CMake 3.21+**
- **vcpkg**: Integrated into the build system for dependency management (LibRaw, libjpeg-turbo, etc.).

---

## Build & Run

Use the provided batch scripts in the root directory:

- **Build**: `.\build.bat` (Compiles shaders, runs CMake, and builds the Release executable).
- **Run**: `.\build\Release\Umbrifera.exe`

---

## Recent Fixes (Windows Branch)
- Fixed "VkResult=-4" crash on image reload by properly managing descriptor set lifecycles.
- Eliminated massive UI lag by moving histogram to an asynchronous GPU pipeline.
- Fixed resize tool to allow upscaling beyond original image dimensions.
- Optimized histogram shader with two-level shared memory reduction.
