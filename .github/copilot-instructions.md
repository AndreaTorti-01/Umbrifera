# Imago Project - Instructions for AI Agents

## Project Overview
Imago is a professional RAW image processing application built with Metal (macOS), ImGui, LibRaw, and GLFW. It features real-time GPU-accelerated image processing with a comprehensive set of adjustment tools.

## Feature Implementation Guidelines

> [!CRITICAL]
> **Before implementing any feature:**
> 1. Check if the feature is listed in the **Planned Features** section of `README.md`
> 2. If it is listed there, read the full specification carefully
> 3. If ANY aspect of the feature is ambiguous or undefined, **ASK FOR CLARIFICATION** before proceeding
> 4. Every implementation detail must be explicit - do not assume behavior
> 5. **After completing a feature**, remove it from the README's Planned Features section

This ensures all implementations match the user's exact expectations and prevents wasted effort on incorrect implementations.

## Architecture

### Core Components
- **Main Application** (`ImagoApp.h/.mm`): Central app logic, state management, initialization
- **UI Rendering** (`ImagoApp_UI.mm`): ImGui-based interface with docking (~2000 lines handling all panels)
- **Image Loading & Export** (`ImagoApp_Image.mm`): LibRaw integration, async image loading, EXIF extraction, image export
- **GPU Image Processing** (`ImagoApp_Image_GPU.mm`): ProcessImage, grain generation, histogram computation on GPU
- **Texture Operations** (`ImagoApp_TextureOps.mm`): Crop, rotation, and undo texture manipulation operations
- **Metal Rendering** (`ImagoApp_Render_Metal.mm`): GPU pipeline initialization, frame rendering, texture setup
- **Shaders** (`shaders/Shaders.metal`): Metal shader code (~1000 lines) for all image processing
- **File Navigator** (`FileNavigator.h/.mm`): Thumbnail browser for RAW files with async loading
- **UI Config** (`include/UIConfig.h`): Centralized UI constants (spacing, sizes, colors)
- **UI Helpers** (`include/UIHelpers.h`): Reusable UI patterns and dialog components

### File Structure
```
Imago/
├── include/           # Header files
│   ├── ImagoApp.h     # Main app class with all state
│   ├── FileNavigator.h    # File browser component
│   ├── UIConfig.h         # UI constants
│   └── UIHelpers.h        # UI helper functions
├── src/               # Implementation files
│   ├── main.cpp                           # Entry point
│   ├── ImagoApp.mm                   # Init, run loop, presets, menu handlers
│   ├── ImagoApp_UI.mm                # All UI rendering (~2000 lines)
│   ├── ImagoApp_Image.mm             # Image loading, export, EXIF
│   ├── ImagoApp_Image_GPU.mm         # GPU image processing and histogram
│   ├── ImagoApp_Texture Ops.mm       # Crop, rotate, undo operations
│   ├── ImagoApp_Render_Metal.mm      # Metal pipeline setup and frame rendering
│   └── FileNavigator.mm                  # File browser implementation
├── shaders/
│   └── Shaders.metal      # Metal shader code (vertex, fragment, compute kernels)
├── assets/            # PNG icon assets
├── build/             # Build output (generated)
├── pipeline.md        # Detailed image processing pipeline documentation
└── README.md          # Project overview and planned features
```

### State Management
All application state is in `ImagoApp` class:
- **Image State**: `m_RawTexture`, `m_ProcessedTexture`, `m_GrainTexture`
- **View State**: `m_ViewZoom`, `m_ViewOffset`, `m_RotationAngle`
- **Edit State**: `m_Uniforms` (all adjustment parameters)
- **Mode State**: `m_CropMode`, `m_ArbitraryRotateDragging`
- **UI State**: `m_ShowExportOptions`, `m_ShowSavePresetDialog`, etc.
- **Async State**: `m_IsLoading`, `m_IsExporting`, loading threads

### Key Technologies
- **Graphics API**: Metal (macOS native GPU)
- **UI Framework**: Dear ImGui with docking enabled
- **RAW Decoding**: LibRaw (DHT demosaicing, 16-bit output)
- **Windowing**: GLFW3
- **Image Format**: 16-bit RGBA pipeline (linear sRGB space)
- **Export**: libjpeg-turbo, libpng, libtiff

