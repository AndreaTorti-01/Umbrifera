#include <metal_stdlib>
using namespace metal;

// Vertex Output Structure
// Passed from Vertex Shader to Fragment Shader
struct VertexOut {
    float4 position [[position]]; // Screen position
    float2 uv;                    // Texture coordinate
};

// Vertex Shader
// Generates a full-screen quad (2 triangles) without using a vertex buffer.
vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
    // Positions for a full-screen quad (Clip Space: -1 to 1)
    const float2 vertices[] = {
        {-1, -1}, {1, -1}, {-1, 1},
        {1, -1}, {1, 1}, {-1, 1}
    };
    float2 pos = vertices[vertexID];
    VertexOut out;
    out.position = float4(pos, 0, 1);
    
    // Map position (-1 to 1) to UV coordinates (0 to 1)
    out.uv = pos * 0.5 + 0.5;
    out.uv.y = 1.0 - out.uv.y; // Flip Y for Metal texture coordinates
    return out;
}

// Uniforms: Parameters sent from CPU to GPU
struct Uniforms {
    float exposure;
    float contrast;
    float highlights;
    float shadows;
    float whites;
    float blacks;
    float saturation;
    float vibrance;
    float hue_offset;
    float temperature;
    float tint;
    float vignette_strength;
    float vignette_feather;
    float vignette_size;
    float grain_amount;
    float grain_size;
    float clarity;       // Mid-frequency local contrast
    float texture_amt;   // High-frequency detail enhancement
    float base_exposure;
    
    // Constants
    float contrast_pivot;
    float blacks_scale;
    float whites_scale;
    
    // HSL Adjustments
    int hsl_enabled;
    float4 hsl_adjustments[15]; // x=Hue, y=Sat, z=Lum
    
    float padding[3];
};

// ... (Helpers remain same)

// Helper: Gaussian weight
float gaussian_weight(float distance, float sigma) {
    return exp(-(distance * distance) / (2.0 * sigma * sigma));
}

// Fragment Shader


// Helper: sRGB to Linear conversion (approximate)
float3 srgb_to_linear(float3 c) {
    return pow(c, 2.2);
}

// Helper: Linear to sRGB conversion (approximate)
float3 linear_to_srgb(float3 c) {
    return pow(c, 1.0/2.2);
}

// Tone Mapping Functions Removed

// Helper: RGB to HSV
float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Helper: HSV to RGB
float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Helper: RGB Hue Rotation using rotation matrix
// Rotates hue in RGB space without color space conversion (avoids precision loss)
// Angle in range [0, 1] where 1 = 360 degrees
float3 rotate_hue_rgb(float3 rgb, float angle) {
    // Angle in radians
    float theta = angle * 6.28318530718; // 2*pi
    
    // Rotation axis: (1, 1, 1) normalized
    float3 axis = normalize(float3(1.0, 1.0, 1.0));
    
    // Rodrigues' rotation formula: v_rot = v*cos(θ) + (k × v)*sin(θ) + k*(k·v)*(1-cos(θ))
    float cosA = cos(theta);
    float sinA = sin(theta);
    float oneMinusCos = 1.0 - cosA;
    
    // k · v
    float dotProduct = dot(axis, rgb);
    
    // k × v (cross product)
    float3 cross = float3(
        axis.y * rgb.z - axis.z * rgb.y,
        axis.z * rgb.x - axis.x * rgb.z,
        axis.x * rgb.y - axis.y * rgb.x
    );
    
    // Apply Rodrigues' formula
    float3 rotated = rgb * cosA + cross * sinA + axis * dotProduct * oneMinusCos;
    
    return rotated;
}
// Helper: High Quality Hash (Dave Hoskins)
// Replaces the problematic sine-based rand
float hash12(float2 p) {
    float3 p3  = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Hash with 3 input values (for temporal variation)
float hash13(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.x + p.y) * p.z);
}

// Hash returning 3 values (for chromatic grain)
float3 hash32(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yzz) * p3.zyx);
}

