# ==========================================
# LAUNCHER.PS1 - Xử lý mật khẩu và tải Toolkit
# ==========================================
$ErrorActionPreference = 'Stop'

# 1. Kiểm tra mật khẩu
$CORRECT_HASH = "499BC7DF9D8873C1C38E6898177C343B2A34D2EB43178A9EB4EFCB993366C8CD"
$MAX_TRY = 3

for ($i = 0; $i -lt $MAX_TRY; $i++) {
    $ss = Read-Host "Nhap mat khau" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    
    $ms = [IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes($plain))
    $hash = (Get-FileHash -InputStream $ms -Algorithm SHA256).Hash
    $ms.Dispose()
    
    if ($hash -ieq $CORRECT_HASH) {
        Write-Host "Xac thuc thanh cong." -ForegroundColor Green
        break
    }
    
    $remain = $MAX_TRY - $i - 1
    if ($remain -gt 0) {
        Write-Host "Sai mat khau. Con lai $remain lan." -ForegroundColor Yellow
    } else {
        Write-Host "Qua so lan cho phep. Dong cua so..." -ForegroundColor Red
        Start-Sleep 2
        exit
    }
}

# 2. Tải và chạy ToolkitCore.ps1
$PS_URL = "https://cdn.jsdelivr.net/gh/NTH-IT/IT-Tool@main/ToolkitCore.ps1"
$PS_PATH = "$env:TEMP\ToolkitCore_$env:TOOLKIT_SESSION_ID.ps1"

Write-Host "Dang tai script chinh..." -ForegroundColor Yellow
try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $PS_URL -OutFile $PS_PATH -UseBasicParsing
} catch {
    Write-Host "Khong the tai script: $_" -ForegroundColor Red
    Read-Host "Nhan Enter de thoat"
    exit
}

if (-not (Test-Path $PS_PATH)) {
    Write-Host "Loi: file khong ton tai." -ForegroundColor Red
    Read-Host "Nhan Enter de thoat"
    exit
}

# 3. Chạy script chính
& $PS_PATH

# 4. Dọn dẹp file sau khi chạy xong
Remove-Item $PS_PATH -Force -ErrorAction SilentlyContinue