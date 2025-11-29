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
    float base_exposure;
    int tonemap_mode;
    
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

// Helper: ACES Tone Mapping (Narkowicz 2015)
float3 ACESFilm(float3 x) {
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return saturate((x*(a*x+b))/(x*(c*x+d)+e));
}

// Helper: Reinhard Tone Mapping
float3 Reinhard(float3 x) {
    return x / (x + 1.0);
}

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
// Helper: High Quality Hash (Dave Hoskins)
// Replaces the problematic sine-based rand
float hash12(float2 p) {
    float3 p3  = fract(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
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

// Fragment Shader
// Runs for every pixel on the screen.
// Runs for every pixel on the screen.
// It reads the input image, applies exposure, and outputs the color.
fragment float4 fragment_main(VertexOut in [[stage_in]], 
                            constant Uniforms& uniforms [[buffer(0)]],
                            texture2d<float> inputTexture [[texture(0)]]) {
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear, address::clamp_to_zero);
    
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
    // Green channel gain is usually inverse of tint.
    wb_gains.g -= uniforms.tint * 0.5;
    
    // Apply WB
    color.rgb *= wb_gains;
    
    // --- 2. Exposure ---
    // Apply Exposure (Linear Space)
    // Combine user exposure with base exposure (normalization)
    color.rgb *= pow(2.0, uniforms.exposure + uniforms.base_exposure);
    
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
        
        float4 total_adj = float4(0.0);
        float total_weight = 0.0;
        
        // Iterate over all 15 slices
        // This gives a high quality Gaussian influence
        for (int i = 0; i < 15; i++) {
            float slice_hue = float(i) / 15.0;
            
            // Calculate distance in hue space (circular)
            float dist = abs(hue - slice_hue);
            if (dist > 0.5) dist = 1.0 - dist;
            
            // Gaussian Weight
            // Sigma controls the width.
            // 15 slices = 1/15 spacing = 0.066
            // Sigma should be around that to have smooth overlap.
            // User requested <1% effect on neighbors.
            // Neighbor dist = 1/15 = 0.066.
            // exp(-(0.066^2)/(2*sigma^2)) < 0.01 => sigma < 0.022.
            float sigma = 0.02;
            float w = gaussian_weight(dist, sigma);
            
            // Optimization: Skip if weight is negligible
            if (w > 0.01) {
                total_adj += uniforms.hsl_adjustments[i] * w;
                total_weight += w;
            }
        }
        
        if (total_weight > 0.001) {
            float4 adj = total_adj / total_weight;
            
            // Apply Hue Shift
            hsv.x += adj.x;
            hsv.x = fract(hsv.x);
            
            // Apply Saturation Shift
            hsv.y = saturate(hsv.y + adj.y);
            
            // Apply Luminance Shift
            // Do NOT saturate Z (Value) to allow HDR values > 1.0
            // Just ensure it doesn't go negative.
            hsv.z = max(0.0, hsv.z + adj.z);
            
            color.rgb = hsv2rgb(hsv);
        }
    }
    
    // Hue Offset (Global)
    if (abs(uniforms.hue_offset) > 0.001) {
        float3 hsv = rgb2hsv(color.rgb);
        hsv.x += uniforms.hue_offset;
        hsv.x = fract(hsv.x);
        color.rgb = hsv2rgb(hsv);
    }
    
    // Contrast (Pivot around mid-grey 0.18 in linear)
    color.rgb = (color.rgb - 0.18) * uniforms.contrast + 0.18;
    
    // Highlights / Shadows (Simple Luma-based masking)
    luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    
    // Shadows: Boost/Cut dark areas
    float shadow_mask = 1.0 - smoothstep(0.0, 0.18, luma);
    color.rgb += uniforms.shadows * 0.1 * shadow_mask; 
    
    // Highlights: Boost/Cut bright areas
    float highlight_mask = smoothstep(0.18, 1.0, luma);
    color.rgb += uniforms.highlights * 0.2 * highlight_mask;
    
    // Whites / Blacks (Levels-like behavior)
    float black_point = -uniforms.blacks * 0.1;
    float white_point = 1.0 - uniforms.whites * 0.2;
    
    // Avoid division by zero
    if (white_point <= black_point + 0.001) white_point = black_point + 0.001;
    
    color.rgb = (color.rgb - black_point) / (white_point - black_point);
    
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
    // smoothstep(edge0, edge1, x)
    // We want 1.0 at center, 0.0 at outside
    float vignette = 1.0 - smoothstep(radius, radius + feather, dist);
    
    // Apply strength (mix with 1.0)
    // Strength 0 -> factor 1.0 everywhere. Strength 1 -> factor vignette.
    vignette = mix(1.0, vignette, uniforms.vignette_strength);
    
    color.rgb *= vignette;
    
    // Film Grain
    if (uniforms.grain_amount > 0.0) {
        // 1. Calculate Luminance (Rec.709)
        float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
        
        // 2. Luminance Response Curve
        // Grain is most visible in mid-tones (0.5), less in shadows/highlights.
        // Smooth parabola peaking at 0.5
        float response = 1.0 - pow(lum - 0.5, 2.0) * 4.0;
        response = saturate(response); // Clamp to 0-1
        
        // 3. Generate Noise Layers (Simplex Noise)
        // Use pixel coordinates scaled by coarseness
        float2 uv = in.uv * float2(inputTexture.get_width(), inputTexture.get_height());
        float coarseness = 1.0 / max(0.1, uniforms.grain_size); // Inverse scale
        
        // Offset UVs for each channel to simulate dye layers
        float noiseR = snoise(uv * coarseness + float2(0.0, 0.0));
        float noiseG = snoise(uv * coarseness + float2(5.2, 1.3));
        float noiseB = snoise(uv * coarseness + float2(10.8, -2.5));
        
        // Clamp noise to avoid artifacts
        noiseR = clamp(noiseR, -1.0, 1.0);
        noiseG = clamp(noiseG, -1.0, 1.0);
        noiseB = clamp(noiseB, -1.0, 1.0);
        
        float3 grainVector = float3(noiseR, noiseG, noiseB);
        
        // 4. Composite using "Soft Light" / Overlay logic
        // Modulate strength by luminance response
        // Increased multiplier from 0.5 to 2.0 for stronger effect
        float finalStrength = uniforms.grain_amount * response * 2.0; 
        
        // Apply grain:
        // output = input + input * grain * strength
        color.rgb += color.rgb * grainVector * finalStrength;
    }
    
    // --- 5. Tone Mapping ---
    // Ensure no negative values before tone mapping to avoid artifacts (especially with Reinhard)
    color.rgb = max(color.rgb, float3(0.0));

    if (uniforms.tonemap_mode == 1) {
        // ACES (Cinematic)
        color.rgb = ACESFilm(color.rgb);
    } else if (uniforms.tonemap_mode == 2) {
        // Reinhard (Soft)
        color.rgb = Reinhard(color.rgb);
        color.rgb = linear_to_srgb(color.rgb);
    } else {
        // Standard (Gamma 2.2)
        color.rgb = saturate(color.rgb);
        color.rgb = linear_to_srgb(color.rgb);
    }
    
    return color;
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
