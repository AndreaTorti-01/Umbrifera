#include "UmbriferaApp.h"
#include "imgui.h"
#include "imgui_impl_glfw.h"

#define GLFW_EXPOSE_NATIVE_COCOA
#include "imgui_impl_metal.h"
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>
#include <Cocoa/Cocoa.h>
#include <iostream>
#include <cmath>

void UmbriferaApp::InitMetal() {
    // 1. Create the Metal Device (GPU interface)
    m_Device = MTLCreateSystemDefaultDevice();
    m_CommandQueue = [m_Device newCommandQueue];
    
    // 2. Setup the Metal Layer on the Window
    NSWindow *nswin = glfwGetCocoaWindow(m_Window);
    m_MetalLayer = [CAMetalLayer layer];
    m_MetalLayer.device = m_Device;
    m_MetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm; // Screen format
    m_MetalLayer.displaySyncEnabled = YES; // VSync
    nswin.contentView.layer = m_MetalLayer;
    nswin.contentView.wantsLayer = YES;

    m_RenderPassDescriptor = [MTLRenderPassDescriptor new];

    m_HistogramBuffer = [m_Device newBufferWithLength:256 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    m_HistogramBufferDisplay = [m_Device newBufferWithLength:256 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    
    // Raw Histogram Buffer (Shared)
    m_RawHistogramBuffer = [m_Device newBufferWithLength:256 * sizeof(uint32_t) options:MTLResourceStorageModeShared];

    NSError* error = nil;
    
    // Load shader from bundle Resources
    NSBundle* bundle = [NSBundle mainBundle];
    NSString* shaderPath = [bundle pathForResource:@"Shaders" ofType:@"metal"];
    
    if (!shaderPath) {
        NSLog(@"Error: Could not find Shaders.metal in bundle resources");
        return;
    }
    
    NSString* shaderSource = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];
    if (!shaderSource) {
        NSLog(@"Error loading shader source: %@", error);
        return;
    }

    id<MTLLibrary> library = [m_Device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"Error compiling shader: %@", error);
        return;
    }
    
    id<MTLFunction> vertexFunction = [library newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunction = [library newFunctionWithName:@"fragment_main"];
    id<MTLFunction> histogramFunction = [library newFunctionWithName:@"histogram_main"];
    id<MTLFunction> boxDownscaleFunction = [library newFunctionWithName:@"box_downscale"];
    id<MTLFunction> rotateFunction = [library newFunctionWithName:@"rotate_kernel"];
    id<MTLFunction> grainFunction = [library newFunctionWithName:@"generate_grain"];

    // 5. Create Render Pipeline State (for drawing the image)
    MTLRenderPipelineDescriptor* pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunction;
    pipelineDescriptor.fragmentFunction = fragmentFunction;
    // The output format of our processing pass (Intermediate texture)
    pipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm; 

    m_RenderPSO = [m_Device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (!m_RenderPSO) {
        NSLog(@"Error creating pipeline state: %@", error);
        return;
    }
    
    // 6. Create Compute Pipeline State (for histogram)
    m_HistogramPSO = [m_Device newComputePipelineStateWithFunction:histogramFunction error:&error];
    if (!m_HistogramPSO) {
        NSLog(@"Error creating compute pipeline state: %@", error);
        return;
    }
    
    // 7. Create Compute Pipeline State (for box filter downscaling)
    m_Lanczos3PSO = [m_Device newComputePipelineStateWithFunction:boxDownscaleFunction error:&error];
    if (!m_Lanczos3PSO) {
        NSLog(@"Error creating box downscale pipeline state: %@", error);
        return;
    }
    
    // 8. Create Compute Pipeline State (for rotation)
    m_RotatePSO = [m_Device newComputePipelineStateWithFunction:rotateFunction error:&error];
    if (!m_RotatePSO) {
        NSLog(@"Error creating rotate pipeline state: %@", error);
        return;
    }
    
    // 9. Create Compute Pipeline State (for film grain generation)
    m_GrainPSO = [m_Device newComputePipelineStateWithFunction:grainFunction error:&error];
    if (!m_GrainPSO) {
        NSLog(@"Error creating grain pipeline state: %@", error);
        return;
    }
}

void UmbriferaApp::CleanupMetal() {
    ImGui_ImplMetal_Shutdown();
}

void UmbriferaApp::RenderFrame() {
    @autoreleasepool {
        // 1. Check if a new image has been loaded in the background thread
        if (m_TextureUploadPending) {
            std::lock_guard<std::mutex> lock(m_LoadingMutex);
            
            // Create Metal Texture for Raw Data (16-bit RGBA)
            // MTLPixelFormatRGBA16Unorm: 16-bit per channel, normalized 0.0-1.0
            // Enable mipmaps for Clarity/Texture local contrast processing
            MTLTextureDescriptor* textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm width:m_PendingWidth height:m_PendingHeight mipmapped:YES];
            
            // Calculate mipmap levels for raw texture
            NSUInteger rawMaxDim = (m_PendingWidth > m_PendingHeight) ? m_PendingWidth : m_PendingHeight;
            NSUInteger rawMipLevels = 1 + (NSUInteger)floor(log2((double)rawMaxDim));
            textureDescriptor.mipmapLevelCount = rawMipLevels;
            textureDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
            m_RawTexture = [m_Device newTextureWithDescriptor:textureDescriptor];
            
            // Upload data to GPU
            MTLRegion region = MTLRegionMake2D(0, 0, m_PendingWidth, m_PendingHeight);
            [m_RawTexture replaceRegion:region mipmapLevel:0 withBytes:m_PendingTextureData16.data() bytesPerRow:m_PendingWidth * 8];
            
            // Generate mipmaps for raw texture (needed for Clarity/Texture)
            id<MTLCommandBuffer> mipCB = [m_CommandQueue commandBuffer];
            id<MTLBlitCommandEncoder> mipBlit = [mipCB blitCommandEncoder];
            [mipBlit generateMipmapsForTexture:m_RawTexture];
            [mipBlit endEncoding];
            [mipCB commit];
            [mipCB waitUntilCompleted];
            
            // Create Processed Texture (Render Target)
            // This is what we display on screen.
            MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:m_PendingWidth height:m_PendingHeight mipmapped:YES];
            
            // Calculate mipmap levels: floor(log2(max(w, h))) + 1
            NSUInteger maxDim = (m_PendingWidth > m_PendingHeight) ? m_PendingWidth : m_PendingHeight;
            NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
            targetDesc.mipmapLevelCount = mipLevels;
            
            targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
            m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
            
            // Create a sampler state for linear filtering
            // This ensures smooth image display when zooming/resizing
            MTLSamplerDescriptor* samplerDesc = [[MTLSamplerDescriptor alloc] init];
            samplerDesc.minFilter = MTLSamplerMinMagFilterLinear;
            samplerDesc.magFilter = MTLSamplerMinMagFilterLinear;
            samplerDesc.mipFilter = MTLSamplerMipFilterLinear;
            samplerDesc.sAddressMode = MTLSamplerAddressModeClampToEdge;
            samplerDesc.tAddressMode = MTLSamplerAddressModeClampToEdge;
            m_TextureSampler = [m_Device newSamplerStateWithDescriptor:samplerDesc];
            
            // Clear CPU memory
            m_PendingTextureData16.clear();
            m_TextureUploadPending = false;
            m_IsLoading = false;
            
            // Reset view state for new image
            m_ViewZoom = 1.0f;
            m_ViewOffset[0] = 0.0f;
            m_ViewOffset[1] = 0.0f;
            m_RotationAngle = 0;
            
            // Set the base exposure calculated by the loader
            m_Uniforms.base_exposure = m_InitialExposure;
            
            // Regenerate grain texture for new image dimensions
            m_GrainNeedsRegeneration = true;
            
            // Initial Process
            m_ImageDirty = true;
            m_RawHistogramDirty = true;
        }
        
        if (m_CropPending) {
            HandlePendingCrop();
        }
        
        if (m_RotatePending) {
            HandlePendingRotation();
        }
        
        if (m_UndoPending) {
            m_UndoPending = false;
            Undo();
        }
            
        // Compute Raw Histogram only when raw texture changes (for Auto Adjust)
        if (m_RawHistogramDirty && m_HistogramPSO && m_RawHistogramBuffer && m_RawTexture) {
            id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
            
            // Clear Buffer
            id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
            [blit fillBuffer:m_RawHistogramBuffer range:NSMakeRange(0, 256 * sizeof(uint32_t)) value:0];
            [blit endEncoding];
            
            // Compute
            id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
            [ce setComputePipelineState:m_HistogramPSO];
            [ce setTexture:m_RawTexture atIndex:0]; // Use Raw Texture
            [ce setBuffer:m_RawHistogramBuffer offset:0 atIndex:0];
            
            NSUInteger w = m_RawTexture.width;
            NSUInteger h = m_RawTexture.height;
            MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
            MTLSize threadgroups = MTLSizeMake((w + 15) / 16, (h + 15) / 16, 1);
            
            [ce dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
            [ce endEncoding];
            
            [cb commit];
            [cb waitUntilCompleted]; // Wait so we can read it immediately
            
            // Read back to CPU vector
            uint32_t* ptr = (uint32_t*)[m_RawHistogramBuffer contents];
            m_RawHistogram.assign(ptr, ptr + 256);
            
            m_RawHistogramDirty = false;
        }
        
        UpdateUniforms();
        
        // Only process image (apply exposure + compute histogram) if something changed
        // AND the previous processing has completed
        if (m_ImageDirty && m_HistogramProcessingComplete) {
            ProcessImage();
            m_ImageDirty = false;
        }
        
        // 2. Prepare Screen Render Pass
        int width, height;
        glfwGetFramebufferSize(m_Window, &width, &height);
        m_MetalLayer.drawableSize = CGSizeMake(width, height);
        id<CAMetalDrawable> drawable = [m_MetalLayer nextDrawable];
        
        id<MTLCommandBuffer> commandBuffer = [m_CommandQueue commandBuffer];
        
        m_RenderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(m_ClearColor[0], m_ClearColor[1], m_ClearColor[2], m_ClearColor[3]);
        m_RenderPassDescriptor.colorAttachments[0].texture = drawable.texture;
        m_RenderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        m_RenderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        // 3. Render ImGui (UI)
        id <MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:m_RenderPassDescriptor];
        [renderEncoder pushDebugGroup:@"ImGui"];

        ImGui_ImplMetal_NewFrame(m_RenderPassDescriptor);
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();
        
        SetupLayout();
        RenderUI();
        
        ImGui::Render();
        ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, renderEncoder);

        if (ImGui::GetIO().ConfigFlags & ImGuiConfigFlags_ViewportsEnable) {
            ImGui::UpdatePlatformWindows();
            ImGui::RenderPlatformWindowsDefault();
        }

        [renderEncoder popDebugGroup];
        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
}