// Hash with temporal seed returning 3 values
float3 hash33(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yzz) * p.zyx);
}

// --- Simplex Noise Implementation ---
// Description : Array and textureless GLSL 2D simplex noise function.
//      Author : Ian McEwan, Ashima Arts.
//  Maintainer : stegu
//     Lastmod : 20110822 (ijm)
//     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
//               Distributed under the MIT License. See LICENSE file.
//               https://github.com/ashima/webgl-noise
//

float3 mod289(float3 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

float2 mod289(float2 x) {
  return x - floor(x * (1.0 / 289.0)) * 289.0;
}

float3 permute(float3 x) {
  return mod289(((x*34.0)+1.0)*x);
}

float snoise(float2 v)
{
  const float4 C = float4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                      0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                     -0.577350269189626,  // -1.0 + 2.0 * C.x
                      0.024390243902439); // 1.0 / 41.0
// First corner
  float2 i  = floor(v + dot(v, C.yy) );
  float2 x0 = v -   i + dot(i, C.xx);

// Other corners
  float2 i1;
  //i1.x = step( x0.y, x0.x ); // x0.x > x0.y ? 1.0 : 0.0
  //i1.y = 1.0 - i1.x;
  i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
  // x0 = x0 - 0.0 + 0.0 * C.xx ;
  // x1 = x0 - i1 + 1.0 * C.xx ;
  // x2 = x0 - 1.0 + 2.0 * C.xx ;
  float4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;

// Permutations
  i = mod289(i); // Avoid truncation effects in permutation
  float3 p = permute( permute( i.y + float3(0.0, i1.y, 1.0 ))
        + i.x + float3(0.0, i1.x, 1.0 ));

  float3 m = max(0.5 - float3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
  m = m*m ;
  m = m*m ;

// Gradients: 41 points uniformly over a line, mapped onto a diamond.
// The ring size 17*17 = 289 is close to a multiple of 41 (41*7 = 287)

  float3 x = 2.0 * fract(p * C.www) - 1.0;
  float3 h = abs(x) - 0.5;
  float3 ox = floor(x + 0.5);
  float3 a0 = x - ox;

// Normalise gradients implicitly by scaling m
// Approximation of: m *= inversesqrt( a0*a0 + h*h );
  m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );

// Compute final noise value at P
  float3 g;
  g.x  = a0.x  * x0.x  + h.x  * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

// --- Film Grain Multi-Layer System ---
// Emulates 35mm negative film grain with physically-based luminance response

// Worley noise (cellular) for clumpy grain structure
// Returns distance to nearest cell center (F1)
float worley(float2 p, float time) {
    float2 ip = floor(p);
    float2 fp = fract(p);
    float d = 1.0;
    
    // Search 3x3 neighborhood
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 offset = float2(x, y);
            // Jitter cell center using hash with temporal variation
            float2 cellCenter = hash32(float2(ip + offset) + time * 0.01).xy;
            float2 diff = offset + cellCenter - fp;
            d = min(d, dot(diff, diff));
        }
    }
    return sqrt(d);
}

