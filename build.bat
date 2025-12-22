@echo off
set GLSLC=C:\VulkanSDK\Bin\glslc.exe
echo Compiling shaders...
if not exist shaders\spv mkdir shaders\spv
%GLSLC% -O shaders\process.comp -o shaders\spv\process.spv
%GLSLC% -O shaders\histogram.comp -o shaders\spv\histogram.spv
%GLSLC% -O shaders\grain.comp -o shaders\spv\grain.spv
%GLSLC% -O shaders\resize.comp -o shaders\spv\resize.spv
%GLSLC% -O shaders\rotate.comp -o shaders\spv\rotate.spv
if %ERRORLEVEL% neq 0 (
    echo Shader compilation failed
    exit /b %ERRORLEVEL%
)

if not exist build mkdir build
cd build
echo Running CMake...
cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=../vcpkg/scripts/buildsystems/vcpkg.cmake
if %ERRORLEVEL% neq 0 (
    echo CMake failed
    exit /b %ERRORLEVEL%
)
echo Building...
cmake --build . --config Release
if %ERRORLEVEL% neq 0 (
    echo Build failed
    exit /b %ERRORLEVEL%
)
cd ..
echo Build successful.
