@echo off
rem Runs the Mangao WRS server (restarts by itself when the code changes). Output also goes to logs\server.log
title Mangao WRS server - keep this window open
cd /d "%~dp0..\server"
call npm run dev 2>&1 | node "%~dp0tee.js" "%~dp0..\logs\server.log"
