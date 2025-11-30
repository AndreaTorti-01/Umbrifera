#include "FileNavigator.h"
#include "imgui.h"
#include "imgui_internal.h"
#include <iostream>
#include <algorithm>
#include <jpeglib.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <Cocoa/Cocoa.h>

// Helper to load texture from asset
static id<MTLTexture> LoadTextureFromAsset(id<MTLDevice> device, const std::string& filename) {
    std::string path = "assets/" + filename;
    // Check if file exists
    if (!std::filesystem::exists(path)) {
        // Try looking in parent directory (if running from build)
        path = "../assets/" + filename;
        if (!std::filesystem::exists(path)) return nil;
    }

    NSURL* url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return nil;
    
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) return nil;
    
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    
    // Draw to bitmap context to get RGBA data
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    std::vector<uint8_t> rawData(width * height * 4);
    CGContextRef context = CGBitmapContextCreate(rawData.data(), width, height, 8, width * 4, colorSpace, (uint32_t)kCGImageAlphaPremultipliedLast | (uint32_t)kCGBitmapByteOrder32Big);
    
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    CGImageRelease(image);
    
    MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:width height:height mipmapped:NO];
    id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0 withBytes:rawData.data() bytesPerRow:width * 4];
    
    return texture;
}

// Helper to decode JPEG from memory to RGBA
static std::vector<uint8_t> DecodeJpegToRgba(const uint8_t* data, size_t size, int* outWidth, int* outHeight) {
    struct jpeg_decompress_struct cinfo;
    struct jpeg_error_mgr jerr;
    
    cinfo.err = jpeg_std_error(&jerr);
    jpeg_create_decompress(&cinfo);
    
    jpeg_mem_src(&cinfo, data, size);
    jpeg_read_header(&cinfo, TRUE);
    
    // Force RGB output
    cinfo.out_color_space = JCS_RGB;
    
    jpeg_start_decompress(&cinfo);
    
    int width = cinfo.output_width;
    int height = cinfo.output_height;
    int channels = cinfo.output_components; // Should be 3
    
    std::vector<uint8_t> rgba(width * height * 4);
    std::vector<uint8_t> rowBuffer(width * channels);
    
    while (cinfo.output_scanline < cinfo.output_height) {
        uint8_t* rowPtr = rowBuffer.data();
        jpeg_read_scanlines(&cinfo, &rowPtr, 1);
        
        // Convert RGB to RGBA
        int y = cinfo.output_scanline - 1;
        for (int x = 0; x < width; x++) {
            rgba[(y * width + x) * 4 + 0] = rowBuffer[x * 3 + 0];
            rgba[(y * width + x) * 4 + 1] = rowBuffer[x * 3 + 1];
            rgba[(y * width + x) * 4 + 2] = rowBuffer[x * 3 + 2];
            rgba[(y * width + x) * 4 + 3] = 255;
        }
    }
    
    jpeg_finish_decompress(&cinfo);
    jpeg_destroy_decompress(&cinfo);
    
    *outWidth = width;
    *outHeight = height;
    return rgba;
}

