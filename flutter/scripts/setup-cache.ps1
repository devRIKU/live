# Route Flutter/Dart build caches to the E: drive to avoid local bloat.
$env:PUB_CACHE = "E:\pub-cache"
$env:DART_CACHE = "E:\dart-cache"
# Optional: point the Flutter SDK root if installed on E:
# $env:FLUTTER_ROOT = "E:\flutter"
Write-Host "PUB_CACHE=$env:PUB_CACHE"
Write-Host "Run: flutter pub get"
Write-Host "Build: flutter build windows --release --build-dir E:\build\lively_openall"