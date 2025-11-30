#include "UmbriferaApp.h"
#include "imgui.h"
#include "imgui_internal.h" // For DockBuilder API
#include "imgui_impl_glfw.h"
#include <stdio.h>

#define GLFW_EXPOSE_NATIVE_COCOA
#include "imgui_impl_metal.h"
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <iostream>

// Error callback for GLFW (Windowing library)
static void glfw_error_callback(int error, const char* description)
{
    fprintf(stderr, "Glfw Error %d: %s\n", error, description);
}

UmbriferaApp::UmbriferaApp() {
    m_Uniforms = {0};
    m_Uniforms.exposure = 0.0f;
    m_Uniforms.contrast = 1.0f;
    m_Uniforms.highlights = 0.0f;
    m_Uniforms.shadows = 0.0f;
    m_Uniforms.whites = 0.0f;
    m_Uniforms.blacks = 0.0f;
    m_Uniforms.saturation = 1.0f;
    m_Uniforms.base_exposure = 0.0f;
    m_Uniforms.vibrance = 0.0f;
    m_Uniforms.hue_offset = 0.0f;
    m_Uniforms.temperature = 0.0f;
    m_Uniforms.tint = 0.0f;
    m_Uniforms.vignette_strength = 0.0f;
    m_Uniforms.vignette_feather = 0.5f;
    m_Uniforms.vignette_size = 0.5f;
    m_Uniforms.grain_amount = 0.0f;
    m_Uniforms.grain_size = 1.6f; // Default coarseness
    
    // Initialize Constants
    m_Uniforms.contrast_pivot = 0.18f; // Mid-grey
    m_Uniforms.blacks_scale = 0.1f;
    m_Uniforms.whites_scale = 0.2f;
    
    m_Uniforms.hsl_enabled = 0;
    for(int i=0; i<15; ++i) m_Uniforms.hsl_adjustments[i] = {0.0f, 0.0f, 0.0f, 0.0f};
    
    LoadPresets();
    
    m_FileNavigator = std::make_unique<FileNavigator>();
}

UmbriferaApp::~UmbriferaApp() {
    Shutdown();
}

bool UmbriferaApp::Init() {
    glfwSetErrorCallback(glfw_error_callback);
    if (!glfwInit())
        return false;

    InitWindow();
    InitGraphics(); // Sets up m_Device
    InitImGui();
    
    m_FileNavigator->Init(m_Device);

    return true;
}

void UmbriferaApp::InitWindow() {
    // We don't want an OpenGL context, so we say NO_API
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_MAXIMIZED, GLFW_TRUE);
    m_Window = glfwCreateWindow(1280, 720, "Umbrifera", nullptr, nullptr);
    
    SetupMacOSMenu();
}

