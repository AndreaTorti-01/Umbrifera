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

// This file handles the Metal (GPU) rendering logic.
// It sets up the graphics pipeline, shaders, and executes the drawing commands.

void UmbriferaApp::InitMetal() {
    // 1. Create the Metal Device (GPU interface)
    m_Device = MTLCreateSystemDefaultDevice();
    m_CommandQueue = [m_Device newCommandQueue];
    
    // 2. Setup the Metal Layer on the Window
    NSWindow *nswin = glfwGetCocoaWindow(m_Window);
    m_MetalLayer = [CAMetalLayer layer];
    m_MetalLayer.device = m_Device;
    m_MetalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm; // Screen format
    nswin.contentView.layer = m_MetalLayer;
    nswin.contentView.wantsLayer = YES;

    m_RenderPassDescriptor = [MTLRenderPassDescriptor new];

    // 3. Create Histogram Buffer (Shared memory between CPU and GPU)
    // Double buffering to prevent reading zeros while GPU clears/writes
    m_HistogramBuffer = [m_Device newBufferWithLength:256 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    // Double buffering to prevent reading zeros while GPU clears/writes
    m_HistogramBuffer = [m_Device newBufferWithLength:256 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    m_HistogramBufferDisplay = [m_Device newBufferWithLength:256 * sizeof(uint32_t) options:MTLResourceStorageModeShared];
    
    // Raw Histogram Buffer (Shared)
    m_RawHistogramBuffer = [m_Device newBufferWithLength:256 * sizeof(uint32_t) options:MTLResourceStorageModeShared];

    // 4. Compile Shaders
    NSError* error = nil;
    
    // Load shader source from file
    // Priority 1: "shaders/Shaders.metal" (Running from project root in Dev)
    NSString* shaderPath = @"shaders/Shaders.metal"; 
    NSString* shaderSource = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:nil];
    
    if (!shaderSource) {
        // Priority 2: "Shaders.metal" (Running from build dir or alongside executable)
        shaderPath = @"Shaders.metal";
        shaderSource = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];
    }
    
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
}

void UmbriferaApp::CleanupMetal() {
    ImGui_ImplMetal_Shutdown();
}

void UmbriferaApp::ProcessImage() {
    if (!m_RawTexture || !m_ProcessedTexture) return;

    // Swap Histogram Buffers
    // The buffer we just displayed becomes the new write target
    // The buffer we just wrote to becomes the new display source
    std::swap(m_HistogramBuffer, m_HistogramBufferDisplay);

    // Create a command buffer for GPU commands
    id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];

    // --- Pass 1: Image Processing (Render to Texture) ---
    // We render the raw texture into the processed texture, applying exposure/color shaders.
    MTLRenderPassDescriptor* rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = m_ProcessedTexture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> re = [cb renderCommandEncoderWithDescriptor:rpd];
    
    // Set Viewport to match the texture size
    // This is critical! If we don't set this, Metal might use a default viewport (e.g. window size)
    // which would result in only a corner of the image being rendered into the texture.
    MTLViewport viewport = {
        0.0, 0.0, 
        (double)m_ProcessedTexture.width, (double)m_ProcessedTexture.height, 
        0.0, 1.0
    };
    [re setViewport:viewport];
    
    [re setRenderPipelineState:m_RenderPSO];
    [re setFragmentBytes:&m_Uniforms length:sizeof(Uniforms) atIndex:0];
    [re setFragmentTexture:m_RawTexture atIndex:0];
    [re drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [re endEncoding];
    
    // --- Pass 1.5: Generate Mipmaps ---
    // This ensures high-quality downsampling when zoomed out.
    id<MTLBlitCommandEncoder> mipBlit = [cb blitCommandEncoder];
    [mipBlit generateMipmapsForTexture:m_ProcessedTexture];
    [mipBlit endEncoding];
    
    // --- Pass 2: Compute Histogram ---
    if (m_HistogramPSO && m_HistogramBuffer) {
        // Clear Histogram Buffer first
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        [blit fillBuffer:m_HistogramBuffer range:NSMakeRange(0, 256 * sizeof(uint32_t)) value:0];
        [blit endEncoding];
        
        // Run Compute Shader
        id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
        [ce setComputePipelineState:m_HistogramPSO];
        [ce setTexture:m_ProcessedTexture atIndex:0];
        [ce setBuffer:m_HistogramBuffer offset:0 atIndex:0];
        
        NSUInteger w = m_ProcessedTexture.width;
        NSUInteger h = m_ProcessedTexture.height;
        MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
        MTLSize threadgroups = MTLSizeMake((w + 15) / 16, (h + 15) / 16, 1);
        
        [ce dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        [ce endEncoding];
        
        // --- Pass 3: Blit Histogram to Display Buffer ---
        // This ensures the UI reads a stable, fully computed histogram from the previous frame (or this frame, synchronized)
        // Since we use StorageModeShared, the CPU can read this buffer directly.
        // We copy from the working buffer (m_HistogramBuffer) to the display buffer (m_HistogramBufferDisplay).
        if (m_HistogramBufferDisplay) {
            id<MTLBlitCommandEncoder> blitHist = [cb blitCommandEncoder];
            [blitHist copyFromBuffer:m_HistogramBuffer sourceOffset:0 
                            toBuffer:m_HistogramBufferDisplay destinationOffset:0 
                                size:256 * sizeof(uint32_t)];
            [blitHist endEncoding];
        }
    }

    [cb commit];
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
            // Bytes per row = Width * 4 channels * 2 bytes (16-bit)
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
            
            // Set the base exposure calculated by the loader
            m_Uniforms.base_exposure = m_InitialExposure;
            
            // Initial Process
            m_ImageDirty = true;
            
            // Compute Raw Histogram immediately for Auto Adjust
            if (m_HistogramPSO && m_RawHistogramBuffer && m_RawTexture) {
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
            }
        }
        
        UpdateUniforms();
        
        // Only process image (apply exposure + compute histogram) if something changed
        if (m_ImageDirty) {
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
