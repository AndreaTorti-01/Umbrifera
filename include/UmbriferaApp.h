#pragma once

#include <vector>
#include <deque>
#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <libraw/libraw.h>

#include "FileNavigator.h"
#include "GpuTypes.h"

#ifdef __APPLE__
#include <simd/simd.h>
typedef vector_float4 Float4;
#else
struct Float4 {
    float x, y, z, w;
};
#endif

struct GLFWwindow;

struct UndoState {
    std::vector<uint16_t> textureData; // 16-bit RGBA pixel data
    int width;
    int height;
};

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
    float denoise_luma;
    float denoise_chroma;
    float sharpen_intensity;
    float base_exposure;
    
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
    Float4 hsl_adjustments[15]; 
    
    // Clipping Indicator
    int show_clipping_indicator; // 0 or 1
    
    float padding[2]; // Alignment
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
    // Reset thumbnail cache (menu action)
    void ResetThumbnailsCache();

public:
    bool m_ResetLayoutRequested = false; // Public so menu handler can access it
    bool m_ShowResizeDialog = false;     // Public so menu handler can access it
    bool m_ButtonBarAtTop = false;       // Button bar position: false = bottom, true = top
    
private:
    void InitWindow();
    void InitImGui();
    void InitGraphics();
    void LoadLogo(const std::string& path);
    GpuTexture LoadAssetTexture(const std::string& path);
    
    void RenderFrame();
    void RenderUI();
    void RenderMenuBar();
    void ProcessImage();
    
    void UpdateUniforms();
    // void LoadRawImage(const std::string& path); // Moved to public
    void SaveImage(const std::string& filename, const std::string& format);
    void SaveImageAsync(const std::string& filename, const std::string& format);
    void SetupLayout();
    void ComputeHistogram();
    void CalculateAutoSettings(); // New: Auto Adjust
    Uniforms GetDefaultUniforms() const; // Get default uniform values
    
    // Image operations
    void ResizeImage(int targetWidth, int targetHeight);
    
    // Texture data retrieval
    void GetTextureBytes(GpuTexture& texture, void* outBytes, size_t bytesPerRow);
    void* GetBufferContents(GpuBuffer& buffer);
    
    // Texture operations
    GpuTexture CreateTexture(int width, int height, GpuPixelFormat format, bool mipmapped, bool renderTarget);
    void UpdateTexture(GpuTexture& texture, const void* data, size_t bytesPerRow);
    void GenerateMipmaps(GpuTexture& texture);

    // Buffer operations
    GpuBuffer CreateBuffer(size_t size, bool storage);
    void UpdateBuffer(GpuBuffer& buffer, const void* data, size_t size);

    // Platform specific helpers
    void InitGraphicsBackend();
    void CleanupGraphicsBackend();
#ifdef __APPLE__
    void SetupMacOSMenu();
    void UpdateMacOSMenu();
#else
    uint32_t FindMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties);
    VkCommandBuffer BeginSingleTimeCommands();
    void EndSingleTimeCommands(VkCommandBuffer commandBuffer);
