# Imago

Imago is a high-performance Raw Image Processor for macOS, built with C++20, Metal, and ImGui. It features a 16-bit linear floating-point pipeline for professional-grade color grading.

## Features

*   **High Performance:** GPU-accelerated processing using Metal.
*   **Professional Color:** 16-bit Linear Floating Point pipeline.
*   **Raw Support:** Supports a wide range of cameras via LibRaw.

## Planned Features

Features are ranked by implementation difficulty for AI agents (⭐ = Easy, ⭐⭐ = Medium, ⭐⭐⭐ = Hard, ⭐⭐⭐⭐ = Very Hard, ⭐⭐⭐⭐⭐ = Extreme).

> **Note for contributors**: When implementing a feature, remove it from this list after completion.

### UI/UX Improvements

#### ⭐⭐ De-Crop Functionality
When re-entering crop mode via the crop button after a previous crop, allow the user to "undo" or expand back to the original uncropped image boundaries (before any crop was applied).

### Geometric Corrections

#### ⭐⭐⭐⭐ Perspective Controls
Add a perspective correction section (hidden under a toggle to reduce UI clutter) with:
1. **Sliders for manual correction:**
   - Vertical tilt (keystone correction)
   - Horizontal tilt
   - Rotation
   - Horizontal stretch
   - Vertical stretch
   - Barrel/pincushion distortion
2. **Guided correction tool:**
   - Allow drawing up to 4 lines on the image (2 vertical, 2 horizontal)
   - Lines should represent "should be straight/parallel" references
   - Auto-calculate and apply perspective correction to make those lines straight/parallel

### Advanced Features

#### ⭐⭐⭐⭐⭐ Masking System
Implement a masking system similar to Lightroom, allowing selective adjustments:
1. **Mask types:**
   - Linear gradient (define direction and feather)
   - Radial/elliptical gradient
   - Manual brush painting
2. **Mask workflow:**
   - When a mask is active, show all adjustment controls centered on that mask
   - Adjustments only affect the masked region
   - Multiple masks can be stacked
3. **Mask visualization:**
   - Toggle to show mask overlay (red or other color)
   - Mask editing controls

#### ⭐⭐⭐⭐⭐ Lens Correction Database
Integrate automatic lens and camera correction via a database:
1. **Corrections:**
   - Distortion correction (barrel/pincushion)
   - Chromatic aberration removal
   - Vignetting compensation
2. **Implementation:**
   - Large integrated database of lens profiles (consider lensfun library or similar)
   - Auto-detection from EXIF data (camera + lens combo)
   - Single toggle at the beginning of the pipeline to enable/disable
   - Enabled by default
   - **Must be applied pre-crop** (before any cropping is done)

#### ⭐⭐⭐⭐⭐+ Neural Network Demosaicing & Denoising (JDD)
**EXTREME DIFFICULTY** - This is the flagship differentiating feature.

Replace the current LibRaw DHT demosaicing with a neural network-based Joint Demosaicing and Denoising (JDD) approach:
1. **Architecture:**
   - Integrated neural network model that operates on raw Bayer data
   - Simultaneously handles demosaicing and denoising in one pass
   - Must run efficiently on Apple Silicon (Metal Performance Shaders or Core ML)
2. **Goals:**
   - Superior image quality compared to traditional algorithms
   - Excellent noise reduction while preserving detail
   - Fast enough for real-time preview (consider progressive refinement)
3. **Research required:**
   - Investigate state-of-the-art JDD architectures (literature review)
   - Consider training on public raw image datasets
   - May require shipping model weights with the application
4. **This is a major selling point** - "Free, open-source, and AI-powered raw processing"

---

## Build Instructions

### Prerequisites

*   macOS (Metal support required)
*   CMake
*   Xcode Command Line Tools (Clang)

### Cloning

```bash
git clone https://github.com/yourusername/Imago.git
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
```
