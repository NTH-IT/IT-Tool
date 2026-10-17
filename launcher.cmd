@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
set "SESSION_ID=%RANDOM%%RANDOM%"
set "TOOLKIT_SESSION_ID=%SESSION_ID%"
set "WINTITLE=Toolkit Da Dung Cho Windows [%SESSION_ID%] - Developed by Mr.Hai"

:: Kiem tra quyen Admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

title %WINTITLE%
color 0B

:: Goi file launcher.ps1 (cung thu muc)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0launcher.ps1"

:: Don dep cac file rac
del /f /q "%temp%\ToolkitCore_%SESSION_ID%.ps1" >nul 2>&1
for %%P in (PrinterFixTool UC20 CanchinhOffice HardwareTest 1398) do del /f /q "%temp%\%%P_*.exe" >nul 2>&1

:: Xoa sach man hinh
cls

:: Tu xoa file launcher.cmd tam va thoat
(goto) 2>nul & del /f /q "%~f0" & exit