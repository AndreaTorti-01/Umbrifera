#include "ImagoApp.h"
#include "imgui.h"
#include "imgui_internal.h" // For DockBuilder API
#include "imgui_impl_glfw.h"
#include <stdio.h>
#import <Cocoa/Cocoa.h>

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

ImagoApp::ImagoApp() {
    // Initialize uniforms to defaults
    // Each slider default appears here, making it easy to update centrally
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
    m_Uniforms.grain_size = 1.0f;
    m_Uniforms.clarity = 0.0f;
    m_Uniforms.denoise_luma = 0.0f;
    m_Uniforms.denoise_chroma = 0.0f;
    m_Uniforms.sharpen_intensity = 0.0f;
    
    // Initialize Constants (immutable, not reset by auto adjust)
    m_Uniforms.contrast_pivot = 0.18f; // Mid-grey
    m_Uniforms.blacks_scale = 0.1f;
    m_Uniforms.whites_scale = 0.2f;
    
    // Initialize Color Grading Wheels
    m_Uniforms.cg_shadows_x = 0.0f;
    m_Uniforms.cg_shadows_y = 0.0f;
    m_Uniforms.cg_midtones_x = 0.0f;
    m_Uniforms.cg_midtones_y = 0.0f;
    m_Uniforms.cg_highlights_x = 0.0f;
    m_Uniforms.cg_highlights_y = 0.0f;
    
    // Initialize HSL System
    m_Uniforms.num_hsl_groups = 0;
    for (int i = 0; i < 16; i++) {
        m_Uniforms.hsl_groups[i].hue = 0.0f;
        m_Uniforms.hsl_groups[i].hue_shift = 0.0f;
        m_Uniforms.hsl_groups[i].saturation = 1.0f;
        m_Uniforms.hsl_groups[i].luminance = 1.0f;
        m_Uniforms.hsl_groups[i].width = 0.15f;
        m_Uniforms.hsl_groups[i].enabled = 0.0f;
    }
    
    LoadPresets();
    
    m_FileNavigator = std::make_unique<FileNavigator>();
}

ImagoApp::~ImagoApp() {
    Shutdown();
}

bool ImagoApp::Init() {
    glfwSetErrorCallback(glfw_error_callback);
    if (!glfwInit())
        return false;

    InitWindow();
    InitGraphics(); // Sets up m_Device
    InitImGui();
    
    m_FileNavigator->Init(m_Device);

    return true;
}

void ImagoApp::InitWindow() {
    // We don't want an OpenGL context, so we say NO_API
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    glfwWindowHint(GLFW_MAXIMIZED, GLFW_TRUE);
    m_Window = glfwCreateWindow(1280, 720, "Imago", nullptr, nullptr);
    
    SetupMacOSMenu();
}

