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
    m_MetalLayer.displaySyncEnabled = YES; // VSync
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

void UmbriferaApp::ProcessImage() {
    if (!m_RawTexture || !m_ProcessedTexture) return;

    // Swap Histogram Buffers
    // The buffer we just displayed becomes the new write target
    // The buffer we just wrote to becomes the new display source
    std::swap(m_HistogramBuffer, m_HistogramBufferDisplay);

    // Create a command buffer for GPU commands
    id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
    
    // --- Pass 0: Generate Grain Texture (if needed) ---
    if (m_GrainNeedsRegeneration && m_GrainPSO) {
        // Create grain texture matching image dimensions
        NSUInteger grainW = m_ProcessedTexture.width;
        NSUInteger grainH = m_ProcessedTexture.height;
        
        // Create or recreate grain texture if size changed
        if (!m_GrainTexture || 
            m_GrainTexture.width != grainW || 
            m_GrainTexture.height != grainH) {
            
            MTLTextureDescriptor* grainDesc = [MTLTextureDescriptor 
                texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float 
                width:grainW 
                height:grainH 
                mipmapped:NO];
            grainDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
            grainDesc.storageMode = MTLStorageModePrivate;
            m_GrainTexture = [m_Device newTextureWithDescriptor:grainDesc];
        }
        
        // Generate grain pattern
        struct GrainParams {
            uint32_t width;
            uint32_t height;
            float grainSize;
            float seed;
        };
        
        GrainParams grainParams;
        grainParams.width = (uint32_t)grainW;
        grainParams.height = (uint32_t)grainH;
        grainParams.grainSize = m_Uniforms.grain_size;
        // Use a fixed random seed for consistent grain pattern
        grainParams.seed = 42.0f;
        
        id<MTLComputeCommandEncoder> grainEncoder = [cb computeCommandEncoder];
        [grainEncoder setComputePipelineState:m_GrainPSO];
        [grainEncoder setTexture:m_GrainTexture atIndex:0];
        [grainEncoder setBytes:&grainParams length:sizeof(GrainParams) atIndex:0];
        
        MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
        MTLSize threadgroups = MTLSizeMake((grainW + 15) / 16, (grainH + 15) / 16, 1);
        [grainEncoder dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
        [grainEncoder endEncoding];
        
        m_GrainNeedsRegeneration = false;
    }

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
    
    // Use default uniforms when in comparison mode, otherwise use current settings
    if (m_CompareMode) {
        Uniforms defaultUniforms = GetDefaultUniforms();
        [re setFragmentBytes:&defaultUniforms length:sizeof(Uniforms) atIndex:0];
    } else {
        [re setFragmentBytes:&m_Uniforms length:sizeof(Uniforms) atIndex:0];
    }
    
    [re setFragmentTexture:m_RawTexture atIndex:0];
    [re setFragmentTexture:m_GrainTexture atIndex:1];  // Pre-computed grain texture
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
        
        // Handle pending crop operation (deferred from previous frame to avoid texture-in-use)
        if (m_CropPending && m_RawTexture && m_Device && m_CommandQueue) {
            m_CropPending = false;
            
            NSUInteger texW = m_RawTexture.width;
            NSUInteger texH = m_RawTexture.height;
            
            // Transform crop coordinates based on rotation
            float rawCropRect[4]; // left, top, right, bottom in raw texture coords
            
            switch (m_PendingCropRotation) {
                case 0:
                default:
                    rawCropRect[0] = m_PendingCropRect[0];
                    rawCropRect[1] = m_PendingCropRect[1];
                    rawCropRect[2] = m_PendingCropRect[2];
                    rawCropRect[3] = m_PendingCropRect[3];
                    break;
                case 90:
                    // 90° CW: view(x,y) -> raw(y, 1-x)
                    rawCropRect[0] = m_PendingCropRect[1];
                    rawCropRect[1] = 1.0f - m_PendingCropRect[2];
                    rawCropRect[2] = m_PendingCropRect[3];
                    rawCropRect[3] = 1.0f - m_PendingCropRect[0];
                    break;
                case 180:
                    // 180°: view(x,y) -> raw(1-x, 1-y)
                    rawCropRect[0] = 1.0f - m_PendingCropRect[2];
                    rawCropRect[1] = 1.0f - m_PendingCropRect[3];
                    rawCropRect[2] = 1.0f - m_PendingCropRect[0];
                    rawCropRect[3] = 1.0f - m_PendingCropRect[1];
                    break;
                case 270:
                    // 270° CW (90° CCW): view(x,y) -> raw(1-y, x)
                    rawCropRect[0] = 1.0f - m_PendingCropRect[3];
                    rawCropRect[1] = m_PendingCropRect[0];
                    rawCropRect[2] = 1.0f - m_PendingCropRect[1];
                    rawCropRect[3] = m_PendingCropRect[2];
                    break;
            }
            
            // Ensure rawCropRect is properly ordered (left < right, top < bottom)
            if (rawCropRect[0] > rawCropRect[2]) {
                float tmp = rawCropRect[0];
                rawCropRect[0] = rawCropRect[2];
                rawCropRect[2] = tmp;
            }
            if (rawCropRect[1] > rawCropRect[3]) {
                float tmp = rawCropRect[1];
                rawCropRect[1] = rawCropRect[3];
                rawCropRect[3] = tmp;
            }
            
            NSUInteger cropX = (NSUInteger)(rawCropRect[0] * texW);
            NSUInteger cropY = (NSUInteger)(rawCropRect[1] * texH);
            NSUInteger cropW = (NSUInteger)((rawCropRect[2] - rawCropRect[0]) * texW);
            NSUInteger cropH = (NSUInteger)((rawCropRect[3] - rawCropRect[1]) * texH);
            
            // Clamp to texture bounds
            if (cropX >= texW) cropX = texW - 1;
            if (cropY >= texH) cropY = texH - 1;
            if (cropX + cropW > texW) cropW = texW - cropX;
            if (cropY + cropH > texH) cropH = texH - cropY;
            
            // Ensure minimum size
            if (cropW < 1) cropW = 1;
            if (cropH < 1) cropH = 1;
            
            // Create new cropped texture
            MTLTextureDescriptor* newDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm width:cropW height:cropH mipmapped:YES];
            NSUInteger maxDim = (cropW > cropH) ? cropW : cropH;
            NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
            newDesc.mipmapLevelCount = mipLevels;
            newDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
            id<MTLTexture> newRawTexture = [m_Device newTextureWithDescriptor:newDesc];
            
            if (newRawTexture) {
                // Copy cropped region using blit encoder
                id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
                id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
                [blit copyFromTexture:m_RawTexture 
                          sourceSlice:0 
                          sourceLevel:0 
                         sourceOrigin:MTLOriginMake(cropX, cropY, 0) 
                           sourceSize:MTLSizeMake(cropW, cropH, 1) 
                            toTexture:newRawTexture 
                     destinationSlice:0 
                     destinationLevel:0 
                    destinationOrigin:MTLOriginMake(0, 0, 0)];
                [blit generateMipmapsForTexture:newRawTexture];
                [blit endEncoding];
                [cb commit];
                [cb waitUntilCompleted];
                
                // Replace raw texture
                m_RawTexture = newRawTexture;
                
                // Create new processed texture
                MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:cropW height:cropH mipmapped:YES];
                targetDesc.mipmapLevelCount = mipLevels;
                targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
                
                // Regenerate grain for new crop dimensions
                m_GrainNeedsRegeneration = true;
                m_ImageDirty = true;
                m_RawHistogramDirty = true;
            }
        }
        
        // Handle pending rotation operation (deferred from previous frame)
        if (m_RotatePending && m_RawTexture && m_Device && m_CommandQueue && m_RotatePSO) {
            m_RotatePending = false;
            
            float angleRad = m_PendingRotationAngle * (M_PI / 180.0f);
            float cosA = cosf(angleRad);
            float sinA = sinf(angleRad);
            
            NSUInteger srcW = m_RawTexture.width;
            NSUInteger srcH = m_RawTexture.height;
            float imgAspect = (float)srcW / (float)srcH;
            
            // Calculate scale factor for the largest inscribed rectangle
            // When rotating a W×H rectangle by θ, the largest axis-aligned rectangle
            // with the same aspect ratio that fits inside has dimensions W/s × H/s where
            // s = max(|cos θ| + |sin θ|/aspect, |cos θ| + |sin θ|*aspect)
            float scaleFactorW = fabsf(cosA) + fabsf(sinA) / imgAspect;
            float scaleFactorH = fabsf(cosA) + fabsf(sinA) * imgAspect;
            float inscribedScale = fmaxf(scaleFactorW, scaleFactorH);
            if (inscribedScale < 1.0f) inscribedScale = 1.0f;
            
            // Output texture is smaller - the largest inscribed rectangle
            NSUInteger dstW = (NSUInteger)((float)srcW / inscribedScale);
            NSUInteger dstH = (NSUInteger)((float)srcH / inscribedScale);
            
            // Create new rotated texture
            MTLTextureDescriptor* newDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm width:dstW height:dstH mipmapped:YES];
            NSUInteger maxDim = (dstW > dstH) ? dstW : dstH;
            NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
            newDesc.mipmapLevelCount = mipLevels;
            newDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
            id<MTLTexture> newRawTexture = [m_Device newTextureWithDescriptor:newDesc];
            
            if (newRawTexture) {
                // Create parameter buffer
                struct RotateParams {
                    float cosAngle;
                    float sinAngle;
                    float scale;
                    uint32_t srcWidth;
                    uint32_t srcHeight;
                };
                RotateParams params;
                params.cosAngle = cosA;
                params.sinAngle = sinA;
                params.scale = 1.0f; // No scaling - we're extracting the inscribed rectangle
                params.srcWidth = (uint32_t)srcW;
                params.srcHeight = (uint32_t)srcH;
                
                id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
                id<MTLComputeCommandEncoder> ce = [cb computeCommandEncoder];
                [ce setComputePipelineState:m_RotatePSO];
                [ce setTexture:m_RawTexture atIndex:0];
                [ce setTexture:newRawTexture atIndex:1];
                [ce setBytes:&params length:sizeof(params) atIndex:0];
                
                MTLSize threadsPerThreadgroup = MTLSizeMake(16, 16, 1);
                MTLSize threadgroups = MTLSizeMake((dstW + 15) / 16, (dstH + 15) / 16, 1);
                [ce dispatchThreadgroups:threadgroups threadsPerThreadgroup:threadsPerThreadgroup];
                [ce endEncoding];
                
                // Generate mipmaps
                id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
                [blit generateMipmapsForTexture:newRawTexture];
                [blit endEncoding];
                
                [cb commit];
                [cb waitUntilCompleted];
                
                // Replace raw texture
                m_RawTexture = newRawTexture;
                
                // Create new processed texture
                MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:dstW height:dstH mipmapped:YES];
                targetDesc.mipmapLevelCount = mipLevels;
                targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
                m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
                
                // Regenerate grain for new rotation dimensions
                m_GrainNeedsRegeneration = true;
                m_ImageDirty = true;
                m_RawHistogramDirty = true;
            }
        }
        
        // Handle pending undo operation (deferred from previous frame)
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

