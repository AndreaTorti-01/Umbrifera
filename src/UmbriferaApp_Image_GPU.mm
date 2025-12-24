#include "UmbriferaApp.h"
#include <Metal/Metal.h>
#include <iostream>
#include <cmath>

void UmbriferaApp::ProcessImage() {
    if (!m_RawTexture || !m_ProcessedTexture) return;

    id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
    
    if (m_GrainNeedsRegeneration && m_GrainPSO) {
        NSUInteger grainW = m_ProcessedTexture.width;
        NSUInteger grainH = m_ProcessedTexture.height;
        
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

    MTLRenderPassDescriptor* rpd = [MTLRenderPassDescriptor renderPassDescriptor];
    rpd.colorAttachments[0].texture = m_ProcessedTexture;
    rpd.colorAttachments[0].loadAction = MTLLoadActionClear;
    rpd.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    rpd.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLRenderCommandEncoder> re = [cb renderCommandEncoderWithDescriptor:rpd];
    
    MTLViewport viewport = {
        0.0, 0.0, 
        (double)m_ProcessedTexture.width, (double)m_ProcessedTexture.height, 
        0.0, 1.0
    };
    [re setViewport:viewport];
    
    [re setRenderPipelineState:m_RenderPSO];
    
    if (m_CompareMode) {
        Uniforms defaultUniforms = GetDefaultUniforms();
        [re setFragmentBytes:&defaultUniforms length:sizeof(Uniforms) atIndex:0];
    } else {
        [re setFragmentBytes:&m_Uniforms length:sizeof(Uniforms) atIndex:0];
    }
    
    [re setFragmentTexture:m_RawTexture atIndex:0];
    [re setFragmentTexture:m_GrainTexture atIndex:1];
    [re drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    [re endEncoding];
    
    id<MTLBlitCommandEncoder> mipBlit = [cb blitCommandEncoder];
    [mipBlit generateMipmapsForTexture:m_ProcessedTexture];
    [mipBlit endEncoding];
    
    if (m_HistogramPSO && m_HistogramBuffer) {
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        [blit fillBuffer:m_HistogramBuffer range:NSMakeRange(0, 256 * sizeof(uint32_t)) value:0];
        [blit endEncoding];
        
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
        
        if (m_HistogramBufferDisplay) {
            id<MTLBlitCommandEncoder> blitHist = [cb blitCommandEncoder];
            [blitHist copyFromBuffer:m_HistogramBuffer sourceOffset:0 
                            toBuffer:m_HistogramBufferDisplay destinationOffset:0 
                                size:256 * sizeof(uint32_t)];
            [blitHist endEncoding];
        }
    }

    m_HistogramProcessingComplete = false;
    
    [cb addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull) {
        std::swap(this->m_HistogramBuffer, this->m_HistogramBufferDisplay);
        this->m_HistogramProcessingComplete = true;
    }];

    [cb commit];
}

void UmbriferaApp::PushUndoState() {
    if (!m_RawTexture) return;
    
    NSUInteger width = m_RawTexture.width;
    NSUInteger height = m_RawTexture.height;
    NSUInteger bytesPerRow = width * 4 * sizeof(uint16_t);
    
    UndoState state;
    state.width = (int)width;
    state.height = (int)height;
    state.textureData.resize(width * height * 4);
    
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [m_RawTexture getBytes:state.textureData.data() bytesPerRow:bytesPerRow fromRegion:region mipmapLevel:0];
    
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
    
    MTLTextureDescriptor* rawDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm 
        width:width height:height mipmapped:YES];
    NSUInteger maxDim = (width > height) ? width : height;
    NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
    rawDesc.mipmapLevelCount = mipLevels;
    rawDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> newRawTexture = [m_Device newTextureWithDescriptor:rawDesc];
    
    if (!newRawTexture) return;
    
    NSUInteger bytesPerRow = width * 4 * sizeof(uint16_t);
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    [newRawTexture replaceRegion:region mipmapLevel:0 withBytes:state.textureData.data() bytesPerRow:bytesPerRow];
    
    id<MTLCommandBuffer> cb = [m_CommandQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
    [blit generateMipmapsForTexture:newRawTexture];
    [blit endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    
    m_RawTexture = newRawTexture;
    
    MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm 
        width:width height:height mipmapped:YES];
    targetDesc.mipmapLevelCount = mipLevels;
    targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
    
    m_GrainNeedsRegeneration = true;
    
    m_ViewZoom = 1.0f;
    m_ViewOffset[0] = 0.0f;
    m_ViewOffset[1] = 0.0f;
    m_RotationAngle = 0;
    
    m_ImageDirty = true;
    m_RawHistogramDirty = true;
}
