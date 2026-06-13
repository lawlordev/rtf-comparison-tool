@echo off
REM ===========================================================================
REM  View the AUDIT LOG (Windows)
REM  Opens logs\audit_log.csv -- the timestamped record of every comparison run
REM  (including runs that found no differences). Open it in Excel to see, sort,
REM  or print proof of which files/folders were checked and when.
REM ===========================================================================
setlocal
set "LOG=%~dp0..\logs\audit_log.csv"
if not exist "%LOG%" (
  echo No audit log yet: %LOG%
  echo It is created automatically the first time you run a comparison.
  pause
  exit /b 0
)
echo Opening audit log: %LOG%
start "" "%LOG%"
exit /b 0
