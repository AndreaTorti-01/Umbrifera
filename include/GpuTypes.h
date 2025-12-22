#pragma once

enum class GpuPixelFormat {
    RGBA8Unorm,
    RGBA16Unorm,
    BGRA8Unorm
};

#ifdef __APPLE__
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>

typedef id<MTLDevice> GpuDevice;
typedef id<MTLCommandQueue> GpuCommandQueue;

struct GpuTexture {
    id<MTLTexture> texture = nil;
    uint32_t width = 0;
    uint32_t height = 0;
    GpuPixelFormat format = GpuPixelFormat::RGBA8Unorm;
    
    operator bool() const { return texture != nil; }
    void* GetImGuiTexture() const { return (void*)texture; }
};

struct GpuBuffer {
    id<MTLBuffer> buffer = nil;
    size_t size = 0;
    
    operator bool() const { return buffer != nil; }
};

typedef id<MTLRenderPipelineState> GpuRenderPipeline;
typedef id<MTLComputePipelineState> GpuComputePipeline;
typedef id<MTLSamplerState> GpuSampler;

#else
#include <vulkan/vulkan.h>
#include "imgui_impl_vulkan.h"

typedef VkDevice GpuDevice;
typedef VkQueue GpuCommandQueue;

struct GpuTexture {
    VkImage image = VK_NULL_HANDLE;
    VkImageView view = VK_NULL_HANDLE;
    VkImageView storageView = VK_NULL_HANDLE; // Single-level view for compute
    VkDeviceMemory memory = VK_NULL_HANDLE;
    VkSampler sampler = VK_NULL_HANDLE;
    VkDescriptorSet descriptorSet = VK_NULL_HANDLE; // For ImGui
    uint32_t width = 0;
    uint32_t height = 0;
    GpuPixelFormat format = GpuPixelFormat::RGBA8Unorm;
    
    operator bool() const { return image != VK_NULL_HANDLE; }
    void* GetImGuiTexture() const { return (void*)descriptorSet; }
};

struct GpuBuffer {
    VkBuffer buffer = VK_NULL_HANDLE;
    VkDeviceMemory memory = VK_NULL_HANDLE;
    size_t size = 0;
    
    operator bool() const { return buffer != VK_NULL_HANDLE; }
};

typedef VkPipeline GpuRenderPipeline;
typedef VkPipeline GpuComputePipeline;
typedef VkSampler GpuSampler;

#endif
