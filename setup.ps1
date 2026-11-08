# Setup script for Lively OpenAll on E: drive
# Run this in PowerShell before building

$env:PUB_CACHE = "E:\pub-cache"
$env:FLUTTER_ROOT = "C:\flutter"  # Adjust to your Flutter SDK path

# Create build directory on E: drive
New-Item -ItemType Directory -Path "E:\build\lively_openall" -Force | Out-Null

# Navigate to flutter project
Set-Location "E:\dev\lively\flutter"

# Get dependencies
flutter pub get

# Analyze code
flutter analyze

# Build (Windows)
flutter build windows --release --build-dir "E:\build\lively_openall"