void UmbriferaApp::PushUndoState() {
    if (!m_RawTexture) return;
    
    NSUInteger width = m_RawTexture.width;
    NSUInteger height = m_RawTexture.height;
    NSUInteger bytesPerRow = width * 4 * sizeof(uint16_t); // RGBA16
    
    UndoState state;
    state.width = (int)width;
    state.height = (int)height;
    state.textureData.resize(width * height * 4); // 4 components per pixel
    
    // Read texture data from GPU
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [m_RawTexture getBytes:state.textureData.data() bytesPerRow:bytesPerRow fromRegion:region mipmapLevel:0];
    
    // Add to undo stack, removing oldest if at max capacity
    if (m_UndoStack.size() >= MAX_UNDO_STATES) {
        m_UndoStack.pop_front();
    }
    m_UndoStack.push_back(std::move(state));
}

void UmbriferaApp::Undo() {
    if (m_UndoStack.empty() || !m_Device || !m_CommandQueue) return;
    
    UndoState state = std::move(m_UndoStack.back());
    m_UndoStack.pop_back();
    
    NSUInteger width = state.width;
    NSUInteger height = state.height;
    
    // Create new raw texture
    MTLTextureDescriptor* rawDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm 
        width:width height:height mipmapped:YES];
    NSUInteger maxDim = (width > height) ? width : height;
    NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
    rawDesc.mipmapLevelCount = mipLevels;
    rawDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> newRawTexture = [m_Device newTextureWithDescriptor:rawDesc];
    
    if (!newRawTexture) return;
    
    // Upload texture data
    NSUInteger bytesPerRow = width * 4 * sizeof(uint16_t);
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [newRawTexture replaceRegion:region mipmapLevel:0 withBytes:state.textureData.data() bytesPerRow:bytesPerRow];
    
    // Generate mipmaps
    id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit generateMipmapsForTexture:newRawTexture];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    
    // Replace raw texture
    m_RawTexture = newRawTexture;
    
    // Create new processed texture
    MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm 
        width:width height:height mipmapped:YES];
    targetDesc.mipmapLevelCount = mipLevels;
    targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
    
    // Regenerate grain for new resize dimensions
    m_GrainNeedsRegeneration = true;
    
    // Reset view
    m_ViewZoom = 1.0f;
    m_ViewOffset[0] = 0.0f;
    m_ViewOffset[1] = 0.0f;
    m_RotationAngle = 0;
    
    // Trigger reprocess
    m_ImageDirty = true;
    m_RawHistogramDirty = true;
}