// Multi-octave value noise for organic texture
float valueNoise(float2 p, float time) {
    float2 ip = floor(p);
    float2 fp = fract(p);
    
    // Smooth interpolation
    float2 u = fp * fp * (3.0 - 2.0 * fp);
    
    // Hash corners with temporal seed
    float3 seed = float3(ip, time);
    float a = hash13(seed + float3(0, 0, 0));
    float b = hash13(seed + float3(1, 0, 0));
    float c = hash13(seed + float3(0, 1, 0));
    float d = hash13(seed + float3(1, 1, 0));
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Grain generation parameters
struct GrainParams {
    uint width;
    uint height;
    float grainSize;
    float seed;  // Random seed for this grain pattern
};

// Compute shader: Generate film grain texture
// Generates a static grain pattern that can be overlaid with exposure-weighting at render time
// Output: RGBA16Float where:
//   R = Layer A (large grain)
//   G = Layer B (medium grain)  
//   B = Layer C (fine grain)
//   A = Chromatic variation seed
kernel void generate_grain(
    texture2d<float, access::write> grainTexture [[texture(0)]],
    constant GrainParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= params.width || gid.y >= params.height) return;
    
    float2 uv = float2(gid) / float2(params.width, params.height);
    float2 scaledUV = float2(gid) * params.grainSize;
    float seed = params.seed;
    
    // === Layer A: Large, soft "base" grain ===
    // Represents largest silver-halide crystals in slower emulsion layers
    float worleyNoise = worley(scaledUV * 0.08, seed);
    float layerA = valueNoise(scaledUV * 0.1, seed) * 0.5 + 0.5;
    layerA = layerA * 0.7 + worleyNoise * 0.3;
    layerA = (layerA - 0.5) * 2.0; // Center around 0, range ~[-1, 1]
    
    // === Layer B: Medium grain (main visible 35mm grain) ===
    float snoise1 = snoise(scaledUV * 0.25 + seed * 100.0) * 0.5;
    float snoise2 = snoise(scaledUV * 0.35 - seed * 50.0) * 0.35;
    float layerB = snoise1 + snoise2; // Range ~[-0.85, 0.85]
    
    // === Layer C: Fine grain / chemical speckling ===
    float3 fineHash = hash33(float3(scaledUV, seed));
    float layerC = (fineHash.x - 0.5) * 2.0;
    float3 fineHash2 = hash33(float3(scaledUV + float2(0.5, 0.0), seed));
    float3 fineHash3 = hash33(float3(scaledUV + float2(0.0, 0.5), seed));
    layerC = layerC * 0.6 + (fineHash2.x + fineHash3.x - 1.0) * 0.4; // Range ~[-1, 1]
    
    // === Chromatic variation seed ===
    // Store a hash value that will be used to derive chromatic offsets at render time
    float chromaSeed = hash13(float3(scaledUV * 0.5, seed + 100.0));
    
    // Normalize layers to [0, 1] range for storage (will be unpacked in fragment shader)
    // Layer A, B, C are in ~[-1, 1], map to [0, 1]
    float4 grainData = float4(
        layerA * 0.5 + 0.5,  // Large grain
        layerB * 0.5 + 0.5,  // Medium grain
        layerC * 0.5 + 0.5,  // Fine grain
        chromaSeed           // Chromatic seed
    );
    
    grainTexture.write(grainData, gid);
}

