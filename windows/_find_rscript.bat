@echo off
REM Helper: locate Rscript.exe and set the RSCRIPT variable for the caller.
REM (No setlocal here, so RSCRIPT persists back to the launcher that calls it.)
set "RSCRIPT="
for /f "delims=" %%I in ('where Rscript.exe 2^>nul') do if not defined RSCRIPT set "RSCRIPT=%%I"
if defined RSCRIPT goto :eof
for /d %%D in ("%ProgramFiles%\R\R-*") do if exist "%%D\bin\x64\Rscript.exe" set "RSCRIPT=%%D\bin\x64\Rscript.exe"
if not defined RSCRIPT for /d %%D in ("%ProgramFiles%\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
if not defined RSCRIPT for /d %%D in ("%ProgramFiles(x86)%\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
if not defined RSCRIPT for /d %%D in ("%LOCALAPPDATA%\Programs\R\R-*") do if exist "%%D\bin\Rscript.exe" set "RSCRIPT=%%D\bin\Rscript.exe"
goto :eof
