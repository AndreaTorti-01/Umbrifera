#include "UmbriferaApp.h"
#include "imgui.h"
#include "imgui_internal.h"
#include <GLFW/glfw3.h>
#include <jpeglib.h>

// This file handles the User Interface (UI) rendering using Dear ImGui.
// It defines how the windows, buttons, and images look and behave.

void UmbriferaApp::SetupLayout() {
    // This function runs once to set up the initial window layout.
    if (m_FirstLayout) {
        // We set a default size for the next window to be created.
        ImGui::SetNextWindowSize(ImVec2(300, 600), ImGuiCond_FirstUseEver);
        m_FirstLayout = false;
    }
}

// Helper function to detect double-click reset for sliders
bool SliderWithReset(const char* label, float* v, float v_min, float v_max, float default_val, const char* format = "%.3f") {
    // Create a hidden label for the slider so it has an ID but doesn't render text
    char sliderLabel[128];
    snprintf(sliderLabel, sizeof(sliderLabel), "##%s", label);
    
    // Draw the slider
    bool changed = ImGui::SliderFloat(sliderLabel, v, v_min, v_max, format);
    
    ImGui::SameLine();
    
    // Draw the reset button with the original label
    if (ImGui::Button(label)) {
        *v = default_val;
        changed = true;
    }
    
    return changed;
}

