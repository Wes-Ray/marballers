
$BUILD_PATH = "C:\\Users\\wes\\Documents\\windev\\marballers\\build\\web"

$REMOTE_SERVER = "blog"  # key config must be setup in .ssh

$PROJECT_NAME = "marballers"
$REMOTE_PATH = "/home/wes/blog/games/$PROJECT_NAME"
$URL = "https://ogsyn.dev/games/$PROJECT_NAME"

$BUILD_BAT = "./build_web.bat"

Write-Host "[*] Building web export..."

$buildBat = Join-Path $PSScriptRoot $BUILD_BAT
& $buildBat
$buildExit = $LASTEXITCODE

if ($buildExit -ne 0) {
  Write-Host
  Write-Host "[!] Build failed with exit code: $buildExit"
  exit 1
}

Write-Host "[*] Build successful, deploying to server..."
   
# Convert Windows path to WSL path format
$wslSource = $BUILD_PATH -replace "\\", "/"
$wslSource = $wslSource -replace "C:", "/mnt/c"

Write-Host "[*] BUILD_PATH: $BUILD_PATH"
Get-ChildItem -Force $BUILD_PATH | Format-Table Name, Length

Write-Host "[*] WSL path: $wslSource"
wsl ls -la "$wslSource"

# Execute rsync command through WSL
wsl rsync -avz --delete "${wslSource}/" "${REMOTE_SERVER}:${REMOTE_PATH}/"
if ($LASTEXITCODE -ne 0) {
   Write-Host "[!] Rsync failed with exit code: $LASTEXITCODE"
   exit 1
}

Write-Host
Write-Host "[*] Deployment for '$PROJECT_NAME' complete!"
Write-Host "[*] Available to play at '$URL'"

