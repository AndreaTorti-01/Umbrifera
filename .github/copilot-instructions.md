# Umbrifera Project - Instructions for AI Agents

## Project Overview
Umbrifera is a professional RAW image processing application built with Metal (macOS), ImGui, LibRaw, and GLFW. It features real-time GPU-accelerated image processing with a comprehensive set of adjustment tools.

## Architecture

### Core Components
- **Main Application** (`UmbriferaApp.h/.mm`): Central app logic, state management
- **UI Rendering** (`UmbriferaApp_UI.mm`): ImGui-based interface with docking
- **Image Processing** (`UmbriferaApp_Image.mm`): LibRaw integration, image loading
- **Metal Rendering** (`UmbriferaApp_Render_Metal.mm`): GPU pipeline, histogram computation
- **Shaders** (`shaders/Shaders.metal`): Metal shader code for image processing
- **File Navigator** (`FileNavigator.h/.mm`): Thumbnail browser for RAW files

### Key Technologies
- **Graphics API**: Metal (macOS native GPU)
- **UI Framework**: Dear ImGui with docking enabled
- **RAW Decoding**: LibRaw
- **Windowing**: GLFW3
- **Image Format**: 16-bit RGBA pipeline (linear space)

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
For backward compatibility, `UmbriferaApp_UI.mm` provides local aliases:
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
1. Base exposure normalization
2. White balance (temperature/tint)
3. Exposure adjustment
4. Tone curve (highlights/shadows/whites/blacks)
5. Contrast
6. Vibrance & Saturation
7. Hue offset (global)
8. **HSL adjustments** (15 color zones, Gaussian falloff, preserves HDR)
9. Vignette
10. Film grain
11. Tone mapping (Standard/ACES/Reinhard)

**Critical**: HSL adjustments do NOT use `saturate()` on luminance to preserve HDR data.

### Histogram
- Industry-standard display (no temporal or spatial smoothing)
- Computed on processed texture in luminance space
- Displayed as filled curve, normalized (ignores extremes 0 and 255)

## Feature Areas

### Presets System
- Stored in `presets.txt` (plain text, pipe-separated key-value pairs)
- "Default" preset is non-deletable, resets all values, uses ACES tone mapping
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
- Displayed in **application window title** (via `glfwSetWindowTitle`): `Umbrifera | Camera Info | Date/Time`
- **No GPS data** (removed per user request)
- Date format: `YYYY-MM-DD HH:MM:SS`

### File Navigator
- Shows only RAW formats: NEF, CR2, CR3, ARW, RAF, DNG
- Thumbnail extraction via LibRaw (async background thread)
- Case-insensitive alphabetical sorting (`strcasecmp`)
- Buttons: Up arrow (`assets/arrow_up.png`), Path input, Open Folder (`assets/folder_open_nf.png`)
- All buttons same height as bar for visual consistency

### Export
- Formats: JPG (with quality/progressive options), PNG, TIFF (8/16-bit, compression)
- **Exports to same directory as source image**
- Overwrite confirmation dialog (styled consistently)
- Real-time size estimation for JPG (async thread on downsampled preview)

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
- When you change anything in the shaders, instead of `./build.sh`, call `./build.sh && (./build/Umbrifera & PID=$!; sleep 1; kill $PID)` so when it runs you see the output from shaders compilation.

## Asset Requirements
Icons should be PNG format, located in `assets/`:
- `folder_open_nf.png`: Open folder button
- `arrow_up.png`: Up directory button
- `folder_closed.png`, `folder_open.png`: Navigator tree icons

---

**Last Updated**: 2025-11-28
**Tip**: Keep this file updated as you work on the application. Document new patterns, gotchas, and architectural decisions.

### Code Hygiene
- **Never keep old commented code around.** If code is removed or replaced, delete it completely. Use git history if retrieval is needed.
- **Comments should describe WHAT the code is doing.** Avoid comments that describe what the code is *supposed* to do, or that reference user requests (e.g. "As requested by user"). Keep comments technical and descriptive.
