cmake_minimum_required(VERSION 4.2.0)

# Enable OBJC and OBJCXX for macOS support
project(Imago LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJCXX_STANDARD 20)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Default to Release build if not specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# Optimization Flags
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    add_compile_options(-O3 -march=native -ffast-math -funroll-loops)
endif()

include(FetchContent)

# 1. GLFW (Locked to 3.4)
FetchContent_Declare(
  glfw
  GIT_REPOSITORY https://github.com/glfw/glfw
  GIT_TAG        3.4
)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(glfw)

# 2. ImGui (Locked to v1.91.5 docking)
FetchContent_Declare(
  imgui
  GIT_REPOSITORY https://github.com/ocornut/imgui
  GIT_TAG        docking
)
FetchContent_MakeAvailable(imgui)

# 3. LibRaw (Locked to 0.21.4)
FetchContent_Declare(
  libraw
  GIT_REPOSITORY https://github.com/LibRaw/LibRaw
  GIT_TAG        0.21.4
)
FetchContent_MakeAvailable(libraw)

# 3.1 LibRaw GPL3 Demosaic Pack
FetchContent_Declare(
  libraw_gpl3
  GIT_REPOSITORY https://github.com/LibRaw/LibRaw-demosaic-pack-GPL3
  GIT_TAG        master
)
FetchContent_MakeAvailable(libraw_gpl3)

# LibRaw doesn't have a root CMakeLists.txt, so we build it manually
file(GLOB_RECURSE LIBRAW_SOURCES "${libraw_SOURCE_DIR}/src/*.cpp")
list(FILTER LIBRAW_SOURCES EXCLUDE REGEX ".*_ph\\.cpp$") # Exclude proprietary/GPL parts if any

# Add GPL3 wrapper implementation
list(APPEND LIBRAW_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/libraw_gpl3_impl.cpp")

add_library(libraw STATIC ${LIBRAW_SOURCES})
target_include_directories(libraw PUBLIC ${libraw_SOURCE_DIR} ${libraw_gpl3_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_include_directories(libraw PRIVATE "${libraw_SOURCE_DIR}/internal")
target_compile_definitions(libraw PUBLIC LIBRAW_NODLL LIBRAW_NOTHREADS LIBRAW_USE_GPL3)

# 4. System Libraries (Production Quality Export)
# Requiring latest stable versions as of Nov 2025
find_package(JPEG 3.0 REQUIRED) # libjpeg-turbo 3.0.4
find_package(PNG 1.6.44 REQUIRED) # libpng 1.6.44
find_package(TIFF 4.7 REQUIRED) # libtiff 4.7.1

# ImGui Setup
set(IMGUI_DIR ${imgui_SOURCE_DIR})
set(IMGUI_SOURCES
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_demo.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_glfw.cpp
    ${IMGUI_DIR}/backends/imgui_impl_metal.mm
)

find_library(METAL_LIB Metal)
find_library(QUARTZCORE_LIB QuartzCore)
find_library(COCOA_LIB Cocoa)
find_library(IOKIT_LIB IOKit)
set(PLATFORM_LIBS ${METAL_LIB} ${QUARTZCORE_LIB} ${COCOA_LIB} ${IOKIT_LIB})

add_library(imgui STATIC ${IMGUI_SOURCES})
target_include_directories(imgui PUBLIC ${IMGUI_DIR} ${IMGUI_DIR}/backends)

# Link GLFW to imgui
target_link_libraries(imgui PUBLIC glfw)
target_compile_options(imgui PRIVATE -fobjc-arc)

# Main Executable - Build as macOS bundle
add_executable(Imago MACOSX_BUNDLE
    src/main.cpp 
    src/ImagoApp.mm
    src/ImagoApp_UI.mm
    src/ImagoApp_Image.mm
    src/ImagoApp_Render_Metal.mm
    src/ImagoApp_Image_GPU.mm
    src/ImagoApp_TextureOps.mm
    src/FileNavigator.mm
)

target_include_directories(Imago PUBLIC include)

set_source_files_properties(src/main.cpp PROPERTIES LANGUAGE OBJCXX)
target_compile_options(Imago PRIVATE -fobjc-arc)

# Set bundle properties
set_target_properties(Imago PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_SOURCE_DIR}/Info.plist
    MACOSX_BUNDLE_BUNDLE_NAME "Imago"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.imago.app"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "1.0.0"
    MACOSX_BUNDLE_ICON_FILE "Imago.icns"
)

# Copy shaders to Resources
set_source_files_properties(shaders/Shaders.metal PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources
)

# Copy icon to Resources
set_source_files_properties(assets/Imago.icns PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources
)

# Copy assets to Resources
file(GLOB ASSETS_PNG "assets/*.png")
set_source_files_properties(${ASSETS_PNG} PROPERTIES
    MACOSX_PACKAGE_LOCATION Resources/assets
)

# Add resources to target
target_sources(Imago PRIVATE
    shaders/Shaders.metal
    assets/Imago.icns
    ${ASSETS_PNG}
)

# Link libraries
target_link_libraries(Imago PRIVATE 
    imgui 
    libraw 
    JPEG::JPEG 
    PNG::PNG 
    TIFF::TIFF 
    ${PLATFORM_LIBS}
)