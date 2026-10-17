@echo off
setlocal
set "SESSION_ID=%RANDOM%%RANDOM%"
set "TOOLKIT_SESSION_ID=%SESSION_ID%"
set "WINTITLE=Toolkit IT Windows [%SESSION_ID%] - Developed by Mr.Hai"

:: Kiem tra quyen Admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit
)

title %WINTITLE%
color 0B

:: Goi file launcher.ps1 (cung thu muc voi file cmd nay)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1"

:: Don dep cac file rac
del /f /q "%temp%\ToolkitCore_%SESSION_ID%.ps1" >nul 2>&1
for %%P in (PrinterFixTool UC20 CanchinhOffice HardwareTest 1398) do del /f /q "%temp%\%%P_*.exe" >nul 2>&1

:: Xoa file launcher.cmd hien tai va thoat
(goto) 2>nul & del /f /q "%~f0" & exit