### Build System
- **macOS Application Bundle**: Proper `.app` bundle structure for distribution
- CMake-based with `MACOSX_BUNDLE` target
- `./build.sh` - Build and sign the application bundle
- `./run.sh` - Launch `Imago.app` (uses `open` command)
- Dependencies auto-downloaded: GLFW, ImGui (docking branch), LibRaw
- **Bundle Structure**:
  ```
  build/Imago.app/
  └── Contents/
      ├── Info.plist              # Bundle metadata
      ├── MacOS/
      │   └── Imago           # Main executable
      ├── Resources/
      │   ├── Shaders.metal       # Metal shader source
      │   └── assets/             # PNG icons
      └── _CodeSignature/         # Ad-hoc signature
  ```
- Resources loaded via `[NSBundle mainBundle]` API
- Automatically signed with ad-hoc signature during build

## UI Design Philosophy

### Centralized UI Configuration
> [!IMPORTANT]
> All UI constants MUST be defined in `include/UIConfig.h`. Never use magic numbers for spacing, sizes, or visual parameters in component code.

**UIConfig.h** contains:
- `UIConfig::GAP_SMALL`, `UIConfig::GAP_LARGE` - Vertical spacing
- `UIConfig::MARGIN` - General margins
- `UIConfig::BUTTON_HEIGHT`, `UIConfig::BUTTON_WIDTH_STANDARD` - Button dimensions
- `UIConfig::DIALOG_PADDING`, `UIConfig::DIALOG_INPUT_WIDTH` - Dialog styling
- `UIConfig::IMAGE_MARGIN` - Margin around image in viewer
- `UIConfig::HISTOGRAM_HEIGHT` - Histogram display height
- `UIConfig::PRESET_BUTTON_WIDTH/HEIGHT`, `UIConfig::PRESETS_AREA_HEIGHT` - Preset UI

When you need a new visual constant, **add it to UIConfig.h** rather than embedding it in component code.

### Reusable UI Helpers
> [!IMPORTANT]
> All repeating UI patterns MUST be encapsulated in `include/UIHelpers.h`. Never duplicate layout logic.

**UIHelpers.h** provides:
- `UIHelpers::GapSmall()`, `UIHelpers::GapLarge()` - Consistent vertical gaps
- `UIHelpers::Separator()` - Gap + separator + gap pattern
- `UIHelpers::Header(text)` - Section headers
- `UIHelpers::CenterNextWindow()` - Center dialog on main viewport
- `UIHelpers::ModalFlags()` - Standard modal window flags
- `UIHelpers::BeginCenteredModal()` / `EndCenteredModal()` - Modal dialog wrapper
- `UIHelpers::CenteredButtonPair()` - Two centered buttons (OK/Cancel pattern)
- `UIHelpers::SliderWithReset()` - Slider with clickable reset label

When you create a new UI pattern that appears more than once, **add it to UIHelpers.h**.

### Standardized Components (Legacy Aliases)
For backward compatibility, `ImagoApp_UI.mm` provides local aliases:
- `UI_GAP_SMALL` → `UIConfig::GAP_SMALL`
- `UI_GAP_LARGE` → `UIConfig::GAP_LARGE`
- `UI_BUTTON_HEIGHT` → `UIConfig::BUTTON_HEIGHT`
- `UI_MARGIN` → `UIConfig::MARGIN`
- `UI_Separator()` → `UIHelpers::Separator()`
- `UI_Header(text)` → `UIHelpers::Header()`
- `UI_GapSmall()` → `UIHelpers::GapSmall()`
- `UI_GapLarge()` → `UIHelpers::GapLarge()`

**Prefer the UIHelpers:: namespace in new code.**

### Panel Layout
Default layout (can be reset):
- **Navigator** (left, 20%): File browser with thumbnails, only shows RAW formats
- **Image Viewer** (center): Main canvas with zoom/pan, buttons at bottom
- **Develop** (right, 25%): Adjustment controls, histogram, presets

### Dialog Guidelines
- **All dialogs** must be centered on main viewport: `ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f))`
- Use `UI_Separator()` for consistent spacing within dialogs
- Modals should use `ImGuiWindowFlags_AlwaysAutoResize`
- When replacing one dialog with another, close the first before opening the second

## Image Processing Pipeline
> [!IMPORTANT]
> A detailed explanation of the image processing pipeline, including mathematical operations and shader logic, is available in `pipeline.md`. **You MUST read this file to understand the pipeline and keep it updated whenever changes are made to the image processing logic.**

### Processing Flow
1. **Load**: LibRaw decodes RAW to 16-bit linear RGB
2. **Upload**: 16-bit RGBA texture to GPU (MTLPixelFormatRGBA16Unorm)
3. **Process**: Metal shader applies all adjustments in one pass
4. **Display**: Processed 8-bit BGRA texture (MTLPixelFormatBGRA8Unorm) with mipmaps
5. **Histogram**: Computed via Metal compute shader on processed texture

