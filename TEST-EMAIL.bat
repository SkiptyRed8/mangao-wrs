@echo off
rem Checks the Gmail settings in server\.env and sends one test email to that Gmail address.
title Mangao WRS - test email
cd /d "%~dp0server"
call npm run mail:test --silent
echo.
pause
