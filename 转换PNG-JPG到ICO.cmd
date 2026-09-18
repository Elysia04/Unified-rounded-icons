@echo off
rem ===================================================================
rem  Drop PNG/JPG files onto THIS file to convert them to rounded icons.
rem  Do NOT drop onto a .ps1 file: Windows will not run a .ps1.
rem  The converter script lives in the _engine subfolder; leave it there.
rem
rem  Every run first writes "launcher started" into
rem  _engine\last-run.log, and ends by recording the exit code there.
rem ===================================================================
setlocal
set "SCRIPT=%~dp0_engine\png-jpg-to-ico.ps1"
set "LOG=%~dp0_engine\last-run.log"

rem A space before the redirection operator matters: with a digit
rem immediately before ">>" cmd would read it as a stdin redirection
rem and silently drop both the text and the redirect.
echo [%DATE% %TIME%] launcher started > "%LOG%"
echo   script: %SCRIPT% > "%LOG%"

if not exist "%SCRIPT%" goto :noscript

rem %* is passed through exactly as the shell handed it over, quotes included.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set RC=%ERRORLEVEL%
echo [%DATE% %TIME%] exit code: %RC% >> "%LOG%"

echo.
echo Exit code: %RC%
if not "%RC%"=="0" goto :failed
echo Done. The .ico files are in the folder next to this file.
goto :finish

:failed
echo Something went wrong. The reason is printed above and is also
echo recorded in _engine\last-run.log
goto :finish

:noscript
echo.
echo [ERROR] Converter script not found. Expected it here:
echo   %SCRIPT%
echo Keep this .cmd file in the same folder as the _engine folder.

:finish
echo.
echo This window stays open on purpose. Read the text above, then press any key.
pause >nul
endlocal
