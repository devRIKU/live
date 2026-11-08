@echo off
:: OpenAll launcher — starts the dev server (web app) automatically.
:: Run this whenever you want the app up without typing a command.
cd /d "%~dp0"
echo Starting OpenAll dev server on http://localhost:5173 …
npm run start