// Fragment Shader
// Runs for every pixel on the screen.
// It reads the input image, applies exposure, and outputs the color.
fragment float4 fragment_main(VertexOut in [[stage_in]], 
                            constant Uniforms& uniforms [[buffer(0)]],
                            texture2d<float> inputTexture [[texture(0)]],
                            texture2d<float> grainTexture [[texture(1)]]) {
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear, address::clamp_to_zero);
    constexpr sampler mipSampler (mag_filter::linear, min_filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler grainSampler (mag_filter::nearest, min_filter::nearest, address::repeat);
    
    // 1. Sample the texture
    // The input texture is 16-bit Linear RGB (from LibRaw)
    float4 color = inputTexture.sample(textureSampler, in.uv);
    
    // --- 1. White Balance ---
    // Apply Temp/Tint
    // Temp: Blue <-> Yellow (Adjust B and R)
    // Tint: Green <-> Magenta (Adjust G)
    // Simple gain model
    float3 wb_gains = float3(1.0, 1.0, 1.0);
    
    // Temperature: Positive = Warmer (More Red, Less Blue), Negative = Cooler (Less Red, More Blue)
    // Range -1 to 1 roughly
    wb_gains.r += uniforms.temperature * 0.5; // Scale factor to make slider feel right
    wb_gains.b -= uniforms.temperature * 0.5;
    
    // Tint: Positive = Magenta (More R+B, Less G?), Negative = Green (More G)
    // Actually standard tint: Positive = Magenta, Negative = Green.
    // Green channel gain gain is usually inverse of tint.
    wb_gains.g -= uniforms.tint * 0.5;
    
    // Apply WB
    color.rgb *= wb_gains;
    
    // --- 2. Exposure ---
    // Apply Exposure (Linear Space)
    // Combine user exposure with base exposure (normalization)
    color.rgb *= pow(2.0, uniforms.exposure + uniforms.base_exposure);
    
    // --- 2.5. Clarity & Texture (Local Contrast Enhancement) ---
    // Clarity: Mid-frequency contrast (larger structures, ~100-300px radius equivalent)
    // Texture: High-frequency detail (fine details, ~10-25px radius equivalent)
    // Uses local contrast enhancement preserving color ratios to avoid desaturation
    
    if (abs(uniforms.clarity) > 0.001 || abs(uniforms.texture_amt) > 0.001) {
        float origLuma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        
        // Calculate LOD offset based on image size for resolution-independent behavior
        // Target: consistent visual radius regardless of megapixels
        // Reference: 4000px image = LOD 0 offset, 8000px = +1 LOD, 2000px = -1 LOD
        float maxDim = max(float(inputTexture.get_width()), float(inputTexture.get_height()));
        float lodOffset = log2(maxDim / 4000.0);
        
        // Texture: High-frequency detail extraction
        // Target ~10-25px blur radius at 4000px image (finer than clarity)
        if (abs(uniforms.texture_amt) > 0.001) {
            float textureLod = 2.0 + lodOffset; // ~4px at LOD 2 * 2^offset
            textureLod = clamp(textureLod, 0.5, 6.0);
            
            // Sample blurred version
            float3 textureBlur = inputTexture.sample(mipSampler, in.uv, level(textureLod)).rgb;
            
            // Work in color space: extract detail per channel, apply to each
            // This preserves hue while enhancing local contrast
            float3 textureDetail = color.rgb - textureBlur;
            
            // Luminance protection: reduce effect in extreme highlights/shadows
            float lumaProtect = smoothstep(0.0, 0.08, origLuma) * smoothstep(1.2, 0.85, origLuma);
            float textureStrength = uniforms.texture_amt * 0.7 * lumaProtect;
            
            // Apply detail enhancement with soft limiting per channel
            float3 textureAdjust = textureDetail * textureStrength;
            textureAdjust = textureAdjust / (1.0 + abs(textureAdjust) * 3.0);
            
            // Add back to color - this is luminance-stable because we're adding
            // the high-frequency component back, not scaling
            color.rgb += textureAdjust;
        }
        
        // Clarity: Mid-frequency structure enhancement
        // Target ~100-300px blur radius at 4000px image
        if (abs(uniforms.clarity) > 0.001) {
            float clarityLod = 6.0 + lodOffset; // ~64px at LOD 6 * 2^offset
            clarityLod = clamp(clarityLod, 3.0, 10.0);
            
            // Sample blurred version
            float3 clarityBlur = inputTexture.sample(mipSampler, in.uv, level(clarityLod)).rgb;
            
            // Recalculate current luma after texture adjustment
            float currentLuma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
            
            // Work in color space like texture: extract per-channel detail
            float3 clarityDetail = color.rgb - clarityBlur;
            
            // Edge-aware masking: reduce effect near strong edges to minimize halos
            float detailMagnitude = length(clarityDetail);
            float edgeMask = 1.0 - smoothstep(0.1, 0.4, detailMagnitude);
            
            // Midtone focus: clarity affects midtones more than extremes
            float midtoneMask = 4.0 * currentLuma * (1.0 - saturate(currentLuma));
            midtoneMask = pow(midtoneMask, 0.5);
            
            float clarityStrength = uniforms.clarity * 0.8 * midtoneMask * (0.3 + 0.7 * edgeMask);
            
            // Apply detail enhancement with soft limiting per channel
            float3 clarityAdjust = clarityDetail * clarityStrength;
            clarityAdjust = clarityAdjust / (1.0 + abs(clarityAdjust) * 2.0);
            
            // Additive approach - luminance stable
            color.rgb += clarityAdjust;
        }
    }
    
    // --- 3. Lighting & Color ---
    
    // Saturation & Vibrance
    float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    // Vibrance
    // Boosts saturation of less saturated pixels more
    // Calculate current saturation
    float max_comp = max(color.r, max(color.g, color.b));
    float min_comp = min(color.r, min(color.g, color.b));
    float sat = (max_comp - min_comp) / (max_comp + 0.0001);
    
    // Vibrance factor: stronger effect on low saturation
    float vibrance_factor = 1.0 + uniforms.vibrance * (1.0 - sat);
    color.rgb = mix(float3(luma), color.rgb, vibrance_factor);
    
    // Saturation (Global)
    // Re-calculate luma as it might have changed
    luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(float3(luma), color.rgb, uniforms.saturation);
    
    // HSL Adjustments (Selective Color)
    if (uniforms.hsl_enabled != 0) {
        float3 hsv = rgb2hsv(color.rgb);
        float hue = hsv.x; // 0.0 to 1.0
        float sat = hsv.y;
        float val = hsv.z;
        
        float4 total_adj = float4(0.0);
        float total_weight = 0.0;
        
        // Iterate over all 15 slices
        for (int i = 0; i < 15; i++) {
            float slice_hue = float(i) / 15.0;
            
            // 1. Hue Distance (Circular)
            float distH = abs(hue - slice_hue);
            if (distH > 0.5) distH = 1.0 - distH;
            
            // 2. Saturation Distance (Target: 1.0)
            // Falloff as saturation decreases
            float distS = 1.0 - sat;
            
            // 3. Value/Luminance Distance (Target: 1.0)
            // Falloff as value decreases (darker pixels)
            float distV = 1.0 - val;
            
            // Combined Gaussian Weight
            // Sigma H: Controls hue width (overlap)
            // Sigma S: Controls saturation falloff (how much it affects low sat)
            // Sigma V: Controls luminance falloff (how much it affects darks)
            
            float sigmaH = 0.028;
            float saturation_threshold = 0.2;
            float saturation_min = 0.0;
            
            float wH = gaussian_weight(distH, sigmaH);
            float wS = smoothstep(saturation_min, saturation_threshold, sat);
            float wV = 1.0;
            
            // Combined weight
            float w = wH * wS * wV;
            
            total_adj += uniforms.hsl_adjustments[i] * w;
            total_weight += w;
            
        }
        
        if (total_weight > 0.001) {
            float4 adj = total_adj / total_weight;
            
            // Apply Hue Shift using RGB rotation (avoids precision loss)
            if (abs(adj.x) > 0.001) {
                color.rgb = rotate_hue_rgb(color.rgb, adj.x);
            }
            
            // Recalculate HSV after hue rotation
            hsv = rgb2hsv(color.rgb);
            
            // Apply Saturation Shift
            hsv.y = saturate(hsv.y + adj.y);
            
            // Apply Luminance Shift
            hsv.z = max(0.0, hsv.z + adj.z);
            
            color.rgb = hsv2rgb(hsv);
        }
    }
    
    // Hue Offset (Global)
    // Uses RGB-space rotation to avoid precision loss from color space conversion
    if (abs(uniforms.hue_offset) > 0.001) {
        color.rgb = rotate_hue_rgb(color.rgb, uniforms.hue_offset);
    }
    
    // Contrast
    // Pivot around mid-grey (0.18)
    color.rgb = (color.rgb - uniforms.contrast_pivot) * uniforms.contrast + uniforms.contrast_pivot;
    
    // --- Tonal Controls with Gaussian Falloff ---
    // Four equidistant control points in PERCEPTUAL (gamma) space:
    // Blacks: 0.0, Shadows: 0.333, Highlights: 0.667, Whites: 1.0
    // We must convert linear luma to perceptual space for correct weighting
    // Sigma = 0.142 ensures 50% influence at half-distance (0.167) between centers
    // Gaussian: exp(-d²/(2σ²)) where σ = 0.142
    // Precomputed: 1/(2σ²) = 24.85
    
    luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    // Convert to perceptual space (approximate gamma 2.2)
    float percLuma = pow(saturate(luma), 1.0/2.2);
    
    float invTwoSigmaSq = 24.85; // 1 / (2 * 0.142²)
    
    // Blacks (center = 0.0 in perceptual space)
    float blacksDist = percLuma - 0.0;
    float blacksWeight = exp(-blacksDist * blacksDist * invTwoSigmaSq);
    
    // Shadows (center = 0.333 in perceptual space)
    float shadowsDist = percLuma - 0.333;
    float shadowsWeight = exp(-shadowsDist * shadowsDist * invTwoSigmaSq);
    
    // Highlights (center = 0.667 in perceptual space)
    float highlightsDist = percLuma - 0.667;
    float highlightsWeight = exp(-highlightsDist * highlightsDist * invTwoSigmaSq);
    
    // Whites (center = 1.0 in perceptual space)
    float whitesDist = percLuma - 1.0;
    float whitesWeight = exp(-whitesDist * whitesDist * invTwoSigmaSq);
    
    // Apply adjustments - all additive with Gaussian weighting
    // Uniform multiplier for all controls now that space is correct
    float tonalAdjust = 0.0;
    tonalAdjust += uniforms.blacks * 0.12 * blacksWeight;
    tonalAdjust += uniforms.shadows * 0.12 * shadowsWeight;
    tonalAdjust += uniforms.highlights * 0.12 * highlightsWeight;
    tonalAdjust += uniforms.whites * 0.12 * whitesWeight;
    
    color.rgb += tonalAdjust;
    
    // --- 4. Effects ---
    
    // Vignette
    // Post-crop, square proportions
    // Calculate UV relative to center
    float2 uv_centered = in.uv - 0.5;
    
    // Correct aspect ratio for "square" vignette
    float aspect = float(inputTexture.get_width()) / float(inputTexture.get_height());
    uv_centered.x *= aspect;
    
    float dist = length(uv_centered);
    
    // Vignette parameters
    // Strength: 0 (no vignette) to 1 (black corners)
    // Size: How far from center it starts. 0 = close to center, 1 = far.
    // Feather: Softness.
    
    // Map user params to math
    // User Size: 0 (small hole) -> 1 (large hole).
    // Let's say default size (0.5) puts the edge at corners.
    // Radius of vignette start
    float radius = uniforms.vignette_size * 0.8; // Scale to reasonable range
    
    // Feather
    float feather = uniforms.vignette_feather * 0.5 + 0.01; // Avoid 0
    
    // Calculate vignette factor
    // smoothstep(radius, radius + feather, dist)
    // We want 1.0 at center, 0.0 at outside
    float vignette = 1.0 - smoothstep(radius, radius + feather, dist);
    
    // Apply strength (mix with 1.0)
    // Strength 0 -> factor 1.0 everywhere. Strength 1 -> factor vignette.
    vignette = mix(1.0, vignette, uniforms.vignette_strength);
    
    color.rgb *= vignette;
    
    // Film Grain (35mm Negative Film Emulation)
    // Uses pre-computed grain texture with exposure-weighted overlay
    if (uniforms.grain_amount > 0.001) {
        // Sample pre-computed grain texture
        // The grain texture tiles across the image at 1:1 pixel ratio
        float2 grainUV = in.uv * float2(inputTexture.get_width(), inputTexture.get_height()) 
                       / float2(grainTexture.get_width(), grainTexture.get_height());
        float4 grainData = grainTexture.sample(grainSampler, grainUV);
        
        // Unpack grain layers from [0,1] back to [-1,1] range
        float layerA = (grainData.r - 0.5) * 2.0;  // Large grain
        float layerB = (grainData.g - 0.5) * 2.0;  // Medium grain
        float layerC = (grainData.b - 0.5) * 2.0;  // Fine grain
        float chromaSeed = grainData.a;
        
        // === Exposure-weighted grain response (computed at render time) ===
        // This allows adjustments to exposure/contrast to affect grain visibility
        float grainLuma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        float percLuma = pow(saturate(grainLuma), 1.0/2.2);
        
        // Shadow boost increases with amount (higher ISO = grainier shadows)
        float shadowBoost = mix(1.0, 1.8, uniforms.grain_amount);
        // Grain response curve: strong in shadows, falls off in highlights
        float grainResponse = pow(1.0 - percLuma, 1.5) * shadowBoost;
        // Add baseline so midtones still have some grain
        grainResponse = mix(0.3, grainResponse, smoothstep(0.0, 0.5, 1.0 - percLuma));
        // Reduce grain in pure highlights
        grainResponse *= smoothstep(1.0, 0.85, percLuma);
        
        // === Layer weighting based on amount ===
        float wA = mix(0.15, 0.35, uniforms.grain_amount);
        float wB = mix(0.35, 0.45, uniforms.grain_amount);
        float wC = mix(0.50, 0.20, uniforms.grain_amount);
        
        // Combine layers with weights
        float grainMono = layerA * wA + layerB * wB + layerC * wC;
        grainMono *= grainResponse;
        
        // Grain intensity scaling
        float grainStrength = uniforms.grain_amount * 0.15;
        
        // Apply monochrome grain
        color.rgb += grainMono * grainStrength;
        
        // === Chromatic grain from seed ===
        // Derive subtle color offsets from the chromaSeed
        float chromaAmount = mix(0.01, 0.04, uniforms.grain_amount);
        float3 chromaOffset;
        chromaOffset.r = (fract(chromaSeed * 127.1) - 0.5) * 2.0 * chromaAmount;
        chromaOffset.g = (fract(chromaSeed * 269.5) - 0.5) * 2.0 * chromaAmount * 0.8;
        chromaOffset.b = (fract(chromaSeed * 419.2) - 0.5) * 2.0 * chromaAmount * 0.9;
        
        color.rgb += chromaOffset * grainResponse * grainStrength;
    }
    
    // --- 5. Tone Mapping ---
    // Tone Mapping (Standard Gamma only)
    color.rgb = max(color.rgb, float3(0.0));
    
    // Standard (Gamma 2.2 approximation)
    color.rgb = saturate(color.rgb);
    color.rgb = linear_to_srgb(color.rgb);
    
    return float4(color.rgb, 1.0);
}

