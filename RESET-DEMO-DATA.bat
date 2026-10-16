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
call "%~dp0tools\java-home.bat"
if errorlevel 1 (echo The Java JDK was not found. Run SETUP-JAVA.bat first. & pause & exit /b 1)
cd /d "%~dp0server-java"
if not exist target\mangao-wrs-server.jar (echo The server is not built yet. Run START.bat once first. & pause & exit /b 1)
"%JAVA_HOME%\bin\java.exe" -jar target\mangao-wrs-server.jar --setup-db --demo
echo.
pause
