@echo off
rem ==========================================================================================
rem  Mangao WRS - one double-click to run the whole system on this laptop.
rem    1. MySQL     starts it if it is not running
rem    2. Database  creates the mangao_wrs database ONLY if it does not exist yet (your data is kept)
rem    3. Server    starts it if it is not running (http://localhost:3100)
rem    4. App       opens the app in Chrome (http://localhost:5100)
rem  Nothing is ever deleted by this file. To start over with clean demo data use RESET-DEMO-DATA.bat
rem ==========================================================================================
setlocal EnableExtensions
title Mangao WRS - start
set "ROOT=%~dp0"
set "BIN=C:\xampp\mysql\bin"
if not exist "%ROOT%logs" mkdir "%ROOT%logs"
echo.
echo  Mangao Water Refilling Station - starting the system
echo.

echo [1/4] MySQL
call :mysql_ping
if not errorlevel 1 (echo       running. & goto mysql_ok)
if not exist "%BIN%\mysqld.exe" (
  echo       XAMPP MySQL was not found in C:\xampp. Install XAMPP or start MySQL yourself.
  pause & exit /b 1
)
echo       starting MySQL...
start "MySQL - keep this window open" /min "%BIN%\mysqld.exe" --defaults-file="%BIN%\my.ini" --standalone
call :mysql_wait
if not errorlevel 1 (echo       running. & goto mysql_ok)
echo.
echo       MySQL did not start. Open the XAMPP Control Panel, press Start beside MySQL,
echo       and read the message there. Last lines of the MySQL log:
powershell -NoProfile -Command "Get-Content 'C:\xampp\mysql\data\mysql_error.log' -Tail 8"
echo.
pause
exit /b 1
:mysql_ok

echo [2/4] Database
cd /d "%ROOT%server"
if not exist .env copy .env.example .env >nul
if not exist node_modules (
  echo       installing the server libraries ^(first time only^)...
  call npm install --no-audit --no-fund
)
"%BIN%\mysql.exe" -u root -e "USE mangao_wrs" >nul 2>&1
if errorlevel 1 (
  echo       creating the mangao_wrs database with the demo accounts ^(first time only^)...
  call npm run db:demo
  if errorlevel 1 (echo       Database setup failed - see the message above. & pause & exit /b 1)
) else (
  echo       mangao_wrs is ready ^(your data is kept^).
)

echo [3/4] Server
call :server_ping
if not errorlevel 1 (echo       running. & goto server_ok)
start "Mangao WRS server" cmd /k call "%ROOT%tools\run-server.bat"
for /L %%i in (1,1,30) do (
  call :server_ping && (echo       running. & goto server_ok)
  timeout /t 1 /nobreak >nul
)
echo       The server did not start. Look at the "Mangao WRS server" window, or logs\server.log
pause
exit /b 1
:server_ok

echo [4/4] App in Chrome
cd /d "%ROOT%app"
if not exist web\index.html (
  echo       preparing the app for Chrome ^(first time only, about a minute^)...
  call flutter create --platforms=web,android --org com.mangao --project-name mangao_wrs . >nul
)
start "Mangao WRS app" cmd /k call "%ROOT%tools\run-app.bat"
echo.
echo  Chrome opens with the app in about a minute (the first time takes longer).
echo.
echo  Log in (phone / password):
echo    Owner     09170000001 / owner123
echo    Staff     09170000002 / staff123
echo    Rider     09170000003 / rider123
echo    Customer  09172001111 / ana123
echo.
echo  Keep the MySQL, server and app windows open while you use the system.
echo  Before shutting down the laptop: close the app window, then stop MySQL in XAMPP
echo  (or close the "MySQL - keep this window open" window).
echo.
pause
exit /b 0

:mysql_ping
"%BIN%\mysqladmin.exe" -u root --connect-timeout=2 ping >nul 2>&1
exit /b %errorlevel%

:mysql_wait
for /L %%i in (1,1,25) do (
  "%BIN%\mysqladmin.exe" -u root --connect-timeout=2 ping >nul 2>&1 && exit /b 0
  timeout /t 1 /nobreak >nul
)
exit /b 1

:server_ping
node -e "require('http').get('http://localhost:3100/health',r=>{let d='';r.on('data',c=>d+=c);r.on('end',()=>process.exit(d.includes('mangao-system')?0:1))}).on('error',()=>process.exit(1))" >nul 2>&1
exit /b %errorlevel%
