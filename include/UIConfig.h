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

} // namespace UIConfig
