cmake_minimum_required(VERSION 4.2.0)

# Enable OBJC and OBJCXX for macOS support
project(Umbrifera LANGUAGES C CXX OBJC OBJCXX)

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

# LibRaw doesn't have a root CMakeLists.txt, so we build it manually
file(GLOB_RECURSE LIBRAW_SOURCES "${libraw_SOURCE_DIR}/src/*.cpp")
list(FILTER LIBRAW_SOURCES EXCLUDE REGEX ".*_ph\\.cpp$") # Exclude proprietary/GPL parts if any
add_library(libraw STATIC ${LIBRAW_SOURCES})
target_include_directories(libraw PUBLIC ${libraw_SOURCE_DIR})
target_compile_definitions(libraw PUBLIC LIBRAW_NODLL LIBRAW_NOTHREADS)

# 4. System Libraries (Production Quality Export)
# Requiring latest stable versions as of Nov 2025
find_package(JPEG 3.0 REQUIRED) # libjpeg-turbo 3.0.4
find_package(PNG 1.6.44 REQUIRED) # libpng 1.6.44
find_package(TIFF 4.7 REQUIRED) # libtiff 4.7.1

# Copy Shaders.metal to the build directory
configure_file(shaders/Shaders.metal Shaders.metal COPYONLY)

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

# Main Executable
add_executable(Umbrifera 
    src/main.cpp 
    src/UmbriferaApp.mm
    src/UmbriferaApp_UI.mm
    src/UmbriferaApp_Image.mm
    src/UmbriferaApp_Render_Metal.mm
)

target_include_directories(Umbrifera PUBLIC include)

set_source_files_properties(src/main.cpp PROPERTIES LANGUAGE OBJCXX)
target_compile_options(Umbrifera PRIVATE -fobjc-arc)

# Link libraries
target_link_libraries(Umbrifera PRIVATE 
    imgui 
    libraw 
    JPEG::JPEG 
    PNG::PNG 
    TIFF::TIFF 
    ${PLATFORM_LIBS}
)