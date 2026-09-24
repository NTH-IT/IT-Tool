@echo off
setlocal EnableDelayedExpansion

:: ============================================================
::  LAUNCHER.CMD - Toolkit Da Dung Cho Windows
::  Phat trien boi Mr.Hai
:: ============================================================

:: ---- Che do dac biet: day la tien trinh watchdog ngam ----
if "%~1"=="__WATCHDOG__" (
    call :DoWatchdog "%~2" "%~3" "%~4"
    exit /b
)

set "SESSION_ID=%RANDOM%%RANDOM%"
set "WINTITLE=Toolkit Da Dung Cho Windows [%SESSION_ID%] - Phat trien boi Mr.Hai"
title %WINTITLE%
color 0B

:: ---- 1. Kiem tra / tu nang quyen Administrator ----
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Dang yeu cau quyen Administrator...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: ---- 2. Xac thuc mat khau (nhap an, hien dau * ) ----
:: Ma hoa Base64 cua script PowerShell doc mat khau an (khong luu plaintext script rieng)
set "READPASS_B64=JABwAD0AIgAiAAoAVwByAGkAdABlAC0ASABvAHMAdAAgAC0ATgBvAE4AZQB3AGwAaQBuAGUAIAAiAE4AaABhAHAAIABtAGEAdAAgAGsAaABhAHUAOgAgACIACgB3AGgAaQBsAGUAKAAkAHQAcgB1AGUAKQB7AAoAIAAgACQAawA9AFsAQwBvAG4AcwBvAGwAZQBdADoAOgBSAGUAYQBkAEsAZQB5ACgAJAB0AHIAdQBlACkACgAgACAAaQBmACgAJABrAC4ASwBlAHkAIAAtAGUAcQAgACIARQBuAHQAZQByACIAKQB7ACAAVwByAGkAdABlAC0ASABvAHMAdAAgACIAIgA7ACAAYgByAGUAYQBrACAAfQAKACAAIABlAGwAcwBlAGkAZgAoACQAawAuAEsAZQB5ACAALQBlAHEAIAAiAEUAcwBjAGEAcABlACIAKQB7ACAAVwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIAAiACMAIwBFAFMAQwAjACMAIgA7ACAAZQB4AGkAdAAgAH0ACgAgACAAZQBsAHMAZQBpAGYAKAAkAGsALgBLAGUAeQAgAC0AZQBxACAAIgBCAGEAYwBrAHMAcABhAGMAZQAiACkAewAKACAAIAAgACAAaQBmACgAJABwAC4ATABlAG4AZwB0AGgAIAAtAGcAdAAgADAAKQB7AAoAIAAgACAAIAAgACAAJABwAD0AJABwAC4AUwB1AGIAcwB0AHIAaQBuAGcAKAAwACwAJABwAC4ATABlAG4AZwB0AGgALQAxACkACgAgACAAIAAgACAAIAAkAHAAbwBzAD0AWwBDAG8AbgBzAG8AbABlAF0AOgA6AEMAdQByAHMAbwByAEwAZQBmAHQACgAgACAAIAAgACAAIABbAEMAbwBuAHMAbwBsAGUAXQA6ADoAUwBlAHQAQwB1AHIAcwBvAHIAUABvAHMAaQB0AGkAbwBuACgAJABwAG8AcwAtADEALABbAEMAbwBuAHMAbwBsAGUAXQA6ADoAQwB1AHIAcwBvAHIAVABvAHAAKQAKACAAIAAgACAAIAAgAFsAQwBvAG4AcwBvAGwAZQBdADoAOgBXAHIAaQB0AGUAKAAiACAAIgApAAoAIAAgACAAIAAgACAAWwBDAG8AbgBzAG8AbABlAF0AOgA6AFMAZQB0AEMAdQByAHMAbwByAFAAbwBzAGkAdABpAG8AbgAoACQAcABvAHMALQAxACwAWwBDAG8AbgBzAG8AbABlAF0AOgA6AEMAdQByAHMAbwByAFQAbwBwACkACgAgACAAIAAgAH0ACgAgACAAfQAKACAAIABlAGwAcwBlACAAewAgACQAcAArAD0AJABrAC4ASwBlAHkAQwBoAGEAcgA7ACAAWwBDAG8AbgBzAG8AbABlAF0AOgA6AFcAcgBpAHQAZQAoACIAKgAiACkAIAB9AAoAfQAKAFcAcgBpAHQAZQAtAE8AdQB0AHAAdQB0ACAAJABwAAoA"

