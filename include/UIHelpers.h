#pragma once

#include "imgui.h"
#include "imgui_internal.h"
#include "UIConfig.h"
#include <cmath>
#include <cstdio>
#include <cstdlib>

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

// Custom slider state for text editing
struct SliderEditState {
    static inline bool isEditing = false;
    static inline char editBuffer[32] = "";
    static inline ImGuiID editingId = 0;
    static inline bool wasDragging = false;
    static inline float dragStartValue = 0.0f;
    static inline ImVec2 dragStartPos = ImVec2(0, 0);
};

// Custom slider with:
// - Thinner, darker grab handle
// - Narrower label text
// - Thicker value text
// - Click to edit: clicking anywhere on slider starts text input
// - Drag to adjust: dragging moves from current value, not cursor position
// - 2 digits shown normally, 4 digits when editing
// Format value with 2 significant digits
inline void FormatValueTwoSigDigits(char* buf, size_t bufSize, float v) {
    float absV = fabsf(v);
    if (absV < 0.0001f) {
        snprintf(buf, bufSize, "0.0");
    } else if (absV >= 100.0f) {
        snprintf(buf, bufSize, "%.0f", v);
    } else if (absV >= 10.0f) {
        snprintf(buf, bufSize, "%.1f", v);
    } else if (absV >= 1.0f) {
        snprintf(buf, bufSize, "%.1f", v);
    } else {
        snprintf(buf, bufSize, "%.2f", v);
    }
}