void UmbriferaApp::InitImGui() {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;

    // Get display scale for Retina/HiDPI support
    NSScreen *mainScreen = [NSScreen mainScreen];
    CGFloat scale = [mainScreen backingScaleFactor];
    
    // Use standard font size (the rendering will be scaled by ImGui)
    float fontSize = 16.0f;
    
    // Load MacOS System Font with antialiasing
    ImFontConfig fontConfig;
    fontConfig.OversampleH = 3; // Improve horizontal antialiasing
    fontConfig.OversampleV = 2; // Improve vertical antialiasing
    fontConfig.PixelSnapH = false; // Allow subpixel rendering
    
    if (io.Fonts->AddFontFromFileTTF("/System/Library/Fonts/SFNS.ttf", fontSize, &fontConfig)) {
        // Success
    } else if (io.Fonts->AddFontFromFileTTF("/System/Library/Fonts/Helvetica.ttc", fontSize, &fontConfig)) {
        // Fallback to Helvetica
    } else {
        // Default
        io.Fonts->AddFontDefault(&fontConfig);
    }
    
    // Setup Material-like Style
    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 8.0f;
    style.FrameRounding = 4.0f;
    style.PopupRounding = 4.0f;
    style.ScrollbarRounding = 4.0f;
    style.GrabRounding = 4.0f;
    style.TabRounding = 6.0f;
    
    // Adjust slider handle (grab) brightness - make it darker
    ImVec4* colors = style.Colors;
    colors[ImGuiCol_SliderGrab] = ImVec4(0.30f, 0.30f, 0.30f, 1.00f); // Darker grab
    colors[ImGuiCol_SliderGrabActive] = ImVec4(0.45f, 0.45f, 0.45f, 1.00f); // Darker active grab
    style.WindowBorderSize = 1.0f; // Visible border for gap effect
    style.FrameBorderSize = 0.0f;
    style.PopupBorderSize = 0.0f;
    style.ChildBorderSize = 1.0f; // Keep border for the controls group
    
    // Continue using the same colors pointer from above
    colors[ImGuiCol_Text]                   = ImVec4(0.90f, 0.90f, 0.90f, 1.00f);
    colors[ImGuiCol_TextDisabled]           = ImVec4(0.50f, 0.50f, 0.50f, 1.00f);
    colors[ImGuiCol_WindowBg]               = ImVec4(0.12f, 0.12f, 0.12f, 1.00f);
    colors[ImGuiCol_ChildBg]                = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    colors[ImGuiCol_PopupBg]                = ImVec4(0.15f, 0.15f, 0.15f, 0.94f);
    colors[ImGuiCol_Border]                 = ImVec4(0.00f, 0.00f, 0.00f, 1.00f); // Black border for "gap" effect
    colors[ImGuiCol_BorderShadow]           = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    colors[ImGuiCol_FrameBg]                = ImVec4(0.20f, 0.20f, 0.20f, 0.54f);
    colors[ImGuiCol_FrameBgHovered]         = ImVec4(0.30f, 0.30f, 0.30f, 0.54f);
    colors[ImGuiCol_FrameBgActive]          = ImVec4(0.40f, 0.40f, 0.40f, 0.54f);
    colors[ImGuiCol_TitleBg]                = ImVec4(0.08f, 0.08f, 0.08f, 1.00f);
    colors[ImGuiCol_TitleBgActive]          = ImVec4(0.08f, 0.08f, 0.08f, 1.00f);
    colors[ImGuiCol_TitleBgCollapsed]       = ImVec4(0.08f, 0.08f, 0.08f, 1.00f);
    colors[ImGuiCol_MenuBarBg]              = ImVec4(0.10f, 0.10f, 0.10f, 1.00f);
    colors[ImGuiCol_ScrollbarBg]            = ImVec4(0.02f, 0.02f, 0.02f, 0.53f);
    colors[ImGuiCol_ScrollbarGrab]          = ImVec4(0.31f, 0.31f, 0.31f, 1.00f);
    colors[ImGuiCol_ScrollbarGrabHovered]   = ImVec4(0.41f, 0.41f, 0.41f, 1.00f);
    colors[ImGuiCol_ScrollbarGrabActive]    = ImVec4(0.51f, 0.51f, 0.51f, 1.00f);
    colors[ImGuiCol_CheckMark]              = ImVec4(0.26f, 0.59f, 0.98f, 1.00f);
    colors[ImGuiCol_SliderGrab]             = ImVec4(0.24f, 0.52f, 0.88f, 1.00f);
    colors[ImGuiCol_SliderGrabActive]       = ImVec4(0.26f, 0.59f, 0.98f, 1.00f);
    colors[ImGuiCol_Button]                 = ImVec4(0.20f, 0.20f, 0.20f, 0.54f);
    colors[ImGuiCol_ButtonHovered]          = ImVec4(0.30f, 0.30f, 0.30f, 0.54f);
    colors[ImGuiCol_ButtonActive]           = ImVec4(0.40f, 0.40f, 0.40f, 0.54f);
    colors[ImGuiCol_Header]                 = ImVec4(0.26f, 0.59f, 0.98f, 0.31f);
    colors[ImGuiCol_HeaderHovered]          = ImVec4(0.26f, 0.59f, 0.98f, 0.80f);
    colors[ImGuiCol_HeaderActive]           = ImVec4(0.26f, 0.59f, 0.98f, 1.00f);
    colors[ImGuiCol_Separator]              = ImVec4(0.43f, 0.43f, 0.50f, 0.50f);
    colors[ImGuiCol_SeparatorHovered]       = ImVec4(0.10f, 0.40f, 0.75f, 0.78f);
    colors[ImGuiCol_SeparatorActive]        = ImVec4(0.10f, 0.40f, 0.75f, 1.00f);
    colors[ImGuiCol_ResizeGrip]             = ImVec4(0.26f, 0.59f, 0.98f, 0.25f);
    colors[ImGuiCol_ResizeGripHovered]      = ImVec4(0.26f, 0.59f, 0.98f, 0.67f);
    colors[ImGuiCol_ResizeGripActive]       = ImVec4(0.26f, 0.59f, 0.98f, 0.95f);
    
    // Tab Styling (Neutral Greys, No Blue Highlight)
    colors[ImGuiCol_Tab]                    = ImVec4(0.18f, 0.18f, 0.18f, 1.00f);
    colors[ImGuiCol_TabHovered]             = ImVec4(0.28f, 0.28f, 0.28f, 1.00f); // Lighter grey on hover
    colors[ImGuiCol_TabActive]              = ImVec4(0.20f, 0.20f, 0.20f, 1.00f); // Subtle difference for active
    colors[ImGuiCol_TabUnfocused]           = ImVec4(0.18f, 0.18f, 0.18f, 1.00f); // Same as normal tab
    colors[ImGuiCol_TabUnfocusedActive]     = ImVec4(0.20f, 0.20f, 0.20f, 1.00f); // Same as active tab
    
    colors[ImGuiCol_DockingPreview]         = ImVec4(0.26f, 0.59f, 0.98f, 0.70f);
    colors[ImGuiCol_DockingEmptyBg]         = ImVec4(0.20f, 0.20f, 0.20f, 1.00f);
    colors[ImGuiCol_PlotLines]              = ImVec4(0.61f, 0.61f, 0.61f, 1.00f);
    
    // Ensure text is left-aligned
    style.WindowTitleAlign = ImVec2(0.0f, 0.5f);

    colors[ImGuiCol_PlotLinesHovered]       = ImVec4(1.00f, 0.43f, 0.35f, 1.00f);
    colors[ImGuiCol_PlotHistogram]          = ImVec4(0.90f, 0.70f, 0.00f, 1.00f);
    colors[ImGuiCol_PlotHistogramHovered]   = ImVec4(1.00f, 0.60f, 0.00f, 1.00f);
    colors[ImGuiCol_TableHeaderBg]          = ImVec4(0.19f, 0.19f, 0.20f, 1.00f);
    colors[ImGuiCol_TableBorderStrong]      = ImVec4(0.31f, 0.31f, 0.35f, 1.00f);
    colors[ImGuiCol_TableBorderLight]       = ImVec4(0.23f, 0.23f, 0.25f, 1.00f);
    colors[ImGuiCol_TableRowBg]             = ImVec4(0.00f, 0.00f, 0.00f, 0.00f);
    colors[ImGuiCol_TableRowBgAlt]          = ImVec4(1.00f, 1.00f, 1.00f, 0.06f);
    colors[ImGuiCol_TextSelectedBg]         = ImVec4(0.26f, 0.59f, 0.98f, 0.35f);
    colors[ImGuiCol_DragDropTarget]         = ImVec4(1.00f, 1.00f, 0.00f, 0.90f);
    colors[ImGuiCol_NavHighlight]           = ImVec4(0.26f, 0.59f, 0.98f, 1.00f);
    colors[ImGuiCol_NavWindowingHighlight]  = ImVec4(1.00f, 1.00f, 1.00f, 0.70f);
    colors[ImGuiCol_NavWindowingDimBg]      = ImVec4(0.80f, 0.80f, 0.80f, 0.20f);
    colors[ImGuiCol_ModalWindowDimBg]       = ImVec4(0.80f, 0.80f, 0.80f, 0.35f);

    ImGui_ImplGlfw_InitForOther(m_Window, true);
    
    ImGui_ImplMetal_Init(m_Device);
}

