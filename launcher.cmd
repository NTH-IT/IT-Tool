@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
set "SESSION_ID=%RANDOM%%RANDOM%"
set "TOOLKIT_SESSION_ID=%SESSION_ID%"
set "WINTITLE=Toolkit Da Dung Cho Windows [%SESSION_ID%] - Phat trien boi Mr.Hai"

:: 1. Kiem tra quyen Admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

title %WINTITLE%
color 0B

:: 2. Tao file PowerShell tam thoi de xu ly (Tranh loi font/encode)
set "PS_TEMP_FILE=%TEMP%\launcher_%SESSION_ID%.ps1"

(
echo $ErrorActionPreference = 'Stop'
echo $CORRECT_HASH = "499BC7DF9D8873C1C38E6898177C343B2A34D2EB43178A9EB4EFCB993366C8CD"
echo $MAX_TRY = 3
echo for ($i=0; $i -lt $MAX_TRY; $i++) {
echo     $ss = Read-Host "Nhap mat khau" -AsSecureString
echo     $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
echo     $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
echo     [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
echo     $ms = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($plain))
echo     $hash = (Get-FileHash -InputStream $ms -Algorithm SHA256).Hash
echo     $ms.Dispose()
echo     if ($hash -ieq $CORRECT_HASH) { Write-Host "Xac thuc thanh cong." -ForegroundColor Green; break }
echo     $remain = $MAX_TRY - $i - 1
echo     if ($remain -gt 0) { Write-Host "Sai mat khau. Con lai $remain lan." -ForegroundColor Yellow }
echo     else { Write-Host "Qua so lan cho phep. Dong cua so..." -ForegroundColor Red; Start-Sleep 2; exit }
echo }
echo $PS_URL = "https://cdn.jsdelivr.net/gh/NTH-IT/IT-Tool@main/ToolkitCore.ps1"
echo $PS_PATH = "$env:TEMP\ToolkitCore_$env:TOOLKIT_SESSION_ID.ps1"
echo Write-Host "Dang tai script chinh..." -ForegroundColor Yellow
echo try {
echo     $ProgressPreference = 'SilentlyContinue'
echo     Invoke-WebRequest -Uri $PS_URL -OutFile $PS_PATH -UseBasicParsing
echo     ^& $PS_PATH
echo } catch {
echo     Write-Host "Khong the tai hoac chay script: $_" -ForegroundColor Red
echo     Read-Host "Nhan Enter de thoat"
echo }
) > "%PS_TEMP_FILE%"

:: 3. Chay file PowerShell tam thoi
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_TEMP_FILE%"

:: 4. Don dep
del /f /q "%PS_TEMP_FILE%" >nul 2>&1
del /f /q "%temp%\ToolkitCore_%SESSION_ID%.ps1" >nul 2>&1
for %%P in (PrinterFixTool UC20 CanchinhOffice HardwareTest 1398) do del /f /q "%temp%\%%P_*.exe" >nul 2>&1

:: 5. Giu cua so lai de xem ket qua (khong xoa file cmd)
echo.
echo ========================================================
echo Phien lam viec ket thuc. Cua so se tu dong dong...
echo ========================================================
timeout /t 2 >nul
exit /b
