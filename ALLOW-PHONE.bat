@echo off
rem Mangao WRS - lets phones on the same Wi-Fi or hotspot reach the server on this laptop.
rem   1. Windows Firewall: allows incoming connections to port 3100 (the Mangao WRS server only)
rem   2. Removes Windows "block Java" rules (made when the "Allow Java" box was cancelled)
rem   3. Shows the address to type in the phone app
rem Windows asks for administrator permission (press Yes). Run it once; it stays set.
setlocal
title Mangao WRS - allow phones
net session >nul 2>&1
if errorlevel 1 (
  echo Windows will ask for permission to change the firewall. Press Yes.
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
echo.
echo [1/3] Allowing port 3100 (Mangao WRS server) in Windows Firewall...
netsh advfirewall firewall delete rule name="Mangao WRS server" >nul 2>&1
netsh advfirewall firewall add rule name="Mangao WRS server" dir=in action=allow protocol=TCP localport=3100 profile=any >nul
if errorlevel 1 (echo       Failed. Run this file again and press Yes. & pause & exit /b 1)
echo       done.
echo [2/3] Removing rules that block Java...
powershell -NoProfile -Command "$r = Get-NetFirewallApplicationFilter | Where-Object { $_.Program -like '*\java.exe' -or $_.Program -like '*\javaw.exe' } | Get-NetFirewallRule | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Block' }; if ($r) { $r | Remove-NetFirewallRule; '      removed ' + @($r).Count + ' rule(s).' } else { '      none found.' }"
echo [3/3] This laptop's address for the phone:
powershell -NoProfile -Command "$c = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' }; if ($c) { $c | ForEach-Object { '      http://' + $_.IPv4Address.IPAddress + ':3100     (' + $_.InterfaceAlias + ')' } } else { '      No network connection found. Connect to the Wi-Fi first.' }"
echo.
echo Check on the phone (same Wi-Fi): open Chrome and go to that address followed by /health
echo   e.g. http://192.168.1.5:3100/health  -- it should show "ok":true
echo If it does: in the app, long-press the logo and type the address (without /health).
echo If it still does not open: the Wi-Fi may block devices from seeing each other (common on
echo school or public Wi-Fi). Turn on the phone's hotspot, connect the laptop to it, and run this again.
echo.
pause
