@echo off
rem Sets JAVA_HOME to the installed JDK (the folder that has bin\javac.exe). Used by the other .bat files.
if defined JAVA_HOME if exist "%JAVA_HOME%\bin\javac.exe" exit /b 0
set "JAVA_HOME="
for /f "tokens=2 delims==" %%a in ('java -XshowSettings:properties -version 2^>^&1 ^| findstr /c:"java.home"') do set "JAVA_HOME=%%a"
for /f "tokens=* delims= " %%a in ("%JAVA_HOME%") do set "JAVA_HOME=%%a"
if not defined JAVA_HOME exit /b 1
if not exist "%JAVA_HOME%\bin\javac.exe" exit /b 1
exit /b 0
