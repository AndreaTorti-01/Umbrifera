# Umbrifera

Umbrifera is a high-performance Raw Image Processor for macOS, built with C++20, Metal, and ImGui. It features a 16-bit linear floating-point pipeline for professional-grade color grading.

## Features

*   **High Performance:** GPU-accelerated processing using Metal.
*   **Professional Color:** 16-bit Linear Floating Point pipeline.
*   **Raw Support:** Supports a wide range of cameras via LibRaw.

## Planned Features

Features are ranked by implementation difficulty for AI agents (⭐ = Easy, ⭐⭐ = Medium, ⭐⭐⭐ = Hard, ⭐⭐⭐⭐ = Very Hard, ⭐⭐⭐⭐⭐ = Extreme).

> **Note for contributors**: When implementing a feature, remove it from this list after completion.

### UI/UX Improvements

#### ⭐ Confirm Crop with Enter Key
Allow pressing Enter to confirm and apply the current crop, equivalent to clicking the "Crop" button.

#### ⭐⭐ De-Crop Functionality
When re-entering crop mode via the crop button after a previous crop, allow the user to "undo" or expand back to the original uncropped image boundaries (before any crop was applied).

#### ⭐⭐ Comparison Mode Button
Add a button to the Image Viewer button row that, **while held pressed**, shows the "original" image (with all sliders at their default/zeroed values) for quick before/after comparison. Use the `compare_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png` icon from the assets folder.

#### ⭐⭐ Clipping Indicator Toggle
Add a toggle or small button (location TBD - suggest near histogram or in button bar) that when enabled, overlays the image with:
- **Red** highlighting on overexposed/clipped areas (values at or near maximum)
- **Green** highlighting on underexposed/clipped areas (values at or near minimum)

### Image Processing Adjustments

#### ⭐ Reduce Contrast Slider Sensitivity
Reduce the strength/sensitivity of the contrast slider near the center position (around 1.0). Small movements near the center should produce more subtle changes.

#### ⭐⭐⭐ Color Grading Wheels
Add three color grading wheels for Shadows, Midtones, and Highlights. Each wheel allows the user to shift the color balance for that tonal range. Wheels should have:
- Low sensitivity near the center (fine control)
- Increasing sensitivity toward edges (bolder adjustments)
- Visual representation showing the current color shift

#### ⭐⭐⭐⭐ New HSL System with Eyedropper
Replace the current 15-slice HSL toggle system with a new dynamic approach:
1. Remove the "Enable HSL Controls" toggle
2. Add an eyedropper icon button (use `dropper_eye_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`)
3. When eyedropper is clicked, user can click on the image to sample a hue
4. The sampled area should be center-weighted (pixels near click point contribute more)
5. If the sampled area is colorful enough (saturation above threshold), add a new HSL control group for that hue
6. Each HSL control group shows: Hue shift, Saturation, Luminance, and Gaussian Width (controls how much neighboring hues are affected)
7. Each control group has an "X" button (use `close_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`) to remove it
8. The eyedropper button moves below the active HSL controls list, allowing adding more

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
```
