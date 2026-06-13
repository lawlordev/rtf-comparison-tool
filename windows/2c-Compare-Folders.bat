@echo off
REM ===========================================================================
REM  BATCH compare two FOLDERS of RTF files (Windows)
REM  Double-click this file. Pick a reference folder, then a comparison folder.
REM  Every .rtf file is compared against its same-named file in the other folder.
REM  ONE report (listing every file, including matches) is archived in the tool's
REM  logs\ folder and every run is recorded in logs\audit_log.csv.
REM  Keep the whole tool folder intact so it can find its logs\ folder.
REM ===========================================================================
setlocal
call "%~dp0_find_rscript.bat"
if not defined RSCRIPT goto :norscript
"%RSCRIPT%" "%~dp0..\R\run_compare_folder.R"
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
