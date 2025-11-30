# Image Processing Pipeline

This document details the complete image processing pipeline of Umbrifera, from raw file loading to final display.

## 1. Raw Loading (CPU - LibRaw)

The application uses `LibRaw` to decode raw image files (NEF, CR2, RAF, etc.). The goal is to extract the rawest possible data in a linear color space to allow for full control in the GPU shader.

*   **File Handling**: The file is opened using `LibRaw::open_file`.
*   **Demosaicing**: `LibRaw::dcraw_process()` is called. By default, this uses **AHD (Adaptive Homogeneity-Directed)** interpolation for high-quality results.
*   **Color Space**:
    *   `output_color = 1` (sRGB).
    *   `gamm = {1.0, 1.0}` (Linear).
    *   **Result**: The output is **Linear sRGB**. This ensures we work in a standard gamut but with linear light values for correct math.
*   **Bit Depth**: `output_bps = 16`. The output is 16-bit integer data (0-65535) to preserve dynamic range and precision.
*   **White Balance**: `use_camera_wb = 1`. The "As Shot" white balance coefficients from the camera metadata are applied during demosaicing.
*   **Black & White Levels**:
    *   **Black Level**: Automatically subtracted by LibRaw during processing.
    *   **White Level**: LibRaw scales the data so that the white point maps to 65535 (16-bit max).
    *   **Note**: We do *not* apply any manual black subtraction or exposure gain in the C++ code; we rely entirely on LibRaw's correct scaling.

## 2. Texture Upload (CPU -> GPU)

The 16-bit integer RGBA data is uploaded to the GPU as a Metal texture.

*   **Pixel Format**: `MTLPixelFormatRGBA16Unorm`.
*   **Normalization**: Metal automatically normalizes the 16-bit integer values (0-65535) to floating-point values (0.0 - 1.0) when the texture is sampled in the shader.

## 3. Image Processing (GPU - Metal Fragment Shader)

The core processing happens in the fragment shader (`fragment_main` in `Shaders.metal`). The input is the normalized Linear sRGB image with mipmaps pre-generated for local contrast processing.

### Step 3.1: White Balance (Temperature & Tint)
Adjusts the color balance relative to the camera's "As Shot" WB.
*   **Temperature**: Adjusts Red (warm) vs Blue (cool).
    *   `R += temp * 0.5`
    *   `B -= temp * 0.5`
*   **Tint**: Adjusts Green (magenta <-> green).
    *   `G -= tint * 0.5`
*   Applied as a simple RGB gain multiplication.

### Step 3.2: Exposure
Adjusts the overall brightness in linear space.
*   **Formula**: `color *= 2^(exposure + base_exposure)`
*   `base_exposure` is currently 0.0 (since LibRaw handles normalization).

### Step 3.3: Clarity & Texture (Local Contrast Enhancement)
Enhances local contrast at different frequency bands using mipmap-based blur approximation.

#### Resolution Independence
*   **LOD Offset**: `log2(maxDimension / 4000)` ensures consistent visual radius regardless of image resolution.
*   Reference: 4000px image = base LOD, 8000px = +1 LOD, 2000px = -1 LOD.

#### Texture (High-Frequency Detail)
*   **Purpose**: Enhances fine details like skin texture, bark, fabric weave.
*   **Radius**: ~10-25 pixels equivalent at 4000px image, using LOD ~2.0 + offset (clamped 0.5-6).
*   **Algorithm**:
    1.  Sample blurred version from adaptive mipmap level
    2.  Extract per-channel detail: `detail = color - blurred_color`
    3.  Apply luminance protection to avoid artifacts in extreme highlights/shadows
    4.  Soft-clip with tanh-like response per channel
    5.  Add detail back: `color += detail_adjusted` (additive, luminance-stable)
*   **Range**: -1.0 (smoothing) to +1.0 (enhancement)

#### Clarity (Mid-Frequency Structure)
*   **Purpose**: Enhances larger structures like facial features, fabric folds, architectural details.
*   **Radius**: ~100-300 pixels equivalent at 4000px image, using LOD ~6.0 + offset (clamped 3-10).
*   **Algorithm**:
    1.  Sample blurred version from adaptive mipmap level
    2.  Extract mid-frequency detail: `detail = current_luma - blurred_luma`
    3.  Apply edge-aware masking to minimize halos near strong edges
    4.  Focus effect on midtones (parabolic mask)
    5.  Soft-clip with tanh-like response
    6.  Scale RGB proportionally: `color *= new_luma / current_luma`
*   **Range**: -1.0 (softening) to +1.0 (enhancement)
*   **Halo Prevention**: Edge strength detection reduces effect near strong luminance transitions.

### Step 3.4: Saturation & Vibrance
*   **Luma Calculation**: `dot(rgb, float3(0.2126, 0.7152, 0.0722))` (Rec.709 coefficients).
*   **Vibrance**: Smart saturation that boosts muted colors more than already saturated ones.
    *   Calculates current saturation: `(max - min) / max`.
    *   Mixes original color with Luma based on inverse saturation.