### Shader Architecture (`Shaders.metal`)
Single-pass fragment shader applies (in order):
1. White balance (temperature/tint) - RGB gain multiplication
2. Exposure adjustment - `color *= 2^(exposure + base_exposure)`
3. Clarity & Texture - Mipmap-based local contrast enhancement
4. Vibrance & Saturation - Smart saturation boost
5. HSL adjustments (15 color zones, Gaussian falloff)
6. Hue offset (global) - RGB-space Rodrigues rotation
7. Contrast - Pivot around 0.18 (linear mid-grey)
8. Tonal controls (Blacks/Shadows/Highlights/Whites) - Gaussian weighted
9. Vignette - Circular, aspect-ratio corrected
10. Film grain (35mm multi-layer with pre-computed texture overlay)
11. Tone mapping (Standard gamma 2.2)

**Critical**: HSL adjustments do NOT use `saturate()` on luminance to preserve HDR data.

### Histogram
- Industry-standard display (no temporal or spatial smoothing)
- Computed on processed texture in luminance space
- Displayed as filled curve, normalized (ignores extremes 0 and 255)

## Feature Areas

### Presets System
- Stored in `presets.txt` (plain text, pipe-separated key-value pairs)
- "Auto" preset calculates optimal values from raw histogram
- Saved via dialog at bottom of Develop panel
- **Overwrite behavior**: Separate confirmation dialog replaces save dialog (not nested)
- Settings serialized via `SerializeUniforms`/`DeserializeUniforms`
- Values are clamped to valid ranges on load (robustness)

### Sidecar Files (XMP)
- Auto-save on slider release (`ImGui::IsItemDeactivatedAfterEdit()`)
- Format: `filename.extension.xmp` (e.g., `image.NEF.xmp`)
- Plain text, same format as presets
- Auto-loads when image is opened

### EXIF Metadata
- Extracted from LibRaw: Camera, ISO, Shutter, Aperture, Focal Length, Date/Time
- Displayed in **application window title** (via `glfwSetWindowTitle`): `Imago | Camera Info | Date/Time`
- **No GPS data** (removed per user request)
- Date format: `YYYY-MM-DD HH:MM:SS`

### File Navigator
- Shows only RAW formats: NEF, CR2, CR3, ARW, RAF, DNG
- Thumbnail extraction via LibRaw (async background thread)
- Case-insensitive alphabetical sorting (`strcasecmp`)
- Buttons: Up arrow (`assets/arrow_shape_up_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`), Path input, Open Folder (`assets/folder_open_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`)
- All buttons same height as bar for visual consistency

### Export
- Formats: JPG (with quality/progressive options), PNG, TIFF (8/16-bit, compression)
- **Exports to same directory as source image**
- Overwrite confirmation dialog (styled consistently)
- Real-time size estimation for JPG (async thread on downsampled preview)

### Resource Loading
- **Shaders**: Loaded from bundle via `[[NSBundle mainBundle] pathForResource:@"Shaders" ofType:@"metal"]`
- **Assets**: Loaded from `Resources/assets/` directory in bundle
- All resources embedded in `.app` bundle at build time via CMake `MACOSX_PACKAGE_LOCATION`
- No relative path dependencies - everything uses `[NSBundle mainBundle]` API
- Resources automatically copied to correct bundle locations during build

## Code Patterns & Best Practices

### Reset Functionality
Use `SliderWithReset()` helper for sliders with clickable reset buttons:
```cpp
if (SliderWithReset("Label", &value, min, max, defaultVal)) changed = true;
```

### Non-linear Sliders
Hue adjustments use cubic root for fine control:
```cpp
float sliderVal = cbrtf(actualValue * scale);
// User edits sliderVal
actualValue = sliderVal * sliderVal * sliderVal * invScale;
```

### Triggering Image Update
Set `m_ImageDirty = true` when uniforms change to trigger GPU reprocessing.

### Error Handling
- Parsing errors in presets/sidecars are caught and ignored (keeps defaults)
- Invalid values are clamped to valid ranges
- Missing assets gracefully degrade (e.g., show text button if icon missing)

## Common Gotchas

1. **ImGui Versions**: Newer ImGui requires string ID for `ImageButton`: `ImGui::ImageButton("##id", texture, size)`
2. **Metal Texture Formats**: Input is RGBA16Unorm, output is BGRA8Unorm
3. **Coordinate Systems**: ImGui uses top-left origin, Metal uses bottom-left (handled in shaders)
4. **LibRaw Variables**: In loading thread, use `RawProcessor` (local), not `m_RawProcessor`
5. **Dialog Centering**: Always call `ImGui::SetNextWindowPos()` BEFORE `ImGui::OpenPopup()`
6. **Window Title**: Set via `glfwSetWindowTitle(m_Window, ...)`, not ImGui panel names
7. **Resource Loading**: Always use `[NSBundle mainBundle]` API to load resources from bundle - never use relative paths