inline bool SliderWithReset(const char* label, float* v, float v_min, float v_max, float default_val, const char* format = nullptr) {
    (void)format; // Unused, we control format internally
    
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return false;
    
    const ImGuiStyle& style = ImGui::GetStyle();
    
    // Use ImGui::GetID to respect current ID stack (from PushID)
    ImGui::PushID(label);
    const ImGuiID id = ImGui::GetID("##slider");
    
    // Fixed slider width for consistency
    const float sliderWidth = UIConfig::SLIDER_FIXED_WIDTH;
    
    bool changed = false;
    bool justFinishedEditing = false;
    
    // Check if we're editing this slider's value
    const bool isEditingThis = (SliderEditState::isEditing && SliderEditState::editingId == id);
    
    // Push styling for thinner, night blue grab
    ImGui::PushStyleVar(ImGuiStyleVar_GrabMinSize, UIConfig::SLIDER_GRAB_MIN_WIDTH);
    ImGui::PushStyleColor(ImGuiCol_SliderGrab, ImVec4(UIConfig::SLIDER_GRAB_R, UIConfig::SLIDER_GRAB_G, UIConfig::SLIDER_GRAB_B, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_SliderGrabActive, ImVec4(UIConfig::SLIDER_GRAB_ACTIVE_R, UIConfig::SLIDER_GRAB_ACTIVE_G, UIConfig::SLIDER_GRAB_ACTIVE_B, 1.0f));
    
    // Create invisible slider to reserve space and handle interactions
    ImGui::SetNextItemWidth(sliderWidth);
    
    if (isEditingThis) {
        // Show text input instead of slider
        ImGui::SetNextItemWidth(sliderWidth);
        
        // Set focus on first frame of editing
        if (SliderEditState::editingId == id) {
            ImGui::SetKeyboardFocusHere();
        }
        
        if (ImGui::InputText("##edit", SliderEditState::editBuffer, sizeof(SliderEditState::editBuffer),
                             ImGuiInputTextFlags_EnterReturnsTrue | ImGuiInputTextFlags_AutoSelectAll)) {
            // User pressed Enter, validate and apply
            char* endPtr;
            float newVal = strtof(SliderEditState::editBuffer, &endPtr);
            if (endPtr != SliderEditState::editBuffer && std::isfinite(newVal)) {
                // Valid number, clamp to range
                newVal = (newVal < v_min) ? v_min : (newVal > v_max ? v_max : newVal);
                *v = newVal;
                changed = true;
            }
            SliderEditState::isEditing = false;
            SliderEditState::editingId = 0;
            justFinishedEditing = true;
        }
        
        // Check for focus loss (clicked elsewhere) - but only after the first frame
        // Use IsItemDeactivated to detect when the input loses focus
        if (!justFinishedEditing && ImGui::IsItemDeactivatedAfterEdit()) {
            // Validate and apply on defocus
            char* endPtr;
            float newVal = strtof(SliderEditState::editBuffer, &endPtr);
            if (endPtr != SliderEditState::editBuffer && std::isfinite(newVal)) {
                newVal = (newVal < v_min) ? v_min : (newVal > v_max ? v_max : newVal);
                *v = newVal;
                changed = true;
            }
            SliderEditState::isEditing = false;
            SliderEditState::editingId = 0;
            justFinishedEditing = true;
        } else if (!justFinishedEditing && ImGui::IsItemDeactivated() && !ImGui::IsItemActive()) {
            // User clicked away without editing - just cancel
            SliderEditState::isEditing = false;
            SliderEditState::editingId = 0;
            justFinishedEditing = true;
        }
    } else {
        // Custom slider behavior: separate click from drag
        ImVec2 sliderPos = window->DC.CursorPos;
        ImVec2 sliderSize = ImVec2(sliderWidth, ImGui::GetFrameHeight());
        ImRect sliderBB(sliderPos, ImVec2(sliderPos.x + sliderSize.x, sliderPos.y + sliderSize.y));
        
        ImGui::ItemSize(sliderSize, style.FramePadding.y);
        if (!ImGui::ItemAdd(sliderBB, id)) {
            ImGui::PopStyleColor(2);
            ImGui::PopStyleVar();
            ImGui::PopID();  // Don't forget to pop ID on early return
            return false;
        }
        
        // Handle mouse interaction
        bool hovered = ImGui::ItemHoverable(sliderBB, id, ImGuiItemFlags_None);
        bool clicked = hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left);
        bool held = ImGui::IsMouseDown(ImGuiMouseButton_Left);
        
        if (clicked) {
            SliderEditState::wasDragging = false;
            SliderEditState::dragStartValue = *v;
            SliderEditState::dragStartPos = ImGui::GetMousePos();
            ImGui::SetActiveID(id, window);
            ImGui::SetFocusID(id, window);
            ImGui::FocusWindow(window);
        }
        
        if (ImGui::GetActiveID() == id) {
            if (held) {
                ImVec2 currentPos = ImGui::GetMousePos();
                float dx = currentPos.x - SliderEditState::dragStartPos.x;
                
                if (!SliderEditState::wasDragging && fabsf(dx) > UIConfig::SLIDER_DRAG_THRESHOLD) {
                    SliderEditState::wasDragging = true;
                }
                
                if (SliderEditState::wasDragging) {
                    // Drag mode: move value relative to start position
                    float range = v_max - v_min;
                    float delta = (dx / sliderSize.x) * range;
                    float newVal = SliderEditState::dragStartValue + delta;
                    newVal = (newVal < v_min) ? v_min : (newVal > v_max ? v_max : newVal);
                    if (*v != newVal) {
                        *v = newVal;
                        changed = true;
                    }
                }
            } else {
                // Mouse released
                if (!SliderEditState::wasDragging) {
                    // Click without drag: start text editing
                    SliderEditState::isEditing = true;
                    SliderEditState::editingId = id;
                    snprintf(SliderEditState::editBuffer, sizeof(SliderEditState::editBuffer), 
                             "%.*f", UIConfig::SLIDER_EDIT_PRECISION, *v);
                }
                SliderEditState::wasDragging = false;
                ImGui::ClearActiveID();
            }
        }
        
        // Draw slider background
        ImU32 frameBgColor = ImGui::GetColorU32(hovered ? ImGuiCol_FrameBgHovered : ImGuiCol_FrameBg);
        ImGui::RenderFrame(sliderBB.Min, sliderBB.Max, frameBgColor, true, style.FrameRounding);
        
        // Draw grab handle
        float t = (v_max > v_min) ? ((*v - v_min) / (v_max - v_min)) : 0.0f;
        t = (t < 0.0f) ? 0.0f : (t > 1.0f ? 1.0f : t);
        
        float grabWidth = UIConfig::SLIDER_GRAB_MIN_WIDTH;
        float grabX = sliderBB.Min.x + t * (sliderSize.x - grabWidth);
        ImRect grabBB(ImVec2(grabX, sliderBB.Min.y + 1), 
                      ImVec2(grabX + grabWidth, sliderBB.Max.y - 1));
        
        ImU32 grabColor = ImGui::GetColorU32((ImGui::GetActiveID() == id) ? ImGuiCol_SliderGrabActive : ImGuiCol_SliderGrab);
        window->DrawList->AddRectFilled(grabBB.Min, grabBB.Max, grabColor, style.GrabRounding);
        
        // Draw value text (2 significant digits)
        char valueText[32];
        FormatValueTwoSigDigits(valueText, sizeof(valueText), *v);
        ImVec2 valueSize = ImGui::CalcTextSize(valueText);
        ImVec2 valuePos = ImVec2(sliderBB.Min.x + (sliderSize.x - valueSize.x) * 0.5f,
                                  sliderBB.Min.y + (sliderSize.y - valueSize.y) * 0.5f);
        
        // Draw text
        ImU32 textColor = ImGui::GetColorU32(ImGuiCol_Text);
        window->DrawList->AddText(valuePos, textColor, valueText);
    }
    
    ImGui::PopStyleColor(2);
    ImGui::PopStyleVar();
    
    // Same line for the reset button
    ImGui::SameLine();
    
    // Draw label as button (for reset functionality)
    if (ImGui::Button(label)) {
        *v = default_val;
        changed = true;
    }
    
    ImGui::PopID();  // Pop the label ID scope
    
    return changed;
}

