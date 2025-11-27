# Umbrifera

Umbrifera is a high-performance Raw Image Processor for macOS, built with C++20, Metal, and ImGui. It features a 16-bit linear floating-point pipeline for professional-grade color grading.

## Features

*   **High Performance:** GPU-accelerated processing using Metal.
*   **Professional Color:** 16-bit Linear Floating Point pipeline.
*   **Raw Support:** Supports a wide range of cameras via LibRaw.

## TODO

*   **AI Denoising & Sharpening:** Implement advanced on-device AI models for high-quality noise reduction and sharpening.

## Build Instructions

### Prerequisites

*   macOS (Metal support required)
*   CMake
*   Xcode Command Line Tools (Clang)

### Cloning

```bash
git clone https://github.com/yourusername/Umbrifera.git
```

## Dependencies

### System Libraries (MacOS)
This project requires the following system libraries to be installed via `brew`:
```bash
brew install libjpeg-turbo libpng libtiff
```

### Managed Dependencies
The following dependencies are automatically downloaded and managed by CMake:
- **GLFW** (3.4)
- **Dear ImGui** (docking branch)
- **LibRaw** (0.21.4)

## Building & Running

```bash
./build.sh
./run.sh
## Dependencies

All external dependencies are located in the `third_party/` directory:
*   **ImGui:** UI framework.
*   **LibRaw:** Raw image decoding.
*   **GLFW:** Window management (fetched automatically via CMake).