// Helper to rotate RGBA image based on EXIF orientation
// Orientation values: 1=normal, 3=180°, 6=90° CW, 8=90° CCW
static std::vector<uint8_t> RotateRgbaByOrientation(const std::vector<uint8_t>& src, int srcWidth, int srcHeight, int orientation, int* outWidth, int* outHeight) {
    if (orientation == 1 || orientation == 0) {
        // No rotation needed
        *outWidth = srcWidth;
        *outHeight = srcHeight;
        return src;
    }
    
    std::vector<uint8_t> dst;
    
    if (orientation == 3) {
        // 180° rotation
        *outWidth = srcWidth;
        *outHeight = srcHeight;
        dst.resize(srcWidth * srcHeight * 4);
        
        for (int y = 0; y < srcHeight; y++) {
            for (int x = 0; x < srcWidth; x++) {
                int srcIdx = (y * srcWidth + x) * 4;
                int dstX = srcWidth - 1 - x;
                int dstY = srcHeight - 1 - y;
                int dstIdx = (dstY * srcWidth + dstX) * 4;
                
                dst[dstIdx + 0] = src[srcIdx + 0];
                dst[dstIdx + 1] = src[srcIdx + 1];
                dst[dstIdx + 2] = src[srcIdx + 2];
                dst[dstIdx + 3] = src[srcIdx + 3];
            }
        }
    } else if (orientation == 6) {
        // 90° clockwise
        *outWidth = srcHeight;
        *outHeight = srcWidth;
        dst.resize(srcWidth * srcHeight * 4);
        
        for (int y = 0; y < srcHeight; y++) {
            for (int x = 0; x < srcWidth; x++) {
                int srcIdx = (y * srcWidth + x) * 4;
                int dstX = srcHeight - 1 - y;
                int dstY = x;
                int dstIdx = (dstY * (*outWidth) + dstX) * 4;
                
                dst[dstIdx + 0] = src[srcIdx + 0];
                dst[dstIdx + 1] = src[srcIdx + 1];
                dst[dstIdx + 2] = src[srcIdx + 2];
                dst[dstIdx + 3] = src[srcIdx + 3];
            }
        }
    } else if (orientation == 8) {
        // 90° counter-clockwise
        *outWidth = srcHeight;
        *outHeight = srcWidth;
        dst.resize(srcWidth * srcHeight * 4);
        
        for (int y = 0; y < srcHeight; y++) {
            for (int x = 0; x < srcWidth; x++) {
                int srcIdx = (y * srcWidth + x) * 4;
                int dstX = y;
                int dstY = srcWidth - 1 - x;
                int dstIdx = (dstY * (*outWidth) + dstX) * 4;
                
                dst[dstIdx + 0] = src[srcIdx + 0];
                dst[dstIdx + 1] = src[srcIdx + 1];
                dst[dstIdx + 2] = src[srcIdx + 2];
                dst[dstIdx + 3] = src[srcIdx + 3];
            }
        }
    } else {
        // Other orientations (mirrored) - just return original for now
        *outWidth = srcWidth;
        *outHeight = srcHeight;
        return src;
    }
    
    return dst;
}

// Helper to check if file is a RAW image (ONLY RAW)
static bool IsRawImageFile(const std::filesystem::path& path) {
    static const std::set<std::string> extensions = {
        ".nef", ".cr2", ".cr3", ".arw", ".raf", ".dng"
    };
    
    std::string ext = path.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), ::tolower);
    return extensions.find(ext) != extensions.end();
}

FileNavigator::FileNavigator() {
    // Default to user home directory
    const char* homeDir = getenv("HOME");
    if (homeDir) {
        m_RootPath = std::filesystem::path(homeDir);
    } else {
        m_RootPath = std::filesystem::current_path();
    }
    m_PathBuffer = m_RootPath.string();
}

FileNavigator::~FileNavigator() {
    m_Running = false;
    m_QueueCV.notify_all();
    if (m_LoaderThread.joinable()) {
        m_LoaderThread.join();
    }
}

