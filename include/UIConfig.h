#pragma once

// =============================================================================
// UI Configuration - Central location for all UI constants and styling
// =============================================================================
// All UI-related constants (spacing, sizes, colors, etc.) MUST be defined here.
// Components should reference these values instead of using magic numbers.
// =============================================================================

namespace UIConfig {

// --- Spacing ---
constexpr float GAP_SMALL = 10.0f;
constexpr float GAP_LARGE = 20.0f;
constexpr float MARGIN = 10.0f;

// --- Buttons ---
constexpr float BUTTON_HEIGHT = 40.0f;
constexpr float BUTTON_WIDTH_STANDARD = 120.0f;

// --- Dialogs ---
constexpr float DIALOG_PADDING = 10.0f;
constexpr float DIALOG_INPUT_WIDTH = 200.0f;

// --- Image Viewer ---
constexpr float IMAGE_MARGIN = 5.0f;  // Margin around image in viewer

// --- Histogram ---
constexpr float HISTOGRAM_HEIGHT = 100.0f;

// --- Presets ---
constexpr float PRESET_BUTTON_WIDTH = 100.0f;
constexpr float PRESET_BUTTON_HEIGHT = 60.0f;
constexpr float PRESETS_AREA_HEIGHT = 80.0f;

// --- Crop Mode ---
constexpr float CROP_RATIO_BUTTON_HEIGHT = 40.0f;
constexpr float CROP_CORNER_RADIUS = 8.0f;
constexpr float CROP_CORNER_HIT_RADIUS = 16.0f;
constexpr float CROP_OVERLAY_ALPHA = 0.6f;

// --- Arbitrary Rotation Mode ---
constexpr float ROTATE_GRID_SPACING = 20.0f;      // Spacing between grid lines
constexpr int ROTATE_GRID_MAJOR_EVERY = 5;        // Major line every N lines
constexpr float ROTATE_SENSITIVITY = 0.15f;       // Degrees per pixel of mouse movement
constexpr float ROTATE_MAX_ANGLE = 90.0f;         // Maximum rotation in either direction

// --- Custom Slider Styling ---
constexpr float SLIDER_GRAB_MIN_WIDTH = 6.0f;     // Thinner grab handle (default ~12)
constexpr float SLIDER_FIXED_WIDTH = 180.0f;      // Fixed slider width for all sliders
constexpr int SLIDER_DISPLAY_PRECISION = 2;       // Total significant digits to show normally
constexpr int SLIDER_EDIT_PRECISION = 4;          // Digits when editing (4 = "0.0000")
constexpr float SLIDER_DRAG_THRESHOLD = 3.0f;     // Pixels of movement to start drag

// Night blue color for slider grab handle (lighter for visibility)
constexpr float SLIDER_GRAB_R = 0.25f;
constexpr float SLIDER_GRAB_G = 0.35f;
constexpr float SLIDER_GRAB_B = 0.55f;
constexpr float SLIDER_GRAB_ACTIVE_R = 0.35f;
constexpr float SLIDER_GRAB_ACTIVE_G = 0.45f;
constexpr float SLIDER_GRAB_ACTIVE_B = 0.70f;

} // namespace UIConfig
