# Lively OpenAll — Flutter (Windows)

Native Windows desktop app built with Flutter + Impeller.

## Prereqs
- Flutter SDK (stable) on Windows, with `windows` desktop enabled.
- Visual Studio 2022 (Desktop C++ workload) for Windows runner.

## Setup (cache on E:)
```powershell
.\scripts\setup-cache.ps1
flutter create --platforms=windows .
flutter pub get
```

## Run
```powershell
flutter run -d windows
```

## Build (release, cache on E:)
```powershell
flutter build windows --release --build-dir E:\build\lively_openall
```

## Architecture
See `../docs/FLUTTER_ARCHITECTURE.md`.