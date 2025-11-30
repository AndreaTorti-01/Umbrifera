#pragma once

#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <libraw/libraw.h>

#include "FileNavigator.h"

#include <Metal/Metal.h>
#include <QuartzCore/QuartzCore.h>
#include <simd/simd.h>

struct GLFWwindow;

struct Uniforms {
    float exposure;
    float contrast;
    float highlights;
    float shadows;
    float whites;
    float blacks;
    float saturation;
    float vibrance;      // New
    float hue_offset;    // New
    float temperature;   // New
    float tint;          // New
    float vignette_strength; // New
    float vignette_feather;  // New
    float vignette_size;     // New
    float grain_amount;      // New
    float grain_size;        // New: Controls coarseness
    float base_exposure;
    // Removed tonemap_mode
    
    // Constants (passed as uniforms for consistency)
    float contrast_pivot;
    float blacks_scale;
    float whites_scale;
    
    // HSL Adjustments
    int hsl_enabled; // 0 or 1
    // 15 colors * 3 params (Hue, Sat, Lum) = 45 floats
    // We can pack them into arrays.
    // Metal arrays in structs need careful alignment.
    // float hsl_hue[15];
    // float hsl_sat[15];
    // float hsl_lum[15];
    // Metal arrays are aligned to 16 bytes (float4).
    // It's safer to use a fixed size array of float4 where x=h, y=s, z=l, w=unused.
    // 15 * 16 bytes = 240 bytes.
    vector_float4 hsl_adjustments[15]; 
    
    float padding[3]; // Alignment
};

class UmbriferaApp {
public:
    UmbriferaApp();
    ~UmbriferaApp();

    bool Init();
    void Run();
    void Shutdown();
    
    void OpenExportDialog(const std::string& format);
    void LoadRawImage(const std::string& path);
    void OpenResizeDialog();

public:
    bool m_ResetLayoutRequested = false; // Public so menu handler can access it
    bool m_ShowResizeDialog = false;     // Public so menu handler can access it
    
private:
    void InitWindow();
    void InitImGui();
    void InitGraphics();
    void LoadLogo(const std::string& path);
    
    void RenderFrame();
    void RenderUI();
    void ProcessImage();
    
    void UpdateUniforms();
    // void LoadRawImage(const std::string& path); // Moved to public
    void SaveImage(const std::string& filename, const std::string& format);
    void SaveImageAsync(const std::string& filename, const std::string& format);
    void SetupLayout();
    void ComputeHistogram();
    void CalculateAutoSettings(); // New: Auto Adjust

    // Platform specific helpers
    void InitMetal();
    void CleanupMetal();
    void SetupMacOSMenu();
    void UpdateMacOSMenu();

    GLFWwindow* m_Window = nullptr;
    float m_ClearColor[4] = {0.45f, 0.55f, 0.60f, 1.00f};
    
    Uniforms m_Uniforms;
    
    // Components
    std::unique_ptr<FileNavigator> m_FileNavigator;
    
    // View State
    float m_ViewZoom = 1.0f;
    float m_ViewOffset[2] = {0.0f, 0.0f};
    bool m_FirstLayout = true;
    bool m_ImageDirty = false; // Flag to trigger re-processing
    
    // Export State
    bool m_ShowExportOptions = false;
    int m_ExportQuality = 90; // JPG Quality
    bool m_ExportProgressive = true; // JPG Progressive
    int m_ExportSubsampling = 2; // 0: 4:4:4, 1: 4:2:2, 2: 4:2:0 (Default: Web Standard)
    bool m_ExportPngInterlaced = false; // PNG Interlaced
    bool m_ExportTiffCompression = true; // true: Deflate (Lossless), false: None
    int m_ExportTiffDepth = 8; // 8 or 16
    std::string m_ExportFormat = "jpg";
    
    // Export UI State
    std::string m_LoadedImagePath = ""; // Track loaded image path for default export name
    bool m_ShowOverwriteConfirm = false;
    std::string m_PendingExportPath = "";
    
    // Async Export
    std::atomic<bool> m_IsExporting{false};
    std::atomic<float> m_ExportProgress{0.0f};
    std::thread m_ExportThread;
    
    // JPEG Size Estimation
    std::atomic<bool> m_IsEstimatingSize{false};
    std::atomic<int> m_EstimatedSizeKB{0};
    std::thread m_SizeEstimationThread;

    // Histogram
    std::vector<float> m_Histogram;
    std::vector<float> m_SmoothHistogram; // For temporal smoothing
    
    // Raw Histogram (for Auto Adjust)
    std::vector<uint32_t> m_RawHistogram;
    id<MTLBuffer> m_RawHistogramBuffer = nil;
    
    // Async Loading
    std::atomic<bool> m_IsLoading{false};
    std::atomic<bool> m_TextureUploadPending{false};
    std::vector<uint16_t> m_PendingTextureData16; // Changed to 16-bit
    int m_PendingWidth = 0;
    int m_PendingHeight = 0;
    float m_InitialExposure = 0.0f; // Calculated exposure compensation
    std::mutex m_LoadingMutex;
    std::thread m_LoadingThread;
    
    // Metal State
    id<MTLDevice> m_Device = nil;
    id<MTLCommandQueue> m_CommandQueue = nil;
    id<MTLRenderPipelineState> m_RenderPSO = nil;
    id<MTLComputePipelineState> m_HistogramPSO = nil;
    id<MTLComputePipelineState> m_Lanczos3PSO = nil;  // Lanczos3 downscale shader
    id<MTLTexture> m_RawTexture = nil;       // Source (Immutable)
    id<MTLTexture> m_ProcessedTexture = nil; // Destination (Render Target)
    
    // Presets
    struct Preset {
        std::string name;
        Uniforms data;
    };
    std::vector<Preset> m_Presets;
    void LoadPresets();
    void SavePresets();
    void ApplyPreset(const Preset& preset);
    
    // Sidecar
    void SaveSidecar();
    void LoadSidecar();
    std::string SerializeUniforms(const Uniforms& u);
    void DeserializeUniforms(const std::string& data, Uniforms& u);
    
    // UI State for Presets
    bool m_ShowSavePresetDialog = false;
    bool m_ShowPresetOverwriteConfirm = false;
    char m_NewPresetName[128] = "";
    
    // EXIF Data
    std::string m_ExifString;  // Top-left: Camera, ISO, Shutter, Aperture, Focal Length
    std::string m_ExifString2; // Bottom-right: GPS, Date/Time
    
    // Resize Dialog State
    int m_ResizeTargetWidth = 0;
    int m_ResizeTargetHeight = 0;

    id<MTLTexture> m_LogoTexture = nil;      // Logo
    id<MTLBuffer> m_HistogramBuffer = nil;
    id<MTLBuffer> m_HistogramBufferDisplay = nil; // Double buffering for display
    id<MTLSamplerState> m_TextureSampler = nil; // For linear filtering
    CAMetalLayer* m_MetalLayer = nil;
    MTLRenderPassDescriptor* m_RenderPassDescriptor = nil;
};
