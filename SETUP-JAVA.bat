@echo off
rem ==========================================================================================
rem  Mangao WRS - one-time setup for the Java (Spring Boot) server. Needs internet.
rem    1. Finds the Java JDK (javac) and remembers where it is
rem    2. Downloads Apache Maven 3.9.9 into tools\maven (only the first time)
rem    3. Downloads the Spring Boot libraries into server-java\target\libs
rem  Result: logs\setup-java-result.txt   Full log: logs\setup-java.log
rem ==========================================================================================
setlocal EnableExtensions
title Mangao WRS - Java setup
set "ROOT=%~dp0"
if not exist "%ROOT%logs" mkdir "%ROOT%logs"
set "LOG=%ROOT%logs\setup-java.log"
set "RESULT=%ROOT%logs\setup-java-result.txt"
echo Mangao WRS Java setup %DATE% %TIME% > "%LOG%"

echo [1/3] Java JDK
set "JH="
for /f "tokens=2 delims==" %%a in ('java -XshowSettings:properties -version 2^>^&1 ^| findstr /c:"java.home"') do set "JH=%%a"
for /f "tokens=* delims= " %%a in ("%JH%") do set "JH=%%a"
if not defined JH (
  echo       Java was not found. Install the JDK from https://adoptium.net then run this again.
  echo FAILED: java not found > "%RESULT%" & pause & exit /b 1
)
if not exist "%JH%\bin\javac.exe" (
  echo       Java is installed but not the JDK ^(javac is missing^): %JH%
  echo       Install the JDK ^(not only the runtime^) from https://adoptium.net then run this again.
  echo FAILED: javac missing in %JH% > "%RESULT%" & pause & exit /b 1
)
set "JAVA_HOME=%JH%"
echo       %JAVA_HOME%
"%JAVA_HOME%\bin\javac.exe" -version >> "%LOG%" 2>&1

echo [2/3] Apache Maven
set "MVN=%ROOT%tools\maven\apache-maven-3.9.9\bin\mvn.cmd"
if exist "%MVN%" (echo       already downloaded. & goto mvn_ok)
echo       downloading Maven 3.9.9 ^(about 9 MB^)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol='Tls12'; New-Item -ItemType Directory -Force '%ROOT%tools\maven' | Out-Null; Invoke-WebRequest 'https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.zip' -OutFile '%ROOT%tools\maven\maven.zip'; Expand-Archive '%ROOT%tools\maven\maven.zip' '%ROOT%tools\maven' -Force; Remove-Item '%ROOT%tools\maven\maven.zip'" >> "%LOG%" 2>&1
if not exist "%MVN%" (
  echo       Download failed - check the internet connection. Details in logs\setup-java.log
  echo FAILED: maven download >> "%RESULT%" & pause & exit /b 1
)
echo       done.
:mvn_ok

echo [3/3] Spring Boot libraries ^(a few minutes the first time^)...
call "%MVN%" -B -f "%ROOT%server-java\pom.xml" dependency:copy-dependencies -DoutputDirectory=target\libs >> "%LOG%" 2>&1
if errorlevel 1 (
  echo       Download of the libraries failed. Details in logs\setup-java.log
  echo FAILED: libraries > "%RESULT%"
  powershell -NoProfile -Command "Get-Content '%LOG%' -Tail 25" >> "%RESULT%"
  pause & exit /b 1
)
set /a N=0
for %%f in ("%ROOT%server-java\target\libs\*.jar") do set /a N+=1
echo       %N% libraries downloaded.
(echo OK & echo JAVA_HOME=%JAVA_HOME% & echo libraries=%N%) > "%RESULT%"
"%JAVA_HOME%\bin\java.exe" -version >> "%RESULT%" 2>&1
echo.
echo  Done. Tell Claude: "Java setup OK".
echo.
pause
exit /b 0