void UmbriferaApp::InitGraphics() {
    InitMetal();
    // Load Logo
    LoadLogo("assets/logo.png");
}

void UmbriferaApp::LoadLogo(const std::string& path) {
    NSString* nsPath = [NSString stringWithUTF8String:path.c_str()];
    NSImage* image = [[NSImage alloc] initWithContentsOfFile:nsPath];
    if (!image) {
        // Try absolute path if relative fails (dev environment)
        NSString* currentDir = [[NSFileManager defaultManager] currentDirectoryPath];
        NSString* absPath = [currentDir stringByAppendingPathComponent:nsPath];
        image = [[NSImage alloc] initWithContentsOfFile:absPath];
    }
    
    if (image) {
        // Convert to CGImage
        CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
        NSUInteger width = CGImageGetWidth(cgImage);
        NSUInteger height = CGImageGetHeight(cgImage);
        
        // Create Metal Texture
        MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:YES];
        m_LogoTexture = [m_Device newTextureWithDescriptor:textureDescriptor];
        
        // Get raw data
        NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
        // Ensure RGBA
        // This might be BGRA or RGBA depending on source.
        // Let's assume standard RGBA for now or check format.
        // Actually NSBitmapImageRep bitmapData gives raw bytes.
        
        MTLRegion region = MTLRegionMake2D(0, 0, width, height);
        [m_LogoTexture replaceRegion:region mipmapLevel:0 withBytes:[rep bitmapData] bytesPerRow:[rep bytesPerRow]];
        
        // Generate mipmaps for smooth scaling
        id<MTLCommandBuffer> commandBuffer = [m_CommandQueue commandBuffer];
        id<MTLBlitCommandEncoder> blitEncoder = [commandBuffer blitCommandEncoder];
        [blitEncoder generateMipmapsForTexture:m_LogoTexture];
        [blitEncoder endEncoding];
        [commandBuffer commit];
    } else {
        std::cerr << "Failed to load logo: " << path << std::endl;
    }
}