void FileNavigator::Init(id<MTLDevice> device) {
    m_Device = device;
    
    // Load Folder Icon (if exists)
    m_FolderIconTexture = LoadTextureFromAsset(device, "folder_open_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    
    // Load Up Arrow Icon
    m_UpArrowTexture = LoadTextureFromAsset(device, "arrow_shape_up_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png");
    
    m_LoaderThread = std::thread(&FileNavigator::ThumbnailLoaderThread, this);
    
    // Load Folder Icons
    m_FolderClosedTexture = LoadTextureFromAsset(device, "folder_24dp_E3E3E3_FILL1_wght400_GRAD0_opsz24.png");
    m_FolderOpenTexture = LoadTextureFromAsset(device, "folder_open_24dp_E3E3E3_FILL1_wght400_GRAD0_opsz24.png");
}

void FileNavigator::SetRootPath(const std::string& path) {
    if (std::filesystem::exists(path) && std::filesystem::is_directory(path)) {
        m_RootPath = path;
        m_PathBuffer = m_RootPath.string();
    }
}

void FileNavigator::SetLogo(id<MTLTexture> logo) {
    m_LogoTexture = logo;
}

void FileNavigator::Render(std::function<void(std::string)> onFileSelected) {
    // Store callback for use in RenderDirectory
    m_OnFileSelected = onFileSelected;
    
    ImGui::Begin("Navigator");
    
    // Top Bar: Path and Up Button
    float barHeight = ImGui::GetFrameHeight();
    float iconSize = barHeight - ImGui::GetStyle().FramePadding.y * 2.0f; // Fit inside frame height
    
    // 1. Up Button
    if (m_UpArrowTexture) {
        if (ImGui::ImageButton("##UpBtn", (ImTextureID)m_UpArrowTexture, ImVec2(iconSize, iconSize))) {
            if (m_RootPath.has_parent_path() && m_RootPath != m_RootPath.root_path()) {
                m_RootPath = m_RootPath.parent_path();
                m_PathBuffer = m_RootPath.string();
            }
        }
    } else {
        if (ImGui::Button("^", ImVec2(barHeight, barHeight))) {
            if (m_RootPath.has_parent_path() && m_RootPath != m_RootPath.root_path()) {
                m_RootPath = m_RootPath.parent_path();
                m_PathBuffer = m_RootPath.string();
            }
        }
    }
    
    ImGui::SameLine();
    
    // 2. Open Folder Button (Moved to left of path)
    if (m_FolderIconTexture) {
        if (ImGui::ImageButton("##OpenFolderBtn", (ImTextureID)m_FolderIconTexture, ImVec2(iconSize, iconSize))) {
            // Open Native Folder Picker
            NSOpenPanel* panel = [NSOpenPanel openPanel];
            [panel setCanChooseFiles:NO];
            [panel setCanChooseDirectories:YES];
            [panel setAllowsMultipleSelection:NO];
            
            if ([panel runModal] == NSModalResponseOK) {
                NSURL* url = [[panel URLs] objectAtIndex:0];
                std::string path = [[url path] UTF8String];
                SetRootPath(path);
            }
        }
    } else {
        if (ImGui::Button("Open", ImVec2(0, barHeight))) {
             // Open Native Folder Picker
            NSOpenPanel* panel = [NSOpenPanel openPanel];
            [panel setCanChooseFiles:NO];
            [panel setCanChooseDirectories:YES];
            [panel setAllowsMultipleSelection:NO];
            
            if ([panel runModal] == NSModalResponseOK) {
                NSURL* url = [[panel URLs] objectAtIndex:0];
                std::string path = [[url path] UTF8String];
                SetRootPath(path);
            }
        }
    }
    
    ImGui::SameLine();
    
    // 3. Path Input
    float availWidth = ImGui::GetContentRegionAvail().x;
    
    char buffer[1024];
    strncpy(buffer, m_PathBuffer.c_str(), sizeof(buffer));
    buffer[sizeof(buffer) - 1] = '\0';
    
    ImGui::PushItemWidth(availWidth);
    if (ImGui::InputText("##Path", buffer, sizeof(buffer), ImGuiInputTextFlags_EnterReturnsTrue)) {
        SetRootPath(buffer);
    }
    ImGui::PopItemWidth();
    
    ImGui::Separator();
    
    // File List
    ImGui::BeginChild("FileList");
    
    // Render from Root
    try {
        if (std::filesystem::exists(m_RootPath)) {
            RenderDirectory(m_RootPath);
        } else {
            ImGui::TextColored(ImVec4(1, 0, 0, 1), "Invalid Path");
        }
    } catch (const std::exception& e) {
        ImGui::TextColored(ImVec4(1, 0, 0, 1), "Error: %s", e.what());
    }
    
    ImGui::EndChild();

    ImGui::End();
}

void FileNavigator::RenderPathBar() {
    // Up Button
    if (ImGui::Button("^")) {
        if (m_RootPath.has_parent_path() && m_RootPath != m_RootPath.root_path()) {
            m_RootPath = m_RootPath.parent_path();
            m_PathBuffer = m_RootPath.string();
        }
    }
    
    ImGui::SameLine();
    
    // Path Input
    // Reserve space for the Open Folder button on the right
    float iconSize = ImGui::GetFrameHeight();
    float buttonWidth = m_FolderIconTexture ? iconSize : 60.0f; // Icon or "Open" button
    float availWidth = ImGui::GetContentRegionAvail().x - buttonWidth - ImGui::GetStyle().ItemSpacing.x;
    
    // We use a temporary buffer to allow editing
    char buffer[1024];
    strncpy(buffer, m_PathBuffer.c_str(), sizeof(buffer));
    buffer[sizeof(buffer) - 1] = '\0';
    
    ImGui::PushItemWidth(availWidth);
    if (ImGui::InputText("##Path", buffer, sizeof(buffer), ImGuiInputTextFlags_EnterReturnsTrue)) {
        SetRootPath(buffer);
    }
    ImGui::PopItemWidth();
}

void FileNavigator::RenderDirectory(const std::filesystem::path& path) {
    // Sort directories first, then files
    std::vector<std::filesystem::directory_entry> dirs;
    std::vector<std::filesystem::directory_entry> files;
    
    for (const auto& entry : std::filesystem::directory_iterator(path)) {
        if (entry.is_directory()) {
            // Skip hidden folders
            if (entry.path().filename().string().rfind(".", 0) != 0) {
                dirs.push_back(entry);
            }
        } else if (entry.is_regular_file()) {
            if (IsRawImageFile(entry.path())) {
                files.push_back(entry);
            }
        }
    }
    
    // Sort alphabetically (case-insensitive)
    auto sortFunc = [](const auto& a, const auto& b) {
        return strcasecmp(a.path().filename().string().c_str(), b.path().filename().string().c_str()) < 0;
    };
    std::sort(dirs.begin(), dirs.end(), sortFunc);
    std::sort(files.begin(), files.end(), sortFunc);
    
    // Render Directories
    for (const auto& entry : dirs) {
        std::string name = entry.path().filename().string();
        
        ImGui::PushID(name.c_str());
        
        // Check if this node is open using ImGui's internal state
        ImGuiStorage* storage = ImGui::GetStateStorage();
        ImGuiID nodeId = ImGui::GetID(name.c_str());
        bool wasOpen = storage->GetInt(nodeId, 0) != 0;
        
        id<MTLTexture> icon = wasOpen ? m_FolderOpenTexture : m_FolderClosedTexture;
        
        // Custom Row Rendering
        ImVec2 startPos = ImGui::GetCursorScreenPos();
        float availWidth = ImGui::GetContentRegionAvail().x;
        float rowHeight = ImGui::GetTextLineHeight() + 4.0f; // Minimal padding
        
        // Draw Icon
        if (icon) {
            ImGui::Image((ImTextureID)icon, ImVec2(16, 16));
        }
        ImGui::SameLine();
        
        // Draw Text
        ImGui::Text("%s", name.c_str());
        
        // Invisible Button for Toggle
        ImGui::SetCursorScreenPos(startPos);
        if (ImGui::InvisibleButton(("##folder" + name).c_str(), ImVec2(availWidth, rowHeight))) {
            wasOpen = !wasOpen;
            storage->SetInt(nodeId, wasOpen ? 1 : 0);
        }
        
        // Hover Effect
        if (ImGui::IsItemHovered()) {
            ImGui::GetWindowDrawList()->AddRectFilled(startPos, 
                ImVec2(startPos.x + availWidth, startPos.y + rowHeight), 
                ImGui::GetColorU32(ImVec4(0.3f, 0.3f, 0.3f, 0.3f)));
        }

        // Context Menu
        if (ImGui::BeginPopupContextItem()) {
            if (ImGui::MenuItem("Set as Root")) {
                SetRootPath(entry.path().string());
            }
            ImGui::EndPopup();
        }
        
        if (wasOpen) {
            ImGui::Indent();
            RenderDirectory(entry.path());
            ImGui::Unindent();
        }
        
        ImGui::PopID();
    }
    
    // Render Files
    for (const auto& entry : files) {
        std::string name = entry.path().filename().string();
        std::string pathStr = entry.path().string();
        
        ImVec2 startPos = ImGui::GetCursorScreenPos();
        float availWidth = ImGui::GetContentRegionAvail().x;
        
        // Constant thumbnail width, variable height based on aspect ratio
        float thumbWidth = 60.0f;
        float thumbHeight = thumbWidth; // Default to square if no thumbnail yet
        float margin = 5.0f;
        
        // Get thumbnail and calculate actual display dimensions
        id<MTLTexture> thumb = GetThumbnail(entry.path());
        if (thumb) {
            float texWidth = (float)[thumb width];
            float texHeight = (float)[thumb height];
            float aspect = texHeight / texWidth;
            thumbHeight = thumbWidth * aspect;
        }
        
        // Row height adapts to thumbnail height
        float rowHeight = thumbHeight + margin * 2;
        float minRowHeight = 40.0f; // Minimum for text visibility
        if (rowHeight < minRowHeight) rowHeight = minRowHeight;
        
        // 1. Draw Content (Thumbnail + Text)
        // Draw Thumbnail with margin, vertically centered in row
        float thumbY = startPos.y + (rowHeight - thumbHeight) * 0.5f;
        ImGui::SetCursorScreenPos(ImVec2(startPos.x + margin, thumbY));
        if (thumb) {
            ImGui::Image((ImTextureID)thumb, ImVec2(thumbWidth, thumbHeight));
        } else {
            // Placeholder while loading
            ImGui::Button("...", ImVec2(thumbWidth, thumbHeight));
        }
        
        // Draw text (vertically centered)
        float textY = startPos.y + (rowHeight - ImGui::GetTextLineHeight()) * 0.5f;
        ImGui::SetCursorScreenPos(ImVec2(startPos.x + thumbWidth + margin * 2 + 4, textY));
        ImGui::Text("%s", name.c_str());
        
        // 2. Draw Invisible Button over everything for click handling
        ImGui::SetCursorScreenPos(startPos);
        bool clicked = ImGui::InvisibleButton(("##file" + pathStr).c_str(), ImVec2(availWidth, rowHeight));
        
        // Draw hover background
        if (ImGui::IsItemHovered()) {
            ImGui::GetWindowDrawList()->AddRectFilled(startPos,
                                    ImVec2(startPos.x + availWidth, startPos.y + rowHeight),
                                    ImGui::GetColorU32(ImVec4(0.3f, 0.3f, 0.3f, 0.3f)));
        }
        
        // Handle click
        if (clicked && m_OnFileSelected) {
            m_OnFileSelected(pathStr);
        }
    }
}

id<MTLTexture> FileNavigator::GetThumbnail(const std::filesystem::path& path) {
    std::string pathStr = path.string();
    
    std::lock_guard<std::mutex> lock(m_ThumbnailMutex);
    auto it = m_Thumbnails.find(pathStr);
    if (it != m_Thumbnails.end()) {
        return it->second.texture;
    }
    
    // Not found, queue it
    m_Thumbnails[pathStr] = {nil, true, false}; // Mark as loading
    QueueThumbnailLoad(path);
    
    return nil;
}

void FileNavigator::QueueThumbnailLoad(const std::filesystem::path& path) {
    std::lock_guard<std::mutex> lock(m_QueueMutex);
    m_LoadQueue.push_back(path);
    m_QueueCV.notify_one();
}

void FileNavigator::ThumbnailLoaderThread() {
    while (m_Running) {
        std::filesystem::path path;
        
        {
            std::unique_lock<std::mutex> lock(m_QueueMutex);
            m_QueueCV.wait(lock, [this] { return !m_LoadQueue.empty() || !m_Running; });
            
            if (!m_Running) break;
            
            path = m_LoadQueue.front();
            m_LoadQueue.erase(m_LoadQueue.begin());
        }
        
        // Load Thumbnail with orientation support
        auto RawProcessor = std::make_unique<LibRaw>();
        id<MTLTexture> texture = nil;
        
        if (RawProcessor->open_file(path.c_str()) == LIBRAW_SUCCESS) {
            // Get EXIF orientation (flip is a bitmask, we need to extract orientation)
            int orientation = RawProcessor->imgdata.sizes.flip;
            // LibRaw flip values: 0=none, 3=180°, 5=90°CCW, 6=90°CW
            // Map to standard EXIF: 1=normal, 3=180°, 6=90°CW, 8=90°CCW
            int exifOrientation = 1;
            if (orientation == 3) exifOrientation = 3;      // 180°
            else if (orientation == 5) exifOrientation = 8; // 90° CCW
            else if (orientation == 6) exifOrientation = 6; // 90° CW
            
            if (RawProcessor->unpack_thumb() == LIBRAW_SUCCESS) {
                libraw_processed_image_t* thumb = RawProcessor->dcraw_make_mem_thumb();
                if (thumb) {
                    if (thumb->type == LIBRAW_IMAGE_JPEG) {
                        int width, height;
                        std::vector<uint8_t> rgba = DecodeJpegToRgba((const uint8_t*)thumb->data, thumb->data_size, &width, &height);
                        
                        if (!rgba.empty() && m_Device) {
                            // Apply rotation based on orientation
                            int finalWidth, finalHeight;
                            std::vector<uint8_t> rotated = RotateRgbaByOrientation(rgba, width, height, exifOrientation, &finalWidth, &finalHeight);
                            
                            @autoreleasepool {
                                MTLTextureDescriptor* desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:finalWidth height:finalHeight mipmapped:NO];
                                texture = [m_Device newTextureWithDescriptor:desc];
                                
                                MTLRegion region = MTLRegionMake2D(0, 0, finalWidth, finalHeight);
                                [texture replaceRegion:region mipmapLevel:0 withBytes:rotated.data() bytesPerRow:finalWidth * 4];
                            }
                        }
                    }
                    LibRaw::dcraw_clear_mem(thumb);
                }
            }
            RawProcessor->recycle();
        }
        
        // Update Cache
        {
            std::lock_guard<std::mutex> lock(m_ThumbnailMutex);
            m_Thumbnails[path.string()].texture = texture;
            m_Thumbnails[path.string()].isLoaded = true;
            m_Thumbnails[path.string()].isLoading = false;
        }
    }
}