void ImagoApp::InitImGui() {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO(); (void)io;
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable;

    // Set imgui.ini path to bundle resources
    static std::string iniPathStr;
    NSString* resourcePath = [[NSBundle mainBundle] resourcePath];
    NSString* iniPath = [resourcePath stringByAppendingPathComponent:@"imgui.ini"];
    iniPathStr = [iniPath UTF8String];
    io.IniFilename = iniPathStr.c_str();
    
    // If no layout has ever been set, request a reset to default layout
    if (![[NSFileManager defaultManager] fileExistsAtPath:iniPath]) {
        m_ResetLayoutRequested = true;
    }

    // Get display scale for Retina/HiDPI support
    NSScreen *mainScreen = [NSScreen mainScreen];
    CGFloat scale = [mainScreen backingScaleFactor];
    
    // Use standard font size (the rendering will be scaled by ImGui)
    float fontSize = 16.0f;
    
    // Load MacOS System Font with antialiasing
    ImFontConfig fontConfig;
    fontConfig.OversampleH = 2; // Improve horizontal antialiasing
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

void ImagoApp::InitGraphics() {
    InitMetal();
    
    m_RotateCWTexture = LoadAssetTexture("rotate_90_degrees_cw_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_RotateCCWTexture = LoadAssetTexture("rotate_90_degrees_ccw_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_CropTexture = LoadAssetTexture("crop_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_CropRotateTexture = LoadAssetTexture("crop_rotate_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_FitScreenTexture = LoadAssetTexture("fit_screen_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_UndoTexture = LoadAssetTexture("undo_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_CompareTexture = LoadAssetTexture("compare_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_EyedropperTexture = LoadAssetTexture("dropper_eye_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    m_CloseTexture = LoadAssetTexture("close_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
}

id<MTLTexture> ImagoApp::LoadAssetTexture(const std::string& filename) {
    // Load from bundle Resources/assets
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* fileNameNS = [NSString stringWithUTF8String:filename.c_str()];
    NSString* nsPath = [bundle pathForResource:[fileNameNS stringByDeletingPathExtension] 
                                        ofType:[fileNameNS pathExtension] 
                                   inDirectory:@"assets"];
    
    if (!nsPath) {
        std::cerr << "Failed to find asset in bundle: " << filename << std::endl;
        return nil;
    }
    
    NSImage* image = [[NSImage alloc] initWithContentsOfFile:nsPath];
    if (!image) {
        std::cerr << "Failed to load asset: " << filename << std::endl;
        return nil;
    }
    
    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    NSUInteger width = CGImageGetWidth(cgImage);
    NSUInteger height = CGImageGetHeight(cgImage);
    
    MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    id<MTLTexture> texture = [m_Device newTextureWithDescriptor:textureDescriptor];
    
    NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [texture replaceRegion:region mipmapLevel:0 withBytes:[rep bitmapData] bytesPerRow:[rep bytesPerRow]];
    
    return texture;
}

void ImagoApp::Run() {
    while (!glfwWindowShouldClose(m_Window)) {
        glfwPollEvents();
        RenderFrame();
    }
}

void ImagoApp::Shutdown() {
    CleanupMetal();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    if (m_Window) {
        glfwDestroyWindow(m_Window);
        m_Window = nullptr;
    }
    glfwTerminate();
}

void ImagoApp::UpdateUniforms() {
    // Track grain_size changes to trigger regeneration
    static float lastGrainSize = -1.0f;
    if (lastGrainSize != m_Uniforms.grain_size) {
        m_GrainNeedsRegeneration = true;
        lastGrainSize = m_Uniforms.grain_size;
    }
    
    // Update clipping indicator flag
    m_Uniforms.show_clipping_indicator = m_ShowClippingIndicator ? 1 : 0;
    
    UpdateMacOSMenu();
}

// Helper interface to handle menu actions
@interface MenuHandler : NSObject
@property (nonatomic, assign) ImagoApp* app;
- (void)exportJpg:(id)sender;
- (void)exportPng:(id)sender;
- (void)exportTiff:(id)sender;
- (void)resetLayout:(id)sender;
- (void)resizeImage:(id)sender;
- (void)toggleButtonBarPosition:(id)sender;
 - (void)resetThumbnailsCache:(id)sender;
@end

void ImagoApp::OpenExportDialog(const std::string& format) {
    // Prevent opening export dialog if no image is loaded
    if (!m_ProcessedTexture) {
        return;
    }

    m_ExportFormat = format;
    m_ShowExportOptions = true;
    // Note: m_ShowExportOptions will be cleared after the popup is opened in RenderUI
}

// --- Serialization ---

std::string ImagoApp::SerializeUniforms(const Uniforms& u) {
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
    ss << "clarity=" << u.clarity << "\n";
    ss << "denoise_luma=" << u.denoise_luma << "\n";
    ss << "denoise_chroma=" << u.denoise_chroma << "\n";
    ss << "sharpen_intensity=" << u.sharpen_intensity << "\n";
    ss << "base_exposure=" << u.base_exposure << "\n";
    
    // Color Grading Wheels
    ss << "cg_shadows_x=" << u.cg_shadows_x << "\n";
    ss << "cg_shadows_y=" << u.cg_shadows_y << "\n";
    ss << "cg_midtones_x=" << u.cg_midtones_x << "\n";
    ss << "cg_midtones_y=" << u.cg_midtones_y << "\n";
    ss << "cg_highlights_x=" << u.cg_highlights_x << "\n";
    ss << "cg_highlights_y=" << u.cg_highlights_y << "\n";
    
    // HSL System
    ss << "num_hsl_groups=" << u.num_hsl_groups << "\n";
    for (int i = 0; i < 16; i++) {
        ss << "hsl_" << i << "_hue=" << u.hsl_groups[i].hue << "\n";
        ss << "hsl_" << i << "_hue_shift=" << u.hsl_groups[i].hue_shift << "\n";
        ss << "hsl_" << i << "_saturation=" << u.hsl_groups[i].saturation << "\n";
        ss << "hsl_" << i << "_luminance=" << u.hsl_groups[i].luminance << "\n";
        ss << "hsl_" << i << "_width=" << u.hsl_groups[i].width << "\n";
        ss << "hsl_" << i << "_enabled=" << u.hsl_groups[i].enabled << "\n";
    }
    
    return ss.str();
}

void ImagoApp::DeserializeUniforms(const std::string& data, Uniforms& u) {
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
            else if (key == "clarity") u.clarity = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "denoise_luma") u.denoise_luma = std::clamp(std::stof(valStr), 0.0f, 1.0f);
            else if (key == "denoise_chroma") u.denoise_chroma = std::clamp(std::stof(valStr), 0.0f, 1.0f);
            else if (key == "sharpen_intensity") u.sharpen_intensity = std::clamp(std::stof(valStr), 0.0f, 1.0f);
            else if (key == "base_exposure") u.base_exposure = std::stof(valStr);
            // Color Grading Wheels
            else if (key == "cg_shadows_x") u.cg_shadows_x = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "cg_shadows_y") u.cg_shadows_y = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "cg_midtones_x") u.cg_midtones_x = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "cg_midtones_y") u.cg_midtones_y = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "cg_highlights_x") u.cg_highlights_x = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            else if (key == "cg_highlights_y") u.cg_highlights_y = std::clamp(std::stof(valStr), -1.0f, 1.0f);
            // HSL System
            else if (key == "num_hsl_groups") u.num_hsl_groups = std::clamp(std::stoi(valStr), 0, 16);
            else if (key.find("hsl_") == 0) {
                size_t firstUnderscore = key.find('_');
                size_t secondUnderscore = key.find('_', firstUnderscore + 1);
                if (firstUnderscore != std::string::npos && secondUnderscore != std::string::npos) {
                    int index = std::stoi(key.substr(firstUnderscore + 1, secondUnderscore - firstUnderscore - 1));
                    std::string subkey = key.substr(secondUnderscore + 1);
                    if (index >= 0 && index < 16) {
                        if (subkey == "hue") u.hsl_groups[index].hue = std::clamp(std::stof(valStr), 0.0f, 1.0f);
                        else if (subkey == "hue_shift") u.hsl_groups[index].hue_shift = std::clamp(std::stof(valStr), -1.0f, 1.0f);
                        else if (subkey == "saturation") u.hsl_groups[index].saturation = std::clamp(std::stof(valStr), 0.0f, 2.0f);
                        else if (subkey == "luminance") u.hsl_groups[index].luminance = std::clamp(std::stof(valStr), 0.0f, 2.0f);
                        else if (subkey == "width") u.hsl_groups[index].width = std::clamp(std::stof(valStr), 0.01f, 0.5f);
                        else if (subkey == "enabled") u.hsl_groups[index].enabled = std::stof(valStr);
                    }
                }
            }
        } catch (...) {
            // Ignore parsing errors and keep defaults/current values
        }
    }
}