void UmbriferaApp::Run() {
    while (!glfwWindowShouldClose(m_Window)) {
        glfwPollEvents();
        RenderFrame();
    }
}

void UmbriferaApp::Shutdown() {
    CleanupMetal();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    if (m_Window) {
        glfwDestroyWindow(m_Window);
        m_Window = nullptr;
    }
    glfwTerminate();
}

void UmbriferaApp::UpdateUniforms() {
    // Update any time-based or dynamic uniforms here
    
    UpdateMacOSMenu();
}

#import <Cocoa/Cocoa.h>

// Helper interface to handle menu actions
@interface MenuHandler : NSObject
@property (nonatomic, assign) UmbriferaApp* app;
- (void)exportJpg:(id)sender;
- (void)exportPng:(id)sender;
- (void)exportTiff:(id)sender;
- (void)resetLayout:(id)sender;
- (void)resizeImage:(id)sender;
@end

void UmbriferaApp::OpenExportDialog(const std::string& format) {
    // Prevent opening export dialog if no image is loaded
    if (!m_ProcessedTexture) {
        return;
    }

    m_ExportFormat = format;
    m_ShowExportOptions = true;
    // Note: m_ShowExportOptions will be cleared after the popup is opened in RenderUI
}

// --- Serialization ---

std::string UmbriferaApp::SerializeUniforms(const Uniforms& u) {
    std::stringstream ss;
    ss << "exposure=" << u.exposure << "\n";
    ss << "contrast=" << u.contrast << "\n";
    ss << "highlights=" << u.highlights << "\n";
    ss << "shadows=" << u.shadows << "\n";
    ss << "whites=" << u.whites << "\n";
    ss << "blacks=" << u.blacks << "\n";
    ss << "saturation=" << u.saturation << "\n";
    ss << "vibrance=" << u.vibrance << "\n";
    ss << "hue_offset=" << u.hue_offset << "\n";
    ss << "temperature=" << u.temperature << "\n";
    ss << "tint=" << u.tint << "\n";
    ss << "vignette_strength=" << u.vignette_strength << "\n";
    ss << "vignette_feather=" << u.vignette_feather << "\n";
    ss << "vignette_size=" << u.vignette_size << "\n";
    ss << "grain_amount=" << u.grain_amount << "\n";
    ss << "base_exposure=" << u.base_exposure << "\n";
    ss << "base_exposure=" << u.base_exposure << "\n";
    // ss << "tonemap_mode=" << u.tonemap_mode << "\n"; // Removed
    ss << "hsl_enabled=" << u.hsl_enabled << "\n";
    ss << "hsl_enabled=" << u.hsl_enabled << "\n";
    
    for (int i = 0; i < 15; i++) {
        ss << "hsl_" << i << "=" << u.hsl_adjustments[i].x << "," << u.hsl_adjustments[i].y << "," << u.hsl_adjustments[i].z << "\n";
    }
    
    return ss.str();
}

