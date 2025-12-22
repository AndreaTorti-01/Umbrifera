#include "UmbriferaApp.h"
#include "imgui.h"
#include "imgui_impl_glfw.h"
#include "imgui_impl_vulkan.h"
#include <stdio.h>
#include <stdlib.h>
#define GLFW_INCLUDE_NONE
#define GLFW_INCLUDE_VULKAN
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <vulkan/vulkan.h>
#include <vector>
#include <iostream>
#include <fstream>
#include <algorithm>

#ifndef __APPLE__

#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

static void check_vk_result(VkResult err) {
    if (err == 0) return;
    fprintf(stderr, "[vulkan] Error: VkResult = %d\n", err);
    if (err < 0) abort();
}

uint32_t UmbriferaApp::FindMemoryType(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(m_VulkanPhysicalDevice, &memProperties);
    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && (memProperties.memoryTypes[i].propertyFlags & properties) == properties)
            return i;
    }
    return 0xFFFFFFFF;
}

VkCommandBuffer UmbriferaApp::BeginSingleTimeCommands() {
    std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);
    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandPool = m_UtilityCommandPool;
    allocInfo.commandBufferCount = 1;

    VkCommandBuffer commandBuffer;
    vkAllocateCommandBuffers(m_Device, &allocInfo, &commandBuffer);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(commandBuffer, &beginInfo);

    return commandBuffer;
}

void UmbriferaApp::EndSingleTimeCommands(VkCommandBuffer commandBuffer) {
    std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);
    vkEndCommandBuffer(commandBuffer);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;

    VkFence fence;
    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    vkCreateFence(m_Device, &fenceInfo, m_VulkanAllocator, &fence);

    vkQueueSubmit(m_CommandQueue, 1, &submitInfo, fence);
    vkWaitForFences(m_Device, 1, &fence, VK_TRUE, UINT64_MAX);
    vkDestroyFence(m_Device, fence, m_VulkanAllocator);

    vkFreeCommandBuffers(m_Device, m_UtilityCommandPool, 1, &commandBuffer);
}

static std::vector<char> ReadFile(const std::string& filename) {
    std::ifstream file(filename, std::ios::ate | std::ios::binary);
    if (!file.is_open()) {
        // Try parent dir
        std::ifstream file2("../" + filename, std::ios::ate | std::ios::binary);
        if (!file2.is_open()) {
            fprintf(stderr, "Failed to open file: %s\n", filename.c_str());
            return {};
        }
        size_t fileSize = (size_t)file2.tellg();
        std::vector<char> buffer(fileSize);
        file2.seekg(0);
        file2.read(buffer.data(), fileSize);
        file2.close();
        return buffer;
    }
    size_t fileSize = (size_t)file.tellg();
    std::vector<char> buffer(fileSize);
    file.seekg(0);
    file.read(buffer.data(), fileSize);
    file.close();
    return buffer;
}

VkShaderModule CreateShaderModule(VkDevice device, const std::vector<char>& code) {
    VkShaderModuleCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = code.size();
    createInfo.pCode = reinterpret_cast<const uint32_t*>(code.data());

    VkShaderModule shaderModule;
    if (vkCreateShaderModule(device, &createInfo, nullptr, &shaderModule) != VK_SUCCESS) {
        return VK_NULL_HANDLE;
    }
    return shaderModule;
}

