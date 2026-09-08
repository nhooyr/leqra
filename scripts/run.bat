@echo off
cd /d "%~dp0.."
where go >nul 2>nul
if errorlevel 1 (
  echo Go is required on the hosting computer. Install it from https://go.dev/doc/install
  pause
  exit /b 1
)
go run ./src %*
if errorlevel 1 pause
