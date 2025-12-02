#include "UmbriferaApp.h"
#include <iostream>
#include <fstream>
#include <vector>
#include <GLFW/glfw3.h> // Needed for glfwPostEmptyEvent



// We use LibRaw to decode raw images (NEF, CR2, ARW, etc.)
// LibRaw is a C++ library that handles the complex task of parsing raw file formats.
void UmbriferaApp::LoadRawImage(const std::string& path) {
    // If we are already loading an image, don't start another load.
    if (m_IsLoading) return;
    m_IsLoading = true;
    
    // Clear undo stack when loading a new image
    m_UndoStack.clear();
    
    // We run the loading process in a separate thread (background task)
    // so that the main application window doesn't freeze while loading.
    m_LoadingThread = std::thread([this, path]() {
        try {
            std::cout << "Loading image: " << path << std::endl;
            
            // Store the loaded image path for default export filename
            m_LoadedImagePath = path;
            
            // Create a new LibRaw processor instance on the heap.
            // We use std::make_unique to manage memory automatically.
            // This object is large, so putting it on the heap prevents stack overflow.
            auto RawProcessor = std::make_unique<LibRaw>();
            
            std::string finalPath = path;
            std::ifstream checkFile(finalPath);
            if (!checkFile.good()) {
                // If file not found in current dir, try parent dir (common in build folders)
                finalPath = "../" + path;
            }
            
            // 1. Open the file
            if (RawProcessor->open_file(finalPath.c_str()) != LIBRAW_SUCCESS) {
                std::cerr << "Failed to open file: " << finalPath << std::endl;
                m_IsLoading = false;
                return;
            }

            // 2. Unpack the raw data (decompress it)
            if (RawProcessor->unpack() != LIBRAW_SUCCESS) {
                std::cerr << "Failed to unpack file: " << path << std::endl;
                m_IsLoading = false;
                return;
            }

            // 3. Configure processing parameters for "Linear" output
            // We want the rawest possible data to do our own color management.
            // output_bps = 16: We want 16-bit data for high precision (better than 8-bit JPEG).
            RawProcessor->imgdata.params.output_bps = 16;
            
            // user_qual = 11: Use DHT (Damped Hybrid Transform) demosaicing.
            // DHT produces the highest quality results with minimal artifacts.
            RawProcessor->imgdata.params.user_qual = 11;
            
            // no_auto_bright = 1: Don't automatically brighten the image. We want control.
            RawProcessor->imgdata.params.no_auto_bright = 1;
            
            // gamm[0] = 1.0, gamm[1] = 1.0: Set Gamma to 1.0 (Linear). 
            // This means no gamma correction is applied by LibRaw.
            // We will apply gamma correction ourselves in the shader later.
            RawProcessor->imgdata.params.gamm[0] = 1.0;
            RawProcessor->imgdata.params.gamm[1] = 1.0;
            
            // use_camera_wb = 1: Use the White Balance settings from the camera.
            RawProcessor->imgdata.params.use_camera_wb = 1;

            // output_color = 1: sRGB. Since we set gamma to 1.0, this gives us Linear sRGB.
            // This ensures consistent color space.
            RawProcessor->imgdata.params.output_color = 1;

            // 4. Process the raw data into an image
            if (RawProcessor->dcraw_process() != LIBRAW_SUCCESS) {
                std::cerr << "Failed to process file: " << path << std::endl;
                m_IsLoading = false;
                return;
            }

            // 5. Create a memory image from the processed data
            libraw_processed_image_t* image = RawProcessor->dcraw_make_mem_image();
            if (!image) {
                std::cerr << "Failed to make memory image" << std::endl;
                m_IsLoading = false;
                return;
            }

            // 6. Convert the LibRaw image (RGB 16-bit) to our format (RGBA 16-bit)
            // We add an Alpha channel (A) set to full opacity.
            int width = image->width;
            int height = image->height;
            std::cout << "Image decoded: " << width << "x" << height << " (16-bit Linear)" << std::endl;
            
            // Get the white level and black level
            // Use linear_max if available (more accurate for some cameras), else maximum
            float white_level = (float)RawProcessor->imgdata.color.linear_max[0];
            if (white_level <= 0.0f) white_level = (float)RawProcessor->imgdata.color.maximum;
            
            float black_level = (float)RawProcessor->imgdata.color.black;
            if (white_level <= 0.0f) white_level = 65535.0f;
            
            // Extract EXIF
            m_ExifString = "";
            if (RawProcessor->imgdata.idata.make[0]) {
                m_ExifString += RawProcessor->imgdata.idata.make;
                m_ExifString += " ";
            }
            if (RawProcessor->imgdata.idata.model[0]) m_ExifString += RawProcessor->imgdata.idata.model;
            
            if (!m_ExifString.empty()) m_ExifString += " | ";
            
            // ISO
            if (RawProcessor->imgdata.other.iso_speed > 0) {
                m_ExifString += "ISO " + std::to_string((int)RawProcessor->imgdata.other.iso_speed) + " | ";
            }
            
            // Shutter Speed
            if (RawProcessor->imgdata.other.shutter > 0) {
                if (RawProcessor->imgdata.other.shutter < 1.0f) {
                    m_ExifString += "1/" + std::to_string((int)(1.0f / RawProcessor->imgdata.other.shutter)) + "s | ";
                } else {
                    char buf[32];
                    snprintf(buf, sizeof(buf), "%.1fs | ", RawProcessor->imgdata.other.shutter);
                    m_ExifString += buf;
                }
            }
            
            // Aperture
            if (RawProcessor->imgdata.other.aperture > 0) {
                char buf[32];
                snprintf(buf, sizeof(buf), "f/%.1f | ", RawProcessor->imgdata.other.aperture);
                m_ExifString += buf;
            }
            
            // Focal Length
            if (RawProcessor->imgdata.other.focal_len > 0) {
                char buf[32];
                snprintf(buf, sizeof(buf), "%.0fmm", RawProcessor->imgdata.other.focal_len);
                m_ExifString += buf;
            }
            
            // Remove trailing separator if exists
            if (m_ExifString.size() >= 3 && m_ExifString.substr(m_ExifString.size() - 3) == " | ") {
                m_ExifString = m_ExifString.substr(0, m_ExifString.size() - 3);
            }
            
            // Extract Date/Time for window title
            m_ExifString2 = "";
            
            // Date/Time
            if (RawProcessor->imgdata.other.timestamp > 0) {
                time_t timestamp = RawProcessor->imgdata.other.timestamp;
                struct tm* timeinfo = localtime(&timestamp);
                char timeBuf[64];
                strftime(timeBuf, sizeof(timeBuf), "%Y-%m-%d %H:%M:%S", timeinfo);
                m_ExifString2 = timeBuf;
            }

            // Calculate Base Exposure (Auto Exposure)malize the image in the shader
            // LibRaw's dcraw_process automatically scales the image to 16-bit range (0-65535)
            // and subtracts the black level.
            // So we don't need to calculate gain or base exposure to normalize it.
            // We set base_exposure to 0.0f (no adjustment).
            float base_exposure = 0.0f;
            
            std::cout << "Black Level: " << black_level << ", White Level: " << white_level << std::endl;
            std::cout << "Base Exposure set to 0.0 (Linear Raw)" << std::endl;

            // We use uint16_t because we requested 16-bit output.
            // 4 channels: Red, Green, Blue, Alpha
            std::vector<uint16_t> rgbaData;
            try {
                rgbaData.resize(width * height * 4);
            } catch (const std::bad_alloc& e) {
                std::cerr << "Failed to allocate memory for image: " << e.what() << std::endl;
                RawProcessor->dcraw_clear_mem(image);
                m_IsLoading = false;
                return;
            }
            
            // Loop through every pixel
            // Cast the byte array to 16-bit pointer since we requested 16-bit output
            uint16_t* raw_pixels = (uint16_t*)image->data;
            
            for (int i = 0; i < width * height; ++i) {
                // LibRaw data is usually RGBRGB...
                // We access 3 colors at a time.
                uint16_t r_raw = raw_pixels[i*3 + 0];
                uint16_t g_raw = raw_pixels[i*3 + 1];
                uint16_t b_raw = raw_pixels[i*3 + 2];
                
                // LibRaw has already subtracted the black level and scaled to 16-bit.
                // So we just use the values directly.
                
                // Store in our vector as RGBA
                rgbaData[i*4 + 0] = r_raw;
                rgbaData[i*4 + 1] = g_raw;
                rgbaData[i*4 + 2] = b_raw;
                rgbaData[i*4 + 3] = 65535; // Full Alpha in 16-bit (2^16 - 1)
            }
            
            // Clean up LibRaw memory
            RawProcessor->dcraw_clear_mem(image);
            
            // 7. Send the data to the main thread
            // We use a mutex (lock) to safely share data between threads.
            {
                std::lock_guard<std::mutex> lock(m_LoadingMutex);
                m_InitialExposure = base_exposure;
                // Move the data to the member variable
                m_PendingTextureData16 = std::move(rgbaData); // Note: Changed to 16-bit vector
                m_PendingWidth = width;
                m_PendingHeight = height;
                m_TextureUploadPending = true; // Signal main thread that data is ready
            }
            
            // Wake up the main loop if it's blocking (e.g. during window drag)
            // This ensures the UI updates immediately when loading finishes.
            glfwPostEmptyEvent();
            
            std::cout << "Image processing complete, ready for upload." << std::endl;
            
            // Load Sidecar if exists
            LoadSidecar();
            
        } catch (const std::exception& e) {
            std::cerr << "Exception in loading thread: " << e.what() << std::endl;
            m_IsLoading = false;
        } catch (...) {
            std::cerr << "Unknown exception in loading thread" << std::endl;
            m_IsLoading = false;
        }
    });
    
    // Detach the thread so it runs independently
    m_LoadingThread.detach();
}

