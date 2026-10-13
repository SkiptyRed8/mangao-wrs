@echo off
rem Runs the Mangao WRS app in Chrome. In this window: r = reload after a change, R = restart, q = quit.
rem Output also goes to logs\app.log
title Mangao WRS app (Chrome) - keep this window open
cd /d "%~dp0..\app"
call flutter run -d chrome --web-port 5100 2>&1 | node "%~dp0tee.js" "%~dp0..\logs\app.log"
