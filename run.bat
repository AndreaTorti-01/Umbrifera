@echo off
if exist build\Release\Umbrifera.exe (
    build\Release\Umbrifera.exe
) else if exist build\Umbrifera.exe (
    build\Umbrifera.exe
) else (
    echo Executable not found. Please run build.bat first.
)