// Compute Shader: Histogram
// Calculates the luminance distribution of the image.
kernel void histogram_main(texture2d<float, access::read> inputTexture [[texture(0)]],
                         device atomic_uint* histogramBuffer [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    
    // Check bounds
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) {
        return;
    }
    
    // Read pixel
    float4 color = inputTexture.read(gid);
    
    // Calculate Luminance (Perceptual Weighting: Rec.709)
    // Input color is already sRGB (from fragment shader), so this luma is perceptual.
    float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    // Calculate bin index (0-255)
    // Linear X-axis mapping dark -> light
    uint bin = uint(saturate(luma) * 255.0);
    
    // Atomic increment
    atomic_fetch_add_explicit(&histogramBuffer[bin], 1, memory_order_relaxed);
}

// Downscale parameters passed via buffer
struct DownscaleParams {
    uint srcWidth;
    uint srcHeight;
    uint dstWidth;
    uint dstHeight;
};

// Compute Shader: Box Filter Downscale (Area Averaging)
// This is the mathematically correct way to downsample images.
// Each output pixel is the weighted average of all source pixels that contribute to it.
// Works in linear space for physically correct color blending.
kernel void box_downscale(texture2d<float, access::read> srcTexture [[texture(0)]],
                          texture2d<float, access::write> dstTexture [[texture(1)]],
                          constant DownscaleParams& params [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    
    // Check bounds
    if (gid.x >= params.dstWidth || gid.y >= params.dstHeight) {
        return;
    }
    
    // Calculate the source region that maps to this destination pixel
    float scaleX = float(params.srcWidth) / float(params.dstWidth);
    float scaleY = float(params.srcHeight) / float(params.dstHeight);
    
    // Source region bounds (floating point)
    float srcX0 = float(gid.x) * scaleX;
    float srcY0 = float(gid.y) * scaleY;
    float srcX1 = float(gid.x + 1) * scaleX;
    float srcY1 = float(gid.y + 1) * scaleY;
    
    // Integer bounds for iteration
    int ix0 = int(floor(srcX0));
    int iy0 = int(floor(srcY0));
    int ix1 = int(ceil(srcX1));
    int iy1 = int(ceil(srcY1));
    
    // Accumulate weighted color
    float4 colorSum = float4(0.0);
    float weightSum = 0.0;
    
    // Iterate over all source pixels that overlap with this destination pixel
    for (int sy = iy0; sy < iy1; sy++) {
        if (sy < 0 || sy >= int(params.srcHeight)) continue;
        
        // Calculate vertical overlap
        float overlapY0 = max(float(sy), srcY0);
        float overlapY1 = min(float(sy + 1), srcY1);
        float wy = overlapY1 - overlapY0;
        
        for (int sx = ix0; sx < ix1; sx++) {
            if (sx < 0 || sx >= int(params.srcWidth)) continue;
            
            // Calculate horizontal overlap
            float overlapX0 = max(float(sx), srcX0);
            float overlapX1 = min(float(sx + 1), srcX1);
            float wx = overlapX1 - overlapX0;
            
            // Weight is the area of overlap
            float weight = wx * wy;
            
            // Read source pixel and accumulate
            float4 sample = srcTexture.read(uint2(sx, sy));
            colorSum += sample * weight;
            weightSum += weight;
        }
    }
    
    // Normalize by total weight
    if (weightSum > 0.0) {
        colorSum /= weightSum;
    }
    
    dstTexture.write(colorSum, gid);
}

// Rotation shader uniforms
struct RotateParams {
    float cosAngle;    // cos(angle)
    float sinAngle;    // sin(angle)
    float scale;       // scale factor to cover output after rotation
    uint srcWidth;     // source texture width
    uint srcHeight;    // source texture height
};

// Rotation compute shader
// Rotates the source texture around its center, scales to cover the output area,
// and writes to the destination texture (which may have different dimensions)
kernel void rotate_kernel(
    texture2d<float, access::sample> srcTexture [[texture(0)]],
    texture2d<float, access::write> dstTexture [[texture(1)]],
    constant RotateParams& params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    // Output dimensions
    uint dstW = dstTexture.get_width();
    uint dstH = dstTexture.get_height();
    
    if (gid.x >= dstW || gid.y >= dstH) return;
    
    // Output center
    float dstCenterX = float(dstW) * 0.5;
    float dstCenterY = float(dstH) * 0.5;
    
    // Source center
    float srcCenterX = float(params.srcWidth) * 0.5;
    float srcCenterY = float(params.srcHeight) * 0.5;
    
    // Destination position relative to center
    float dx = float(gid.x) + 0.5 - dstCenterX;
    float dy = float(gid.y) + 0.5 - dstCenterY;
    
    // Inverse rotation (rotate backwards to find source position)
    // and scale (divide by scale to find source position)
    float invScale = 1.0 / params.scale;
    float rx = (dx * params.cosAngle + dy * params.sinAngle) * invScale;
    float ry = (-dx * params.sinAngle + dy * params.cosAngle) * invScale;
    
    // Source position
    float srcX = rx + srcCenterX;
    float srcY = ry + srcCenterY;
    
    // Convert to UV coordinates for sampling
    float u = srcX / float(params.srcWidth);
    float v = srcY / float(params.srcHeight);
    
    // Sample with bilinear filtering
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float4 color = srcTexture.sample(texSampler, float2(u, v));
    
    dstTexture.write(color, gid);
}