#endif

    GLFWwindow* m_Window = nullptr;
    float m_ClearColor[4] = {0.45f, 0.55f, 0.60f, 1.00f};
    
    Uniforms m_Uniforms;
    
    // Components
    std::unique_ptr<FileNavigator> m_FileNavigator;
    
    // View State
    float m_ViewZoom = 1.0f;
    float m_ViewOffset[2] = {0.0f, 0.0f};
    int m_RotationAngle = 0; // 0, 90, 180, 270 degrees
    bool m_FirstLayout = true;
    bool m_ImageDirty = false; // Flag to trigger re-processing
    bool m_RawHistogramDirty = false; // Flag to recompute raw histogram (for Auto Adjust)
    bool m_RawHistogramReadbackNeeded = false; // Flag to perform deferred histogram readback
    
    // Crop Mode State
    bool m_CropMode = false;
    int m_CropRatioIndex = 0; // 0 = Free, 1 = 1:1, 2 = 16:9, etc.
    // Crop rectangle in normalized image coordinates (0.0 - 1.0)
    float m_CropRect[4] = {0.0f, 0.0f, 1.0f, 1.0f}; // left, top, right, bottom
    int m_CropDragCorner = -1; // -1 = none, 0-3 = corners (TL, TR, BR, BL), 4 = move whole rect
    bool m_CropDragging = false;
    
    // Arbitrary Rotation State (activated by dragging on the rotate button)
    float m_ArbitraryRotationAngle = 0.0f; // -90 to +90 degrees
    bool m_ArbitraryRotateDragging = false;
    float m_ArbitraryRotateDragStartX = 0.0f;
    float m_ArbitraryRotateStartAngle = 0.0f;
    
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
    GpuBuffer m_RawHistogramBuffer = {};
    int m_HistogramFrameCounter = 0;
    static constexpr int HISTOGRAM_SKIP_FRAMES = 4;
    
    // Async Loading
    std::atomic<bool> m_IsLoading{false};
    std::atomic<bool> m_TextureUploadPending{false};
    std::vector<uint16_t> m_PendingTextureData16; // Changed to 16-bit
    int m_PendingWidth = 0;
    int m_PendingHeight = 0;
    float m_InitialExposure = 0.0f; // Calculated exposure compensation
    std::mutex m_LoadingMutex;
    std::recursive_mutex m_VulkanResourceMutex;
    std::thread m_LoadingThread;
    
    // Graphics State
    GpuDevice m_Device = {};
    GpuCommandQueue m_CommandQueue = {};
    GpuRenderPipeline m_RenderPSO = {};
    GpuComputePipeline m_HistogramPSO = {};
    GpuComputePipeline m_ResizePSO = {};    // Resize/Downscale shader
    GpuComputePipeline m_RotatePSO = {};    // Rotation shader
    GpuComputePipeline m_GrainPSO = {};     // Film grain generation shader
    VkDescriptorSet m_HistogramDescriptorSet = VK_NULL_HANDLE;  // Cached descriptor set for histogram
    GpuTexture m_RawTexture = {};       // Source (Immutable)
    GpuTexture m_ProcessedTexture = {}; // Destination (Render Target)
    GpuTexture m_GrainTexture = {};     // Pre-computed film grain pattern
    bool m_GrainNeedsRegeneration = true;    // Flag to regenerate grain texture
    
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
    
    // Pending Crop Operation (deferred to next frame to avoid texture-in-use issues)
    bool m_CropPending = false;
    float m_PendingCropRect[4] = {0.0f, 0.0f, 1.0f, 1.0f};
    int m_PendingCropRotation = 0;
    
    // Pending Rotation Operation (deferred to next frame)
    bool m_RotatePending = false;
    float m_PendingRotationAngle = 0.0f; // degrees
    
    // Pending Undo Operation (deferred to next frame to avoid texture-in-use issues)
    bool m_UndoPending = false;

    GpuTexture m_LogoTexture = {};
    GpuTexture m_RotateCWTexture = {};
    GpuTexture m_RotateCCWTexture = {};
    GpuTexture m_CropTexture = {};
    GpuTexture m_CropRotateTexture = {};
    GpuTexture m_FitScreenTexture = {};
    GpuTexture m_UndoTexture = {};
    GpuTexture m_CompareTexture = {};
    
    // Comparison Mode (show original image while button held)
    bool m_CompareMode = false;
    
    // Clipping Indicator (toggled via histogram click)
    bool m_ShowClippingIndicator = false;
    
    // Undo State (up to 10 states)
    static constexpr int MAX_UNDO_STATES = 10;
    std::deque<UndoState> m_UndoStack;
    void PushUndoState();
    void Undo();
    GpuBuffer m_UniformBuffer = {};
    GpuBuffer m_HistogramBuffer = {};
    GpuBuffer m_HistogramBufferDisplay = {}; // Double buffering for display
    VkFence m_HistogramFence = VK_NULL_HANDLE;
    VkCommandBuffer m_HistogramCommandBuffer = VK_NULL_HANDLE;
    std::atomic<bool> m_HistogramProcessingComplete{true}; // Tracks if histogram GPU work is done
    GpuSampler m_TextureSampler = {}; // For linear filtering
#ifdef __APPLE__
    CAMetalLayer* m_MetalLayer = nil;
    MTLRenderPassDescriptor* m_RenderPassDescriptor = nil;
#else
    VkInstance m_VulkanInstance = VK_NULL_HANDLE;
    VkPhysicalDevice m_VulkanPhysicalDevice = VK_NULL_HANDLE;
    VkSurfaceKHR m_VulkanSurface = VK_NULL_HANDLE;
    VkDescriptorPool m_VulkanDescriptorPool = VK_NULL_HANDLE;
    ImGui_ImplVulkanH_Window m_VulkanMainWindowData;
    uint32_t m_VulkanQueueFamily = (uint32_t)-1;
    VkAllocationCallbacks* m_VulkanAllocator = nullptr;
    uint32_t m_VulkanMinImageCount = 2;
    bool m_VulkanSwapChainRebuild = false;

    // Vulkan Pipeline Layouts
    VkDescriptorSetLayout m_ComputeDescriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout m_ComputePipelineLayout = VK_NULL_HANDLE;
    VkDescriptorSetLayout m_HistogramDescriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout m_HistogramPipelineLayout = VK_NULL_HANDLE;
    
    VkDescriptorSetLayout m_ResizeDescriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout m_ResizePipelineLayout = VK_NULL_HANDLE;

    VkDescriptorSetLayout m_RotateDescriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout m_RotatePipelineLayout = VK_NULL_HANDLE;

    VkDescriptorSetLayout m_GrainDescriptorSetLayout = VK_NULL_HANDLE;
    VkPipelineLayout m_GrainPipelineLayout = VK_NULL_HANDLE;

    VkCommandPool m_UtilityCommandPool = VK_NULL_HANDLE;

    void InitComputePipelines();
    void ComputeRawHistogram();
    void GenerateGrainTexture();
    void DestroyTexture(GpuTexture& tex);
#endif
};