void UmbriferaApp::DeserializeUniforms(const std::string& data, Uniforms& u) {
    std::stringstream ss(data);
    std::string line;
    while (std::getline(ss, line)) {
        size_t eqPos = line.find('=');
        if (eqPos == std::string::npos) continue;
        
        std::string key = line.substr(0, eqPos);
        std::string valStr = line.substr(eqPos + 1);
        
        try {
            if (key == "exposure") u.exposure = std::clamp(std::stof(valStr), -5.0f, 5.0f);
            else if (key == "contrast") u.contrast = std::clamp(std::stof(valStr), 0.5f, 1.5f);
            else if (key == "highlights") u.highlights = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "shadows") u.shadows = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "whites") u.whites = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "blacks") u.blacks = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "saturation") u.saturation = std::clamp(std::stof(valStr), 0.0f, 2.0f);
            else if (key == "vibrance") u.vibrance = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "hue_offset") u.hue_offset = std::clamp(std::stof(valStr), -0.5f, 0.5f);
            else if (key == "temperature") u.temperature = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "tint") u.tint = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "vignette_strength") u.vignette_strength = std::clamp(std::stof(valStr), 0.0f, 1.0f);
            else if (key == "vignette_feather") u.vignette_feather = std::clamp(std::stof(valStr), 0.0f, 1.0f);
            else if (key == "vignette_size") u.vignette_size = std::clamp(std::stof(valStr), 0.0f, 1.0f);
            else if (key == "grain_amount") u.grain_amount = std::clamp(std::stof(valStr), 0.0f, 1.0f);
            else if (key == "base_exposure") u.base_exposure = std::stof(valStr); // No strict clamp, but usually > 0
            else if (key == "base_exposure") u.base_exposure = std::stof(valStr); // No strict clamp, but usually > 0
            // else if (key == "tonemap_mode") u.tonemap_mode = std::clamp(std::stoi(valStr), 0, 2); // Removed
            else if (key == "hsl_enabled") u.hsl_enabled = std::clamp(std::stoi(valStr), 0, 1);
            else if (key == "hsl_enabled") u.hsl_enabled = std::clamp(std::stoi(valStr), 0, 1);
            else if (key.rfind("hsl_", 0) == 0) {
                // Parse hsl_N=x,y,z
                int index = std::stoi(key.substr(4));
                if (index >= 0 && index < 15) {
                    size_t c1 = valStr.find(',');
                    size_t c2 = valStr.find(',', c1 + 1);
                    if (c1 != std::string::npos && c2 != std::string::npos) {
                        u.hsl_adjustments[index].x = std::clamp(std::stof(valStr.substr(0, c1)), -0.1f, 0.1f); // Hue is small range
                        u.hsl_adjustments[index].y = std::clamp(std::stof(valStr.substr(c1 + 1, c2 - c1 - 1)), -1.0f, 1.0f);
                        u.hsl_adjustments[index].z = std::clamp(std::stof(valStr.substr(c2 + 1)), -1.0f, 1.0f);
                    }
                }
            }
        } catch (...) {
            // Ignore parsing errors and keep defaults/current values
        }
    }
}

