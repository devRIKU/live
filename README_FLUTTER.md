# Lively OpenAll — Flutter Rewrite

## Project Location
This project has been migrated to `E:\dev\lively`.

## Prerequisites
- Flutter SDK (Windows) — install from https://flutter.dev/docs/get-started/install/windows
- Visual Studio 2019+ with Windows 11 SDK (for WebView2 plugin and flutter_pty)
- nuget.exe in PATH (for flutter_pty build)
- Node.js 18+ (for the backend prototype server)

## Quick Start

### 1. Set up environment
```powershell
$env:PUB_CACHE = "E:\pub-cache"
cd E:\dev\lively\flutter
```

### 2. Get dependencies
```powershell
flutter pub get
```

### 3. Run the backend (optional, for live LLM providers)
```powershell
cd E:\dev\lively\backend
node server.mjs
```

### 4. Analyze and build
```powershell
flutter analyze
flutter build windows --release --build-dir E:\build\lively_openall
```

### 5. Run the app
```powershell
flutter run -d windows
```

## Architecture
See `docs/FLUTTER_ARCHITECTURE.md` for the full architecture and migration status.

## Build Cache
All build artifacts go to `E:\build\lively_openall` and pub cache to `E:\pub-cache` to keep the C: drive clean.