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
    float base_exposure;
    int tonemap_mode;
};

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

// Fragment Shader
// Runs for every pixel on the screen.
// It reads the input image, applies exposure, and outputs the color.
fragment float4 fragment_main(VertexOut in [[stage_in]], 
                            constant Uniforms& uniforms [[buffer(0)]],
                            texture2d<float> inputTexture [[texture(0)]]) {
    constexpr sampler textureSampler (mag_filter::linear, min_filter::linear, address::clamp_to_zero);
    
    // 1. Sample the texture
    // The input texture is 16-bit Linear RGB (from LibRaw)
    float4 color = inputTexture.sample(textureSampler, in.uv);
    
    // 2. Apply Exposure (Linear Space)
    // Combine user exposure with base exposure (normalization)
    color.rgb *= pow(2.0, uniforms.exposure + uniforms.base_exposure);
    
    // 3. Apply Adjustments in Linear Space (Physically Correct)
    // Saturation
    float luma = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    color.rgb = mix(float3(luma), color.rgb, uniforms.saturation);
    
    // Contrast (Pivot around mid-grey 0.18 in linear)
    color.rgb = (color.rgb - 0.18) * uniforms.contrast + 0.18;
    
    // Highlights / Shadows (Simple Luma-based masking)
    // Shadows: Boost/Cut dark areas
    float shadow_mask = 1.0 - smoothstep(0.0, 0.18, luma);
    color.rgb += uniforms.shadows * 0.1 * shadow_mask; 
    
    // Highlights: Boost/Cut bright areas
    float highlight_mask = smoothstep(0.18, 1.0, luma);
    color.rgb += uniforms.highlights * 0.2 * highlight_mask;
    
    // Whites / Blacks (Levels-like behavior)
    // Blacks: Negative values crush blacks (move black point up), Positive values lift blacks (move black point down)
    // Whites: Positive values boost whites (move white point down), Negative values dim whites (move white point up)
    float black_point = -uniforms.blacks * 0.1;
    float white_point = 1.0 - uniforms.whites * 0.2;
    
    // Avoid division by zero
    if (white_point <= black_point + 0.001) white_point = black_point + 0.001;
    
    color.rgb = (color.rgb - black_point) / (white_point - black_point);
    
    // 4. Tone Mapping
    // Ensure no negative values before tone mapping to avoid artifacts (especially with Reinhard)
    color.rgb = max(color.rgb, float3(0.0));

    if (uniforms.tonemap_mode == 1) {
        // ACES (Cinematic)
        // Narkowicz ACES approximation outputs values that are roughly in display space (sRGB).
        color.rgb = ACESFilm(color.rgb);
    } else if (uniforms.tonemap_mode == 2) {
        // Reinhard (Soft)
        // Simple compression, keeps colors somewhat desaturated in highlights.
        // Output is Linear, needs Gamma.
        color.rgb = Reinhard(color.rgb);
        color.rgb = linear_to_srgb(color.rgb);
    } else {
        // Standard (Gamma 2.2)
        // Just clip and convert.
        color.rgb = saturate(color.rgb);
        color.rgb = linear_to_srgb(color.rgb);
    }
    
    return color;
}

// Compute Shader: Histogram
// Calculates the brightness distribution of the image.
kernel void histogram_main(texture2d<float, access::read> inputTexture [[texture(0)]],
                         device atomic_uint* histogram [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    // Check bounds
    if (gid.x >= inputTexture.get_width() || gid.y >= inputTexture.get_height()) return;
    
    float4 color = inputTexture.read(gid);
    
    // Calculate Luminance (perceived brightness)
    // Rec. 709 coefficients
    float lum = 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
    
    // Map 0.0-1.0 to 0-255 bin index
    uint bin = uint(lum * 255.0);
    if (bin > 255) bin = 255;
    
    // Atomically increment the counter for this brightness bin
    atomic_fetch_add_explicit(&histogram[bin], 1, memory_order_relaxed);
}