void UmbriferaApp::SaveSidecar() {
    if (m_LoadedImagePath.empty()) return;
    
    std::string sidecarPath = m_LoadedImagePath + ".xmp";
    std::ofstream out(sidecarPath);
    if (out.is_open()) {
        out << SerializeUniforms(m_Uniforms);
        out.close();
    }
}

void UmbriferaApp::LoadSidecar() {
    if (m_LoadedImagePath.empty()) return;
    
    std::string sidecarPath = m_LoadedImagePath + ".xmp";
    std::ifstream in(sidecarPath);
    if (in.is_open()) {
        std::stringstream buffer;
        buffer << in.rdbuf();
        DeserializeUniforms(buffer.str(), m_Uniforms);
        in.close();
        
        // Ensure constants are always set (they should never change)
        m_Uniforms.contrast_pivot = 0.18f;
        m_Uniforms.blacks_scale = 0.1f;
        m_Uniforms.whites_scale = 0.2f;
    } else {
        // No sidecar exists, apply Auto settings
        CalculateAutoSettings();
        SaveSidecar(); // Save the auto-calculated values
    }
}

// --- Presets ---

void UmbriferaApp::LoadPresets() {
    m_Presets.clear();
    
    // Auto Preset (Special - calls CalculateAutoSettings)
    Preset autoPreset;
    autoPreset.name = "Auto";
    // Initialize with default values
    autoPreset.data.exposure = 0.0f;
    autoPreset.data.contrast = 1.0f;
    autoPreset.data.highlights = 0.0f;
    autoPreset.data.shadows = 0.0f;
    autoPreset.data.whites = 0.0f;
    autoPreset.data.blacks = 0.0f;
    autoPreset.data.saturation = 1.0f;
    autoPreset.data.vibrance = 0.0f;
    autoPreset.data.hue_offset = 0.0f;
    autoPreset.data.temperature = 0.0f;
    autoPreset.data.tint = 0.0f;
    autoPreset.data.vignette_strength = 0.0f;
    autoPreset.data.vignette_feather = 0.5f;
    autoPreset.data.vignette_size = 0.5f;
    autoPreset.data.grain_amount = 0.0f;
    autoPreset.data.hsl_enabled = 0;
    
    // Constants
    autoPreset.data.contrast_pivot = 0.18f;
    autoPreset.data.blacks_scale = 0.1f;
    autoPreset.data.whites_scale = 0.2f;
    autoPreset.data.hsl_enabled = 0;
    for(int i=0; i<15; ++i) autoPreset.data.hsl_adjustments[i] = {0.0f, 0.0f, 0.0f, 0.0f};
    
    m_Presets.push_back(autoPreset);
    
    // Load from file
    std::ifstream in("presets.txt");
    if (in.is_open()) {
        std::string line;
        Preset currentPreset;
        std::string currentData;
        bool readingData = false;
        
        while (std::getline(in, line)) {
            if (line.rfind("PRESET:", 0) == 0) {
                if (readingData) {
                    DeserializeUniforms(currentData, currentPreset.data);
                    m_Presets.push_back(currentPreset);
                    currentData.clear();
                }
                currentPreset.name = line.substr(7);
                readingData = true;
            } else if (readingData) {
                currentData += line + "\n";
            }
        }
        if (readingData) {
            DeserializeUniforms(currentData, currentPreset.data);
            m_Presets.push_back(currentPreset);
        }
        in.close();
    }
}

void UmbriferaApp::SavePresets() {
    std::ofstream out("presets.txt");
    if (out.is_open()) {
        // Skip default preset (index 0)
        for (size_t i = 1; i < m_Presets.size(); i++) {
            out << "PRESET:" << m_Presets[i].name << "\n";
            out << SerializeUniforms(m_Presets[i].data);
        }
        out.close();
    }
}

