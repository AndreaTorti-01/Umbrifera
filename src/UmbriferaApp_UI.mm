#include "UmbriferaApp.h"
#include "UIConfig.h"
#include "UIHelpers.h"
#include "imgui.h"
#include "imgui_internal.h"
#include <GLFW/glfw3.h>
#include <jpeglib.h>

// This file handles the User Interface (UI) rendering using Dear ImGui.
// It defines how the windows, buttons, and images look and behave.

// Local helper for sliders (uses UIHelpers version internally)
static bool SliderWithReset(const char* label, float* v, float v_min, float v_max, float default_val, const char* format = "%.3f") {
    return UIHelpers::SliderWithReset(label, v, v_min, v_max, default_val, format);
}

// Aliases for backward compatibility with existing code
static void UI_Separator() { UIHelpers::Separator(); }
static void UI_Header(const char* text) { UIHelpers::Header(text); }
static void UI_GapSmall() { UIHelpers::GapSmall(); }
static void UI_GapLarge() { UIHelpers::GapLarge(); }

void UmbriferaApp::SetupLayout() {
    // This function runs once to set up the initial window layout.
    if (m_FirstLayout) {
        ImGui::SetNextWindowSize(ImVec2(300, 600), ImGuiCond_FirstUseEver);
        m_FirstLayout = false;
    }
}

void UmbriferaApp::OpenResizeDialog() {
    if (!m_ProcessedTexture) return;
    
    m_ShowResizeDialog = true;
    m_ResizeTargetWidth = (int)m_RawTexture.width;
    m_ResizeTargetHeight = (int)m_RawTexture.height;
}

