@echo off
REM ===========================================================================
REM  Compare two RTF files using FILE-PICKER dialogs (Windows)
REM  Alternative to 2-Compare-RTF-Files.bat for those who prefer clicking
REM  files instead of pasting paths. Two dialogs appear; pick the two files.
REM ===========================================================================
setlocal
call "%~dp0_find_rscript.bat"
if not defined RSCRIPT goto :norscript
"%RSCRIPT%" "%~dp0..\run_compare.R"
echo.
pause
exit /b %ERRORLEVEL%

:norscript
echo.
echo Could not find R on this computer.
echo Please install R from https://cran.r-project.org/bin/windows/base/ and try again.
echo.
pause
exit /b 2
