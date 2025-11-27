#include "UmbriferaApp.h"
#include "imgui.h"
#include "imgui_internal.h" // For DockBuilder API
#include "imgui_impl_glfw.h"
#include <stdio.h>

#define GLFW_EXPOSE_NATIVE_COCOA
#include "imgui_impl_metal.h"
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

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
    m_Uniforms.tonemap_mode = 1; // Default to ACES
}

UmbriferaApp::~UmbriferaApp() {
    Shutdown();
}

bool UmbriferaApp::Init() {
    glfwSetErrorCallback(glfw_error_callback);
    if (!glfwInit())
        return false;

    InitWindow();
    InitGraphics();
    InitImGui();

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
    
    // Build font atlas with proper Retina texture
    io.Fonts->Build();
    
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
    colors[ImGuiCol_Tab]                    = ImVec4(0.18f, 0.18f, 0.18f, 0.86f);
    colors[ImGuiCol_TabHovered]             = ImVec4(0.26f, 0.59f, 0.98f, 0.80f);
    colors[ImGuiCol_TabActive]              = ImVec4(0.20f, 0.20f, 0.20f, 1.00f);
    colors[ImGuiCol_TabUnfocused]           = ImVec4(0.07f, 0.10f, 0.15f, 0.97f);
    colors[ImGuiCol_TabUnfocusedActive]     = ImVec4(0.14f, 0.14f, 0.14f, 1.00f);
    colors[ImGuiCol_DockingPreview]         = ImVec4(0.26f, 0.59f, 0.98f, 0.70f);
    colors[ImGuiCol_DockingEmptyBg]         = ImVec4(0.20f, 0.20f, 0.20f, 1.00f);
    colors[ImGuiCol_PlotLines]              = ImVec4(0.61f, 0.61f, 0.61f, 1.00f);
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
    // Start loading the default image
    LoadRawImage("image.NEF");
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
    m_ExportFormat = format;
    m_ShowExportOptions = true;
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
    // Does nothing for now
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