*   **Saturation**: Global linear interpolation between Luma (greyscale) and Color.

### Step 3.5: HSL Adjustments (Selective Color)
Allows tweaking Hue, Saturation, and Luminance for specific color ranges.
*   **Color Model**: RGB is converted to HSV.
*   **Slicing**: The Hue circle is divided into 15 slices.
*   **Weighting**: A Gaussian weight is calculated based on the pixel's hue distance from each slice center.
*   **Application**: The weighted adjustments are applied to the pixel's H, S, and V values.
*   **Conversion**: Converted back to RGB.

### Step 3.6: Hue Offset
Global rotation of the hue wheel.
*   Applied in HSV space.

### Step 3.7: Contrast
Adjusts the contrast curve pivoting around mid-grey.
*   **Pivot**: 0.18 (Linear Mid-Grey).
*   **Formula**: `color = (color - 0.18) * contrast + 0.18`.

### Step 3.8: Tonal Controls (Blacks, Shadows, Highlights, Whites)
Four equidistant tonal controls with Gaussian falloff, similar to HSL adjustments.

#### Control Centers (in normalized luminance 0-1)
*   **Blacks**: 0.0 (pure black)
*   **Shadows**: 0.333 (dark tones)
*   **Highlights**: 0.667 (bright tones)
*   **Whites**: 1.0 (pure white)

#### Gaussian Falloff
*   **Sigma**: 0.142, calculated so that at half-distance (0.167) between centers, influence = 50%
*   **Formula**: `weight = exp(-distance² / (2 * σ²))` where `1/(2σ²) = 24.85`

#### Application
*   All four controls are additive adjustments weighted by their Gaussian falloff
*   **Blacks/Whites multiplier**: 0.15 (endpoint controls, stronger effect)
*   **Shadows/Highlights multiplier**: 0.12 (midtone controls, balanced effect)
*   **Formula**: `color += (blacks*0.15*blacksWeight + shadows*0.12*shadowsWeight + highlights*0.12*highlightsWeight + whites*0.15*whitesWeight)`

### Step 3.9: Vignette
Darkens the corners of the image.
*   **Shape**: Circular, aspect-ratio corrected (square relative to the crop).
*   **Falloff**: `smoothstep` based on distance from center.

### Step 3.11: Tone Mapping
Compresses the high dynamic range (linear) into the displayable range (0.0 - 1.0).
*   **Standard Gamma**: Simple saturation (clipping) followed by `linear_to_srgb` (approx. Gamma 2.2).
*   *Note: Previous ACES and Reinhard tone mapping options have been removed in favor of a pure standard gamma workflow.*

## 4. Histogram (GPU - Compute Shader)

Calculates the luminance distribution for the UI.
*   **Input**: The processed image (sRGB).
*   **Luma**: Perceptual luma using Rec.709 coefficients.
*   **Binning**: 256 bins.
*   **Method**: Atomic addition in a compute shader.

## 5. Resize (GPU - Compute Shader)

High-quality image resizing using box filter (area averaging).

*   **Algorithm**: Box filter with sub-pixel precision - the mathematically correct method for downsampling.
*   **Principle**: Each output pixel is computed as the weighted average of all source pixels that contribute to its area.
*   **Weight Calculation**: The weight of each source pixel is proportional to its overlap area with the destination pixel's footprint.
*   **Implementation**: Metal compute shader (`box_downscale`) calculates exact overlap for each source/destination pixel pair.
*   **Color Space**: Works in linear space (RGBA16Unorm) for physically correct color blending without artifacts.
*   **Constraint**: Only downscaling is supported (output dimensions ≤ input dimensions).
*   **Aspect Ratio**: Locked - changing width automatically adjusts height and vice versa.

## 6. Auto Adjust Logic

The "Auto" button calculates optimal starting values based on the **Raw Histogram** (computed from the linear raw data immediately after loading). The goal is a natural look that respects the image's intended brightness - dark images stay dark, bright images stay bright.

1.  **Raw Histogram Analysis**: 
    *   Computes mean luminance
    *   Finds robust min/max using 0.5th and 99.5th percentiles (ignores outliers)
2.  **Auto Exposure** (Conservative):
    *   Calculates full exposure shift to reach 0.18 (linear mid-grey)
    *   Applies only 60% of the correction to preserve intended brightness
    *   Clamped to ±2.5 stops
3.  **Auto Contrast**: Gentle boost (1.05) for subtle definition.
4.  **Auto Blacks/Whites** (Additive Model):
    *   Estimates new min/max after exposure shift
    *   **Blacks**: Darkened if newMin > 0.02 (headroom exists), scale ~5x
    *   **Whites**: Brightened if newMax < 0.95 (headroom exists), scale ~2.5x
5.  **Shadows/Highlights**: Reset to 0 - left for user creative control
6.  **Auto Vibrance**: Modest boost (0.1) for natural colors
7.  **Resets**: Temperature, Tint, Clarity, Texture, Shadows, Highlights set to neutral (0.0)
