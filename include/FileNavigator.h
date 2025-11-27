#pragma once

#include <string>
#include <vector>
#include <filesystem>
#include <set>
#include <map>
#include <functional>
#include <mutex>
#include <atomic>
#include <thread>

#include <Metal/Metal.h>
#include <libraw/libraw.h>

class FileNavigator {
public:
    FileNavigator();
    ~FileNavigator();

    void Init(id<MTLDevice> device);
    void Render(std::function<void(std::string)> onFileSelected);
    
    // Set the root directory explicitly
    void SetRootPath(const std::string& path);

private:
    void RenderDirectory(const std::filesystem::path& path);
    void RenderPathBar();
    
    // Thumbnail Management
    id<MTLTexture> GetThumbnail(const std::filesystem::path& path);
    void QueueThumbnailLoad(const std::filesystem::path& path);
    void ThumbnailLoaderThread();

private:
    id<MTLDevice> m_Device = nil;
    
    // Navigation State
    std::filesystem::path m_RootPath;
    std::string m_PathBuffer; // For InputText
    
    // UI State
    float m_PanelWidth = 300.0f; // Default width
    
    // Thumbnail Cache
    struct ThumbnailInfo {
        id<MTLTexture> texture = nil;
        bool isLoading = false;
        bool isLoaded = false;
    };
    std::map<std::string, ThumbnailInfo> m_Thumbnails;
    std::mutex m_ThumbnailMutex;

    // Folder Icons
    id<MTLTexture> m_FolderOpenTexture = nil;
    id<MTLTexture> m_FolderClosedTexture = nil;
    
    // Async Loading
    std::vector<std::filesystem::path> m_LoadQueue;
    std::mutex m_QueueMutex;
    std::condition_variable m_QueueCV;
    std::atomic<bool> m_Running{true};
    std::thread m_LoaderThread;
    
    // Callback  for file selection
    std::function<void(std::string)> m_OnFileSelected;
};
