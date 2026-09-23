@echo off
setlocal EnableDelayedExpansion
title Toolkit Da Dung Cho Windows
color 0B

:: ============================================================
::  LAUNCHER.CMD
::  - Tu nang quyen Administrator neu can
::  - Xac thuc mat khau bang SHA-256 hash (khong luu plaintext)
::  - Tai ToolkitCore.ps1 ve %TEMP% va chay
::  - Tu xoa script tai %TEMP% khi thoat
:: ============================================================

:: ---- 1. Kiem tra / tu nang quyen Administrator ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Dang yeu cau quyen Administrator...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---- 2. Xac thuc mat khau (so sanh SHA-256 hash) ----
:: TODO: thay CORRECT_HASH bang hash SHA-256 thuc te cua mat khau anh chon.
:: Tao hash bang PowerShell:
::   (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('MAT_KHAU_CUA_BAN'))) -Algorithm SHA256).Hash
set "CORRECT_HASH=REPLACE_WITH_YOUR_SHA256_HASH"
set "MAX_TRY=3"
set "TRY=0"

:ASK_PASSWORD
set /p "PWD_INPUT=Nhap mat khau de tiep tuc: "

for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('%PWD_INPUT%'))) -Algorithm SHA256).Hash"`) do set "INPUT_HASH=%%H"

if /I "!INPUT_HASH!"=="!CORRECT_HASH!" goto PASSWORD_OK

set /a TRY+=1
if !TRY! GEQ !MAX_TRY! (
    echo Sai mat khau qua so lan cho phep. Dong cong cu.
    timeout /t 2 >nul
    exit /b
)
echo Mat khau khong dung. Con lai !MAX_TRY!-!TRY! lan thu.
goto ASK_PASSWORD

:PASSWORD_OK
echo Xac thuc thanh cong.

:: ---- 3. Tai ToolkitCore.ps1 ve %TEMP% ----
:: TODO: thay bang URL host thuc te cua ban (vd https://haiit.theworkpc.com/tools/ToolkitCore.ps1)
set "PS_URL=https://haiit.theworkpc.com/tools/ToolkitCore.ps1"
set "PS_PATH=%temp%\ToolkitCore_%RANDOM%.ps1"

echo Dang tai script chinh...
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%PS_URL%' -OutFile '%PS_PATH%' -UseBasicParsing } catch { exit 1 }"

if not exist "%PS_PATH%" (
    echo Khong the tai script. Kiem tra ket noi mang hoac URL cau hinh.
    pause
    exit /b
)

:: ---- 4. Chay script chinh ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_PATH%"

:: ---- 5. Don dep: xoa script tai %TEMP% ----
if exist "%PS_PATH%" del /f /q "%PS_PATH%" >nul 2>&1

endlocal
exit /b
