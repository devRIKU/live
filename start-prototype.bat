@echo off
:: Lively / OpenAll Prototype Launcher
cd /d "%~dp0"
echo ===================================================
echo  Starting Lively Prototype Backend + OpenAll UI
echo ===================================================
echo.
echo Starting Backend Server on http://localhost:3001...
start "Lively Backend" node backend/server.mjs
echo.

:: Start the deep-research service when its dependencies are installed. The UI
:: falls back to simulated data otherwise and labels it "Demo data".
if exist ".venv\Scripts\python.exe" (
  ".venv\Scripts\python.exe" -c "import fastapi, uvicorn" >nul 2>&1
  if not errorlevel 1 (
    echo Starting Research Service on http://127.0.0.1:8000...
    start "Lively Research" /D "%~dp0research-service" "%~dp0.venv\Scripts\python.exe" -m uvicorn main:app --host 127.0.0.1 --port 8000
    set "VITE_RESEARCH_URL=http://127.0.0.1:8000"
  )
)
if not defined VITE_RESEARCH_URL (
  echo Research service not installed - the UI will show simulated demo data.
  echo   Install it with: .venv\Scripts\python.exe -m pip install -r research-service\requirements.txt
)
echo.
echo Server endpoints:
echo  - OpenAll React App: http://localhost:5173
echo  - Standalone Chat UI: http://localhost:3001/Chat%%20UI%%20v3.html
echo  - API:                http://localhost:3001/api/chat/completions
echo  - Providers:          http://localhost:3001/api/providers
echo.
cd openall
npm run dev
