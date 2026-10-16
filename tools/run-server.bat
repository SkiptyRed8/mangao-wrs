@echo off
rem Runs the Mangao WRS server (Java + Spring Boot). Output also goes to logs\server.log
rem To use code changes: close this window and double-click START.bat (it rebuilds the server).
title Mangao WRS server (Java) - keep this window open
cd /d "%~dp0..\server-java"
call "%~dp0java-home.bat"
set "LOG=%~dp0..\logs\server.log"
"%JAVA_HOME%\bin\java.exe" -Dfile.encoding=UTF-8 -Dstdout.encoding=UTF-8 -jar target\mangao-wrs-server.jar 2>&1 | powershell -NoProfile -Command "$f=$env:LOG; Set-Content -Path $f -Value '' -Encoding UTF8; $input | ForEach-Object { $_; Add-Content -Path $f -Value $_ -Encoding UTF8 }"