void UmbriferaApp::InitGraphicsBackend() {
    VkResult err;

    printf("Creating Vulkan Instance...\n");
    // Create Vulkan Instance
    {
        uint32_t extensions_count = 0;
        const char** extensions = glfwGetRequiredInstanceExtensions(&extensions_count);
        if (!extensions) {
            fprintf(stderr, "Failed to get required Vulkan extensions from GLFW\n");
            exit(-1);
        }
        VkInstanceCreateInfo create_info = {};
        create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        create_info.enabledExtensionCount = extensions_count;
        create_info.ppEnabledExtensionNames = extensions;
        err = vkCreateInstance(&create_info, m_VulkanAllocator, &m_VulkanInstance);
        check_vk_result(err);
    }

    printf("Selecting Physical Device...\n");
    // Select Physical Device
    {
        uint32_t gpu_count;
        err = vkEnumeratePhysicalDevices(m_VulkanInstance, &gpu_count, nullptr);
        check_vk_result(err);
        if (gpu_count == 0) {
            fprintf(stderr, "No Vulkan-compatible GPUs found\n");
            exit(-1);
        }
        std::vector<VkPhysicalDevice> gpus(gpu_count);
        err = vkEnumeratePhysicalDevices(m_VulkanInstance, &gpu_count, gpus.data());
        check_vk_result(err);
        m_VulkanPhysicalDevice = gpus[0]; // Just pick the first one for now
    }

    printf("Selecting Queue Family...\n");
    // Select Queue Family
    {
        uint32_t count;
        vkGetPhysicalDeviceQueueFamilyProperties(m_VulkanPhysicalDevice, &count, nullptr);
        std::vector<VkQueueFamilyProperties> queues(count);
        vkGetPhysicalDeviceQueueFamilyProperties(m_VulkanPhysicalDevice, &count, queues.data());
        bool found = false;
        for (uint32_t i = 0; i < count; i++) {
            if (queues[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
                m_VulkanQueueFamily = i;
                found = true;
                break;
            }
        }
        if (!found) {
            fprintf(stderr, "No graphics queue family found\n");
            exit(-1);
        }
    }

    printf("Creating Logical Device...\n");
    // Create Logical Device
    {
        int device_extension_count = 1;
        const char* device_extensions[] = { "VK_KHR_swapchain" };
        float queue_priority[] = { 1.0f };
        VkDeviceQueueCreateInfo queue_info[1] = {};
        queue_info[0].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_info[0].queueFamilyIndex = m_VulkanQueueFamily;
        queue_info[0].queueCount = 1;
        queue_info[0].pQueuePriorities = queue_priority;
        VkDeviceCreateInfo create_info = {};
        create_info.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        create_info.queueCreateInfoCount = 1;
        create_info.pQueueCreateInfos = queue_info;
        create_info.enabledExtensionCount = device_extension_count;
        create_info.ppEnabledExtensionNames = device_extensions;
        err = vkCreateDevice(m_VulkanPhysicalDevice, &create_info, m_VulkanAllocator, &m_Device);
        check_vk_result(err);
        vkGetDeviceQueue(m_Device, m_VulkanQueueFamily, 0, &m_CommandQueue);
    }

    printf("Creating Descriptor Pool...\n");
    // Create Descriptor Pool
    {
        VkDescriptorPoolSize pool_sizes[] = {
            { VK_DESCRIPTOR_TYPE_SAMPLER, 1000 },
            { VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, 1000 },
            { VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE, 1000 },
            { VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, 1000 },
            { VK_DESCRIPTOR_TYPE_UNIFORM_TEXEL_BUFFER, 1000 },
            { VK_DESCRIPTOR_TYPE_STORAGE_TEXEL_BUFFER, 1000 },
            { VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, 1000 },
            { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1000 },
            { VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER_DYNAMIC, 1000 },
            { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER_DYNAMIC, 1000 },
            { VK_DESCRIPTOR_TYPE_INPUT_ATTACHMENT, 1000 }
        };
        VkDescriptorPoolCreateInfo pool_info = {};
        pool_info.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        pool_info.flags = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;
        pool_info.maxSets = 1000 * (uint32_t)IM_ARRAYSIZE(pool_sizes);
        pool_info.poolSizeCount = (uint32_t)IM_ARRAYSIZE(pool_sizes);
        pool_info.pPoolSizes = pool_sizes;
        err = vkCreateDescriptorPool(m_Device, &pool_info, m_VulkanAllocator, &m_VulkanDescriptorPool);
        check_vk_result(err);
    }

    printf("Creating Window Surface...\n");
    // Create Window Surface
    {
        err = glfwCreateWindowSurface(m_VulkanInstance, m_Window, m_VulkanAllocator, &m_VulkanSurface);
        check_vk_result(err);
    }

    printf("Creating Framebuffers...\n");
    // Create Framebuffers
    int w, h;
    glfwGetFramebufferSize(m_Window, &w, &h);
    ImGui_ImplVulkanH_Window* wd = &m_VulkanMainWindowData;
    wd->Surface = m_VulkanSurface;
    
    // Check for WSI support
    VkBool32 res;
    vkGetPhysicalDeviceSurfaceSupportKHR(m_VulkanPhysicalDevice, m_VulkanQueueFamily, wd->Surface, &res);
    if (res != VK_TRUE) {
        fprintf(stderr, "Error: no WSI support on physical device 0\n");
        exit(-1);
    }

    // Select Surface Format
    const VkFormat requestSurfaceImageFormat[] = { VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_B8G8R8_UNORM, VK_FORMAT_R8G8B8_UNORM };
    const VkColorSpaceKHR requestSurfaceColorSpace = VK_COLORSPACE_SRGB_NONLINEAR_KHR;
    wd->SurfaceFormat = ImGui_ImplVulkanH_SelectSurfaceFormat(m_VulkanPhysicalDevice, wd->Surface, requestSurfaceImageFormat, (size_t)IM_ARRAYSIZE(requestSurfaceImageFormat), requestSurfaceColorSpace);

    // Select Present Mode
    VkPresentModeKHR present_modes[] = { VK_PRESENT_MODE_FIFO_KHR };
    wd->PresentMode = ImGui_ImplVulkanH_SelectPresentMode(m_VulkanPhysicalDevice, wd->Surface, &present_modes[0], IM_ARRAYSIZE(present_modes));

    printf("Creating Swapchain...\n");
    // Create SwapChain, RenderPass, Framebuffer, etc.
    ImGui_ImplVulkanH_CreateOrResizeWindow(m_VulkanInstance, m_VulkanPhysicalDevice, m_Device, wd, m_VulkanQueueFamily, m_VulkanAllocator, w, h, m_VulkanMinImageCount, 0);

    // Create Utility Command Pool
    {
        VkCommandPoolCreateInfo pool_info = {};
        pool_info.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        pool_info.queueFamilyIndex = m_VulkanQueueFamily;
        pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        err = vkCreateCommandPool(m_Device, &pool_info, m_VulkanAllocator, &m_UtilityCommandPool);
        check_vk_result(err);
    }

    printf("Initializing ImGui Vulkan...\n");
    if (ImGui::GetCurrentContext() == nullptr) {
        fprintf(stderr, "Error: No ImGui context found!\n");
        exit(-1);
    }
    // Setup ImGui Vulkan
    ImGui_ImplVulkan_InitInfo init_info = {};
    init_info.Instance = m_VulkanInstance;
    init_info.PhysicalDevice = m_VulkanPhysicalDevice;
    init_info.Device = m_Device;
    init_info.QueueFamily = m_VulkanQueueFamily;
    init_info.Queue = m_CommandQueue;
    init_info.PipelineCache = VK_NULL_HANDLE;
    init_info.DescriptorPool = m_VulkanDescriptorPool;
    init_info.MinImageCount = m_VulkanMinImageCount;
    init_info.ImageCount = wd->ImageCount;
    init_info.Allocator = m_VulkanAllocator;
    init_info.CheckVkResultFn = check_vk_result;
    init_info.PipelineInfoMain.RenderPass = wd->RenderPass;
    init_info.PipelineInfoMain.Subpass = 0;
    init_info.PipelineInfoMain.MSAASamples = VK_SAMPLE_COUNT_1_BIT;
    
    if (!ImGui_ImplVulkan_Init(&init_info)) {
        fprintf(stderr, "Failed to initialize ImGui Vulkan backend\n");
        exit(-1);
    }
    printf("ImGui Vulkan initialized successfully.\n");

    InitComputePipelines();

    // Create Histogram Fence
    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT; // Start signaled so we can submit first time
    vkCreateFence(m_Device, &fenceInfo, m_VulkanAllocator, &m_HistogramFence);
}

void UmbriferaApp::InitComputePipelines() {
    printf("Initializing Compute Pipelines...\n");

    // 1. Create Descriptor Set Layout for Main Processing
    VkDescriptorSetLayoutBinding bindings[4] = {};
    bindings[0].binding = 0;
    bindings[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    bindings[0].descriptorCount = 1;
    bindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    bindings[1].binding = 1;
    bindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    bindings[1].descriptorCount = 1;
    bindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    bindings[2].binding = 2;
    bindings[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    bindings[2].descriptorCount = 1;
    bindings[2].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    bindings[3].binding = 3;
    bindings[3].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    bindings[3].descriptorCount = 1;
    bindings[3].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo layoutInfo{};
    layoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    layoutInfo.bindingCount = 4;
    layoutInfo.pBindings = bindings;

    if (vkCreateDescriptorSetLayout(m_Device, &layoutInfo, m_VulkanAllocator, &m_ComputeDescriptorSetLayout) != VK_SUCCESS) {
        fprintf(stderr, "Failed to create compute descriptor set layout\n");
        return;
    }

    // 2. Create Pipeline Layout
    VkPipelineLayoutCreateInfo pipelineLayoutInfo{};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = 1;
    pipelineLayoutInfo.pSetLayouts = &m_ComputeDescriptorSetLayout;

    if (vkCreatePipelineLayout(m_Device, &pipelineLayoutInfo, m_VulkanAllocator, &m_ComputePipelineLayout) != VK_SUCCESS) {
        fprintf(stderr, "Failed to create compute pipeline layout\n");
        return;
    }

    // 3. Create Compute Pipeline
    auto computeShaderCode = ReadFile("shaders/spv/process.spv");
    if (!computeShaderCode.empty()) {
        VkShaderModule computeShaderModule = CreateShaderModule(m_Device, computeShaderCode);
        if (computeShaderModule != VK_NULL_HANDLE) {
            VkComputePipelineCreateInfo pipelineInfo{};
            pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
            pipelineInfo.layout = m_ComputePipelineLayout;
            pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
            pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
            pipelineInfo.stage.module = computeShaderModule;
            pipelineInfo.stage.pName = "main";

            if (vkCreateComputePipelines(m_Device, VK_NULL_HANDLE, 1, &pipelineInfo, m_VulkanAllocator, &m_RenderPSO) != VK_SUCCESS) {
                fprintf(stderr, "Failed to create compute pipeline\n");
            }
            vkDestroyShaderModule(m_Device, computeShaderModule, m_VulkanAllocator);
        }
    }

    // 4. Create Histogram Pipeline
    VkDescriptorSetLayoutBinding histBindings[2] = {};
    histBindings[0].binding = 0;
    histBindings[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    histBindings[0].descriptorCount = 1;
    histBindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    histBindings[1].binding = 1;
    histBindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    histBindings[1].descriptorCount = 1;
    histBindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo histLayoutInfo{};
    histLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    histLayoutInfo.bindingCount = 2;
    histLayoutInfo.pBindings = histBindings;

    if (vkCreateDescriptorSetLayout(m_Device, &histLayoutInfo, m_VulkanAllocator, &m_HistogramDescriptorSetLayout) != VK_SUCCESS) {
        fprintf(stderr, "Failed to create histogram descriptor set layout\n");
    }

    VkPipelineLayoutCreateInfo histPipelineLayoutInfo{};
    histPipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    histPipelineLayoutInfo.setLayoutCount = 1;
    histPipelineLayoutInfo.pSetLayouts = &m_HistogramDescriptorSetLayout;

    if (vkCreatePipelineLayout(m_Device, &histPipelineLayoutInfo, m_VulkanAllocator, &m_HistogramPipelineLayout) != VK_SUCCESS) {
        fprintf(stderr, "Failed to create histogram pipeline layout\n");
    }

    auto histShaderCode = ReadFile("shaders/spv/histogram.spv");
    if (!histShaderCode.empty()) {
        VkShaderModule histShaderModule = CreateShaderModule(m_Device, histShaderCode);
        if (histShaderModule != VK_NULL_HANDLE) {
            VkComputePipelineCreateInfo histPipelineInfo{};
            histPipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
            histPipelineInfo.layout = m_HistogramPipelineLayout;
            histPipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
            histPipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
            histPipelineInfo.stage.module = histShaderModule;
            histPipelineInfo.stage.pName = "main";

            if (vkCreateComputePipelines(m_Device, VK_NULL_HANDLE, 1, &histPipelineInfo, m_VulkanAllocator, &m_HistogramPSO) != VK_SUCCESS) {
                fprintf(stderr, "Failed to create histogram compute pipeline\n");
            }
            vkDestroyShaderModule(m_Device, histShaderModule, m_VulkanAllocator);
        }
    }

    // 5. Create Grain Pipeline
    VkDescriptorSetLayoutBinding grainBindings[1] = {};
    grainBindings[0].binding = 0;
    grainBindings[0].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    grainBindings[0].descriptorCount = 1;
    grainBindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo grainLayoutInfo{};
    grainLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    grainLayoutInfo.bindingCount = 1;
    grainLayoutInfo.pBindings = grainBindings;

    vkCreateDescriptorSetLayout(m_Device, &grainLayoutInfo, m_VulkanAllocator, &m_GrainDescriptorSetLayout);

    VkPushConstantRange grainPushConstant{};
    grainPushConstant.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    grainPushConstant.offset = 0;
    grainPushConstant.size = 16; // width, height, grainSize, seed

    VkPipelineLayoutCreateInfo grainPipelineLayoutInfo{};
    grainPipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    grainPipelineLayoutInfo.setLayoutCount = 1;
    grainPipelineLayoutInfo.pSetLayouts = &m_GrainDescriptorSetLayout;
    grainPipelineLayoutInfo.pushConstantRangeCount = 1;
    grainPipelineLayoutInfo.pPushConstantRanges = &grainPushConstant;

    vkCreatePipelineLayout(m_Device, &grainPipelineLayoutInfo, m_VulkanAllocator, &m_GrainPipelineLayout);

    auto grainShaderCode = ReadFile("shaders/spv/grain.spv");
    if (!grainShaderCode.empty()) {
        VkShaderModule grainShaderModule = CreateShaderModule(m_Device, grainShaderCode);
        VkComputePipelineCreateInfo grainPipelineInfo{};
        grainPipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        grainPipelineInfo.layout = m_GrainPipelineLayout;
        grainPipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        grainPipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
        grainPipelineInfo.stage.module = grainShaderModule;
        grainPipelineInfo.stage.pName = "main";
        vkCreateComputePipelines(m_Device, VK_NULL_HANDLE, 1, &grainPipelineInfo, m_VulkanAllocator, &m_GrainPSO);
        vkDestroyShaderModule(m_Device, grainShaderModule, m_VulkanAllocator);
    }

    // 6. Create Resize Pipeline
    VkDescriptorSetLayoutBinding resizeBindings[2] = {};
    resizeBindings[0].binding = 0;
    resizeBindings[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    resizeBindings[0].descriptorCount = 1;
    resizeBindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    resizeBindings[1].binding = 1;
    resizeBindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    resizeBindings[1].descriptorCount = 1;
    resizeBindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo resizeLayoutInfo{};
    resizeLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    resizeLayoutInfo.bindingCount = 2;
    resizeLayoutInfo.pBindings = resizeBindings;

    vkCreateDescriptorSetLayout(m_Device, &resizeLayoutInfo, m_VulkanAllocator, &m_ResizeDescriptorSetLayout);

    VkPushConstantRange resizePushConstant{};
    resizePushConstant.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    resizePushConstant.offset = 0;
    resizePushConstant.size = 16; // srcW, srcH, dstW, dstH

    VkPipelineLayoutCreateInfo resizePipelineLayoutInfo{};
    resizePipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    resizePipelineLayoutInfo.setLayoutCount = 1;
    resizePipelineLayoutInfo.pSetLayouts = &m_ResizeDescriptorSetLayout;
    resizePipelineLayoutInfo.pushConstantRangeCount = 1;
    resizePipelineLayoutInfo.pPushConstantRanges = &resizePushConstant;

    vkCreatePipelineLayout(m_Device, &resizePipelineLayoutInfo, m_VulkanAllocator, &m_ResizePipelineLayout);

    auto resizeShaderCode = ReadFile("shaders/spv/resize.spv");
    if (!resizeShaderCode.empty()) {
        VkShaderModule resizeShaderModule = CreateShaderModule(m_Device, resizeShaderCode);
        VkComputePipelineCreateInfo resizePipelineInfo{};
        resizePipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        resizePipelineInfo.layout = m_ResizePipelineLayout;
        resizePipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        resizePipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
        resizePipelineInfo.stage.module = resizeShaderModule;
        resizePipelineInfo.stage.pName = "main";
        vkCreateComputePipelines(m_Device, VK_NULL_HANDLE, 1, &resizePipelineInfo, m_VulkanAllocator, &m_ResizePSO);
        vkDestroyShaderModule(m_Device, resizeShaderModule, m_VulkanAllocator);
    }

    // 7. Create Rotate Pipeline
    VkDescriptorSetLayoutBinding rotateBindings[2] = {};
    rotateBindings[0].binding = 0;
    rotateBindings[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    rotateBindings[0].descriptorCount = 1;
    rotateBindings[0].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    rotateBindings[1].binding = 1;
    rotateBindings[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    rotateBindings[1].descriptorCount = 1;
    rotateBindings[1].stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;

    VkDescriptorSetLayoutCreateInfo rotateLayoutInfo{};
    rotateLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    rotateLayoutInfo.bindingCount = 2;
    rotateLayoutInfo.pBindings = rotateBindings;

    vkCreateDescriptorSetLayout(m_Device, &rotateLayoutInfo, m_VulkanAllocator, &m_RotateDescriptorSetLayout);

    VkPushConstantRange rotatePushConstant{};
    rotatePushConstant.stageFlags = VK_SHADER_STAGE_COMPUTE_BIT;
    rotatePushConstant.offset = 0;
    rotatePushConstant.size = 20; // cos, sin, scale, srcW, srcH

    VkPipelineLayoutCreateInfo rotatePipelineLayoutInfo{};
    rotatePipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    rotatePipelineLayoutInfo.setLayoutCount = 1;
    rotatePipelineLayoutInfo.pSetLayouts = &m_RotateDescriptorSetLayout;
    rotatePipelineLayoutInfo.pushConstantRangeCount = 1;
    rotatePipelineLayoutInfo.pPushConstantRanges = &rotatePushConstant;

    vkCreatePipelineLayout(m_Device, &rotatePipelineLayoutInfo, m_VulkanAllocator, &m_RotatePipelineLayout);

    auto rotateShaderCode = ReadFile("shaders/spv/rotate.spv");
    if (!rotateShaderCode.empty()) {
        VkShaderModule rotateShaderModule = CreateShaderModule(m_Device, rotateShaderCode);
        VkComputePipelineCreateInfo rotatePipelineInfo{};
        rotatePipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
        rotatePipelineInfo.layout = m_RotatePipelineLayout;
        rotatePipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        rotatePipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
        rotatePipelineInfo.stage.module = rotateShaderModule;
        rotatePipelineInfo.stage.pName = "main";
        vkCreateComputePipelines(m_Device, VK_NULL_HANDLE, 1, &rotatePipelineInfo, m_VulkanAllocator, &m_RotatePSO);
        vkDestroyShaderModule(m_Device, rotateShaderModule, m_VulkanAllocator);
    }

    printf("Compute Pipelines initialized.\n");
}

void UmbriferaApp::DestroyTexture(GpuTexture& tex) {
    if (tex.image != VK_NULL_HANDLE) {
        vkDestroyImageView(m_Device, tex.view, m_VulkanAllocator);
        if (tex.storageView != VK_NULL_HANDLE) {
            vkDestroyImageView(m_Device, tex.storageView, m_VulkanAllocator);
        }
        vkDestroyImage(m_Device, tex.image, m_VulkanAllocator);
        vkFreeMemory(m_Device, tex.memory, m_VulkanAllocator);
        vkDestroySampler(m_Device, tex.sampler, m_VulkanAllocator);
        // Note: ImGui descriptor set is not explicitly freed here as it's part of the pool
        // but we could use ImGui_ImplVulkan_RemoveTexture if needed.
        tex.image = VK_NULL_HANDLE;
        tex.view = VK_NULL_HANDLE;
        tex.storageView = VK_NULL_HANDLE;
    }
}

void UmbriferaApp::CleanupGraphicsBackend() {
    vkDeviceWaitIdle(m_Device);

    if (m_UtilityCommandPool) {
        vkDestroyCommandPool(m_Device, m_UtilityCommandPool, m_VulkanAllocator);
    }

    if (m_RawHistogramBuffer) {
        vkDestroyBuffer(m_Device, m_RawHistogramBuffer.buffer, m_VulkanAllocator);
        vkFreeMemory(m_Device, m_RawHistogramBuffer.memory, m_VulkanAllocator);
    }
    if (m_UniformBuffer) {
        vkDestroyBuffer(m_Device, m_UniformBuffer.buffer, m_VulkanAllocator);
        vkFreeMemory(m_Device, m_UniformBuffer.memory, m_VulkanAllocator);
    }
    if (m_HistogramBuffer) {
        vkDestroyBuffer(m_Device, m_HistogramBuffer.buffer, m_VulkanAllocator);
        vkFreeMemory(m_Device, m_HistogramBuffer.memory, m_VulkanAllocator);
    }
    if (m_HistogramBufferDisplay) {
        vkDestroyBuffer(m_Device, m_HistogramBufferDisplay.buffer, m_VulkanAllocator);
        vkFreeMemory(m_Device, m_HistogramBufferDisplay.memory, m_VulkanAllocator);
    }

    if (m_HistogramFence) {
        vkDestroyFence(m_Device, m_HistogramFence, m_VulkanAllocator);
    }
    if (m_HistogramCommandBuffer) {
        vkFreeCommandBuffers(m_Device, m_UtilityCommandPool, 1, &m_HistogramCommandBuffer);
    }

    if (m_RenderPSO) vkDestroyPipeline(m_Device, m_RenderPSO, m_VulkanAllocator);
    if (m_ComputePipelineLayout) vkDestroyPipelineLayout(m_Device, m_ComputePipelineLayout, m_VulkanAllocator);
    if (m_ComputeDescriptorSetLayout) vkDestroyDescriptorSetLayout(m_Device, m_ComputeDescriptorSetLayout, m_VulkanAllocator);

    if (m_HistogramPSO) vkDestroyPipeline(m_Device, m_HistogramPSO, m_VulkanAllocator);
    if (m_HistogramPipelineLayout) vkDestroyPipelineLayout(m_Device, m_HistogramPipelineLayout, m_VulkanAllocator);
    if (m_HistogramDescriptorSetLayout) vkDestroyDescriptorSetLayout(m_Device, m_HistogramDescriptorSetLayout, m_VulkanAllocator);

    DestroyTexture(m_RawTexture);
    DestroyTexture(m_ProcessedTexture);
    DestroyTexture(m_LogoTexture);
    DestroyTexture(m_RotateCWTexture);
    DestroyTexture(m_RotateCCWTexture);
    DestroyTexture(m_CropTexture);
    DestroyTexture(m_CropRotateTexture);
    DestroyTexture(m_FitScreenTexture);

    ImGui_ImplVulkan_Shutdown();
    ImGui_ImplVulkanH_DestroyWindow(m_VulkanInstance, m_Device, &m_VulkanMainWindowData, m_VulkanAllocator);
    vkDestroyDescriptorPool(m_Device, m_VulkanDescriptorPool, m_VulkanAllocator);
    vkDestroyDevice(m_Device, m_VulkanAllocator);
    vkDestroySurfaceKHR(m_VulkanInstance, m_VulkanSurface, m_VulkanAllocator);
    vkDestroyInstance(m_VulkanInstance, m_VulkanAllocator);
}

void UmbriferaApp::RenderFrame() {
    ImGui_ImplVulkanH_Window* wd = &m_VulkanMainWindowData;
    if (m_VulkanSwapChainRebuild) {
        int width, height;
        glfwGetFramebufferSize(m_Window, &width, &height);
        if (width > 0 && height > 0) {
            ImGui_ImplVulkan_SetMinImageCount(m_VulkanMinImageCount);
            ImGui_ImplVulkanH_CreateOrResizeWindow(m_VulkanInstance, m_VulkanPhysicalDevice, m_Device, &m_VulkanMainWindowData, m_VulkanQueueFamily, m_VulkanAllocator, width, height, m_VulkanMinImageCount, 0);
            m_VulkanMainWindowData.FrameIndex = 0;
            m_VulkanSwapChainRebuild = false;
        }
    }

    // Handle Texture Upload (if a new image was loaded)
    if (m_TextureUploadPending) {
        std::lock_guard<std::mutex> lock(m_LoadingMutex);
        
        {
            std::lock_guard<std::recursive_mutex> vulkanLock(m_VulkanResourceMutex);
            vkDeviceWaitIdle(m_Device); // Ensure all GPU operations finish before destroying textures
            
            // Reset histogram descriptor set since we're destroying textures
            if (m_HistogramDescriptorSet != VK_NULL_HANDLE) {
                vkFreeDescriptorSets(m_Device, m_VulkanDescriptorPool, 1, &m_HistogramDescriptorSet);
                m_HistogramDescriptorSet = VK_NULL_HANDLE;
            }
            
            DestroyTexture(m_RawTexture);
            DestroyTexture(m_ProcessedTexture);
        }

        // Create the GPU texture
        m_RawTexture = CreateTexture(m_PendingWidth, m_PendingHeight, GpuPixelFormat::RGBA16Unorm, false, false);
        
        // Upload the data
        UpdateTexture(m_RawTexture, m_PendingTextureData16.data(), m_PendingWidth * 8); // 8 bytes per pixel for 16-bit RGBA
        
        // Create the destination texture (where processed image goes)
        m_ProcessedTexture = CreateTexture(m_PendingWidth, m_PendingHeight, GpuPixelFormat::BGRA8Unorm, true, true);
        
        m_PendingTextureData16.clear();
        m_TextureUploadPending = false;
        m_IsLoading = false;
        m_ImageDirty = true; // Trigger initial processing
        m_RawHistogramDirty = true; // Trigger histogram computation
        
        // Reset view
        m_ViewZoom = 1.0f;
        m_ViewOffset[0] = 0.0f;
        m_ViewOffset[1] = 0.0f;
        m_RotationAngle = 0;
        
        // Load sidecar if exists
        LoadSidecar();
    }

    VkResult err;

    // 1. Update Uniforms
    UpdateUniforms();

    // Compute histogram asynchronously
    ComputeHistogram();

    // Handle pending crop operation
    if (m_CropPending && m_RawTexture) {
        m_CropPending = false;
        
        // Calculate crop coordinates in pixels
        uint32_t x = (uint32_t)(m_CropRect[0] * m_RawTexture.width);
        uint32_t y = (uint32_t)(m_CropRect[1] * m_RawTexture.height);
        uint32_t w = (uint32_t)(m_CropRect[2] * m_RawTexture.width);
        uint32_t h = (uint32_t)(m_CropRect[3] * m_RawTexture.height);
        
        if (w > 0 && h > 0) {
            GpuTexture croppedRaw = CreateTexture(w, h, GpuPixelFormat::RGBA16Unorm, false, true);
            
            VkCommandBuffer commandBuffer = BeginSingleTimeCommands();
            
            // Copy region from raw to cropped
            VkImageCopy copyRegion{};
            copyRegion.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            copyRegion.srcSubresource.mipLevel = 0;
            copyRegion.srcSubresource.baseArrayLayer = 0;
            copyRegion.srcSubresource.layerCount = 1;
            copyRegion.srcOffset = {(int32_t)x, (int32_t)y, 0};
            
            copyRegion.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            copyRegion.dstSubresource.mipLevel = 0;
            copyRegion.dstSubresource.baseArrayLayer = 0;
            copyRegion.dstSubresource.layerCount = 1;
            copyRegion.dstOffset = {0, 0, 0};
            
            copyRegion.extent = {w, h, 1};
            
            // Transition both to TRANSFER layouts
            VkImageMemoryBarrier barriers[2] = {};
            barriers[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            barriers[0].oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            barriers[0].newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            barriers[0].image = m_RawTexture.image;
            barriers[0].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            barriers[0].subresourceRange.levelCount = 1;
            barriers[0].subresourceRange.layerCount = 1;
            barriers[0].srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
            barriers[0].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
            
            barriers[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            barriers[1].oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
            barriers[1].newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            barriers[1].image = croppedRaw.image;
            barriers[1].subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            barriers[1].subresourceRange.levelCount = 1;
            barriers[1].subresourceRange.layerCount = 1;
            barriers[1].srcAccessMask = 0;
            barriers[1].dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            
            vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 2, barriers);
            
            vkCmdCopyImage(commandBuffer, m_RawTexture.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, croppedRaw.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copyRegion);
            
            // Transition back
            barriers[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            barriers[0].newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            barriers[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
            barriers[0].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
            
            barriers[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
            barriers[1].newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            barriers[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            barriers[1].dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
            
            vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 2, barriers);
            
            EndSingleTimeCommands(commandBuffer);
            
            DestroyTexture(m_RawTexture);
            m_RawTexture = croppedRaw;
            
            // Recreate processed texture
            DestroyTexture(m_ProcessedTexture);
            m_ProcessedTexture = CreateTexture(w, h, GpuPixelFormat::BGRA8Unorm, true, true);
            
            m_GrainNeedsRegeneration = true;
            m_ImageDirty = true;
            m_RawHistogramDirty = true;
        }
    }
    
    // Handle pending rotation operation
    if (m_RotatePending && m_RawTexture && m_RotatePSO) {
        m_RotatePending = false;
        
        float angleRad = m_PendingRotationAngle * (3.1415926535f / 180.0f);
        float cosA = cosf(angleRad);
        float sinA = sinf(angleRad);
        
        uint32_t srcW = m_RawTexture.width;
        uint32_t srcH = m_RawTexture.height;
        float imgAspect = (float)srcW / (float)srcH;
        
        float scaleFactorW = fabsf(cosA) + fabsf(sinA) / imgAspect;
        float scaleFactorH = fabsf(cosA) + fabsf(sinA) * imgAspect;
        float inscribedScale = fmaxf(scaleFactorW, scaleFactorH);
        if (inscribedScale < 1.0f) inscribedScale = 1.0f;
        
        uint32_t dstW = (uint32_t)((float)srcW / inscribedScale);
        uint32_t dstH = (uint32_t)((float)srcH / inscribedScale);
        
        GpuTexture rotatedRaw = CreateTexture(dstW, dstH, GpuPixelFormat::RGBA16Unorm, false, true);
        
        VkCommandBuffer commandBuffer = BeginSingleTimeCommands();
        
        vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_RotatePSO);
        
        VkDescriptorSet descriptorSet;
        VkDescriptorSetAllocateInfo dsAllocInfo{};
        dsAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        dsAllocInfo.descriptorPool = m_VulkanDescriptorPool;
        dsAllocInfo.descriptorSetCount = 1;
        dsAllocInfo.pSetLayouts = &m_RotateDescriptorSetLayout;
        
        if (vkAllocateDescriptorSets(m_Device, &dsAllocInfo, &descriptorSet) == VK_SUCCESS) {
            VkDescriptorImageInfo inputInfo{};
            inputInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            inputInfo.imageView = m_RawTexture.view;
            inputInfo.sampler = m_RawTexture.sampler;
            
            VkDescriptorImageInfo outputInfo{};
            outputInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
            outputInfo.imageView = rotatedRaw.storageView;
            
            VkWriteDescriptorSet descriptorWrites[2] = {};
            descriptorWrites[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            descriptorWrites[0].dstSet = descriptorSet;
            descriptorWrites[0].dstBinding = 0;
            descriptorWrites[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            descriptorWrites[0].descriptorCount = 1;
            descriptorWrites[0].pImageInfo = &inputInfo;
            
            descriptorWrites[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
            descriptorWrites[1].dstSet = descriptorSet;
            descriptorWrites[1].dstBinding = 1;
            descriptorWrites[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
            descriptorWrites[1].descriptorCount = 1;
            descriptorWrites[1].pImageInfo = &outputInfo;
            
            vkUpdateDescriptorSets(m_Device, 2, descriptorWrites, 0, nullptr);
            vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_RotatePipelineLayout, 0, 1, &descriptorSet, 0, nullptr);
            
            struct {
                float cosAngle, sinAngle, scale, srcW, srcH;
            } pushConstants;
            pushConstants.cosAngle = cosA;
            pushConstants.sinAngle = sinA;
            pushConstants.scale = 1.0f;
            pushConstants.srcW = (float)srcW;
            pushConstants.srcH = (float)srcH;
            
            vkCmdPushConstants(commandBuffer, m_RotatePipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(pushConstants), &pushConstants);
            
            // Transition rotatedRaw to GENERAL
            VkImageMemoryBarrier barrier{};
            barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
            barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
            barrier.image = rotatedRaw.image;
            barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            barrier.subresourceRange.levelCount = 1;
            barrier.subresourceRange.layerCount = 1;
            barrier.srcAccessMask = 0;
            barrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
            vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
            
            vkCmdDispatch(commandBuffer, (dstW + 15) / 16, (dstH + 15) / 16, 1);
            
            // Transition to SHADER_READ_ONLY_OPTIMAL
            barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
            barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
            barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
            barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
            vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
        }
        
        EndSingleTimeCommands(commandBuffer);
        
        DestroyTexture(m_RawTexture);
        m_RawTexture = rotatedRaw;
        
        // Recreate processed texture
        DestroyTexture(m_ProcessedTexture);
        m_ProcessedTexture = CreateTexture(dstW, dstH, GpuPixelFormat::BGRA8Unorm, true, true);
        
        m_GrainNeedsRegeneration = true;
        m_ImageDirty = true;
        m_RawHistogramDirty = true;
    }

    // 2. Handle Image Processing
    if (m_ImageDirty) {
        ProcessImage();
        m_HistogramFrameCounter = 0;
        // m_ImageDirty = false; // Handled inside ProcessImage
    }
    
    // Histogram is now computed CPU-side in the UI from texture data
    // This eliminates GPU synchronization stalls
    
    if (m_RawHistogramDirty) {
        ComputeRawHistogram();
    }
    
    // Perform deferred histogram readback (one frame after GPU computation)
    if (m_RawHistogramReadbackNeeded && m_RawHistogramBuffer) {
        void* mapped = GetBufferContents(m_RawHistogramBuffer);
        m_RawHistogram.assign((uint32_t*)mapped, (uint32_t*)mapped + 256);
        vkUnmapMemory(m_Device, m_RawHistogramBuffer.memory);
        m_RawHistogramReadbackNeeded = false;
    }

    // 3. Start ImGui Frame
    ImGui_ImplVulkan_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

    SetupLayout();
    RenderUI();
    ImGui::Render();

    // 4. Render to Swapchain
    ImGui_ImplVulkanH_Frame* fd = &wd->Frames[wd->FrameIndex];
    {
        err = vkWaitForFences(m_Device, 1, &fd->Fence, VK_TRUE, UINT64_MAX);
        check_vk_result(err);
        err = vkResetFences(m_Device, 1, &fd->Fence);
        check_vk_result(err);
    }
    {
        err = vkResetCommandPool(m_Device, fd->CommandPool, 0);
        check_vk_result(err);
        VkCommandBufferBeginInfo info = {};
        info.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        info.flags |= VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        err = vkBeginCommandBuffer(fd->CommandBuffer, &info);
        check_vk_result(err);
    }

    // If image is dirty, we could potentially run compute here in the same command buffer
    // but for now we keep it separate to avoid complex synchronization with ImGui's internal command buffer.
    // However, we removed vkQueueWaitIdle from the main loop by using a dedicated pool and better sync.
    // Actually, the best performance is to use a fence for the compute work.

    {
        VkRenderPassBeginInfo info = {};
        info.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        info.renderPass = wd->RenderPass;
        info.framebuffer = fd->Framebuffer;
        info.renderArea.extent.width = wd->Width;
        info.renderArea.extent.height = wd->Height;
        info.clearValueCount = 1;
        info.pClearValues = &wd->ClearValue;
        vkCmdBeginRenderPass(fd->CommandBuffer, &info, VK_SUBPASS_CONTENTS_INLINE);
    }

    // Record ImGui primitives into command buffer
    ImGui_ImplVulkan_RenderDrawData(ImGui::GetDrawData(), fd->CommandBuffer);

    // Submit command buffer
    vkCmdEndRenderPass(fd->CommandBuffer);
    
    VkSemaphore image_acquired_semaphore  = wd->FrameSemaphores[wd->SemaphoreIndex].ImageAcquiredSemaphore;
    VkSemaphore render_complete_semaphore = wd->FrameSemaphores[wd->SemaphoreIndex].RenderCompleteSemaphore;
    {
        VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo info = {};
        info.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        info.waitSemaphoreCount = 1;
        info.pWaitSemaphores = &image_acquired_semaphore;
        info.pWaitDstStageMask = &wait_stage;
        info.commandBufferCount = 1;
        info.pCommandBuffers = &fd->CommandBuffer;
        info.signalSemaphoreCount = 1;
        info.pSignalSemaphores = &render_complete_semaphore;

        err = vkEndCommandBuffer(fd->CommandBuffer);
        check_vk_result(err);
        err = vkQueueSubmit(m_CommandQueue, 1, &info, fd->Fence);
        check_vk_result(err);
    }

    // Update viewports if enabled
    if (ImGui::GetIO().ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
        ImGui::UpdatePlatformWindows();
        ImGui::RenderPlatformWindowsDefault();
    }

    // Present
    {
        if (m_VulkanSwapChainRebuild) return;
        VkPresentInfoKHR info = {};
        info.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        info.waitSemaphoreCount = 1;
        info.pWaitSemaphores = &render_complete_semaphore;
        info.swapchainCount = 1;
        info.pSwapchains = &wd->Swapchain;
        info.pImageIndices = &wd->FrameIndex;
        err = vkQueuePresentKHR(m_CommandQueue, &info);
        if (err == VK_ERROR_OUT_OF_DATE_KHR || err == VK_SUBOPTIMAL_KHR) {
            m_VulkanSwapChainRebuild = true;
            return;
        }
        check_vk_result(err);
        wd->SemaphoreIndex = (wd->SemaphoreIndex + 1) % wd->ImageCount; // Now we can use the next set of semaphores
    }
}

void UmbriferaApp::GenerateGrainTexture() {
    if (!m_GrainPSO) return;

    int grainW = 1024;
    int grainH = 1024;

    if (!m_GrainTexture || m_GrainTexture.width != grainW || m_GrainTexture.height != grainH) {
        DestroyTexture(m_GrainTexture);
        m_GrainTexture = CreateTexture(grainW, grainH, GpuPixelFormat::RGBA8Unorm, false, true);
    }

    std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);

    VkCommandBuffer commandBuffer = BeginSingleTimeCommands();

    vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_GrainPSO);

    VkDescriptorSet descriptorSet;
    VkDescriptorSetAllocateInfo dsAllocInfo{};
    dsAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    dsAllocInfo.descriptorPool = m_VulkanDescriptorPool;
    dsAllocInfo.descriptorSetCount = 1;
    dsAllocInfo.pSetLayouts = &m_GrainDescriptorSetLayout;

    if (vkAllocateDescriptorSets(m_Device, &dsAllocInfo, &descriptorSet) == VK_SUCCESS) {
        VkDescriptorImageInfo outputInfo{};
        outputInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
        outputInfo.imageView = m_GrainTexture.storageView;

        VkWriteDescriptorSet descriptorWrite{};
        descriptorWrite.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrite.dstSet = descriptorSet;
        descriptorWrite.dstBinding = 0;
        descriptorWrite.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
        descriptorWrite.descriptorCount = 1;
        descriptorWrite.pImageInfo = &outputInfo;

        vkUpdateDescriptorSets(m_Device, 1, &descriptorWrite, 0, nullptr);
        vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_GrainPipelineLayout, 0, 1, &descriptorSet, 0, nullptr);

        struct {
            float width, height, grainSize, seed;
        } pushConstants;
        pushConstants.width = (float)grainW;
        pushConstants.height = (float)grainH;
        pushConstants.grainSize = m_Uniforms.grain_size;
        pushConstants.seed = (float)rand() / (float)RAND_MAX;

        vkCmdPushConstants(commandBuffer, m_GrainPipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(pushConstants), &pushConstants);

        // Transition to GENERAL
        VkImageMemoryBarrier barrier{};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        barrier.image = m_GrainTexture.image;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

        vkCmdDispatch(commandBuffer, (grainW + 15) / 16, (grainH + 15) / 16, 1);

        // Transition to SHADER_READ_ONLY_OPTIMAL
        barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    }

    EndSingleTimeCommands(commandBuffer);
    m_GrainNeedsRegeneration = false;
}

void UmbriferaApp::ProcessImage() {
    if (!m_RawTexture || !m_ProcessedTexture || !m_RenderPSO) return;

    if (m_GrainNeedsRegeneration || !m_GrainTexture) {
        GenerateGrainTexture();
    }

    std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);

    if (!m_UniformBuffer) {
        m_UniformBuffer = CreateBuffer(sizeof(Uniforms), false);
    }
    UpdateBuffer(m_UniformBuffer, &m_Uniforms, sizeof(Uniforms));

    VkCommandBufferAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandPool = m_UtilityCommandPool;
    allocInfo.commandBufferCount = 1;

    VkCommandBuffer commandBuffer;
    vkAllocateCommandBuffers(m_Device, &allocInfo, &commandBuffer);

    VkCommandBufferBeginInfo beginInfo{};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vkBeginCommandBuffer(commandBuffer, &beginInfo);

    vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_RenderPSO);

    // Create and update descriptor set
    VkDescriptorSet descriptorSet;
    VkDescriptorSetAllocateInfo dsAllocInfo{};
    dsAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    dsAllocInfo.descriptorPool = m_VulkanDescriptorPool;
    dsAllocInfo.descriptorSetCount = 1;
    dsAllocInfo.pSetLayouts = &m_ComputeDescriptorSetLayout;

    if (vkAllocateDescriptorSets(m_Device, &dsAllocInfo, &descriptorSet) != VK_SUCCESS) {
        vkEndCommandBuffer(commandBuffer);
        vkFreeCommandBuffers(m_Device, m_UtilityCommandPool, 1, &commandBuffer);
        return;
    }

    VkDescriptorImageInfo inputInfo{};
    inputInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    inputInfo.imageView = m_RawTexture.view;
    inputInfo.sampler = m_RawTexture.sampler;

    VkDescriptorImageInfo outputInfo{};
    outputInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
    outputInfo.imageView = m_ProcessedTexture.storageView;

    VkDescriptorBufferInfo uniformInfo{};
    uniformInfo.buffer = m_UniformBuffer.buffer;
    uniformInfo.offset = 0;
    uniformInfo.range = sizeof(Uniforms);

    VkDescriptorImageInfo grainInfo{};
    grainInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    grainInfo.imageView = m_GrainTexture.view;
    grainInfo.sampler = m_GrainTexture.sampler;

    VkWriteDescriptorSet descriptorWrites[4] = {};
    descriptorWrites[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[0].dstSet = descriptorSet;
    descriptorWrites[0].dstBinding = 0;
    descriptorWrites[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    descriptorWrites[0].descriptorCount = 1;
    descriptorWrites[0].pImageInfo = &inputInfo;

    descriptorWrites[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[1].dstSet = descriptorSet;
    descriptorWrites[1].dstBinding = 1;
    descriptorWrites[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    descriptorWrites[1].descriptorCount = 1;
    descriptorWrites[1].pImageInfo = &outputInfo;

    descriptorWrites[2].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[2].dstSet = descriptorSet;
    descriptorWrites[2].dstBinding = 2;
    descriptorWrites[2].descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
    descriptorWrites[2].descriptorCount = 1;
    descriptorWrites[2].pBufferInfo = &uniformInfo;

    descriptorWrites[3].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    descriptorWrites[3].dstSet = descriptorSet;
    descriptorWrites[3].dstBinding = 3;
    descriptorWrites[3].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    descriptorWrites[3].descriptorCount = 1;
    descriptorWrites[3].pImageInfo = &grainInfo;

    vkUpdateDescriptorSets(m_Device, 4, descriptorWrites, 0, nullptr);

    vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_ComputePipelineLayout, 0, 1, &descriptorSet, 0, nullptr);

    // Transition output image to GENERAL layout for writing
    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = m_ProcessedTexture.image;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = VK_REMAINING_MIP_LEVELS;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;

    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    uint32_t groupCountX = (m_ProcessedTexture.width + 15) / 16;
    uint32_t groupCountY = (m_ProcessedTexture.height + 15) / 16;
    vkCmdDispatch(commandBuffer, groupCountX, groupCountY, 1);

    // Transition output image back to SHADER_READ_ONLY_OPTIMAL for ImGui
    barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    vkEndCommandBuffer(commandBuffer);

    VkSubmitInfo submitInfo{};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &commandBuffer;

    // Use a fence to avoid vkQueueWaitIdle
    VkFence fence;
    VkFenceCreateInfo fenceInfo{};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    vkCreateFence(m_Device, &fenceInfo, m_VulkanAllocator, &fence);

    vkQueueSubmit(m_CommandQueue, 1, &submitInfo, fence);
    
    // Wait for compute to finish (still blocking but better than waitIdle which waits for EVERYTHING)
    vkWaitForFences(m_Device, 1, &fence, VK_TRUE, UINT64_MAX);
    vkDestroyFence(m_Device, fence, m_VulkanAllocator);

    // Generate mipmaps if needed
    GenerateMipmaps(m_ProcessedTexture);

    // Free descriptor set
    vkFreeDescriptorSets(m_Device, m_VulkanDescriptorPool, 1, &descriptorSet);
    vkFreeCommandBuffers(m_Device, m_UtilityCommandPool, 1, &commandBuffer);

    m_ImageDirty = false;
}

void UmbriferaApp::ComputeHistogram() {
    if (!m_ProcessedTexture || !m_HistogramPSO) return;

    // Check if previous histogram work is still in progress
    if (m_HistogramFence != VK_NULL_HANDLE) {
        if (vkGetFenceStatus(m_Device, m_HistogramFence) == VK_NOT_READY) {
            return; // Still busy
        }
        vkResetFences(m_Device, 1, &m_HistogramFence);
    }

    // Free previous command buffer if it exists
    if (m_HistogramCommandBuffer != VK_NULL_HANDLE) {
        vkFreeCommandBuffers(m_Device, m_UtilityCommandPool, 1, &m_HistogramCommandBuffer);
        m_HistogramCommandBuffer = VK_NULL_HANDLE;
    }

    if (!m_HistogramBuffer) {
        m_HistogramBuffer = CreateBuffer(256 * sizeof(uint32_t), true);
        m_HistogramDescriptorSet = VK_NULL_HANDLE;
    }
    if (!m_HistogramBufferDisplay) {
        m_HistogramBufferDisplay = CreateBuffer(256 * sizeof(uint32_t), true);
    }

    // Allocate descriptor set once per image (not every frame)
    if (m_HistogramDescriptorSet == VK_NULL_HANDLE) {
        VkDescriptorSetAllocateInfo allocInfo{};
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocInfo.descriptorPool = m_VulkanDescriptorPool;
        allocInfo.descriptorSetCount = 1;
        allocInfo.pSetLayouts = &m_HistogramDescriptorSetLayout;

        if (vkAllocateDescriptorSets(m_Device, &allocInfo, &m_HistogramDescriptorSet) != VK_SUCCESS) {
            return;
        }

        VkDescriptorImageInfo inputInfo{};
        inputInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        inputInfo.imageView = m_ProcessedTexture.view;
        inputInfo.sampler = m_ProcessedTexture.sampler;

        VkDescriptorBufferInfo bufferInfo{};
        bufferInfo.buffer = m_HistogramBuffer.buffer;
        bufferInfo.offset = 0;
        bufferInfo.range = 256 * sizeof(uint32_t);

        VkWriteDescriptorSet descriptorWrites[2] = {};
        descriptorWrites[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrites[0].dstSet = m_HistogramDescriptorSet;
        descriptorWrites[0].dstBinding = 0;
        descriptorWrites[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        descriptorWrites[0].descriptorCount = 1;
        descriptorWrites[0].pImageInfo = &inputInfo;

        descriptorWrites[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrites[1].dstSet = m_HistogramDescriptorSet;
        descriptorWrites[1].dstBinding = 1;
        descriptorWrites[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        descriptorWrites[1].descriptorCount = 1;
        descriptorWrites[1].pBufferInfo = &bufferInfo;

        vkUpdateDescriptorSets(m_Device, 2, descriptorWrites, 0, nullptr);
    }

    {
        std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);
        
        VkCommandBufferAllocateInfo allocInfo{};
        allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        allocInfo.commandPool = m_UtilityCommandPool;
        allocInfo.commandBufferCount = 1;

        if (vkAllocateCommandBuffers(m_Device, &allocInfo, &m_HistogramCommandBuffer) != VK_SUCCESS) {
            return;
        }

        VkCommandBufferBeginInfo beginInfo{};
        beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        vkBeginCommandBuffer(m_HistogramCommandBuffer, &beginInfo);

        // Clear histogram buffer
        vkCmdFillBuffer(m_HistogramCommandBuffer, m_HistogramBuffer.buffer, 0, 256 * sizeof(uint32_t), 0);

        // Barrier to ensure clear is done
        VkBufferMemoryBarrier clearBarrier{};
        clearBarrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        clearBarrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        clearBarrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
        clearBarrier.buffer = m_HistogramBuffer.buffer;
        clearBarrier.offset = 0;
        clearBarrier.size = 256 * sizeof(uint32_t);
        vkCmdPipelineBarrier(m_HistogramCommandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 1, &clearBarrier, 0, nullptr);

        vkCmdBindPipeline(m_HistogramCommandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_HistogramPSO);
        vkCmdBindDescriptorSets(m_HistogramCommandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_HistogramPipelineLayout, 0, 1, &m_HistogramDescriptorSet, 0, nullptr);

        uint32_t groupCountX = (m_ProcessedTexture.width + 15) / 16;
        uint32_t groupCountY = (m_ProcessedTexture.height + 15) / 16;
        vkCmdDispatch(m_HistogramCommandBuffer, groupCountX, groupCountY, 1);

        // Barrier to ensure compute is done
        VkBufferMemoryBarrier computeBarrier{};
        computeBarrier.sType = VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER;
        computeBarrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        computeBarrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        computeBarrier.buffer = m_HistogramBuffer.buffer;
        computeBarrier.offset = 0;
        computeBarrier.size = 256 * sizeof(uint32_t);
        vkCmdPipelineBarrier(m_HistogramCommandBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 1, &computeBarrier, 0, nullptr);

        // Copy to display buffer
        VkBufferCopy copyRegion{};
        copyRegion.size = 256 * sizeof(uint32_t);
        vkCmdCopyBuffer(m_HistogramCommandBuffer, m_HistogramBuffer.buffer, m_HistogramBufferDisplay.buffer, 1, &copyRegion);

        vkEndCommandBuffer(m_HistogramCommandBuffer);

        VkSubmitInfo submitInfo{};
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &m_HistogramCommandBuffer;

        vkQueueSubmit(m_CommandQueue, 1, &submitInfo, m_HistogramFence);
    }
}

void UmbriferaApp::ComputeRawHistogram() {
    if (!m_RawTexture || !m_HistogramPSO) return;

    if (!m_RawHistogramBuffer) {
        m_RawHistogramBuffer = CreateBuffer(256 * sizeof(uint32_t), true);
    }

    {
        std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);
        
        VkCommandBuffer commandBuffer = BeginSingleTimeCommands();

        vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_HistogramPSO);

        VkDescriptorSet descriptorSet;
        VkDescriptorSetAllocateInfo allocInfo{};
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocInfo.descriptorPool = m_VulkanDescriptorPool;
        allocInfo.descriptorSetCount = 1;
        allocInfo.pSetLayouts = &m_HistogramDescriptorSetLayout;

        if (vkAllocateDescriptorSets(m_Device, &allocInfo, &descriptorSet) != VK_SUCCESS) {
            EndSingleTimeCommands(commandBuffer);
            return;
        }

        VkDescriptorImageInfo inputInfo{};
        inputInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        inputInfo.imageView = m_RawTexture.view;
        inputInfo.sampler = m_RawTexture.sampler;

        VkDescriptorBufferInfo bufferInfo{};
        bufferInfo.buffer = m_RawHistogramBuffer.buffer;
        bufferInfo.offset = 0;
        bufferInfo.range = 256 * sizeof(uint32_t);

        VkWriteDescriptorSet descriptorWrites[2] = {};
        descriptorWrites[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrites[0].dstSet = descriptorSet;
        descriptorWrites[0].dstBinding = 0;
        descriptorWrites[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        descriptorWrites[0].descriptorCount = 1;
        descriptorWrites[0].pImageInfo = &inputInfo;

        descriptorWrites[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrites[1].dstSet = descriptorSet;
        descriptorWrites[1].dstBinding = 1;
        descriptorWrites[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
        descriptorWrites[1].descriptorCount = 1;
        descriptorWrites[1].pBufferInfo = &bufferInfo;

        vkUpdateDescriptorSets(m_Device, 2, descriptorWrites, 0, nullptr);

        vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_HistogramPipelineLayout, 0, 1, &descriptorSet, 0, nullptr);

        uint32_t groupCountX = (m_RawTexture.width + 15) / 16;
        uint32_t groupCountY = (m_RawTexture.height + 15) / 16;
        vkCmdDispatch(commandBuffer, groupCountX, groupCountY, 1);

        EndSingleTimeCommands(commandBuffer);
        
        vkFreeDescriptorSets(m_Device, m_VulkanDescriptorPool, 1, &descriptorSet);
    }

    // Defer readback to next frame to avoid GPU stall
    m_RawHistogramReadbackNeeded = true;
    
    m_RawHistogramDirty = false;
}

void UmbriferaApp::ResizeImage(int targetWidth, int targetHeight) {
    if (!m_RawTexture || !m_ResizePSO) return;

    GpuTexture resizedRaw = CreateTexture(targetWidth, targetHeight, GpuPixelFormat::RGBA16Unorm, false, true);

    std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);

    VkCommandBuffer commandBuffer = BeginSingleTimeCommands();

    vkCmdBindPipeline(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_ResizePSO);

    VkDescriptorSet descriptorSet;
    VkDescriptorSetAllocateInfo dsAllocInfo{};
    dsAllocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    dsAllocInfo.descriptorPool = m_VulkanDescriptorPool;
    dsAllocInfo.descriptorSetCount = 1;
    dsAllocInfo.pSetLayouts = &m_ResizeDescriptorSetLayout;

    if (vkAllocateDescriptorSets(m_Device, &dsAllocInfo, &descriptorSet) == VK_SUCCESS) {
        VkDescriptorImageInfo inputInfo{};
        inputInfo.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        inputInfo.imageView = m_RawTexture.view;
        inputInfo.sampler = m_RawTexture.sampler;

        VkDescriptorImageInfo outputInfo{};
        outputInfo.imageLayout = VK_IMAGE_LAYOUT_GENERAL;
        outputInfo.imageView = resizedRaw.storageView;

        VkWriteDescriptorSet descriptorWrites[2] = {};
        descriptorWrites[0].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrites[0].dstSet = descriptorSet;
        descriptorWrites[0].dstBinding = 0;
        descriptorWrites[0].descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        descriptorWrites[0].descriptorCount = 1;
        descriptorWrites[0].pImageInfo = &inputInfo;

        descriptorWrites[1].sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        descriptorWrites[1].dstSet = descriptorSet;
        descriptorWrites[1].dstBinding = 1;
        descriptorWrites[1].descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
        descriptorWrites[1].descriptorCount = 1;
        descriptorWrites[1].pImageInfo = &outputInfo;

        vkUpdateDescriptorSets(m_Device, 2, descriptorWrites, 0, nullptr);
        vkCmdBindDescriptorSets(commandBuffer, VK_PIPELINE_BIND_POINT_COMPUTE, m_ResizePipelineLayout, 0, 1, &descriptorSet, 0, nullptr);

        struct {
            float srcW, srcH, dstW, dstH;
        } pushConstants;
        pushConstants.srcW = (float)m_RawTexture.width;
        pushConstants.srcH = (float)m_RawTexture.height;
        pushConstants.dstW = (float)targetWidth;
        pushConstants.dstH = (float)targetHeight;

        vkCmdPushConstants(commandBuffer, m_ResizePipelineLayout, VK_SHADER_STAGE_COMPUTE_BIT, 0, sizeof(pushConstants), &pushConstants);

        // Transition resizedRaw to GENERAL
        VkImageMemoryBarrier barrier{};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_GENERAL;
        barrier.image = resizedRaw.image;
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

        vkCmdDispatch(commandBuffer, (targetWidth + 15) / 16, (targetHeight + 15) / 16, 1);

        // Transition to SHADER_READ_ONLY_OPTIMAL
        barrier.oldLayout = VK_IMAGE_LAYOUT_GENERAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_SHADER_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
    }

    EndSingleTimeCommands(commandBuffer);

    DestroyTexture(m_RawTexture);
    m_RawTexture = resizedRaw;

    // Recreate processed texture with new size
    DestroyTexture(m_ProcessedTexture);
    m_ProcessedTexture = CreateTexture(targetWidth, targetHeight, GpuPixelFormat::BGRA8Unorm, true, true);
    
    m_ImageDirty = true;
    m_RawHistogramDirty = true;
    m_GrainNeedsRegeneration = true;
}

void UmbriferaApp::GetTextureBytes(GpuTexture& texture, void* outBytes, size_t bytesPerRow) {
    if (!texture) return;

    VkDeviceSize imageSize = texture.width * texture.height * (texture.format == GpuPixelFormat::RGBA16Unorm ? 8 : 4);

    GpuBuffer stagingBuffer = CreateBuffer(imageSize, false);

    VkCommandBuffer commandBuffer = BeginSingleTimeCommands();

    // Transition image to TRANSFER_SRC_OPTIMAL
    // We use UNDEFINED as oldLayout to be safe, even if it's not optimal (it might discard contents, but we are reading them anyway?)
    // Actually, we should use the current layout. Since we transition back to SHADER_READ_ONLY_OPTIMAL in ProcessImage,
    // and RawTexture is also in that layout, we can use it.
    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = texture.image;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;
    barrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;

    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy region{};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = {0, 0, 0};
    region.imageExtent = {(uint32_t)texture.width, (uint32_t)texture.height, 1};

    vkCmdCopyImageToBuffer(commandBuffer, texture.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, stagingBuffer.buffer, 1, &region);

    // Transition back
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_ALL_COMMANDS_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    EndSingleTimeCommands(commandBuffer);

    void* mapped = GetBufferContents(stagingBuffer);
    memcpy(outBytes, mapped, (size_t)imageSize);
    vkUnmapMemory(m_Device, stagingBuffer.memory);

    vkDestroyBuffer(m_Device, stagingBuffer.buffer, m_VulkanAllocator);
    vkFreeMemory(m_Device, stagingBuffer.memory, m_VulkanAllocator);
}

GpuTexture UmbriferaApp::CreateTexture(int width, int height, GpuPixelFormat format, bool mipmapped, bool renderTarget) {
    std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);
    GpuTexture tex;
    tex.width = width;
    tex.height = height;
    tex.format = format;

    VkImageCreateInfo imageInfo{};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.extent.width = width;
    imageInfo.extent.height = height;
    imageInfo.extent.depth = 1;
    imageInfo.mipLevels = mipmapped ? (uint32_t)floor(log2((float)(std::max)(width, height))) + 1 : 1;
    imageInfo.arrayLayers = 1;
    
    if (format == GpuPixelFormat::RGBA16Unorm)
        imageInfo.format = VK_FORMAT_R16G16B16A16_UNORM;
    else if (format == GpuPixelFormat::BGRA8Unorm)
        imageInfo.format = VK_FORMAT_B8G8R8A8_UNORM;
    else
        imageInfo.format = VK_FORMAT_R8G8B8A8_UNORM;

    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    imageInfo.usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (renderTarget) imageInfo.usage |= VK_IMAGE_USAGE_STORAGE_BIT | VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (vkCreateImage(m_Device, &imageInfo, m_VulkanAllocator, &tex.image) != VK_SUCCESS) {
        return {};
    }

    VkMemoryRequirements memRequirements;
    vkGetImageMemoryRequirements(m_Device, tex.image, &memRequirements);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = FindMemoryType(memRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);

    if (vkAllocateMemory(m_Device, &allocInfo, m_VulkanAllocator, &tex.memory) != VK_SUCCESS) {
        return {};
    }

    vkBindImageMemory(m_Device, tex.image, tex.memory, 0);

    VkImageViewCreateInfo viewInfo{};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = tex.image;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = imageInfo.format;
    viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    viewInfo.subresourceRange.baseMipLevel = 0;
    viewInfo.subresourceRange.levelCount = imageInfo.mipLevels;
    viewInfo.subresourceRange.baseArrayLayer = 0;
    viewInfo.subresourceRange.layerCount = 1;

    if (vkCreateImageView(m_Device, &viewInfo, m_VulkanAllocator, &tex.view) != VK_SUCCESS) {
        return {};
    }

    // Create Storage View (always 1 mip level)
    viewInfo.subresourceRange.levelCount = 1;
    if (vkCreateImageView(m_Device, &viewInfo, m_VulkanAllocator, &tex.storageView) != VK_SUCCESS) {
        return {};
    }

    // Create Sampler
    VkSamplerCreateInfo samplerInfo{};
    samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    samplerInfo.magFilter = VK_FILTER_LINEAR;
    samplerInfo.minFilter = VK_FILTER_LINEAR;
    samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    samplerInfo.anisotropyEnable = VK_FALSE;
    samplerInfo.maxAnisotropy = 1.0f;
    samplerInfo.borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK;
    samplerInfo.unnormalizedCoordinates = VK_FALSE;
    samplerInfo.compareEnable = VK_FALSE;
    samplerInfo.compareOp = VK_COMPARE_OP_ALWAYS;
    samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;
    samplerInfo.minLod = 0.0f;
    samplerInfo.maxLod = (float)imageInfo.mipLevels;
    samplerInfo.mipLodBias = 0.0f;

    if (vkCreateSampler(m_Device, &samplerInfo, m_VulkanAllocator, &tex.sampler) != VK_SUCCESS) {
        return {};
    }

    // Create Descriptor Set for ImGui
    tex.descriptorSet = ImGui_ImplVulkan_AddTexture(tex.sampler, tex.view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    return tex;
}

void UmbriferaApp::UpdateTexture(GpuTexture& texture, const void* data, size_t bytesPerRow) {
    std::lock_guard<std::recursive_mutex> lock(m_VulkanResourceMutex);
    VkDeviceSize imageSize = texture.width * texture.height * (texture.format == GpuPixelFormat::RGBA16Unorm ? 8 : 4);

    VkBuffer stagingBuffer;
    VkDeviceMemory stagingBufferMemory;
    
    VkBufferCreateInfo bufferInfo{};
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = imageSize;
    bufferInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    vkCreateBuffer(m_Device, &bufferInfo, m_VulkanAllocator, &stagingBuffer);

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(m_Device, stagingBuffer, &memRequirements);
    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = FindMemoryType(memRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    vkAllocateMemory(m_Device, &allocInfo, m_VulkanAllocator, &stagingBufferMemory);
    vkBindBufferMemory(m_Device, stagingBuffer, stagingBufferMemory, 0);

    void* mapped;
    vkMapMemory(m_Device, stagingBufferMemory, 0, imageSize, 0, &mapped);
    memcpy(mapped, data, (size_t)imageSize);
    vkUnmapMemory(m_Device, stagingBufferMemory);

    VkCommandBuffer commandBuffer = BeginSingleTimeCommands();

    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = texture.image;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;
    barrier.srcAccessMask = 0;
    barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    VkBufferImageCopy region{};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = {0, 0, 0};
    region.imageExtent = {(uint32_t)texture.width, (uint32_t)texture.height, 1};

    vkCmdCopyBufferToImage(commandBuffer, stagingBuffer, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);

    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT | VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    EndSingleTimeCommands(commandBuffer);

    vkDestroyBuffer(m_Device, stagingBuffer, m_VulkanAllocator);
    vkFreeMemory(m_Device, stagingBufferMemory, m_VulkanAllocator);
}

void UmbriferaApp::GenerateMipmaps(GpuTexture& texture) {
    if (!texture) return;
    
    // Check if image supports linear filtering for blit
    VkFormatProperties formatProperties;
    VkFormat format;
    if (texture.format == GpuPixelFormat::RGBA16Unorm) format = VK_FORMAT_R16G16B16A16_UNORM;
    else if (texture.format == GpuPixelFormat::BGRA8Unorm) format = VK_FORMAT_B8G8R8A8_UNORM;
    else format = VK_FORMAT_R8G8B8A8_UNORM;
    
    vkGetPhysicalDeviceFormatProperties(m_VulkanPhysicalDevice, format, &formatProperties);
    if (!(formatProperties.optimalTilingFeatures & VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT)) {
        return; // Not supported
    }

    uint32_t mipLevels = (uint32_t)floor(log2((float)(std::max)(texture.width, texture.height))) + 1;
    if (mipLevels <= 1) return;

    VkCommandBuffer commandBuffer = BeginSingleTimeCommands();

    VkImageMemoryBarrier barrier{};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.image = texture.image;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;

    int32_t mipWidth = texture.width;
    int32_t mipHeight = texture.height;

    for (uint32_t i = 1; i < mipLevels; i++) {
        barrier.subresourceRange.baseMipLevel = i - 1;
        barrier.subresourceRange.levelCount = 1;
        barrier.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;

        vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

        // Transition level i to TRANSFER_DST_OPTIMAL
        barrier.subresourceRange.baseMipLevel = i;
        barrier.oldLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;

        vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

        VkImageBlit blit{};
        blit.srcOffsets[0] = {0, 0, 0};
        blit.srcOffsets[1] = {mipWidth, mipHeight, 1};
        blit.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.srcSubresource.mipLevel = i - 1;
        blit.srcSubresource.baseArrayLayer = 0;
        blit.srcSubresource.layerCount = 1;
        blit.dstOffsets[0] = {0, 0, 0};
        blit.dstOffsets[1] = { mipWidth > 1 ? mipWidth / 2 : 1, mipHeight > 1 ? mipHeight / 2 : 1, 1 };
        blit.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        blit.dstSubresource.mipLevel = i;
        blit.dstSubresource.baseArrayLayer = 0;
        blit.dstSubresource.layerCount = 1;

        vkCmdBlitImage(commandBuffer, texture.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, texture.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &blit, VK_FILTER_LINEAR);

        barrier.subresourceRange.baseMipLevel = i - 1;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

        vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

        if (mipWidth > 1) mipWidth /= 2;
        if (mipHeight > 1) mipHeight /= 2;
    }

    // Transition the last mip level to SHADER_READ_ONLY_OPTIMAL
    barrier.subresourceRange.baseMipLevel = mipLevels - 1;
    barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;

    vkCmdPipelineBarrier(commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);

    EndSingleTimeCommands(commandBuffer);
}

GpuBuffer UmbriferaApp::CreateBuffer(size_t size, bool storage) {
    GpuBuffer buf;
    buf.size = size;

    VkBufferCreateInfo bufferInfo{};
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    if (storage) bufferInfo.usage |= VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    if (vkCreateBuffer(m_Device, &bufferInfo, m_VulkanAllocator, &buf.buffer) != VK_SUCCESS) {
        return {};
    }

    VkMemoryRequirements memRequirements;
    vkGetBufferMemoryRequirements(m_Device, buf.buffer, &memRequirements);

    VkMemoryAllocateInfo allocInfo{};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memRequirements.size;
    allocInfo.memoryTypeIndex = FindMemoryType(memRequirements.memoryTypeBits, VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    if (vkAllocateMemory(m_Device, &allocInfo, m_VulkanAllocator, &buf.memory) != VK_SUCCESS) {
        return {};
    }

    vkBindBufferMemory(m_Device, buf.buffer, buf.memory, 0);

    return buf;
}

void UmbriferaApp::UpdateBuffer(GpuBuffer& buffer, const void* data, size_t size) {
    void* mapped;
    vkMapMemory(m_Device, buffer.memory, 0, size, 0, &mapped);
    memcpy(mapped, data, size);
    vkUnmapMemory(m_Device, buffer.memory);
}

void* UmbriferaApp::GetBufferContents(GpuBuffer& buffer) {
    void* mapped;
    vkMapMemory(m_Device, buffer.memory, 0, buffer.size, 0, &mapped);
    return mapped;
}

void UmbriferaApp::LoadLogo(const std::string& path) {
    printf("Loading logo: %s\n", path.c_str());
    int w, h, n;
    unsigned char* data = stbi_load(path.c_str(), &w, &h, &n, 4);
    if (data) {
        printf("Logo loaded: %dx%d\n", w, h);
        m_LogoTexture = CreateTexture(w, h, GpuPixelFormat::RGBA8Unorm, false, false);
        UpdateTexture(m_LogoTexture, data, w * 4);
        stbi_image_free(data);
    } else {
        fprintf(stderr, "Failed to load logo: %s\n", path.c_str());
    }
}

GpuTexture UmbriferaApp::LoadAssetTexture(const std::string& path) {
    printf("Loading asset: %s\n", path.c_str());
    int w, h, n;
    unsigned char* data = stbi_load(path.c_str(), &w, &h, &n, 4);
    if (data) {
        printf("Asset loaded: %dx%d\n", w, h);
        GpuTexture tex = CreateTexture(w, h, GpuPixelFormat::RGBA8Unorm, false, false);
        UpdateTexture(tex, data, w * 4);
        stbi_image_free(data);
        return tex;
    } else {
        fprintf(stderr, "Failed to load asset: %s\n", path.c_str());
        return {};
    }
}

#endif