set "CORRECT_HASH=499BC7DF9D8873C1C38E6898177C343B2A34D2EB43178A9EB4EFCB993366C8CD"
set "MAX_TRY=3"
set "TRY=0"

:ASK_PASSWORD
for /f "usebackq delims=" %%P in (`powershell -NoProfile -EncodedCommand "!READPASS_B64!"`) do set "PWD_INPUT=%%P"

if "!PWD_INPUT!"=="##ESC##" (
    echo Da huy. Dong cong cu.
    exit /b
)

for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "(Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes('!PWD_INPUT!'))) -Algorithm SHA256).Hash"`) do set "INPUT_HASH=%%H"

if /I "!INPUT_HASH!"=="!CORRECT_HASH!" goto PASSWORD_OK

set /a TRY+=1
if !TRY! GEQ !MAX_TRY! (
    echo Sai mat khau qua so lan cho phep. Dong cong cu.
    timeout /t 2 >nul
    exit /b
)
echo Mat khau khong dung. Con lai !MAX_TRY!-!TRY! lan thu ^(ESC de thoat^).
goto ASK_PASSWORD

:PASSWORD_OK
echo Xac thuc thanh cong.

:: ---- 3. Tai ToolkitCore.ps1 (dung jsDelivr CDN, nhanh hon raw.githubusercontent.com) ----
set "PS_URL=https://cdn.jsdelivr.net/gh/NTH-IT/IT-Tool@main/ToolkitCore.ps1"
set "PS_PATH=%temp%\ToolkitCore_%SESSION_ID%.ps1"

echo Dang tai script chinh...
powershell -NoProfile -Command "try { Invoke-WebRequest -Uri '%PS_URL%' -OutFile '%PS_PATH%' -UseBasicParsing } catch { exit 1 }"

if not exist "%PS_PATH%" (
    echo Khong the tai script. Kiem tra ket noi mang hoac URL cau hinh.
    pause
    exit /b
)

:: ---- 4. Khoi chay watchdog ngam (start /b) - dam bao don dep du dong bang nut X ----
set "CLEANLIST=%temp%\toolkit_cleanlist_%SESSION_ID%.lst"
> "%CLEANLIST%" (
    echo %PS_PATH%
    echo %~f0
)
start "" /b cmd /c ""%~f0" __WATCHDOG__ "%WINTITLE%" "%CLEANLIST%" "%SESSION_ID%""

:: ---- 5. Chay script chinh (truyen SESSION_ID de ToolkitCore.ps1 biet bien the) ----
set "TOOLKIT_SESSION_ID=%SESSION_ID%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_PATH%"

:: ---- 6. Don dep truc tiep khi thoat binh thuong (watchdog se don dep du phong neu buoc nay khong chay toi, vd dong bang X) ----
if exist "%PS_PATH%" del /f /q "%PS_PATH%" >nul 2>&1
if exist "%CLEANLIST%" del /f /q "%CLEANLIST%" >nul 2>&1
del /f /q "%temp%\PrinterFixTool_*.exe" >nul 2>&1

endlocal
exit /b

:: ============================================================
:: SUBROUTINE: DoWatchdog
:: Chay ngam (start /b), theo doi cua so console theo WINTITLE.
:: Khi cua so bien mat (dong bang nut X hoac thoat binh thuong),
:: tu dong xoa toan bo file tam: ToolkitCore.ps1, PrinterFixTool.exe,
:: file danh sach, va chinh launcher.cmd (neu dang chay tu %temp%).
:: ============================================================
:DoWatchdog
setlocal EnableDelayedExpansion
set "WT=%~1"
set "LSTFILE=%~2"
set "SID=%~3"

:WD_LOOP
timeout /t 2 /nobreak >nul
tasklist /v /fo csv 2>nul | find /i "%WT%" >nul
if %errorlevel%==0 goto WD_LOOP

:: Cua so chinh da dong -> don dep toan bo
if exist "%LSTFILE%" (
    for /f "usebackq delims=" %%F in ("%LSTFILE%") do (
        if exist "%%F" del /f /q "%%F" >nul 2>&1
    )
    del /f /q "%LSTFILE%" >nul 2>&1
)
del /f /q "%temp%\PrinterFixTool_*.exe" >nul 2>&1
del /f /q "%temp%\ToolkitCore_%SID%.ps1" >nul 2>&1

endlocal
exit /b
