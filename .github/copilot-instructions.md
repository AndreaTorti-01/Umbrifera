# Umbrifera AI Coding Instructions

## Project Overview
Umbrifera is a high-performance Raw Image Processor built with C++20, Metal (macOS), and ImGui. It focuses on 16-bit linear floating-point precision for professional-grade color grading.

## Architecture & Organization
- **Monolithic Core:** The `UmbriferaApp` class manages the application lifecycle. Its implementation is split across multiple files by domain:
  - `src/UmbriferaApp.mm`: Lifecycle (Init, Run, Shutdown) and window creation.
  - `src/UmbriferaApp_Render_Metal.mm`: Metal setup, pipeline state, and render loop.
  - `src/UmbriferaApp_UI.mm`: ImGui layout, widget logic, and interaction.
  - `src/UmbriferaApp_Image.mm`: LibRaw integration, async image loading, and export logic.
- **Rendering:** macOS only (Metal).
- **Shader Logic:** All Metal shader code resides in `shaders/Shaders.metal`. This file is copied to the build directory by CMake and loaded at runtime.
- **Data Flow:** 
  - CPU -> GPU communication relies on the `Uniforms` struct. **Crucial:** Ensure the C++ `Uniforms` struct in `include/UmbriferaApp.h` exactly matches the Metal struct in `Shaders.metal` (including padding).

## Rendering Pipeline
1. **Input:** Raw images are decoded via LibRaw into a 16-bit Linear RGBA Metal texture (`m_RawTexture`).
2. **Processing Pass:** A fragment shader applies Exposure -> Saturation/Contrast -> Shadows/Highlights -> Tone Mapping. Output goes to `m_ProcessedTexture`.
3. **Histogram Pass:** A compute shader calculates luminance distribution from `m_ProcessedTexture`.
4. **Display Pass:** ImGui renders the UI, drawing `m_ProcessedTexture` as an image within the window.

## Key Patterns & Conventions
- **Dirty Flag Optimization:** Heavy image processing (Pass 2) only runs when `m_ImageDirty` is true. Set this flag whenever a UI slider changes.
- **Async Loading:** Image loading happens in a detached thread (`m_LoadingThread`). Use `m_TextureUploadPending` to signal the main thread to upload data to the GPU.
- **Tone Mapping:** The pipeline supports multiple tone mappers (ACES, Reinhard, Standard). ACES is the default.
- **UI Layout:** Use `ImGui::BeginChild` for grouping controls. Use `ImGui::GetWindowDrawList()` for custom drawing (e.g., separators) instead of standard ImGui separators when specific styling is needed.
- **Export:** Image export (JPG/PNG/TIFF) is handled in `src/UmbriferaApp_Image.mm` using `libjpeg`, `libpng`, and `libtiff`.

## Build & Workflow
- **Build System:** CMake.
- **Standard Command:** Use `./build.sh && ./run.sh` to compile and run.
- **Shader Updates:** When modifying `shaders/Shaders.metal`, you must re-run the build script (or CMake configure) to copy the updated file to the build directory, or ensure the app loads from source in dev mode.

## Dependencies
- **ImGui:** Fetched via CMake. Used with Docking and Viewports enabled.
- **LibRaw:** Fetched via CMake. Handles raw file parsing.
- **GLFW:** Window management (fetched via CMake).

## Development Process
- **Incremental Development:** Build one small piece at a time and verify it works before moving to the next.
- **Continuous Testing:** Keep running tests (or manual verification) frequently to catch issues early.

## Task Tracking
- **Tasks File:** Maintain a `tasks.md` file in the root directory to track progress, planned features, and known bugs. Update this file as you complete tasks or identify new ones. This replaces the use of temporary notebooks for task tracking.
