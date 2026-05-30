@echo off
REM ===========================================================================
REM  Step 1: install the R packages this tool needs (run once). (Windows)
REM ===========================================================================
setlocal
call "%~dp0_find_rscript.bat"
if not defined RSCRIPT goto :norscript
"%RSCRIPT%" "%~dp0..\install_packages.R"
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
