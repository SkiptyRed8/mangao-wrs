@echo off
rem Mangao WRS - start over with clean demo data.
rem Removes the mangao_wrs database through MySQL (the safe way) and builds it again with the demo accounts.
rem Other databases are not touched. Never delete folders in C:\xampp\mysql\data by hand.
setlocal EnableExtensions
title Mangao WRS - reset demo data
set "BIN=C:\xampp\mysql\bin"
echo This deletes every order and record in the Mangao WRS database and loads the demo data again.
choice /C YN /M "Continue"
if errorlevel 2 exit /b 1
"%BIN%\mysqladmin.exe" -u root --connect-timeout=2 ping >nul 2>&1
if errorlevel 1 (
  echo MySQL is not running. Double-click START.bat first ^(or press Start in XAMPP^), then run this again.
  pause & exit /b 1
)
cd /d "%~dp0server"
if not exist .env copy .env.example .env >nul
if not exist node_modules call npm install --no-audit --no-fund
call npm run db:demo
echo.
pause