void ImagoApp::SaveSidecar() {
    if (m_LoadedImagePath.empty()) return;
    
    std::string sidecarPath = m_LoadedImagePath + ".xmp";
    std::ofstream out(sidecarPath);
    if (out.is_open()) {
        out << SerializeUniforms(m_Uniforms);
        out.close();
    }
}

void ImagoApp::LoadSidecar() {
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

void ImagoApp::ResetThumbnailsCache() {
    if (m_FileNavigator) {
        m_FileNavigator->ClearThumbnailCache();
    }
}

// --- Presets ---

void ImagoApp::LoadPresets() {
    m_Presets.clear();
    
    // Auto Preset (Special - calls CalculateAutoSettings)
    Preset autoPreset;
    autoPreset.name = "Auto";
    // Initialize with default values using the centralized defaults
    autoPreset.data = GetDefaultUniforms();
    
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

void ImagoApp::SavePresets() {
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

void ImagoApp::ApplyPreset(const Preset& preset) {
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

void ImagoApp::CalculateAutoSettings() {
    if (m_RawHistogram.empty()) return;
    
    // Get default Uniforms for resetting
    Uniforms defaults = GetDefaultUniforms();
    
    // Store the original exposure/contrast/blacks/whites for restoration
    // These are the only values we calculate in auto mode
    float autoExposure = 0.0f;
    float autoContrast = 1.12f;
    float autoBlacks = 0.0f;
    float autoWhites = 0.0f;
    float autoVibrance = 0.1f;
    
    // Analyze Raw Histogram (256 bins)
    // Find the range and distribution of tonal values
    
    long totalPixels = 0;
    long sumLuma = 0;
    int minBin = -1;
    int maxBin = -1;
    
    // Find percentile points for robust black/white point detection
    // Ignore extreme 0.5% on each end to avoid outliers
    long runningCount = 0;
    int percentile05 = 0;  // 0.5th percentile
    int percentile995 = 255; // 99.5th percentile
    bool found05 = false;
    
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
    
    // Second pass: find percentiles
    long threshold05 = (long)(totalPixels * 0.005f);
    long threshold995 = (long)(totalPixels * 0.995f);
    runningCount = 0;
    
    for (int i = 0; i < 256; i++) {
        runningCount += m_RawHistogram[i];
        if (!found05 && runningCount >= threshold05) {
            percentile05 = i;
            found05 = true;
        }
        if (runningCount >= threshold995) {
            percentile995 = i;
            break;
        }
    }
    
    float meanLuma = (float)sumLuma / totalPixels / 255.0f; // 0.0 - 1.0
    float minLuma = (float)percentile05 / 255.0f;  // Robust min (0.5th percentile)
    float maxLuma = (float)percentile995 / 255.0f; // Robust max (99.5th percentile)
    
    // 1. Auto Exposure
    // Be conservative: don't force every image to mid-grey
    // Only adjust if significantly off from reasonable range
    float targetMean = 0.18f;
    
    if (meanLuma < 0.001f) meanLuma = 0.001f;
    
    // Calculate what exposure would center the image
    float fullShift = log2f(targetMean / meanLuma);
    
    // Apply only partial correction to preserve intended brightness
    // Dark images stay somewhat dark, bright images stay somewhat bright
    float exposureShift = fullShift * 0.6f; // 60% correction
    exposureShift = std::clamp(exposureShift, -2.5f, 2.5f);
    
    autoExposure = exposureShift;
    
    // 2. Auto Contrast
    // Moderate contrast boost for punch
    autoContrast = 1.12f;
    
    // 3. Auto Blacks/Whites
    // With new Gaussian model, these are additive adjustments
    // Calculate how much to adjust based on histogram endpoints
    
    float gain = powf(2.0f, exposureShift);
    float newMin = minLuma * gain; // Predicted min after exposure
    float newMax = maxLuma * gain; // Predicted max after exposure
    
    // Blacks: if newMin > 0, we have room to deepen blacks
    // Slider value of 1.0 with weight 0.15 adds 0.15 to luma
    // We want to shift blacks down if there's headroom
    // autoBlacks negative = darken blacks
    if (newMin > 0.02f) {
        // There's room to set a black point
        // Scale: newMin of 0.1 -> blacks of -0.5 (moderate darkening)
        autoBlacks = -std::clamp(newMin * 5.0f, 0.0f, 0.6f);
    }
    
    // Whites: if newMax < 1, we have room to brighten whites
    // autoWhites positive = brighten whites  
    if (newMax < 0.95f) {
        // There's room to extend whites
        // Scale: newMax of 0.8 -> whites of 0.5 (moderate brightening)
        autoWhites = std::clamp((1.0f - newMax) * 2.5f, 0.0f, 0.5f);
    }
    
    autoBlacks = std::clamp(autoBlacks, -1.0f, 1.0f);
    autoWhites = std::clamp(autoWhites, -1.0f, 1.0f);
    
    // 5. Modest vibrance, neutral saturation
    autoVibrance = 0.1f;
    
    // === Reset all uniforms to defaults, then apply auto-calculated values ===
    // This ensures future sliders are automatically included without code changes
    
    // Store base_exposure and constants separately - these are not reset by auto
    float savedBaseExposure = m_Uniforms.base_exposure;
    float savedContrastPivot = m_Uniforms.contrast_pivot;
    float savedBlacksScale = m_Uniforms.blacks_scale;
    float savedWhitesScale = m_Uniforms.whites_scale;
    
    // Reset to defaults (including HSL controls)
    m_Uniforms = defaults;
    
    // Restore immutable values (constants only, not user-editable sliders)
    m_Uniforms.base_exposure = savedBaseExposure;
    m_Uniforms.contrast_pivot = savedContrastPivot;
    m_Uniforms.blacks_scale = savedBlacksScale;
    m_Uniforms.whites_scale = savedWhitesScale;
    
    // Now apply auto-calculated values
    m_Uniforms.exposure = autoExposure;
    m_Uniforms.contrast = autoContrast;
    m_Uniforms.blacks = autoBlacks;
    m_Uniforms.whites = autoWhites;
    m_Uniforms.vibrance = autoVibrance;
    m_Uniforms.saturation = 1.0f;
    
    // Trigger update
    m_ImageDirty = true;
}

void ImagoApp::SampleHueAt(float normX, float normY) {
    if (!m_ProcessedTexture) return;
    
    int width = (int)m_ProcessedTexture.width;
    int height = (int)m_ProcessedTexture.height;
    
    // Map normalized coordinates to pixel coordinates
    int px = (int)(normX * width);
    int py = (int)(normY * height);
    
    // Clamp
    px = std::clamp(px, 0, width - 1);
    py = std::clamp(py, 0, height - 1);
    
    // Sample a 3x3 window around the point
    const int radius = 1;
    float sumR = 0, sumG = 0, sumB = 0, sumCount = 0;
    
    int regionX = std::max(0, px - radius);
    int regionY = std::max(0, py - radius);
    int regionW = std::min(width - regionX, radius * 2 + 1);
    int regionH = std::min(height - regionY, radius * 2 + 1);
    
    std::vector<uint8_t> pixels(regionW * regionH * 4);
    MTLRegion region = MTLRegionMake2D(regionX, regionY, regionW, regionH);
    
    [m_ProcessedTexture getBytes:pixels.data() bytesPerRow:regionW * 4 fromRegion:region mipmapLevel:0];
    
    for (int y = 0; y < regionH; y++) {
        for (int x = 0; x < regionW; x++) {
            int idx = (y * regionW + x) * 4;
            // BGRA8Unorm
            float b = pixels[idx] / 255.0f;
            float g = pixels[idx + 1] / 255.0f;
            float r = pixels[idx + 2] / 255.0f;
            
            sumR += r;
            sumG += g;
            sumB += b;
            sumCount += 1.0f;
        }
    }
    
    if (sumCount > 0) {
        float r = sumR / sumCount;
        float g = sumG / sumCount;
        float b = sumB / sumCount;
        
        // Convert to HSV
        float h, s, v;
        ImGui::ColorConvertRGBtoHSV(r, g, b, h, s, v);
        
        // Check saturation threshold (e.g., 0.05)
        if (s > 0.05f && m_Uniforms.num_hsl_groups < 16) {
            int idx = m_Uniforms.num_hsl_groups;
            m_Uniforms.hsl_groups[idx].hue = h;
            m_Uniforms.hsl_groups[idx].hue_shift = 0.0f;
            m_Uniforms.hsl_groups[idx].saturation = 1.0f;
            m_Uniforms.hsl_groups[idx].luminance = 1.0f;
            m_Uniforms.hsl_groups[idx].width = 0.15f;
            m_Uniforms.hsl_groups[idx].enabled = 1.0f;
            m_Uniforms.num_hsl_groups++;
            m_ImageDirty = true;
        }
    }
}

ColorSample ImagoApp::SampleColorAt(float normX, float normY) {
    if (!m_ProcessedTexture) return {0, 0, 0, 1};
    
    int width = (int)m_ProcessedTexture.width;
    int height = (int)m_ProcessedTexture.height;
    
    // Map normalized coordinates to pixel coordinates
    int px = (int)(normX * width);
    int py = (int)(normY * height);
    
    // Clamp
    px = std::clamp(px, 0, width - 1);
    py = std::clamp(py, 0, height - 1);
    
    // Sample a 3x3 window around the point
    const int radius = 1;
    float sumR = 0, sumG = 0, sumB = 0, sumCount = 0;
    
    int regionX = std::max(0, px - radius);
    int regionY = std::max(0, py - radius);
    int regionW = std::min(width - regionX, radius * 2 + 1);
    int regionH = std::min(height - regionY, radius * 2 + 1);
    
    std::vector<uint8_t> pixels(regionW * regionH * 4);
    MTLRegion region = MTLRegionMake2D(regionX, regionY, regionW, regionH);
    
    [m_ProcessedTexture getBytes:pixels.data() bytesPerRow:regionW * 4 fromRegion:region mipmapLevel:0];
    
    for (int y = 0; y < regionH; y++) {
        for (int x = 0; x < regionW; x++) {
            int idx = (y * regionW + x) * 4;
            // BGRA8Unorm
            float b = pixels[idx] / 255.0f;
            float g = pixels[idx + 1] / 255.0f;
            float r = pixels[idx + 2] / 255.0f;
            
            sumR += r;
            sumG += g;
            sumB += b;
            sumCount += 1.0f;
        }
    }
    
    if (sumCount > 0) {
        return {sumR / sumCount, sumG / sumCount, sumB / sumCount, 1.0f};
    }
    return {0, 0, 0, 1};
}

Uniforms ImagoApp::GetDefaultUniforms() const {
    Uniforms defaults = {};
    
    // Slider defaults (these appear in the UI and are user-editable)
    defaults.exposure = 0.0f;
    defaults.contrast = 1.0f;
    defaults.highlights = 0.0f;
    defaults.shadows = 0.0f;
    defaults.whites = 0.0f;
    defaults.blacks = 0.0f;
    defaults.saturation = 1.0f;
    defaults.vibrance = 0.0f;
    defaults.hue_offset = 0.0f;
    defaults.temperature = 0.0f;
    defaults.tint = 0.0f;
    defaults.vignette_strength = 0.0f;
    defaults.vignette_feather = 0.5f;
    defaults.vignette_size = 0.5f;
    defaults.grain_amount = 0.0f;
    defaults.grain_size = 1.0f;
    defaults.clarity = 0.0f;
    defaults.denoise_luma = 0.0f;
    defaults.denoise_chroma = 0.0f;
    defaults.sharpen_intensity = 0.0f;
    defaults.base_exposure = 0.0f;
    
    // Constants (not user-editable)
    defaults.contrast_pivot = 0.18f;
    defaults.blacks_scale = 0.1f;
    defaults.whites_scale = 0.2f;
    
    // Color Grading Wheels (all centered by default)
    defaults.cg_shadows_x = 0.0f;
    defaults.cg_shadows_y = 0.0f;
    defaults.cg_midtones_x = 0.0f;
    defaults.cg_midtones_y = 0.0f;
    defaults.cg_highlights_x = 0.0f;
    defaults.cg_highlights_y = 0.0f;
    
    // HSL System
    defaults.num_hsl_groups = 0;
    for (int i = 0; i < 16; i++) {
        defaults.hsl_groups[i].hue = 0.0f;
        defaults.hsl_groups[i].hue_shift = 0.0f;
        defaults.hsl_groups[i].saturation = 1.0f;
        defaults.hsl_groups[i].luminance = 1.0f;
        defaults.hsl_groups[i].width = 0.15f; // Default Gaussian width
        defaults.hsl_groups[i].enabled = 0.0f;
    }
    
    return defaults;
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
- (void)toggleButtonBarPosition:(id)sender {
    if (_app) {
        _app->m_ButtonBarAtTop = !_app->m_ButtonBarAtTop;
        // Update menu item state
        NSMenuItem* item = (NSMenuItem*)sender;
        [item setState:_app->m_ButtonBarAtTop ? NSControlStateValueOn : NSControlStateValueOff];
    }
}
 - (void)resetThumbnailsCache:(id)sender {
    if (_app) {
        _app->ResetThumbnailsCache();
    }
}
@end

static MenuHandler* g_MenuHandler = nil;

void ImagoApp::SetupMacOSMenu() {
    if (g_MenuHandler == nil) {
        g_MenuHandler = [[MenuHandler alloc] init];
        g_MenuHandler.app = this;
    }

    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
    [NSApp setMainMenu:mainMenu];

    // 1. App Menu (Imago)
    NSMenuItem* appMenuItem = [mainMenu addItemWithTitle:@"Imago" action:nil keyEquivalent:@""];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"Imago"];
    [appMenuItem setSubmenu:appMenu];

    [appMenu addItemWithTitle:@"About Imago" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Imago" action:@selector(terminate:) keyEquivalent:@"q"];

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
    
    NSMenuItem* toggleButtonBarItem = [viewMenu addItemWithTitle:@"Toolbar at Top" action:@selector(toggleButtonBarPosition:) keyEquivalent:@""];
    [toggleButtonBarItem setTarget:g_MenuHandler];
    [toggleButtonBarItem setState:NSControlStateValueOff];

    // 4. Tools Menu
    NSMenuItem* toolsMenuItem = [mainMenu addItemWithTitle:@"Tools" action:nil keyEquivalent:@""];
    NSMenu* toolsMenu = [[NSMenu alloc] initWithTitle:@"Tools"];
    [toolsMenuItem setSubmenu:toolsMenu];
    
    NSMenuItem* resizeItem = [toolsMenu addItemWithTitle:@"Resize" action:@selector(resizeImage:) keyEquivalent:@""];
    [resizeItem setTarget:g_MenuHandler];

    // 5. More Menu (Reset cache, misc)
    NSMenuItem* moreMenuItem = [mainMenu addItemWithTitle:@"More" action:nil keyEquivalent:@""];
    NSMenu* moreMenu = [[NSMenu alloc] initWithTitle:@"More"];
    [moreMenuItem setSubmenu:moreMenu];

    NSMenuItem* resetThumbs = [moreMenu addItemWithTitle:@"Reset Thumbnails Cache" action:@selector(resetThumbnailsCache:) keyEquivalent:@""];
    [resetThumbs setTarget:g_MenuHandler];
}

void ImagoApp::UpdateMacOSMenu() {
    // Can update menu state here if needed (e.g. disable items during export)
}
