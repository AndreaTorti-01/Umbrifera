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
#include <condition_variable>

#include "GpuTypes.h"
#include <libraw/libraw.h>

class FileNavigator {
public:
    FileNavigator();
    ~FileNavigator();

    void Init(GpuDevice device, 
              std::function<GpuTexture(const std::string&)> assetLoader = nullptr,
              std::function<GpuTexture(int, int, const void*)> textureCreator = nullptr);
    void Render(std::function<void(std::string)> onFileSelected);
    
    // Set the root directory explicitly
    void SetRootPath(const std::string& path);
    
    // Set Logo
    void SetLogo(GpuTexture logo);
    
    // Disk cache management
    void ClearThumbnailCache();

private:
    void RenderDirectory(const std::filesystem::path& path);
    void RenderPathBar();
    
    // Thumbnail Management
    GpuTexture GetThumbnail(const std::filesystem::path& path);
    void QueueThumbnailLoad(const std::filesystem::path& path);
    void ThumbnailLoaderThread();

private:
    GpuDevice m_Device = {};
    
    // Navigation State
    std::filesystem::path m_RootPath;
    std::string m_PathBuffer; // For InputText
    
    // UI State
    float m_PanelWidth = 300.0f; // Default width
    
    // Thumbnail Cache
    struct ThumbnailInfo {
        GpuTexture texture = {};
        bool isLoading = false;
        bool isLoaded = false;
    };
    std::map<std::string, ThumbnailInfo> m_Thumbnails;
    std::mutex m_ThumbnailMutex;
    // Disk cache directory for thumbnails
    std::string m_CacheDir;

    // Folder Icons
    GpuTexture m_FolderOpenTexture = {};
    GpuTexture m_FolderClosedTexture = {};
    GpuTexture m_FolderIconTexture = {};
    GpuTexture m_UpArrowTexture = {};
    GpuTexture m_LogoTexture = {};
    
    // Async Loading
    std::vector<std::filesystem::path> m_LoadQueue;
    std::mutex m_QueueMutex;
    std::condition_variable m_QueueCV;
    std::atomic<bool> m_Running{true};
    std::thread m_LoaderThread;
    
    // Callback  for file selection
    std::function<void(std::string)> m_OnFileSelected;
    std::function<GpuTexture(int, int, const void*)> m_TextureCreator;
};
