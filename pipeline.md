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

The core processing happens in the fragment shader (`fragment_main` in `Shaders.metal`). The input is the normalized Linear sRGB image.

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

### Step 3.3: Saturation & Vibrance
*   **Luma Calculation**: `dot(rgb, float3(0.2126, 0.7152, 0.0722))` (Rec.709 coefficients).
*   **Vibrance**: Smart saturation that boosts muted colors more than already saturated ones.
    *   Calculates current saturation: `(max - min) / max`.
    *   Mixes original color with Luma based on inverse saturation.
*   **Saturation**: Global linear interpolation between Luma (greyscale) and Color.

### Step 3.4: HSL Adjustments (Selective Color)
Allows tweaking Hue, Saturation, and Luminance for specific color ranges.
*   **Color Model**: RGB is converted to HSV.
*   **Slicing**: The Hue circle is divided into 15 slices.
*   **Weighting**: A Gaussian weight is calculated based on the pixel's hue distance from each slice center.
*   **Application**: The weighted adjustments are applied to the pixel's H, S, and V values.
*   **Conversion**: Converted back to RGB.

### Step 3.5: Hue Offset
Global rotation of the hue wheel.
*   Applied in HSV space.

### Step 3.6: Contrast
Adjusts the contrast curve pivoting around mid-grey.
*   **Pivot**: 0.18 (Linear Mid-Grey).
*   **Formula**: `color = (color - 0.18) * contrast + 0.18`.

### Step 3.7: Highlights & Shadows
Recover detail in bright or dark areas using luma masking.
*   **Shadows Mask**: `1.0 - smoothstep(0.0, 0.18, luma)`. Targets darkest tones.
*   **Highlights Mask**: `smoothstep(0.18, 1.0, luma)`. Targets brightest tones.
*   **Application**: Additive adjustment (`color += adjustment * mask`).

### Step 3.8: Whites & Blacks (Levels)
Expands or compresses the dynamic range endpoints.
*   **Black Point**: `-blacks * 0.1`.
*   **White Point**: `1.0 - whites * 0.2`.
*   **Formula**: `color = (color - black_point) / (white_point - black_point)`.

### Step 3.9: Vignette
Darkens the corners of the image.
*   **Shape**: Circular, aspect-ratio corrected (square relative to the crop).
*   **Falloff**: `smoothstep` based on distance from center.

### Step 3.10: Tone Mapping
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

The "Auto" button calculates optimal starting values based on the **Raw Histogram** (computed from the linear raw data immediately after loading).

1.  **Raw Histogram Analysis**: Computes the mean luminance of the linear data.
2.  **Auto Exposure**: Calculates the exposure shift needed to move the mean luminance to a target value (0.18 linear).
3.  **Auto Contrast**: Sets a default boost (1.1).
4.  **Auto Blacks/Whites**:
    *   Estimates the new min/max after exposure shift.
    *   Calculates `blacks` and `whites` slider values to stretch this range to fill 0.0 - 1.0.
5.  **Defaults**: Sets reasonable defaults for Vibrance (0.2) and Saturation (1.0).