void UmbriferaApp::RenderUI() {
    // Export Options Modal
    if (m_ShowExportOptions) {
        std::string title = m_ExportFormat == "jpg" ? "JPG Export" : (m_ExportFormat == "png" ? "PNG Export" : "TIFF Export");
        ImGui::OpenPopup(title.c_str());
        ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
    }
    
    std::string title = m_ExportFormat == "jpg" ? "JPG Export" : (m_ExportFormat == "png" ? "PNG Export" : "TIFF Export");
    
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(10.0f, 10.0f));
    if (ImGui::BeginPopupModal(title.c_str(), NULL, ImGuiWindowFlags_AlwaysAutoResize)) {
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
            std::string fullPath = std::string(filename) + "." + m_ExportFormat;
            
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

    // Create a DockSpace that covers the whole application window.
    // This allows us to drag and drop windows inside the app.
    ImGuiID dockspace_id = ImGui::DockSpaceOverViewport(0, ImGui::GetMainViewport());

    // Handle reset layout request
    if (m_ResetLayoutRequested) {
        ImGui::DockBuilderRemoveNode(dockspace_id);
        ImGui::DockBuilderAddNode(dockspace_id, ImGuiDockNodeFlags_DockSpace);
        
        ImGui::DockBuilderSetNodeSize(dockspace_id, ImGui::GetMainViewport()->Size);
        
        ImGuiID dock_id_right = ImGui::DockBuilderSplitNode(dockspace_id, ImGuiDir_Right, 0.20f, nullptr, &dockspace_id);
        
        ImGui::DockBuilderDockWindow("Image Viewer", dockspace_id);
        ImGui::DockBuilderDockWindow("Develop", dock_id_right);
        
        ImGui::DockBuilderFinish(dockspace_id);
        m_ResetLayoutRequested = false;
    }

    // --- Center Window: Image Viewer ---
    // This is where we display the photo.
    ImGui::Begin("Image Viewer");
    
    // Top Margin
    ImGui::Dummy(ImVec2(0.0f, 10.0f));

    if (m_ProcessedTexture) {
        // Margins
        float margin = 10.0f;
        
        // Reserve space for buttons at bottom
        // Taller row: FrameHeight + Padding (e.g., 20 + 20 = 40px)
        float buttonBarHeight = ImGui::GetFrameHeight() + 20.0f;
        
        ImVec2 windowSize = ImGui::GetContentRegionAvail();
        
        // Canvas Size: Window - Margins - ButtonBar
        // We subtract 2*margin from width (Left/Right)
        // We subtract margin from height (Bottom margin before buttons)
        ImVec2 availSize = ImVec2(windowSize.x - 2.0f * margin, windowSize.y - buttonBarHeight - margin);
        
        // Apply Left Margin
        ImGui::SetCursorPosX(ImGui::GetCursorPosX() + margin);
        
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
        
        float btnRowY = cursorScreenPos.y + availSize.y + margin;
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
        // Show loading spinner or progress bar if no image
        if (m_IsLoading) {
            // Center the progress bar
            float windowWidth = ImGui::GetWindowWidth();
            float windowHeight = ImGui::GetWindowHeight();
            float barWidth = 300.0f;
            float barHeight = 30.0f;
            
            ImGui::SetCursorPos(ImVec2((windowWidth - barWidth) * 0.5f, (windowHeight - barHeight) * 0.5f));
            
            // Animated Progress Bar (Indeterminate)
            float time = (float)ImGui::GetTime();
            float fraction = fmodf(time * 0.5f, 1.0f); // 0.0 to 1.0 loop
            
            ImGui::BeginGroup();
            ImGui::Text("Loading Image...");
            ImGui::ProgressBar(fraction, ImVec2(barWidth, 0));
            ImGui::EndGroup();
        } else {
            ImGui::Text("No image loaded.");
        }
    }
    ImGui::End();
    
    // --- Right Window: Develop ---
    ImGui::Begin("Develop");
    
    // Top Margin
    ImGui::Dummy(ImVec2(0.0f, 10.0f));

    // Histogram Display
    // Read back histogram data from GPU buffer
    if (m_HistogramBuffer) {
        uint32_t* ptr = (uint32_t*)[m_HistogramBuffer contents];
        
        // Ensure size
        if (m_Histogram.size() != 256) m_Histogram.resize(256, 0.0f);
        
        // 1. Temporal Smoothing (Exponential Moving Average)
        // This reduces flickering/oscillating.
        float alpha = 0.15f; // Smoothing factor (lower = smoother over time)
        for (int i = 0; i < 256; i++) {
            float newVal = (float)ptr[i];
            m_Histogram[i] = m_Histogram[i] * (1.0f - alpha) + newVal * alpha;
        }
        
        // 2. Spatial Smoothing (Simple Blur)
        // We create a temporary vector for display so we don't blur the state repeatedly.
        // "Make each bar be influenced by the surrounding ones"
        std::vector<float> smoothedHist(256);
        
        // 5-tap Gaussian-ish kernel [0.1, 0.2, 0.4, 0.2, 0.1]
        for (int i = 0; i < 256; i++) {
            float sum = 0.0f;
            float weightSum = 0.0f;
            
            // Kernel radius 2
            for (int offset = -2; offset <= 2; offset++) {
                int idx = i + offset;
                if (idx >= 0 && idx < 256) {
                    float w = 0.0f;
                    if (abs(offset) == 0) w = 0.4f;
                    else if (abs(offset) == 1) w = 0.2f;
                    else w = 0.1f;
                    
                    sum += m_Histogram[idx] * w;
                    weightSum += w;
                }
            }
            smoothedHist[i] = sum / weightSum;
        }
        
        // 3. Normalization
        float maxVal = 0.0f;
        // Find max value to normalize the graph
        // We ignore the absolute extremes (0 and 255) for scaling calculation
        // to prevent clipped pixels from squashing the rest of the histogram.
        for (int i = 1; i < 255; i++) {
            if (smoothedHist[i] > maxVal) maxVal = smoothedHist[i];
        }
        if (maxVal <= 0.0f) maxVal = 1.0f;
        
        // Normalize
        for (float& v : smoothedHist) v /= maxVal;
        
        // Plot
        // We use 1.1f as max scale to leave a little headroom, but clipped values (at 0 or 255) might exceed 1.0
        ImGui::PlotHistogram("##histogram", smoothedHist.data(), (int)smoothedHist.size(), 0, NULL, 0.0f, 1.1f, ImVec2(ImGui::GetContentRegionAvail().x, 80));
    }
    
    ImGui::Dummy(ImVec2(0.0f, 10.0f));
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0.0f, 10.0f));
    
    // Removed BeginChild to remove the black rectangle border
    // ImGui::BeginChild("LightControls", ImVec2(0, 300), true);
    
    bool changed = false;
    changed |= SliderWithReset("Exposure", &m_Uniforms.exposure, -5.0f, 5.0f, 0.0f);
    changed |= SliderWithReset("Contrast", &m_Uniforms.contrast, 0.5f, 1.5f, 1.0f);
    
    ImGui::Dummy(ImVec2(0.0f, 20.0f)); // Spacing
    
    changed |= SliderWithReset("Highlights", &m_Uniforms.highlights, -1.0f, 1.0f, 0.0f);
    changed |= SliderWithReset("Shadows", &m_Uniforms.shadows, -1.0f, 1.0f, 0.0f);
    changed |= SliderWithReset("Whites", &m_Uniforms.whites, -1.0f, 1.0f, 0.0f);
    changed |= SliderWithReset("Blacks", &m_Uniforms.blacks, -1.0f, 1.0f, 0.0f);
    
    ImGui::Dummy(ImVec2(0.0f, 20.0f)); // Spacing
    
    changed |= SliderWithReset("Saturation", &m_Uniforms.saturation, 0.0f, 2.0f, 1.0f);
    
    ImGui::Dummy(ImVec2(0.0f, 20.0f)); // Spacing
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0.0f, 20.0f)); // Spacing
    
    // Tone Mapping Selector
    const char* items[] = { "Standard (Gamma 2.2)", "Cinematic (ACES)", "Soft (Reinhard)" };
    changed |= ImGui::Combo("Tone Curve", &m_Uniforms.tonemap_mode, items, IM_ARRAYSIZE(items));
    
    if (changed) {
        m_ImageDirty = true; // Trigger re-processing
    }
    
    // ImGui::EndChild();
    
    // Bottom Margin
    ImGui::Dummy(ImVec2(0.0f, 10.0f));

    ImGui::End();
}
