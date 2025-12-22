@echo off

echo Building web build with bat (must be in project dir)
call .\build_web.bat

echo #
echo # build successful
echo #
echo Launching server 
python -m http.server --directory ./build/web