#include <jpeglib.h>
#include <png.h>
#include <tiffio.h>

void UmbriferaApp::SaveImageAsync(const std::string& filename, const std::string& format) {
    if (!m_ProcessedTexture) {
        std::cerr << "No image to save!" << std::endl;
        return;
    }
    
    int width = (int)m_ProcessedTexture.width;
    int height = (int)m_ProcessedTexture.height;
    
    // Read pixels from GPU on main thread (synchronous readback)
    // We need to do this here because we can't access Metal texture from another thread easily without command buffer sync.
    // Since this is a readback, it will block the main thread briefly, but the encoding (heavy part) will be async.
    std::vector<uint8_t> pixels(width * height * 4);
    [m_ProcessedTexture getBytes:pixels.data() bytesPerRow:width * 4 fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];

    // Metal texture is BGRA (usually). We need RGBA.
    // We also force Alpha to 255.
    for (int i = 0; i < width * height; i++) {
        uint8_t b = pixels[i * 4 + 0];
        uint8_t r = pixels[i * 4 + 2];
        pixels[i * 4 + 0] = r;
        pixels[i * 4 + 2] = b;
        pixels[i * 4 + 3] = 255;
    }
    
    m_IsExporting = true;
    m_ExportProgress = 0.0f;
    
    // Launch export thread
    if (m_ExportThread.joinable()) m_ExportThread.join();
    
    m_ExportThread = std::thread([this, filename, format, width, height, pixels = std::move(pixels)]() {
        // Copy settings to local variables to avoid race conditions if UI changes them
        int quality = m_ExportQuality;
        bool progressive = m_ExportProgressive;
        int subsampling = m_ExportSubsampling;
        // int pngCompression = m_ExportPngCompression; // Removed, always 9
        bool pngInterlaced = m_ExportPngInterlaced;
        bool tiffCompressionEnabled = m_ExportTiffCompression;
        int tiffDepth = m_ExportTiffDepth;
        
        if (format == "jpg") {
            struct jpeg_compress_struct cinfo;
            struct jpeg_error_mgr jerr;
            
            FILE * outfile;
            if ((outfile = fopen(filename.c_str(), "wb")) == NULL) {
                std::cerr << "Can't open " << filename << std::endl;
                m_IsExporting = false;
                return;
            }
            
            cinfo.err = jpeg_std_error(&jerr);
            jpeg_create_compress(&cinfo);
            jpeg_stdio_dest(&cinfo, outfile);
            
            cinfo.image_width = width;
            cinfo.image_height = height;
            cinfo.input_components = 3; // RGB (we'll strip alpha)
            cinfo.in_color_space = JCS_RGB;
            
            jpeg_set_defaults(&cinfo);
            jpeg_set_quality(&cinfo, quality, TRUE);
            
            if (progressive) jpeg_simple_progression(&cinfo);
            
            // Subsampling
            // 0: 4:4:4 (1x1, 1x1, 1x1)
            // 1: 4:2:2 (2x1, 1x1, 1x1)
            // 2: 4:2:0 (2x2, 1x1, 1x1)
            if (subsampling == 0) {
                cinfo.comp_info[0].h_samp_factor = 1;
                cinfo.comp_info[0].v_samp_factor = 1;
            } else if (subsampling == 1) {
                cinfo.comp_info[0].h_samp_factor = 2;
                cinfo.comp_info[0].v_samp_factor = 1;
            } else {
                cinfo.comp_info[0].h_samp_factor = 2;
                cinfo.comp_info[0].v_samp_factor = 2;
            }
            
            jpeg_start_compress(&cinfo, TRUE);
            
            JSAMPROW row_pointer[1];
            int row_stride = width * 3;
            std::vector<uint8_t> row_buffer(row_stride);
            
            while (cinfo.next_scanline < cinfo.image_height) {
                // Convert RGBA to RGB for this row
                int y = cinfo.next_scanline;
                for (int x = 0; x < width; x++) {
                    row_buffer[x*3 + 0] = pixels[(y*width + x)*4 + 0];
                    row_buffer[x*3 + 1] = pixels[(y*width + x)*4 + 1];
                    row_buffer[x*3 + 2] = pixels[(y*width + x)*4 + 2];
                }
                
                row_pointer[0] = row_buffer.data();
                jpeg_write_scanlines(&cinfo, row_pointer, 1);
                
                m_ExportProgress = (float)cinfo.next_scanline / (float)height;
            }
            
            jpeg_finish_compress(&cinfo);
            fclose(outfile);
            jpeg_destroy_compress(&cinfo);
            
            std::cout << "Saved JPG to " << filename << std::endl;
            
        } else if (format == "png") {
            FILE *fp = fopen(filename.c_str(), "wb");
            if(!fp) {
                m_IsExporting = false;
                return;
            }
            
            png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
            if (!png) { fclose(fp); m_IsExporting = false; return; }
            
            png_infop info = png_create_info_struct(png);
            if (!info) { png_destroy_write_struct(&png, NULL); fclose(fp); m_IsExporting = false; return; }
            
            if (setjmp(png_jmpbuf(png))) {
                png_destroy_write_struct(&png, &info);
                fclose(fp);
                m_IsExporting = false;
                return;
            }
            
            png_init_io(png, fp);
            
            png_set_IHDR(png, info, width, height, 8, 
                         PNG_COLOR_TYPE_RGBA, 
                         pngInterlaced ? PNG_INTERLACE_ADAM7 : PNG_INTERLACE_NONE, 
                         PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
            
            png_set_compression_level(png, 9); // Always best compression
            
            png_write_info(png, info);
            
            std::vector<png_bytep> row_pointers(height);
            // We need to cast const uint8_t* to png_bytep (uint8_t*)
            // Since we own the vector in this lambda, it's safe to modify if needed, but we are just reading.
            for(int y = 0; y < height; y++) {
                row_pointers[y] = (png_bytep)&pixels[y * width * 4];
            }
            
            // Write rows one by one to update progress
            // png_write_image(png, row_pointers.data()); // This would be all at once
            
            // Manual loop for progress
            if (pngInterlaced) {
                // Interlaced requires multiple passes, hard to track exact progress per line linearly.
                // Just write all for interlaced or use png_write_rows carefully.
                // For simplicity, write all at once for interlaced.
                png_write_image(png, row_pointers.data());
                m_ExportProgress = 1.0f;
            } else {
                for (int y = 0; y < height; y++) {
                    png_write_row(png, row_pointers[y]);
                    m_ExportProgress = (float)(y + 1) / (float)height;
                }
            }
            
            png_write_end(png, NULL);
            fclose(fp);
            png_destroy_write_struct(&png, &info);
            
            std::cout << "Saved PNG to " << filename << std::endl;
            
        } else if (format == "tiff") {
            TIFF* tif = TIFFOpen(filename.c_str(), "w");
            if (!tif) {
                m_IsExporting = false;
                return;
            }
            
            TIFFSetField(tif, TIFFTAG_IMAGEWIDTH, width);
            TIFFSetField(tif, TIFFTAG_IMAGELENGTH, height);
            TIFFSetField(tif, TIFFTAG_SAMPLESPERPIXEL, 4);
            TIFFSetField(tif, TIFFTAG_BITSPERSAMPLE, tiffDepth);
            TIFFSetField(tif, TIFFTAG_ORIENTATION, ORIENTATION_TOPLEFT);
            TIFFSetField(tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
            TIFFSetField(tif, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_RGB);
            
            // Compression: 8 (Deflate) if enabled, else 1 (None)
            TIFFSetField(tif, TIFFTAG_COMPRESSION, tiffCompressionEnabled ? 8 : 1);
            
            // Extra samples (Alpha)
            uint16_t extra_samples[] = { EXTRASAMPLE_ASSOCALPHA }; 
            TIFFSetField(tif, TIFFTAG_EXTRASAMPLES, 1, extra_samples);
            
            // Rows per strip - default is often good, but we can set it.
            TIFFSetField(tif, TIFFTAG_ROWSPERSTRIP, TIFFDefaultStripSize(tif, width * 4));
            
            if (tiffDepth == 8) {
                for (int y = 0; y < height; y++) {
                    if (TIFFWriteScanline(tif, (void*)&pixels[y * width * 4], y, 0) < 0) {
                        break;
                    }
                    m_ExportProgress = (float)(y + 1) / (float)height;
                }
            } else {
                // 16-bit export
                // We have 8-bit data in 'pixels'. We need to scale it up to 16-bit.
                // Ideally we would have kept the 16-bit data from the beginning, but the processed texture is likely 8-bit (BGRA8Unorm).
                // If the texture was RGBA16Float, we would need to read it differently.
                // Assuming the display texture is 8-bit for now.
                // Scaling 8-bit to 16-bit is just x * 257.
                std::vector<uint16_t> row16(width * 4);
                for (int y = 0; y < height; y++) {
                    const uint8_t* srcRow = &pixels[y * width * 4];
                    for (int x = 0; x < width * 4; x++) {
                        row16[x] = (uint16_t)srcRow[x] * 257;
                    }
                    if (TIFFWriteScanline(tif, row16.data(), y, 0) < 0) {
                        break;
                    }
                    m_ExportProgress = (float)(y + 1) / (float)height;
                }
            }
            
            TIFFClose(tif);
            std::cout << "Saved TIFF to " << filename << std::endl;
        }
        
        m_IsExporting = false;
    });
    
    m_ExportThread.detach();
}

void UmbriferaApp::SaveImage(const std::string& filename, const std::string& format) {
    SaveImageAsync(filename, format);
}