## Important Reminders

### Before Making Changes
- Use standardized UI helpers (`UI_Separator()`, etc.) 
- Center dialogs on main viewport
- Check if change affects `m_ImageDirty` flag
- Consider if values need clamping for robustness

### After Making Changes
- Test preset save/load/overwrite flow
- Verify histogram updates in real-time
- Check sidecar file persistence
- **Update this file** with any new patterns or architectural changes
- Test the app by running `./run.sh` which launches the proper `.app` bundle

## Asset Requirements
Icons should be PNG format, located in `assets/`:
- `folder_open_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`: Open folder button
- `arrow_shape_up_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`: Up directory button
- `folder_24dp_E3E3E3_FILL1_wght400_GRAD0_opsz24.png`, `folder_open_24dp_E3E3E3_FILL1_wght400_GRAD0_opsz24.png`: Navigator tree icons
- `compare_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`: Comparison mode button
- `dropper_eye_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`: Eyedropper for HSL hue sampling
- `close_24dp_E3E3E3_FILL0_wght400_GRAD0_opsz24.png`: Close/remove button (X icon)

---

**Last Updated**: 2025-12-24
**Tip**: Keep this file updated as you work on the application. Document new patterns, gotchas, and architectural decisions.

### Code Hygiene Standards

**Bad comments** (do NOT include these):
- Obvious statements: `// Clear buffer` before `buffer.clear()`
- Positioning hints: `// Lighter grey on hover` on color assignments
- File-level descriptions: should be in documentation, not code
- Redundant explanations: when code is self-explanatory
- Cryptic placeholders: `// ... (Helpers remain same)`

**Good comments** (DO include these):
- WHY decisions: `// Double-buffering prevents reading zeros during GPU write`
- Algorithm explanations: `// Transform crop: view(x,y) -> raw(y, 1-x) for 90° rotation`
- Non-obvious logic: behavior that isn't clear from code alone
- Gotchas: `// Metal requires explicit viewport; defaults to window size`
- Important links: references to pipeline.md for complex operations

### File Organization  
- **Split large files** when they exceed ~400 lines and mix distinct concerns
- Each file should have a single, clear responsibility:
  - `ImagoApp_Render_Metal.mm` - Metal pipeline initialization and frame rendering
  - `ImagoApp_Image_GPU.mm` - GPU image processing (ProcessImage, grain, histogram)
  - `ImagoApp_TextureOps.mm` - Texture manipulation (crop, rotate, undo)
  - `ImagoApp_Image.mm` - File I/O and CPU-side image operations
  - `ImagoApp_UI.mm` - All UI rendering (currently ~2000 lines; candidates for further splits: dialogs, image viewer, develop panel)

### Code Patterns
- **Never keep commented-out code** - delete completely; use git history if needed
- **Extract reusable UI patterns** to `UIHelpers.h` instead of duplicating
- **Centralize constants** in `UIConfig.h` - no magic numbers in component code
- **Bundle related operations** - keep crop, rotate, undo together for logic clarity
- **Group GPU operations** - separate compute kernels from main processing pipeline

### Recent Cleanup (Dec 2025)
- Removed logo loading feature (~40 lines)
- Split `ImagoApp_Render_Metal.mm` into:
  - ProcessImage, grain generation → `ImagoApp_Image_GPU.mm`
  - Crop, rotate, undo operations → `ImagoApp_TextureOps.mm`
  - Main rendering pipeline → stays in `ImagoApp_Render_Metal.mm`
- Removed ~40 useless comments (obvious statements, redundant explanations)
- **Converted to proper macOS .app bundle**:
  - Created `Info.plist` with bundle metadata
  - Updated CMakeLists.txt to use `MACOSX_BUNDLE` target
  - Resources embedded in bundle via `MACOSX_PACKAGE_LOCATION`
  - Updated resource loading to use `[NSBundle mainBundle]` API
  - Automatic ad-hoc code signature in build script
  - Proper bundle structure: `Contents/{MacOS,Resources,_CodeSignature}`
- **Integrated LibRaw GPL3 Demosaic Pack (AMaZE)**:
  - Created `LibRawGPL3` subclass to bridge abandoned GPL3 pack with modern LibRaw (0.21+)
  - Implemented `amaze_callback` using LibRaw's `interpolate_bayer_cb` system
  - Clean integration without modifying upstream LibRaw source code