// Non-linear slider with cubic root mapping for fine control near center
// valueToSlider: converts the actual value to slider position (e.g., cbrt(val * scale))
// sliderToValue: converts slider position back to actual value (e.g., slider^3 / scale)
// v: pointer to the actual value (not the slider value)
// slider_min, slider_max: typically -1.0 to 1.0
// default_val: the default value for reset
// scale: scaling factor for the cubic mapping
inline bool SliderWithResetNonLinear(const char* label, float* v, float slider_min, float slider_max, 
                                      float default_val, float scale = 1.0f) {
    ImGuiWindow* window = ImGui::GetCurrentWindow();
    if (window->SkipItems) return false;
    
    const ImGuiStyle& style = ImGui::GetStyle();
    
    // Use ImGui::GetID to respect current ID stack (from PushID)
    ImGui::PushID(label);
    const ImGuiID id = ImGui::GetID("##slider");
    
    // Convert value to slider position using cubic root
    float sliderVal = cbrtf(*v * scale);
    if (sliderVal > slider_max) sliderVal = slider_max;
    if (sliderVal < slider_min) sliderVal = slider_min;
    
    // Fixed slider width for consistency
    const float sliderWidth = UIConfig::SLIDER_FIXED_WIDTH;
    
    bool changed = false;
    bool justFinishedEditing = false;
    
    const bool isEditingThis = (SliderEditState::isEditing && SliderEditState::editingId == id);
    
    ImGui::PushStyleVar(ImGuiStyleVar_GrabMinSize, UIConfig::SLIDER_GRAB_MIN_WIDTH);
    ImGui::PushStyleColor(ImGuiCol_SliderGrab, ImVec4(UIConfig::SLIDER_GRAB_R, UIConfig::SLIDER_GRAB_G, UIConfig::SLIDER_GRAB_B, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_SliderGrabActive, ImVec4(UIConfig::SLIDER_GRAB_ACTIVE_R, UIConfig::SLIDER_GRAB_ACTIVE_G, UIConfig::SLIDER_GRAB_ACTIVE_B, 1.0f));
    
    if (isEditingThis) {
        ImGui::SetNextItemWidth(sliderWidth);
        
        // Set focus on first frame of editing
        if (SliderEditState::editingId == id) {
            ImGui::SetKeyboardFocusHere();
        }
        
        if (ImGui::InputText("##edit", SliderEditState::editBuffer, sizeof(SliderEditState::editBuffer),
                             ImGuiInputTextFlags_EnterReturnsTrue | ImGuiInputTextFlags_AutoSelectAll)) {
            char* endPtr;
            float newVal = strtof(SliderEditState::editBuffer, &endPtr);
            if (endPtr != SliderEditState::editBuffer && std::isfinite(newVal)) {
                // Clamp the actual value to the range implied by the slider
                float actualMin = (slider_min * slider_min * slider_min) / scale;
                float actualMax = (slider_max * slider_max * slider_max) / scale;
                if (slider_min < 0) actualMin = -fabsf(actualMin);
                if (slider_max < 0) actualMax = -fabsf(actualMax);
                if (actualMin > actualMax) { float t = actualMin; actualMin = actualMax; actualMax = t; }
                newVal = (newVal < actualMin) ? actualMin : (newVal > actualMax ? actualMax : newVal);
                *v = newVal;
                changed = true;
            }
            SliderEditState::isEditing = false;
            SliderEditState::editingId = 0;
            justFinishedEditing = true;
        }
        
        // Check for focus loss - use IsItemDeactivated for proper detection
        if (!justFinishedEditing && ImGui::IsItemDeactivatedAfterEdit()) {
            char* endPtr;
            float newVal = strtof(SliderEditState::editBuffer, &endPtr);
            if (endPtr != SliderEditState::editBuffer && std::isfinite(newVal)) {
                float actualMin = (slider_min * slider_min * slider_min) / scale;
                float actualMax = (slider_max * slider_max * slider_max) / scale;
                if (slider_min < 0) actualMin = -fabsf(actualMin);
                if (slider_max < 0) actualMax = -fabsf(actualMax);
                if (actualMin > actualMax) { float t = actualMin; actualMin = actualMax; actualMax = t; }
                newVal = (newVal < actualMin) ? actualMin : (newVal > actualMax ? actualMax : newVal);
                *v = newVal;
                changed = true;
            }
            SliderEditState::isEditing = false;
            SliderEditState::editingId = 0;
            justFinishedEditing = true;
        } else if (!justFinishedEditing && ImGui::IsItemDeactivated() && !ImGui::IsItemActive()) {
            // User clicked away without editing - just cancel
            SliderEditState::isEditing = false;
            SliderEditState::editingId = 0;
            justFinishedEditing = true;
        }
    } else {
        ImVec2 sliderPos = window->DC.CursorPos;
        ImVec2 sliderSize = ImVec2(sliderWidth, ImGui::GetFrameHeight());
        ImRect sliderBB(sliderPos, ImVec2(sliderPos.x + sliderSize.x, sliderPos.y + sliderSize.y));
        
        ImGui::ItemSize(sliderSize, style.FramePadding.y);
        if (!ImGui::ItemAdd(sliderBB, id)) {
            ImGui::PopStyleColor(2);
            ImGui::PopStyleVar();
            ImGui::PopID();  // Don't forget to pop ID on early return
            return false;
        }
        
        bool hovered = ImGui::ItemHoverable(sliderBB, id, ImGuiItemFlags_None);
        bool clicked = hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left);
        bool held = ImGui::IsMouseDown(ImGuiMouseButton_Left);
        
        if (clicked) {
            SliderEditState::wasDragging = false;
            SliderEditState::dragStartValue = sliderVal;  // Store slider value, not actual value
            SliderEditState::dragStartPos = ImGui::GetMousePos();
            ImGui::SetActiveID(id, window);
            ImGui::SetFocusID(id, window);
            ImGui::FocusWindow(window);
        }
        
        if (ImGui::GetActiveID() == id) {
            if (held) {
                ImVec2 currentPos = ImGui::GetMousePos();
                float dx = currentPos.x - SliderEditState::dragStartPos.x;
                
                if (!SliderEditState::wasDragging && fabsf(dx) > UIConfig::SLIDER_DRAG_THRESHOLD) {
                    SliderEditState::wasDragging = true;
                }
                
                if (SliderEditState::wasDragging) {
                    float range = slider_max - slider_min;
                    float delta = (dx / sliderSize.x) * range;
                    float newSliderVal = SliderEditState::dragStartValue + delta;
                    newSliderVal = (newSliderVal < slider_min) ? slider_min : (newSliderVal > slider_max ? slider_max : newSliderVal);
                    // Convert slider to actual value
                    float newActualVal = newSliderVal * newSliderVal * newSliderVal / scale;
                    if (*v != newActualVal) {
                        *v = newActualVal;
                        sliderVal = newSliderVal;
                        changed = true;
                    }
                }
            } else {
                if (!SliderEditState::wasDragging) {
                    SliderEditState::isEditing = true;
                    SliderEditState::editingId = id;
                    snprintf(SliderEditState::editBuffer, sizeof(SliderEditState::editBuffer), 
                             "%.*f", UIConfig::SLIDER_EDIT_PRECISION, *v);
                }
                SliderEditState::wasDragging = false;
                ImGui::ClearActiveID();
            }
        }
        
        ImU32 frameBgColor = ImGui::GetColorU32(hovered ? ImGuiCol_FrameBgHovered : ImGuiCol_FrameBg);
        ImGui::RenderFrame(sliderBB.Min, sliderBB.Max, frameBgColor, true, style.FrameRounding);
        
        float t = (slider_max > slider_min) ? ((sliderVal - slider_min) / (slider_max - slider_min)) : 0.0f;
        t = (t < 0.0f) ? 0.0f : (t > 1.0f ? 1.0f : t);
        
        float grabWidth = UIConfig::SLIDER_GRAB_MIN_WIDTH;
        float grabX = sliderBB.Min.x + t * (sliderSize.x - grabWidth);
        ImRect grabBB(ImVec2(grabX, sliderBB.Min.y + 1), 
                      ImVec2(grabX + grabWidth, sliderBB.Max.y - 1));
        
        ImU32 grabColor = ImGui::GetColorU32((ImGui::GetActiveID() == id) ? ImGuiCol_SliderGrabActive : ImGuiCol_SliderGrab);
        window->DrawList->AddRectFilled(grabBB.Min, grabBB.Max, grabColor, style.GrabRounding);
        
        // Display actual value (2 significant digits)
        char valueText[32];
        FormatValueTwoSigDigits(valueText, sizeof(valueText), *v);
        ImVec2 valueSize = ImGui::CalcTextSize(valueText);
        ImVec2 valuePos = ImVec2(sliderBB.Min.x + (sliderSize.x - valueSize.x) * 0.5f,
                                  sliderBB.Min.y + (sliderSize.y - valueSize.y) * 0.5f);
        
        ImU32 textColor = ImGui::GetColorU32(ImGuiCol_Text);
        window->DrawList->AddText(valuePos, textColor, valueText);
    }
    
    ImGui::PopStyleColor(2);
    ImGui::PopStyleVar();
    
    ImGui::SameLine();
    
    // Draw label as button (for reset functionality)
    if (ImGui::Button(label)) {
        *v = default_val;
        changed = true;
    }
    
    ImGui::PopID();  // Pop the label ID scope
    
    return changed;
}

} // namespace UIHelpers
