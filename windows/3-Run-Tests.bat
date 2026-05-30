@echo off
REM ===========================================================================
REM  Run the automated test suite (optional). (Windows)
REM ===========================================================================
setlocal
call "%~dp0_find_rscript.bat"
if not defined RSCRIPT goto :norscript
"%RSCRIPT%" "%~dp0..\R\run_tests.R"
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
