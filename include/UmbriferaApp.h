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
    float base_exposure;
    int tonemap_mode; // 0: Standard (Gamma), 1: Cinematic (ACES), 2: Soft (Reinhard)
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

public:
    bool m_ResetLayoutRequested = false; // Public so menu handler can access it
    
private:
    void InitWindow();
    void InitImGui();
    void InitGraphics();
    
    void RenderFrame();
    void RenderUI();
    void ProcessImage();
    
    void UpdateUniforms();
    // void LoadRawImage(const std::string& path); // Moved to public
    void SaveImage(const std::string& filename, const std::string& format);
    void SaveImageAsync(const std::string& filename, const std::string& format);
    void SetupLayout();
    void ComputeHistogram();

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
    id<MTLTexture> m_RawTexture = nil;       // Source (Immutable)
    id<MTLTexture> m_ProcessedTexture = nil; // Destination (Render Target)
    id<MTLBuffer> m_HistogramBuffer = nil;
    id<MTLSamplerState> m_TextureSampler = nil; // For linear filtering
    CAMetalLayer* m_MetalLayer = nil;
    MTLRenderPassDescriptor* m_RenderPassDescriptor = nil;
};
