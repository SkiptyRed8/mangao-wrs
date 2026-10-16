@echo off
rem Checks the Gmail settings in server-java\.env and sends one test email to that Gmail address.
title Mangao WRS - test email
call "%~dp0tools\java-home.bat"
if errorlevel 1 (echo The Java JDK was not found. Run SETUP-JAVA.bat first. & pause & exit /b 1)
cd /d "%~dp0server-java"
if not exist target\mangao-wrs-server.jar (echo The server is not built yet. Run START.bat once first. & pause & exit /b 1)
"%JAVA_HOME%\bin\java.exe" -jar target\mangao-wrs-server.jar --mail-test
echo.
pause
