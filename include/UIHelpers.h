#pragma once

#include "imgui.h"
#include "UIConfig.h"

// =============================================================================
// UI Helpers - Reusable UI patterns and dialog components
// =============================================================================
// All repeating UI patterns should be encapsulated here as functions.
// This ensures consistency across the application and simplifies maintenance.
// =============================================================================

namespace UIHelpers {

// --- Spacing Helpers ---

// Adds a small vertical gap
inline void GapSmall() {
    ImGui::Dummy(ImVec2(0.0f, UIConfig::GAP_SMALL));
}

// Adds a large vertical gap
inline void GapLarge() {
    ImGui::Dummy(ImVec2(0.0f, UIConfig::GAP_LARGE));
}

// Standard separator pattern: gap + separator + gap
inline void Separator() {
    ImGui::Dummy(ImVec2(0.0f, UIConfig::GAP_SMALL));
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0.0f, UIConfig::GAP_SMALL));
}

// --- Section Helpers ---

// Section header text
inline void Header(const char* text) {
    ImGui::Text("%s", text);
}

// --- Dialog Helpers ---

// Centers the next window on the main viewport (call BEFORE OpenPopup)
inline void CenterNextWindow() {
    ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
}

// Standard modal dialog flags
inline ImGuiWindowFlags ModalFlags() {
    return ImGuiWindowFlags_AlwaysAutoResize;
}

// Standard modal dialog flags without move
inline ImGuiWindowFlags ModalFlagsNoMove() {
    return ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoTitleBar;
}

// Begins a centered modal dialog with standard styling
// Returns true if the modal is open
// Call CenterNextWindow() and ImGui::OpenPopup() before this
inline bool BeginCenteredModal(const char* name, bool* p_open = nullptr) {
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(UIConfig::DIALOG_PADDING, UIConfig::DIALOG_PADDING));
    return ImGui::BeginPopupModal(name, p_open, ModalFlags());
}

// Ends a modal dialog started with BeginCenteredModal
inline void EndCenteredModal() {
    ImGui::EndPopup();
    ImGui::PopStyleVar();
}

// Renders two centered buttons (e.g., "OK" and "Cancel")
// Returns 1 if first button clicked, 2 if second button clicked, 0 otherwise
inline int CenteredButtonPair(const char* label1, const char* label2, float buttonWidth = UIConfig::BUTTON_WIDTH_STANDARD) {
    float spacing = ImGui::GetStyle().ItemSpacing.x;
    float totalWidth = buttonWidth * 2 + spacing;
    float startX = (ImGui::GetWindowWidth() - totalWidth) * 0.5f;
    
    ImGui::SetCursorPosX(startX);
    int result = 0;
    if (ImGui::Button(label1, ImVec2(buttonWidth, 0))) {
        result = 1;
    }
    ImGui::SameLine();
    if (ImGui::Button(label2, ImVec2(buttonWidth, 0))) {
        result = 2;
    }
    return result;
}

// --- Slider with Reset ---

// Slider with a clickable label that resets to default value
inline bool SliderWithReset(const char* label, float* v, float v_min, float v_max, float default_val, const char* format = "%.3f") {
    char sliderLabel[128];
    snprintf(sliderLabel, sizeof(sliderLabel), "##%s", label);
    
    bool changed = ImGui::SliderFloat(sliderLabel, v, v_min, v_max, format);
    
    ImGui::SameLine();
    
    if (ImGui::Button(label)) {
        *v = default_val;
        changed = true;
    }
    
    return changed;
}

} // namespace UIHelpers