void UmbriferaApp::ApplyPreset(const Preset& preset) {
    // Preserve base exposure and constants as they should never change
    float currentBaseExposure = m_Uniforms.base_exposure;
    float currentContrastPivot = m_Uniforms.contrast_pivot;
    float currentBlacksScale = m_Uniforms.blacks_scale;
    float currentWhitesScale = m_Uniforms.whites_scale;
    
    m_Uniforms = preset.data;
    
    m_Uniforms.base_exposure = currentBaseExposure;
    m_Uniforms.contrast_pivot = currentContrastPivot;
    m_Uniforms.blacks_scale = currentBlacksScale;
    m_Uniforms.whites_scale = currentWhitesScale;
}

void UmbriferaApp::CalculateAutoSettings() {
    if (m_RawHistogram.empty()) return;
    
    // Analyze Raw Histogram (256 bins)
    // We want to find the range of the data and the mean.
    
    long totalPixels = 0;
    long sumLuma = 0;
    int minBin = -1;
    int maxBin = -1;
    
    for (int i = 0; i < 256; i++) {
        uint32_t count = m_RawHistogram[i];
        if (count > 0) {
            if (minBin == -1) minBin = i;
            maxBin = i;
            totalPixels += count;
            sumLuma += (long)count * i;
        }
    }
    
    if (totalPixels == 0) return;
    
    float meanLuma = (float)sumLuma / totalPixels / 255.0f; // 0.0 - 1.0
    float minLuma = (float)minBin / 255.0f;
    float maxLuma = (float)maxBin / 255.0f;
    
    // 1. Auto Exposure
    // Target mean luma around mid-grey (0.18) but slightly brighter for "pleasing" look (e.g. 0.25)
    // But raw data is linear, so 0.18 is actually quite dark visually.
    // Let's target 0.18 in linear space.
    float targetMean = 0.18f;
    
    // Avoid division by zero or extreme values
    if (meanLuma < 0.001f) meanLuma = 0.001f;
    
    // Exposure shift = log2(Target / Current)
    float exposureShift = log2f(targetMean / meanLuma);
    
    // Clamp exposure shift to reasonable range
    exposureShift = std::clamp(exposureShift, -3.0f, 3.0f);
    
    m_Uniforms.exposure = exposureShift;
    
    // 2. Auto Contrast
    // Default to slightly boosted contrast
    m_Uniforms.contrast = 1.1f;
    
    // 3. Auto Blacks/Whites (Dynamic Range Expansion)
    // We want to stretch the histogram to fill 0.0 - 1.0
    // After exposure shift, the new min/max will be:
    // newMin = minLuma * 2^exposure
    // newMax = maxLuma * 2^exposure
    
    float gain = powf(2.0f, exposureShift);
    float newMin = minLuma * gain;
    float newMax = maxLuma * gain;
    
    // Blacks: We want newMin to map to 0.0
    // Formula: (x - black_point) / (white_point - black_point)
    // black_point = -blacks * 0.1
    // So we want -blacks * 0.1 approx newMin
    // blacks = -newMin / 0.1 = -newMin * 10
    
    // Whites: We want newMax to map to 1.0
    // white_point = 1.0 - whites * 0.2
    // So we want 1.0 - whites * 0.2 approx newMax
    // whites * 0.2 = 1.0 - newMax
    // whites = (1.0 - newMax) / 0.2 = (1.0 - newMax) * 5
    
    float autoBlacks = -newMin * 10.0f;
    float autoWhites = (1.0f - newMax) * 5.0f;
    
    m_Uniforms.blacks = std::clamp(autoBlacks, -0.5f, 0.5f); // Don't crush too much
    m_Uniforms.whites = std::clamp(autoWhites, -0.5f, 0.5f); // Don't blow out too much
    
    // 4. Auto Vibrance/Saturation
    // Just set reasonable defaults
    m_Uniforms.vibrance = 0.2f;
    m_Uniforms.saturation = 1.0f;
    
    // Reset others
    m_Uniforms.highlights = 0.0f;
    m_Uniforms.shadows = 0.0f;
    m_Uniforms.temperature = 0.0f;
    m_Uniforms.tint = 0.0f;
    
    // Trigger update
    m_ImageDirty = true;
}
@implementation MenuHandler
- (void)exportJpg:(id)sender {
    if (_app) {
        _app->OpenExportDialog("jpg");
    }
}
- (void)exportPng:(id)sender {
    if (_app) {
        _app->OpenExportDialog("png");
    }
}
- (void)exportTiff:(id)sender {
    if (_app) {
        _app->OpenExportDialog("tiff");
    }
}
- (void)resetLayout:(id)sender {
    if (_app) {
        // Set a flag to reset layout during the next frame
        // Can't call DockBuilder here as we're outside the ImGui frame context
        _app->m_ResetLayoutRequested = true;
    }
}
- (void)resizeImage:(id)sender {
    if (_app) {
        _app->OpenResizeDialog();
    }
}
@end