void UmbriferaApp::RenderUI() {
    // Loading Modal (Blocks interaction)
    if (m_IsLoading) {
        if (!ImGui::IsPopupOpen("Loading...")) {
            ImGui::OpenPopup("Loading...");
        }
    }
    
    ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
    if (ImGui::BeginPopupModal("Loading...", NULL, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar)) {
        ImGui::Text("Loading Image...");
        
        // Simple Spinner Animation
        float time = (float)ImGui::GetTime();
        float angle = time * 6.0f;
        float radius = 20.0f;
        ImVec2 center = ImGui::GetCursorScreenPos();
        center.x += 100.0f; // Center in 200px window
        center.y += 30.0f;
        
        ImGui::GetWindowDrawList()->PathClear();
        int num_segments = 30;
        for (int i = 0; i < num_segments; i++) {
            float a = angle + ((float)i / (float)num_segments) * 2.0f * 3.14159f;
            ImGui::GetWindowDrawList()->PathLineTo(ImVec2(center.x + cosf(a) * radius, center.y + sinf(a) * radius));
        }
        ImGui::GetWindowDrawList()->PathStroke(ImGui::GetColorU32(ImGuiCol_Text), 0, 3.0f);
        
        ImGui::Dummy(ImVec2(200, 60)); // Space for spinner
        
        if (!m_IsLoading) {
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }

    // Export Options Modal
    static bool wasPopupOpen = false;
    bool isPopupOpen = false;
    
    if (m_ShowExportOptions && m_ProcessedTexture) { // Only allow if image loaded
        std::string title = m_ExportFormat == "jpg" ? "JPG Export" : (m_ExportFormat == "png" ? "PNG Export" : "TIFF Export");
        ImGui::OpenPopup(title.c_str());
        ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
        m_ShowExportOptions = false; // Clear so we can detect next open
    }
    
    std::string title = m_ExportFormat == "jpg" ? "JPG Export" : (m_ExportFormat == "png" ? "PNG Export" : "TIFF Export");
    
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10.0f, 10.0f));
    if (ImGui::BeginPopupModal(title.c_str(), NULL, ImGuiWindowFlags_AlwaysAutoResize)) {
        isPopupOpen = true;
        
        // Helper for consistent spacing
        auto SeparatorBlock = []() { 
            ImGui::Dummy(ImVec2(0.0f, 10.0f)); 
            ImGui::Separator(); 
            ImGui::Dummy(ImVec2(0.0f, 10.0f)); 
        };

        // Top Margin
        ImGui::Dummy(ImVec2(0.0f, 10.0f));
        
        // Default filename from loaded image
        static char filename[128] = "export";
        static bool filenameInitialized = false;
        if (!filenameInitialized && !m_LoadedImagePath.empty()) {
            // Extract filename without extension
            size_t lastSlash = m_LoadedImagePath.find_last_of("/\\");
            size_t lastDot = m_LoadedImagePath.find_last_of(".");
            std::string baseName = m_LoadedImagePath.substr(lastSlash + 1, lastDot - lastSlash - 1);
            strncpy(filename, baseName.c_str(), sizeof(filename) - 1);
            filename[sizeof(filename) - 1] = '\0';
            filenameInitialized = true;
        }
        
        ImGui::PushStyleColor(ImGuiCol_FrameBg, ImVec4(0.2f, 0.4f, 0.8f, 0.6f)); // Highlight filename box
        ImGui::InputText("Filename", filename, IM_ARRAYSIZE(filename));
        ImGui::PopStyleColor();
        
        // Separator between Filename and Options
        SeparatorBlock();
        
        if (m_ExportFormat == "jpg") {
            // Track if settings changed to trigger re-estimation
            static int lastQuality = m_ExportQuality;
            static int lastSubsampling = m_ExportSubsampling;
            static bool lastProgressive = m_ExportProgressive;
            static bool estimationTriggered = false;
            
            // Reset on dialog open (when popup just opened)
            if (!wasPopupOpen && isPopupOpen) {
                estimationTriggered = false;
            }
            
            bool settingsChanged = (lastQuality != m_ExportQuality || 
                                   lastSubsampling != m_ExportSubsampling || 
                                   lastProgressive != m_ExportProgressive);
            
            // Trigger estimation on first open or when settings change
            if ((settingsChanged || !estimationTriggered) && !m_IsEstimatingSize && m_ProcessedTexture) {
                lastQuality = m_ExportQuality;
                lastSubsampling = m_ExportSubsampling;
                lastProgressive = m_ExportProgressive;
                estimationTriggered = true;
                
                // Trigger size estimation in background thread
                m_IsEstimatingSize = true;
                if (m_SizeEstimationThread.joinable()) m_SizeEstimationThread.join();
                
                m_SizeEstimationThread = std::thread([this]() {
                    int width = (int)m_ProcessedTexture.width;
                    int height = (int)m_ProcessedTexture.height;
                    
                    // Read a downscaled version for estimation (1/4 scale = 1/16 pixels)
                    int sampleWidth = width / 4;
                    int sampleHeight = height / 4;
                    if (sampleWidth < 100) sampleWidth = width;
                    if (sampleHeight < 100) sampleHeight = height;
                    
                    std::vector<uint8_t> samplePixels(sampleWidth * sampleHeight * 4);
                    
                    // Sample from the texture
                    std::vector<uint8_t> fullPixels(width * height * 4);
                    [m_ProcessedTexture getBytes:fullPixels.data() bytesPerRow:width * 4 fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
                    
                    // Downsample (simple nearest neighbor)
                    for (int y = 0; y < sampleHeight; y++) {
                        for (int x = 0; x < sampleWidth; x++) {
                            int srcX = x * width / sampleWidth;
                            int srcY = y * height / sampleHeight;
                            for (int c = 0; c < 4; c++) {
                                samplePixels[(y * sampleWidth + x) * 4 + c] = fullPixels[(srcY * width + srcX) * 4 + c];
                            }
                        }
                    }
                    
                    // Swap BGRA to RGB
                    std::vector<uint8_t> rgbSample(sampleWidth * sampleHeight * 3);
                    for (int i = 0; i < sampleWidth * sampleHeight; i++) {
                        rgbSample[i * 3 + 0] = samplePixels[i * 4 + 2]; // R
                        rgbSample[i * 3 + 1] = samplePixels[i * 4 + 1]; // G
                        rgbSample[i * 3 + 2] = samplePixels[i * 4 + 0]; // B
                    }
                    
                    // Compress to memory
                    struct jpeg_compress_struct cinfo;
                    struct jpeg_error_mgr jerr;
                    cinfo.err = jpeg_std_error(&jerr);
                    jpeg_create_compress(&cinfo);
                    
                    unsigned char* outbuffer = nullptr;
                    unsigned long outsize = 0;
                    jpeg_mem_dest(&cinfo, &outbuffer, &outsize);
                    
                    cinfo.image_width = sampleWidth;
                    cinfo.image_height = sampleHeight;
                    cinfo.input_components = 3;
                    cinfo.in_color_space = JCS_RGB;
                    
                    jpeg_set_defaults(&cinfo);
                    jpeg_set_quality(&cinfo, m_ExportQuality, TRUE);
                    
                    if (m_ExportProgressive) jpeg_simple_progression(&cinfo);
                    
                    // Subsampling
                    if (m_ExportSubsampling == 0) {
                        cinfo.comp_info[0].h_samp_factor = 1;
                        cinfo.comp_info[0].v_samp_factor = 1;
                    } else if (m_ExportSubsampling == 1) {
                        cinfo.comp_info[0].h_samp_factor = 2;
                        cinfo.comp_info[0].v_samp_factor = 1;
                    } else {
                        cinfo.comp_info[0].h_samp_factor = 2;
                        cinfo.comp_info[0].v_samp_factor = 2;
                    }
                    
                    jpeg_start_compress(&cinfo, TRUE);
                    
                    JSAMPROW row_pointer[1];
                    int row_stride = sampleWidth * 3;
                    while (cinfo.next_scanline < cinfo.image_height) {
                        row_pointer[0] = &rgbSample[cinfo.next_scanline * row_stride];
                        jpeg_write_scanlines(&cinfo, row_pointer, 1);
                    }
                    
                    jpeg_finish_compress(&cinfo);
                    
                    // Extrapolate size
                    float scaleFactor = (float)(width * height) / (float)(sampleWidth * sampleHeight);
                    int estimatedBytes = (int)(outsize * scaleFactor);
                    m_EstimatedSizeKB = estimatedBytes / 1024;
                    
                    jpeg_destroy_compress(&cinfo);
                    if (outbuffer) free(outbuffer);
                    
                    m_IsEstimatingSize = false;
                });
                
                m_SizeEstimationThread.detach();
            }
            
            // Quality slider
            ImGui::SliderInt("Quality", &m_ExportQuality, 1, 100);
            
            ImGui::Dummy(ImVec2(0.0f, 5.0f));

            // Progressive checkbox BELOW the slider
            ImGui::Checkbox("Optimize for Web (Progressive)", &m_ExportProgressive);
            
            ImGui::Dummy(ImVec2(0.0f, 5.0f));

            const char* subsampling_items[] = { 
                "Maximum Detail (Larger File)", 
                "Balanced", 
                "Web Standard (Recommended)" 
            };
            ImGui::Combo("Color Detail", &m_ExportSubsampling, subsampling_items, IM_ARRAYSIZE(subsampling_items));
            
            ImGui::Dummy(ImVec2(0.0f, 10.0f));

            // Size preview - Moved to bottom right
            if (m_IsEstimatingSize) {
                const char* text = "Calculating file size...";
                float textWidth = ImGui::CalcTextSize(text).x;
                ImGui::SetCursorPosX(ImGui::GetWindowWidth() - textWidth - ImGui::GetStyle().WindowPadding.x);
                ImGui::TextDisabled("%s", text);
            } else if (m_EstimatedSizeKB > 0) {
                char buffer[64];
                if (m_EstimatedSizeKB < 1024) {
                    snprintf(buffer, sizeof(buffer), "Estimated size: ~%d KB", (int)m_EstimatedSizeKB);
                } else {
                    snprintf(buffer, sizeof(buffer), "Estimated size: ~%.1f MB", m_EstimatedSizeKB / 1024.0f);
                }
                float textWidth = ImGui::CalcTextSize(buffer).x;
                ImGui::SetCursorPosX(ImGui::GetWindowWidth() - textWidth - ImGui::GetStyle().WindowPadding.x);
                ImGui::Text("%s", buffer);
            }
            
        } else if (m_ExportFormat == "png") {
            // PNG - no options, no text
            ImGui::TextDisabled("No options available for PNG.");
        } else if (m_ExportFormat == "tiff") {
            // Simplified TIFF Compression Toggle
            ImGui::Checkbox("Optimize File Size (Lossless)", &m_ExportTiffCompression);
            
            ImGui::Dummy(ImVec2(0.0f, 5.0f));

            const char* depth_items[] = { "8-bit", "16-bit" };
            int current_depth_idx = (m_ExportTiffDepth == 16) ? 1 : 0;
            if (ImGui::Combo("Bit Depth", &current_depth_idx, depth_items, IM_ARRAYSIZE(depth_items))) {
                m_ExportTiffDepth = (current_depth_idx == 1) ? 16 : 8;
            }
        }
        
        // Separator between Options and Buttons
        SeparatorBlock();

        // Center buttons
        float buttonWidth = 120.0f;
        float spacing = ImGui::GetStyle().ItemSpacing.x;
        float totalWidth = buttonWidth * 2 + spacing;
        float startX = (ImGui::GetWindowWidth() - totalWidth) * 0.5f;
        
        ImGui::SetCursorPosX(startX);
        if (ImGui::Button("Export", ImVec2(buttonWidth, 0))) {
            std::string fullPath;
            
            // Export to same directory as loaded image
            if (!m_LoadedImagePath.empty()) {
                size_t lastSlash = m_LoadedImagePath.find_last_of("/\\");
                std::string dir = m_LoadedImagePath.substr(0, lastSlash + 1);
                fullPath = dir + std::string(filename) + "." + m_ExportFormat;
            } else {
                fullPath = std::string(filename) + "." + m_ExportFormat;
            }
            
            // Check if file exists
            std::ifstream checkFile(fullPath);
            if (checkFile.good()) {
                checkFile.close();
                m_PendingExportPath = fullPath;
                m_ShowExportOptions = false; // Close export options
                ImGui::CloseCurrentPopup();
                m_ShowOverwriteConfirm = true; // Show overwrite dialog
            } else {
                SaveImageAsync(fullPath, m_ExportFormat);
                m_ShowExportOptions = false;
                ImGui::CloseCurrentPopup();
            }
        }
        ImGui::SetItemDefaultFocus();
        ImGui::SameLine();
        if (ImGui::Button("Cancel", ImVec2(buttonWidth, 0))) {
            m_ShowExportOptions = false;
            ImGui::CloseCurrentPopup();
        }
        
        // Bottom Margin
        ImGui::Dummy(ImVec2(0.0f, 10.0f));
        
        ImGui::EndPopup();
    }
    ImGui::PopStyleVar();
    
    // Update state for next frame
    wasPopupOpen = isPopupOpen;
    
    // Overwrite Confirmation Dialog (SEPARATE from Export Options)
    if (m_ShowOverwriteConfirm) {
        ImGui::OpenPopup("Confirm Overwrite");
        ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
    }
    
    if (ImGui::BeginPopupModal("Confirm Overwrite", NULL, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::Text("File already exists:");
        ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "%s", m_PendingExportPath.c_str());
        ImGui::Spacing();
        ImGui::Text("Do you want to overwrite it?");
        ImGui::Separator();
        
        if (ImGui::Button("Overwrite", ImVec2(120, 0))) {
            SaveImageAsync(m_PendingExportPath, m_ExportFormat);
            m_ShowOverwriteConfirm = false;
            ImGui::CloseCurrentPopup();
        }
        ImGui::SetItemDefaultFocus();
        ImGui::SameLine();
        if (ImGui::Button("Cancel", ImVec2(120, 0))) {
            m_ShowOverwriteConfirm = false;
            ImGui::CloseCurrentPopup();
        }
        ImGui::EndPopup();
    }
    
    // Export Progress Overlay
    if (m_IsExporting) {
        ImGui::OpenPopup("Exporting...");
        ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
        if (ImGui::BeginPopupModal("Exporting...", NULL, ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar)) {
            ImGui::Text("Exporting Image...");
            ImGui::ProgressBar(m_ExportProgress, ImVec2(200, 0));
            ImGui::EndPopup();
        }
    }
    
    // Resize Dialog
    if (m_ShowResizeDialog && m_RawTexture) {
        ImGui::OpenPopup("Resize Image");
        UIHelpers::CenterNextWindow();
        m_ShowResizeDialog = false;
    }
    
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(UIConfig::DIALOG_PADDING, UIConfig::DIALOG_PADDING));
    if (ImGui::BeginPopupModal("Resize Image", NULL, UIHelpers::ModalFlags())) {
        static int editingField = 0; // 0 = none, 1 = width, 2 = height
        static char widthBuf[16] = "";
        static char heightBuf[16] = "";
        static bool initialized = false;
        
        int originalWidth = (int)m_RawTexture.width;
        int originalHeight = (int)m_RawTexture.height;
        float aspectRatio = (float)originalWidth / (float)originalHeight;
        
        // Initialize buffers on first open
        if (!initialized) {
            snprintf(widthBuf, sizeof(widthBuf), "%d", m_ResizeTargetWidth);
            snprintf(heightBuf, sizeof(heightBuf), "%d", m_ResizeTargetHeight);
            initialized = true;
        }
        
        // Top margin
        UIHelpers::GapSmall();
        
        // Original size display
        ImGui::Text("Original Size: %d x %d pixels", originalWidth, originalHeight);
        
        UIHelpers::GapSmall();
        
        // Layout: Input fields on left, labels on right
        float inputWidth = 80.0f;
        
        // Width row: [input] Width (pixels)
        ImGui::SetNextItemWidth(inputWidth);
        if (ImGui::InputText("##ResizeWidth", widthBuf, sizeof(widthBuf), ImGuiInputTextFlags_CharsDecimal)) {
            std::string str(widthBuf);
            
            size_t start = str.find_first_not_of('0');
            if (start == std::string::npos) {
                str = str.empty() ? "" : "0";
            } else if (start > 0) {
                str = str.substr(start);
            }
            
            if (!str.empty()) {
                int val = std::atoi(str.c_str());
                if (val > originalWidth) val = originalWidth;
                if (val < 1) val = 1;
                
                m_ResizeTargetWidth = val;
                m_ResizeTargetHeight = (int)((float)val / aspectRatio + 0.5f);
                if (m_ResizeTargetHeight < 1) m_ResizeTargetHeight = 1;
                if (m_ResizeTargetHeight > originalHeight) m_ResizeTargetHeight = originalHeight;
                
                snprintf(widthBuf, sizeof(widthBuf), "%d", m_ResizeTargetWidth);
                snprintf(heightBuf, sizeof(heightBuf), "%d", m_ResizeTargetHeight);
            }
        }
        ImGui::SameLine();
        ImGui::Text("Width (pixels)");
        
        // Height row: [input] Height (pixels)
        ImGui::SetNextItemWidth(inputWidth);
        if (ImGui::InputText("##ResizeHeight", heightBuf, sizeof(heightBuf), ImGuiInputTextFlags_CharsDecimal)) {
            std::string str(heightBuf);
            
            size_t start = str.find_first_not_of('0');
            if (start == std::string::npos) {
                str = str.empty() ? "" : "0";
            } else if (start > 0) {
                str = str.substr(start);
            }
            
            if (!str.empty()) {
                int val = std::atoi(str.c_str());
                if (val > originalHeight) val = originalHeight;
                if (val < 1) val = 1;
                
                m_ResizeTargetHeight = val;
                m_ResizeTargetWidth = (int)((float)val * aspectRatio + 0.5f);
                if (m_ResizeTargetWidth < 1) m_ResizeTargetWidth = 1;
                if (m_ResizeTargetWidth > originalWidth) m_ResizeTargetWidth = originalWidth;
                
                snprintf(widthBuf, sizeof(widthBuf), "%d", m_ResizeTargetWidth);
                snprintf(heightBuf, sizeof(heightBuf), "%d", m_ResizeTargetHeight);
            }
        }
        ImGui::SameLine();
        ImGui::Text("Height (pixels)");
        
        UIHelpers::Separator();
        
        // Centered buttons
        int result = UIHelpers::CenteredButtonPair("Resize", "Cancel");
        if (result == 1) {
            // Perform resize using Lanczos3 shader
            if (m_ResizeTargetWidth > 0 && m_ResizeTargetHeight > 0 &&
                m_ResizeTargetWidth <= originalWidth && m_ResizeTargetHeight <= originalHeight &&
                (m_ResizeTargetWidth != originalWidth || m_ResizeTargetHeight != originalHeight)) {
                
                // Create new resized raw texture
                MTLTextureDescriptor* newRawDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm 
                    width:m_ResizeTargetWidth height:m_ResizeTargetHeight mipmapped:NO];
                newRawDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
                id<MTLTexture> newRawTexture = [m_Device newTextureWithDescriptor:newRawDesc];
                
                // Run box filter downscale compute shader
                struct DownscaleParams {
                    uint32_t srcWidth;
                    uint32_t srcHeight;
                    uint32_t dstWidth;
                    uint32_t dstHeight;
                } params = {
                    (uint32_t)originalWidth,
                    (uint32_t)originalHeight,
                    (uint32_t)m_ResizeTargetWidth,
                    (uint32_t)m_ResizeTargetHeight
                };
                
                id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
                id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
                [ce setComputePipelineState:m_Lanczos3PSO];
                [ce setTexture:m_RawTexture atIndex:0];
                [ce setTexture:newRawTexture atIndex:1];
                [ce setBytes:&params length:sizeof(params) atIndex:0];
                
                MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
                MTLSize threadgroups = MTLSizeMake(
                    (m_ResizeTargetWidth + 15) / 16,
                    (m_ResizeTargetHeight + 15) / 16, 1);
                
                [ce dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
                [ce endEncoding];
                [cb commit];
                [cb waitUntilCompleted];
                
                // Replace raw texture
                m_RawTexture = newRawTexture;
                
                // Create new processed texture
                MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm 
                    width:m_ResizeTargetWidth height:m_ResizeTargetHeight mipmapped:YES];
                NSUInteger maxDim = (m_ResizeTargetWidth > m_ResizeTargetHeight) ? m_ResizeTargetWidth : m_ResizeTargetHeight;
                NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
                targetDesc.mipmapLevelCount = mipLevels;
                targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
                
                // Reset view
                m_ViewZoom = 1.0f;
                m_ViewOffset[0] = 0.0f;
                m_ViewOffset[1] = 0.0f;
                
                // Trigger reprocess
                m_ImageDirty = true;
            }
            
            initialized = false;
            ImGui::CloseCurrentPopup();
        }
        if (result == 2) {
            initialized = false;
            ImGui::CloseCurrentPopup();
        }
        
        UIHelpers::GapSmall();
        
        ImGui::EndPopup();
    }
    ImGui::PopStyleVar();

    // Create a DockSpace that covers the whole application window.
    // This allows us to drag and drop windows inside the app.
    // ImGuiDockNodeFlags_NoWindowMenuButton: Removes the small triangle button on the tab bar
    ImGuiID dockspace_id = ImGui::DockSpaceOverViewport(0, ImGui::GetMainViewport(), ImGuiDockNodeFlags_NoWindowMenuButton);

    // Handle reset layout request
    if (m_ResetLayoutRequested) {
        ImGui::DockBuilderRemoveNode(dockspace_id);
        ImGui::DockBuilderAddNode(dockspace_id, ImGuiDockNodeFlags_DockSpace);
        
        ImGui::DockBuilderSetNodeSize(dockspace_id, ImGui::GetMainViewport()->Size);
        
        ImGuiID dock_id_left = ImGui::DockBuilderSplitNode(dockspace_id, ImGuiDir_Left, 0.20f, nullptr, &dockspace_id);
        ImGuiID dock_id_right = ImGui::DockBuilderSplitNode(dockspace_id, ImGuiDir_Right, 0.25f, nullptr, &dockspace_id);
        
        ImGui::DockBuilderDockWindow("Navigator", dock_id_left);
        ImGui::DockBuilderDockWindow("Image Viewer", dockspace_id);
        ImGui::DockBuilderDockWindow("Develop", dock_id_right);
        
        ImGui::DockBuilderFinish(dockspace_id);
        m_ResetLayoutRequested = false;
    }
    
    // Draw File Navigator
    if (m_FileNavigator) {
        if (m_LogoTexture) {
            m_FileNavigator->SetLogo(m_LogoTexture);
        }
        m_FileNavigator->Render([this](std::string path) {
            LoadRawImage(path);
        });
    }

    // --- Center Window: Image Viewer ---
    // This is where we display the photo.
    ImGui::Begin("Image Viewer");
    
    // Update application window title with EXIF data
    if (!m_ExifString.empty() || !m_ExifString2.empty()) {
        std::string windowTitle = "Umbrifera";
        if (!m_ExifString.empty()) {
            windowTitle += " | " + m_ExifString;
        }
        if (!m_ExifString2.empty()) {
            windowTitle += " | " + m_ExifString2;
        }
        glfwSetWindowTitle(m_Window, windowTitle.c_str());
    }
    
    if (m_ProcessedTexture) {
        // Margins (uses centralized config value)
        float buttonBarHeight = ImGui::GetFrameHeight() + 20.0f;
        float margin = UIConfig::IMAGE_MARGIN;
        
        ImVec2 windowSize = ImGui::GetContentRegionAvail();
        
        // Canvas Size: Window - Margins
        // Width: Window - Left Margin - Right Margin
        // Height: Window - Top Margin - Bottom Margin - ButtonBarHeight
        ImVec2 availSize = ImVec2(windowSize.x - 2.0f * margin, windowSize.y - 2.0f * margin - buttonBarHeight);
        
        // Apply Left and Top Margin
        ImGui::SetCursorPosX(ImGui::GetCursorPosX() + margin);
        ImGui::SetCursorPosY(ImGui::GetCursorPosY() + margin);
        
        ImVec2 cursorScreenPos = ImGui::GetCursorScreenPos();
        
        // 1. Invisible Button for Input Capture
        ImGui::SetNextItemAllowOverlap();
        ImGui::InvisibleButton("canvas", availSize);
        
        bool isHovered = ImGui::IsItemHovered();
        bool isActive = ImGui::IsItemActive();
        
        // Calculate Fit Scale
        float aspect = (float)m_ProcessedTexture.width / (float)m_ProcessedTexture.height;
        float scaleX = availSize.x / (float)m_ProcessedTexture.width;
        float scaleY = availSize.y / (float)m_ProcessedTexture.height;
        float fitScale = (scaleX < scaleY) ? scaleX : scaleY;
        
        // Calculate Final Scale
        float finalScale = fitScale * m_ViewZoom;
        
        // Calculate Display Size
        float dispW = m_ProcessedTexture.width * finalScale;
        float dispH = m_ProcessedTexture.height * finalScale;
        
        // Calculate Center Position (Canvas Center + Offset)
        float centerX = cursorScreenPos.x + availSize.x * 0.5f + m_ViewOffset[0] * dispW;
        float centerY = cursorScreenPos.y + availSize.y * 0.5f + m_ViewOffset[1] * dispH;
        
        ImVec2 p_min = ImVec2(centerX - dispW * 0.5f, centerY - dispH * 0.5f);
        ImVec2 p_max = ImVec2(centerX + dispW * 0.5f, centerY + dispH * 0.5f);
        
        // Draw Image with Clipping
        ImGui::PushClipRect(cursorScreenPos, ImVec2(cursorScreenPos.x + availSize.x, cursorScreenPos.y + availSize.y), true);
        ImGui::GetWindowDrawList()->AddImage((ImTextureID)m_ProcessedTexture, p_min, p_max);
        ImGui::PopClipRect();
        
        // Handle Input
        ImGuiIO& io = ImGui::GetIO();
        
        // Zoom
        if (isHovered && io.MouseWheel != 0.0f) {
            float zoomSpeed = 0.1f;
            float oldZoom = m_ViewZoom;
            float newZoom = oldZoom + io.MouseWheel * zoomSpeed * oldZoom;
            if (newZoom < 0.1f) newZoom = 0.1f;
            if (newZoom > 10.0f) newZoom = 10.0f;
            
            // Zoom towards mouse
            ImVec2 mousePos = ImGui::GetMousePos();
            
            // Calculate new center to keep mouse over same pixel
            float ratio = newZoom / oldZoom;
            float newCenterX = mousePos.x - (mousePos.x - centerX) * ratio;
            float newCenterY = mousePos.y - (mousePos.y - centerY) * ratio;
            
            // Update Offset
            float canvasCenterX = cursorScreenPos.x + availSize.x * 0.5f;
            float canvasCenterY = cursorScreenPos.y + availSize.y * 0.5f;
            
            float newDispW = m_ProcessedTexture.width * fitScale * newZoom;
            float newDispH = m_ProcessedTexture.height * fitScale * newZoom;
            
            m_ViewOffset[0] = (newCenterX - canvasCenterX) / newDispW;
            m_ViewOffset[1] = (newCenterY - canvasCenterY) / newDispH;
            
            m_ViewZoom = newZoom;
        }
        
        // Pan
        if (isActive && ImGui::IsMouseDragging(ImGuiMouseButton_Left)) {
            ImVec2 delta = io.MouseDelta;
            m_ViewOffset[0] += delta.x / dispW;
            m_ViewOffset[1] += delta.y / dispH;
        }
        
        // Buttons at bottom
        // Calculate position for button row (after canvas + margin)
        ImVec2 winPos = ImGui::GetWindowPos();
        ImVec2 winSize = ImGui::GetWindowSize();
        
        // Position button bar at the very bottom of the window area
        float btnRowY = winPos.y + winSize.y - buttonBarHeight;
        ImVec2 btnRowMin = ImVec2(winPos.x, btnRowY);
        ImVec2 btnRowMax = ImVec2(winPos.x + winSize.x, btnRowY + buttonBarHeight);
        
        ImGui::GetWindowDrawList()->AddRectFilled(btnRowMin, btnRowMax, ImGui::GetColorU32(ImGuiCol_MenuBarBg));
        
        // Vertically center buttons in the row
        float btnY = btnRowMin.y + (buttonBarHeight - ImGui::GetFrameHeight()) * 0.5f;
        
        // Reset View (Centered in Window)
        const char* resetLabel = "Reset View";
        float resetWidth = ImGui::CalcTextSize(resetLabel).x + 20.0f; // Standard padding
        ImGui::SetCursorScreenPos(ImVec2(winPos.x + (winSize.x - resetWidth) * 0.5f, btnY));
        if (ImGui::Button(resetLabel, ImVec2(resetWidth, 0))) {
            m_ViewZoom = 1.0f;
            m_ViewOffset[0] = 0.0f;
            m_ViewOffset[1] = 0.0f;
        }
        
        // Crop (Right Aligned with margin)
        const char* cropLabel = "Crop";
        float cropWidth = ImGui::CalcTextSize(cropLabel).x + 20.0f;
        ImGui::SetCursorScreenPos(ImVec2(winPos.x + winSize.x - cropWidth - 20.0f, btnY));
        if (ImGui::Button(cropLabel, ImVec2(cropWidth, 0))) {
            // TODO: Implement crop functionality
        }
        
    } else {
        // Tutorial Text when no image is loaded
        ImVec2 windowSize = ImGui::GetContentRegionAvail();
        ImVec2 center = ImGui::GetCursorScreenPos();
        center.x += windowSize.x * 0.5f;
        center.y += windowSize.y * 0.5f;
        
        const char* text1 = "Welcome to Umbrifera";
        const char* text2 = "Use the File Navigator on the left to open a RAW image.";
        const char* text3 = "Right-click a folder to set it as the root directory.";
        const char* text4 = "Use the top menu to Export your work.";
        const char* text5 = "Click on any slider label to reset its value.";
        
        auto RenderCenteredText = [&](const char* text, float yOffset) {
            ImVec2 textSize = ImGui::CalcTextSize(text);
            ImGui::SetCursorScreenPos(ImVec2(center.x - textSize.x * 0.5f, center.y + yOffset));
            ImGui::Text("%s", text);
        };
        
        RenderCenteredText(text1, -60);
        RenderCenteredText(text2, -20);
        RenderCenteredText(text3, 0);
        RenderCenteredText(text4, 20);
        RenderCenteredText(text5, 40);
    }
    ImGui::End();
    


    // --- Right Window: Develop ---
    ImGui::Begin("Develop");
    
    // Disable controls if no image
    if (!m_ProcessedTexture) {
        ImGui::BeginDisabled();
    }
    
    // Top Margin
    UI_GapSmall();

    // Histogram Display
    // Read back histogram data from GPU buffer (Use Display buffer which is stable)
    if (m_HistogramBufferDisplay) {
        uint32_t* ptr = (uint32_t*)[m_HistogramBufferDisplay contents];
        
        // Ensure size
        if (m_Histogram.size() != 256) m_Histogram.resize(256, 0.0f);
        
        // 1. Read and Linear Scaling
        float maxVal = 0.0f;
        
        // Find max value in the meaningful range (1-254) to avoid clipping spikes dominating
        for (int i = 0; i < 256; i++) {
            float currentCount = (float)ptr[i];
            
            // Direct read (smoothing is handled in display loop)
            m_Histogram[i] = currentCount;
            
            // Calculate max for scaling
            if (i > 0 && i < 255) {
                if (m_Histogram[i] > maxVal) maxVal = m_Histogram[i];
            }
        }
        
        if (maxVal <= 0.0f) maxVal = 1.0f;
        
        // 2. Draw Graph (256 Vertical Bars)
        ImVec2 canvas_pos = ImGui::GetCursorScreenPos();
        ImVec2 canvas_size = ImVec2(ImGui::GetContentRegionAvail().x, 100); // Taller for better detail
        
        ImDrawList* draw_list = ImGui::GetWindowDrawList();
        
        // Background (Slightly Lighter Grey)
        draw_list->AddRectFilled(canvas_pos, ImVec2(canvas_pos.x + canvas_size.x, canvas_pos.y + canvas_size.y), IM_COL32(40, 40, 40, 255));
        
        // Ensure smooth histogram is initialized
        if (m_SmoothHistogram.size() != 256) {
            m_SmoothHistogram.resize(256, 0.0f);
        }

        float dt = ImGui::GetIO().DeltaTime;
        float speed = 20.0f; // Tunable speed
        float alpha = 1.0f - expf(-speed * dt);
        if (alpha > 1.0f) alpha = 1.0f;

        float barWidth = canvas_size.x / 256.0f;
        
        for (int i = 0; i < 256; ++i) {
            float targetHeight = m_Histogram[i] / maxVal;
            if (targetHeight > 1.0f) targetHeight = 1.0f;
            
            // Apply smoothing
            m_SmoothHistogram[i] = m_SmoothHistogram[i] * (1.0f - alpha) + targetHeight * alpha;
            
            float normalizedHeight = m_SmoothHistogram[i];
            
            if (normalizedHeight > 0.001f) {
                float x1 = canvas_pos.x + (float)i * barWidth;
                float x2 = canvas_pos.x + (float)(i + 1) * barWidth;
                
                // Ensure continuity
                // ImGui handles subpixel coordinates, so x2 of this bin is x1 of next bin.
                
                float y1 = canvas_pos.y + canvas_size.y - normalizedHeight * canvas_size.y;
                float y2 = canvas_pos.y + canvas_size.y;
                
                draw_list->AddRectFilled(ImVec2(x1, y1), ImVec2(x2, y2), IM_COL32(200, 200, 200, 255));
            }
        }
        
        ImGui::Dummy(canvas_size);
    }
    
    UI_Separator();

    bool changed = false;

    // --- Presets ---
    UI_Header("Presets");
    // Removed border (false)
    ImGui::BeginChild("Presets", ImVec2(0, 80), false, ImGuiWindowFlags_HorizontalScrollbar);
    for (size_t i = 0; i < m_Presets.size(); i++) {
        if (i > 0) ImGui::SameLine();
        
        ImGui::PushID((int)i);
        if (ImGui::Button(m_Presets[i].name.c_str(), ImVec2(100, 60))) {
            // Special handling for "Auto" preset
            if (m_Presets[i].name == "Auto") {
                CalculateAutoSettings();
                SaveSidecar(); // Save the auto-calculated values
            } else {
                ApplyPreset(m_Presets[i]);
                SaveSidecar(); // Save immediately when preset applied
            }
            changed = true; // Trigger image update
        }
        
        // Context Menu for Deletion (except Auto)
        if (i > 0 && ImGui::BeginPopupContextItem()) {
            if (ImGui::MenuItem("Delete")) {
                m_Presets.erase(m_Presets.begin() + i);
                SavePresets();
                i--; // Adjust index
            }
            ImGui::EndPopup();
        }
        ImGui::PopID();
    }
    ImGui::EndChild();
    
    UI_Separator();
    
    // Removed BeginChild to remove the black rectangle border
    // ImGui::BeginChild("LightControls", ImVec2(0, 300), true);
    
    // White Balance
    UI_Header("White Balance");
    if (SliderWithReset("Temperature", &m_Uniforms.temperature, -1.0f, 1.0f, 0.0f)) changed = true;
    if (SliderWithReset("Tint", &m_Uniforms.tint, -1.0f, 1.0f, 0.0f)) changed = true;
    
    UI_Separator();
    
    // Light & Color
    UI_Header("Light & Color");
    if (SliderWithReset("Exposure", &m_Uniforms.exposure, -5.0f, 5.0f, 0.0f)) changed = true;
    if (SliderWithReset("Contrast", &m_Uniforms.contrast, 0.5f, 1.5f, 1.0f)) changed = true;
    
    UI_GapSmall();
    
    if (SliderWithReset("Highlights", &m_Uniforms.highlights, -1.0f, 1.0f, 0.0f)) changed = true;
    if (SliderWithReset("Shadows", &m_Uniforms.shadows, -1.0f, 1.0f, 0.0f)) changed = true;
    if (SliderWithReset("Whites", &m_Uniforms.whites, -1.0f, 1.0f, 0.0f)) changed = true;
    if (SliderWithReset("Blacks", &m_Uniforms.blacks, -1.0f, 1.0f, 0.0f)) changed = true;
    
    UI_GapSmall();
    
    if (SliderWithReset("Vibrance", &m_Uniforms.vibrance, -1.0f, 1.0f, 0.0f)) changed = true;
    if (SliderWithReset("Saturation", &m_Uniforms.saturation, 0.0f, 2.0f, 1.0f)) changed = true;
    
    // Custom Hue Offset Slider with non-linear sensitivity
    {
        float val = m_Uniforms.hue_offset;
        float sliderVal = cbrtf(m_Uniforms.hue_offset * 2.0f); 
        if (sliderVal > 1.0f) sliderVal = 1.0f;
        if (sliderVal < -1.0f) sliderVal = -1.0f;
        
        // Use SliderWithReset logic manually to handle non-linear mapping
        ImGui::PushID("HueOffset");
        if (ImGui::SliderFloat("##HueOffset", &sliderVal, -1.0f, 1.0f)) {
            m_Uniforms.hue_offset = sliderVal * sliderVal * sliderVal * 0.5f;
            changed = true;
        }
        ImGui::SameLine();
        if (ImGui::Button("Hue Offset")) {
            m_Uniforms.hue_offset = 0.0f;
            changed = true;
        }
        ImGui::PopID();
    }
    
    UI_Separator();
    
    // HSL Adjustments
    bool hsl_active = m_Uniforms.hsl_enabled != 0;
    if (ImGui::Checkbox("Enable HSL", &hsl_active)) {
        m_Uniforms.hsl_enabled = hsl_active ? 1 : 0;
        changed = true;
    }
    
    if (hsl_active) {
        UI_GapSmall();
        
        // Colors for headers (approximate)
        ImVec4 headerColors[15] = {
            ImVec4(1.0f, 0.0f, 0.0f, 1.0f), // Red
            ImVec4(1.0f, 0.25f, 0.0f, 1.0f),
            ImVec4(1.0f, 0.5f, 0.0f, 1.0f),
            ImVec4(1.0f, 0.75f, 0.0f, 1.0f),
            ImVec4(1.0f, 1.0f, 0.0f, 1.0f), // Yellow
            ImVec4(0.5f, 1.0f, 0.0f, 1.0f),
            ImVec4(0.0f, 1.0f, 0.0f, 1.0f), // Green
            ImVec4(0.0f, 1.0f, 0.5f, 1.0f),
            ImVec4(0.0f, 1.0f, 1.0f, 1.0f), // Cyan
            ImVec4(0.0f, 0.5f, 1.0f, 1.0f),
            ImVec4(0.0f, 0.0f, 1.0f, 1.0f), // Blue
            ImVec4(0.5f, 0.0f, 1.0f, 1.0f),
            ImVec4(0.75f, 0.0f, 1.0f, 1.0f),
            ImVec4(1.0f, 0.0f, 1.0f, 1.0f), // Magenta
            ImVec4(1.0f, 0.0f, 0.5f, 1.0f)
        };
        
        for (int i = 0; i < 15; i++) {
            ImGui::PushID(i);
            
            // Tint the reset buttons
            ImVec4 baseColor = headerColors[i];
            // Make it subtle for the button
            ImVec4 buttonColor = ImVec4(baseColor.x, baseColor.y, baseColor.z, 0.3f);
            ImVec4 buttonHover = ImVec4(baseColor.x, baseColor.y, baseColor.z, 0.5f);
            ImVec4 buttonActive = ImVec4(baseColor.x, baseColor.y, baseColor.z, 0.7f);
            
            ImGui::PushStyleColor(ImGuiCol_Button, buttonColor);
            ImGui::PushStyleColor(ImGuiCol_ButtonHovered, buttonHover);
            ImGui::PushStyleColor(ImGuiCol_ButtonActive, buttonActive);
            
            // Hue (Non-linear)
            float hVal = m_Uniforms.hsl_adjustments[i].x;
            float hSlider = cbrtf(hVal * 10.0f); 
            
            if (ImGui::SliderFloat("##Hue", &hSlider, -1.0f, 1.0f, "%.3f")) {
                m_Uniforms.hsl_adjustments[i].x = hSlider * hSlider * hSlider * 0.1f;
                changed = true;
            }
            ImGui::SameLine();
            if (ImGui::Button("Hue")) {
                m_Uniforms.hsl_adjustments[i].x = 0.0f;
                changed = true;
            }
            
            // Saturation
            float sVal = m_Uniforms.hsl_adjustments[i].y;
            float sSlider = cbrtf(sVal);
            if (ImGui::SliderFloat("##Sat", &sSlider, -1.0f, 1.0f, "%.3f")) {
                m_Uniforms.hsl_adjustments[i].y = sSlider * sSlider * sSlider;
                changed = true;
            }
            ImGui::SameLine();
            if (ImGui::Button("Saturation")) {
                m_Uniforms.hsl_adjustments[i].y = 0.0f;
                changed = true;
            }
            
            // Luminance
            float lVal = m_Uniforms.hsl_adjustments[i].z;
            float lSlider = cbrtf(lVal);
            if (ImGui::SliderFloat("##Lum", &lSlider, -1.0f, 1.0f, "%.3f")) {
                m_Uniforms.hsl_adjustments[i].z = lSlider * lSlider * lSlider;
                changed = true;
            }
            ImGui::SameLine();
            if (ImGui::Button("Luminance")) {
                m_Uniforms.hsl_adjustments[i].z = 0.0f;
                changed = true;
            }
            
            ImGui::PopStyleColor(3); // Pop button colors
            ImGui::PopID();
            
            // Gap after every color
            UI_GapSmall();
        }
    }
    
    UI_Separator();
    
    // Effects
    
    // Vignette
    UI_Header("Vignette");
    ImGui::PushID("VignetteControls");
    if (SliderWithReset("Strength", &m_Uniforms.vignette_strength, 0.0f, 1.0f, 0.0f)) changed = true;
    if (SliderWithReset("Size", &m_Uniforms.vignette_size, 0.0f, 1.0f, 0.5f)) changed = true;
    if (SliderWithReset("Feather", &m_Uniforms.vignette_feather, 0.0f, 1.0f, 0.5f)) changed = true;
    ImGui::PopID();
    
    UI_GapSmall();
    
    // Film Grain
    UI_Header("Film Grain");
    ImGui::PushID("GrainControls");
    if (SliderWithReset("Amount", &m_Uniforms.grain_amount, 0.0f, 1.0f, 0.0f)) changed = true;
    // Size slider removed as requested
    ImGui::PopID();
    
    // Save Preset Dialog
    if (m_ShowSavePresetDialog) {
        ImGui::OpenPopup("Save Preset");
        ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
    }
    
    if (ImGui::BeginPopupModal("Save Preset", NULL, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::Text("Enter preset name:");
        
        // Auto-focus input
        if (m_ShowSavePresetDialog) {
            ImGui::SetKeyboardFocusHere();
            m_ShowSavePresetDialog = false; // Only focus once
        }
        
        bool enterPressed = ImGui::InputText("##PresetName", m_NewPresetName, IM_ARRAYSIZE(m_NewPresetName), ImGuiInputTextFlags_EnterReturnsTrue);
        
        UI_Separator();
        
        if (ImGui::Button("Save", ImVec2(120, 0)) || enterPressed) {
            std::string newName = m_NewPresetName;
            // Trim whitespace
            const char* ws = " \t\n\r\f\v";
            newName.erase(newName.find_last_not_of(ws) + 1);
            newName.erase(0, newName.find_first_not_of(ws));

            if (newName.length() > 0) {
                // Check for duplicate
                bool exists = false;
                for (const auto& p : m_Presets) {
                    if (p.name == newName) {
                        exists = true;
                        break;
                    }
                }
                
                if (exists) {
                    // Close current dialog and open overwrite confirmation via flag
                    ImGui::CloseCurrentPopup();
                    m_ShowPresetOverwriteConfirm = true;
                } else {
                    Preset newPreset;
                    newPreset.name = newName;
                    newPreset.data = m_Uniforms;
                    m_Presets.push_back(newPreset);
                    SavePresets();
                    ImGui::CloseCurrentPopup();
                }
            }
        }
        ImGui::SameLine();
        if (ImGui::Button("Cancel", ImVec2(120, 0))) {
            ImGui::CloseCurrentPopup();
        }
        
        ImGui::EndPopup();
    }
    
    if (m_ShowPresetOverwriteConfirm) {
        ImGui::OpenPopup("Confirm Preset Overwrite");
        ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
        m_ShowPresetOverwriteConfirm = false;
    }

    // Overwrite Confirmation Dialog (separate, not nested)
    if (ImGui::BeginPopupModal("Confirm Preset Overwrite", NULL, ImGuiWindowFlags_AlwaysAutoResize)) {
        ImGui::Text("Preset already exists:");
        ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.2f, 1.0f), "%s", m_NewPresetName);
        ImGui::Spacing();
        ImGui::Text("Do you want to overwrite it?");
        
        UI_Separator();
        
        if (ImGui::Button("Overwrite", ImVec2(120, 0))) {
            // Find and replace
            for (auto& p : m_Presets) {
                if (p.name == m_NewPresetName) {
                    p.data = m_Uniforms;
                    break;
                }
            }
            SavePresets();
            ImGui::CloseCurrentPopup();
        }
        ImGui::SameLine();
        if (ImGui::Button("Cancel", ImVec2(120, 0))) {
            ImGui::CloseCurrentPopup();
        }
        
        ImGui::EndPopup();
    }
    
    // --- Sidecar Saving ---
    // Check if any slider was released or toggle changed
    if (changed || ImGui::IsItemDeactivatedAfterEdit()) {
        SaveSidecar();
    }
    ImGui::Dummy(ImVec2(0.0f, 20.0f));
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0.0f, 20.0f));

    // Save Preset Button (Moved to bottom)
    float availWidth = ImGui::GetContentRegionAvail().x;
    float buttonWidth = 150.0f;
    ImGui::SetCursorPosX((availWidth - buttonWidth) * 0.5f + ImGui::GetCursorPosX());
    if (ImGui::Button("Save Preset", ImVec2(buttonWidth, 40))) {
        m_ShowSavePresetDialog = true;
        m_NewPresetName[0] = '\0'; // Reset name
    }
    
    if (changed) {
        m_ImageDirty = true; // Trigger re-processing
    }
    
    // ImGui::EndChild();
    
    // Bottom Margin
    ImGui::Dummy(ImVec2(0.0f, 10.0f));

    if (!m_ProcessedTexture) {
        ImGui::EndDisabled();
    }

    ImGui::End();
}
