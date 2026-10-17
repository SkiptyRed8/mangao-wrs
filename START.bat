@echo off
rem ==========================================================================================
rem  Mangao WRS - one double-click to run the whole system on this laptop.
rem    1. MySQL     starts it if it is not running
rem    2. Server    builds the Java (Spring Boot) server when its code changed; creates the mangao_wrs
rem                 database ONLY if it does not exist yet (your data is kept)
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

echo [2/4] Java server and database
call "%ROOT%tools\java-home.bat"
if errorlevel 1 (
  echo       The Java JDK was not found. Double-click SETUP-JAVA.bat first ^(one time^), then START.bat again.
  pause & exit /b 1
)
set "MVN=%ROOT%tools\maven\apache-maven-3.9.9\bin\mvn.cmd"
if not exist "%MVN%" (
  echo       Maven is not set up yet. Double-click SETUP-JAVA.bat first ^(one time^), then START.bat again.
  pause & exit /b 1
)
cd /d "%ROOT%server-java"
rem Settings: the first time, keep the old server's settings (Gmail App Password, owner account).
if not exist .env (
  if exist "%ROOT%server\.env" (copy "%ROOT%server\.env" .env >nul) else (copy .env.example .env >nul)
)
rem Damaged-gallon photos saved by the old server.
if exist "%ROOT%server\uploads\damage" if not exist uploads\damage (
  mkdir uploads\damage >nul 2>&1
  xcopy /e /i /q /y "%ROOT%server\uploads\damage" uploads\damage >nul
)
rem Build the server when the code changed (or the first time).
set "NEEDBUILD=1"
if exist target\mangao-wrs-server.jar (
  powershell -NoProfile -Command "$jar=(Get-Item 'target\mangao-wrs-server.jar').LastWriteTime; $src=Get-ChildItem -Recurse -File src,pom.xml | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if($src.LastWriteTime -gt $jar){exit 1}else{exit 0}"
  if not errorlevel 1 set "NEEDBUILD=0"
)
if "%NEEDBUILD%"=="1" (
  echo       building the server ^(about a minute; only when the code changes^)...
  call "%MVN%" -B -q -o package -DskipTests > "%ROOT%logs\build.log" 2>&1
  if errorlevel 1 call "%MVN%" -B -q package -DskipTests > "%ROOT%logs\build.log" 2>&1
  if not exist target\mangao-wrs-server.jar (
    echo       The build failed. See logs\build.log
    pause & exit /b 1
  )
)
"%BIN%\mysql.exe" -u root -e "USE mangao_wrs" >nul 2>&1
if errorlevel 1 (
  echo       creating the mangao_wrs database with the demo accounts ^(first time only^)...
  "%JAVA_HOME%\bin\java.exe" -jar target\mangao-wrs-server.jar --setup-db --demo
  if errorlevel 1 (echo       Database setup failed - see the message above. & pause & exit /b 1)
) else (
  echo       mangao_wrs is ready ^(your data is kept^).
)

echo [3/4] Server
call :server_ping
if not errorlevel 1 (echo       running. & goto server_ok)
call :old_ping
if not errorlevel 1 (
  echo       The old Node.js server is still running. Close the window named "Mangao WRS server",
  echo       then press any key here to start the Java server.
  pause >nul
)
start "Mangao WRS server" cmd /k call "%ROOT%tools\run-server.bat"
for /L %%i in (1,1,60) do (
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
rem Laptop address for phones on the same Wi-Fi or hotspot (backup to the online server).
set "LANIP="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch '^(127|169\.254)' } | Sort-Object InterfaceMetric | Select-Object -First 1).IPAddress"`) do set "LANIP=%%a"
if defined LANIP (
  echo  Phone backup ^(same Wi-Fi or hotspot^): long-press the logo in the app and type
  echo    http://%LANIP%:3100
  echo  If Windows asks to allow Java on the network, tick Private networks and press Allow.
  echo.
)
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
rem The Java server answers /health with "server":"java".
powershell -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing 'http://localhost:3100/health' -TimeoutSec 2; if($r.Content -match 'server.\s*:\s*.java'){exit 0}else{exit 1}}catch{exit 1}" >nul 2>&1
exit /b %errorlevel%

:old_ping
rem The first (Node.js) server is still running on port 3100.
powershell -NoProfile -Command "try{$r=Invoke-WebRequest -UseBasicParsing 'http://localhost:3100/health' -TimeoutSec 2; if($r.Content -match 'mangao-system'){exit 0}else{exit 1}}catch{exit 1}" >nul 2>&1
exit /b %errorlevel%