static MenuHandler* g_MenuHandler = nil;

void UmbriferaApp::SetupMacOSMenu() {
    if (g_MenuHandler == nil) {
        g_MenuHandler = [[MenuHandler alloc] init];
        g_MenuHandler.app = this;
    }

    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    [NSApp setMainMenu:mainMenu];

    // 1. App Menu (Umbrifera)
    NSMenuItem* appMenuItem = [mainMenu addItemWithTitle:@"Umbrifera" action:nil keyEquivalent:@""];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"Umbrifera"];
    [appMenuItem setSubmenu:appMenu];

    [appMenu addItemWithTitle:@"About Umbrifera" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Umbrifera" action:@selector(terminate:) keyEquivalent:@"q"];

    // 2. Export Menu (Top Level)
    NSMenuItem* exportMenuItem = [mainMenu addItemWithTitle:@"Export" action:nil keyEquivalent:@""];
    NSMenu* exportMenu = [[NSMenu alloc] initWithTitle:@"Export"];
    [exportMenuItem setSubmenu:exportMenu];
    
    NSMenuItem* jpgItem = [exportMenu addItemWithTitle:@"Export as JPG..." action:@selector(exportJpg:) keyEquivalent:@"e"];
    [jpgItem setTarget:g_MenuHandler];
    
    NSMenuItem* pngItem = [exportMenu addItemWithTitle:@"Export as PNG..." action:@selector(exportPng:) keyEquivalent:@""];
    [pngItem setTarget:g_MenuHandler];
    
    NSMenuItem* tiffItem = [exportMenu addItemWithTitle:@"Export as TIFF..." action:@selector(exportTiff:) keyEquivalent:@""];
    [tiffItem setTarget:g_MenuHandler];
    
    // 3. View Menu
    NSMenuItem* viewMenuItem = [mainMenu addItemWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu* viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    [viewMenuItem setSubmenu:viewMenu];
    
    NSMenuItem* resetLayoutItem = [viewMenu addItemWithTitle:@"Reset Layout" action:@selector(resetLayout:) keyEquivalent:@"r"];
    [resetLayoutItem setTarget:g_MenuHandler];

    // 4. Tools Menu
    NSMenuItem* toolsMenuItem = [mainMenu addItemWithTitle:@"Tools" action:nil keyEquivalent:@""];
    NSMenu* toolsMenu = [[NSMenu alloc] initWithTitle:@"Tools"];
    [toolsMenuItem setSubmenu:toolsMenu];
    
    NSMenuItem* resizeItem = [toolsMenu addItemWithTitle:@"Resize" action:@selector(resizeImage:) keyEquivalent:@""];
    [resizeItem setTarget:g_MenuHandler];
}

void UmbriferaApp::UpdateMacOSMenu() {
    // Can update menu state here if needed (e.g. disable items during export)
}
