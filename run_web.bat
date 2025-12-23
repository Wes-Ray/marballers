@echo off

echo Building web build with bat (must be in project dir)
call .\build_web.bat

IF ERRORLEVEL 1 (
    echo.
    echo # BUILD FAILED - NOT STARTING SERVER
    exit /b 1
)

echo #
echo # build successful
echo #
echo Launching server 
python -m http.server --directory ./build/web
