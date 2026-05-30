@echo off
REM ===========================================================================
REM  Compare two RTF files by PATH (Windows)
REM  Double-click this file, then paste/type the two file paths when prompted.
REM  A report is saved next to the first file.
REM  (Prefer clicking files instead? Use 2b-Compare-Using-File-Picker.bat.)
REM ===========================================================================
setlocal
call "%~dp0_find_rscript.bat"
if not defined RSCRIPT goto :norscript
"%RSCRIPT%" "%~dp0..\run_compare_paths.R"
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
