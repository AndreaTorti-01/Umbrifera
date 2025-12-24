#include "UmbriferaApp.h"
#include <Metal/Metal.h>
#include <cmath>

void UmbriferaApp::HandlePendingCrop() {
    if (!m_CropPending || !m_RawTexture || !m_Device || !m_CommandQueue) return;
    m_CropPending = false;
    
    NSUInteger texW = m_RawTexture.width;
    NSUInteger texH = m_RawTexture.height;
    
    float rawCropRect[4];
    
    switch (m_PendingCropRotation) {
        case 0:
        default:
            rawCropRect[0] = m_PendingCropRect[0];
            rawCropRect[1] = m_PendingCropRect[1];
            rawCropRect[2] = m_PendingCropRect[2];
            rawCropRect[3] = m_PendingCropRect[3];
            break;
        case 90:
            rawCropRect[0] = m_PendingCropRect[1];
            rawCropRect[1] = 1.0f - m_PendingCropRect[2];
            rawCropRect[2] = m_PendingCropRect[3];
            rawCropRect[3] = 1.0f - m_PendingCropRect[0];
            break;
        case 180:
            rawCropRect[0] = 1.0f - m_PendingCropRect[2];
            rawCropRect[1] = 1.0f - m_PendingCropRect[3];
            rawCropRect[2] = 1.0f - m_PendingCropRect[0];
            rawCropRect[3] = 1.0f - m_PendingCropRect[1];
            break;
        case 270:
            rawCropRect[0] = 1.0f - m_PendingCropRect[3];
            rawCropRect[1] = m_PendingCropRect[0];
            rawCropRect[2] = 1.0f - m_PendingCropRect[1];
            rawCropRect[3] = m_PendingCropRect[2];
            break;
    }
    
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
    
    if (cropX >= texW) cropX = texW - 1;
    if (cropY >= texH) cropY = texH - 1;
    if (cropX + cropW > texW) cropW = texW - cropX;
    if (cropY + cropH > texH) cropH = texH - cropY;
    
    if (cropW < 1) cropW = 1;
    if (cropH < 1) cropH = 1;
    
    MTLTextureDescriptor* newDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm width:cropW height:cropH mipmapped:YES];
    NSUInteger maxDim = (cropW > cropH) ? cropW : cropH;
    NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
    newDesc.mipmapLevelCount = mipLevels;
    newDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> newRawTexture = [m_Device newTextureWithDescriptor:newDesc];
    
    if (newRawTexture) {
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
        
        m_RawTexture = newRawTexture;
        
        MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:cropW height:cropH mipmapped:YES];
        targetDesc.mipmapLevelCount = mipLevels;
        targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
        
        m_GrainNeedsRegeneration = true;
        m_ImageDirty = true;
        m_RawHistogramDirty = true;
    }
}

void UmbriferaApp::HandlePendingRotation() {
    if (!m_RotatePending || !m_RawTexture || !m_Device || !m_CommandQueue || !m_RotatePSO) return;
    m_RotatePending = false;
    
    float angleRad = m_PendingRotationAngle * (M_PI / 180.0f);
    float cosA = cosf(angleRad);
    float sinA = sinf(angleRad);
    
    NSUInteger srcW = m_RawTexture.width;
    NSUInteger srcH = m_RawTexture.height;
    float imgAspect = (float)srcW / (float)srcH;
    
    float scaleFactorW = fabsf(cosA) + fabsf(sinA) / imgAspect;
    float scaleFactorH = fabsf(cosA) + fabsf(sinA) * imgAspect;
    float inscribedScale = fmaxf(scaleFactorW, scaleFactorH);
    if (inscribedScale < 1.0f) inscribedScale = 1.0f;
    
    NSUInteger dstW = (NSUInteger)((float)srcW / inscribedScale);
    NSUInteger dstH = (NSUInteger)((float)srcH / inscribedScale);
    
    MTLTextureDescriptor* newDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Unorm width:dstW height:dstH mipmapped:YES];
    NSUInteger maxDim = (dstW > dstH) ? dstW : dstH;
    NSUInteger mipLevels = 1 + (NSUInteger)floor(log2((double)maxDim));
    newDesc.mipmapLevelCount = mipLevels;
    newDesc.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    id<MTLTexture> newRawTexture = [m_Device newTextureWithDescriptor:newDesc];
    
    if (newRawTexture) {
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
        params.scale = 1.0f;
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
        
        id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
        [blit generateMipmapsForTexture:newRawTexture];
        [blit endEncoding];
        
        [cb commit];
        [cb waitUntilCompleted];
        
        m_RawTexture = newRawTexture;
        
        MTLTextureDescriptor* targetDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:dstW height:dstH mipmapped:YES];
        targetDesc.mipmapLevelCount = mipLevels;
        targetDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        m_ProcessedTexture = [m_Device newTextureWithDescriptor:targetDesc];
        
        m_GrainNeedsRegeneration = true;
        m_ImageDirty = true;
        m_RawHistogramDirty = true;
    }
}
