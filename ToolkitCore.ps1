# ============================================================
#  BO CONG CU DA DUNG CHO WINDOWS - CORE SCRIPT (PowerShell)
#  Luu y: script nay thuc hien nhieu thay doi he thong (mang,
#  ban quyen, Windows Update...). Chi chay tren may duoc phep
#  quan tri va da duoc xac thuc boi launcher.cmd.
# ============================================================

$ErrorActionPreference = "SilentlyContinue"
$LogFile = "$env:TEMP\toolkit_actions_$(Get-Date -Format yyyyMMdd_HHmmss).log"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $env:USERNAME | $Message"
    Add-Content -Path $LogFile -Value $line
}

function Confirm-Action {
    param([string]$Prompt)
    Write-Host ""
    Write-Host "CANH BAO: $Prompt" -ForegroundColor Yellow
    $resp = Read-Host "Go YES de xac nhan tiep tuc"
    return ($resp -eq "YES")
}

function Pause-Return {
    Write-Host ""
    Read-Host "Nhan Enter de quay lai menu" | Out-Null
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin)) {
    Write-Host "Script can chay voi quyen Administrator. Vui long chay lai launcher voi quyen admin." -ForegroundColor Red
    Pause-Return
    exit
}

# ============================================================
# 1. NETWORK TROUBLESHOOT
# ============================================================

function Show-NetworkInfo {
    Clear-Host
    Write-Host "=== THONG TIN MANG HIEN TAI ===" -ForegroundColor Cyan
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "Hostname : $($cs.Name)"
    Write-Host "Domain/Workgroup : $($cs.Domain)  (PartOfDomain: $($cs.PartOfDomain))"
    Write-Host ""
    Get-NetIPConfiguration | ForEach-Object {
        Write-Host "-- Adapter: $($_.InterfaceAlias) --"
        Write-Host "  IPv4      : $($_.IPv4Address.IPAddress)"
        Write-Host "  Gateway   : $($_.IPv4DefaultGateway.NextHop)"
        Write-Host "  DNS       : $($_.DNSServer.ServerAddresses -join ', ')"
    }
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
        Write-Host "  MAC ($($_.Name)): $($_.MacAddress)"
    }
    Write-Log "Xem thong tin mang"
    Pause-Return
}

function Set-ComputerNameDomain {
    Clear-Host
    Write-Host "=== DOI TEN MAY / DOMAIN ===" -ForegroundColor Cyan
    $newName = Read-Host "Nhap Hostname moi (de trong = bo qua)"
    $newDomainOrWorkgroup = Read-Host "Nhap Domain/Workgroup moi (de trong = bo qua)"

    if (-not (Confirm-Action "Doi ten may/domain se yeu cau KHOI DONG LAI may.")) { return }

    if ($newName -ne "") {
        Rename-Computer -NewName $newName -Force
        Write-Log "Doi hostname thanh $newName"
    }
    if ($newDomainOrWorkgroup -ne "") {
        $cred = Get-Credential -Message "Nhap tai khoan co quyen join domain (bo trong neu doi workgroup)"
        try {
            Add-Computer -DomainName $newDomainOrWorkgroup -Credential $cred -Force -ErrorAction Stop
            Write-Log "Join domain $newDomainOrWorkgroup"
        } catch {
            Add-Computer -WorkgroupName $newDomainOrWorkgroup -Force
            Write-Log "Doi workgroup thanh $newDomainOrWorkgroup"
        }
    }
    Write-Host "Hoan tat. Vui long khoi dong lai may de ap dung." -ForegroundColor Green
    Pause-Return
}

function Reset-IPAddress {
    Clear-Host
    Write-Host "=== XOA IP CU / NHAN IP MOI ===" -ForegroundColor Cyan
    ipconfig /release
    ipconfig /flushdns
    ipconfig /registerdns
    netsh winsock reset
    netsh int ip reset
    ipconfig /renew
    Write-Log "Reset IP: release/flushdns/registerdns/winsock/int-ip/renew"
    Write-Host "Da thuc hien xong. Neu doi winsock/int ip, nen khoi dong lai may." -ForegroundColor Green
    Pause-Return
}

function Set-StaticIP {
    Clear-Host
    Write-Host "=== DAT IP TINH ===" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceIndex -AutoSize
    $idx = Read-Host "Nhap InterfaceIndex muon cau hinh"
    $ip = Read-Host "Nhap dia chi IP (vd 192.168.1.50)"
    $prefix = Read-Host "Nhap Prefix length (vd 24 cho /24)"
    $gw = Read-Host "Nhap Default Gateway (vd 192.168.1.1)"

    if (-not (Confirm-Action "Se xoa cau hinh IP cu tren interface $idx va dat IP tinh moi.")) { return }

    Remove-NetIPAddress -InterfaceIndex $idx -Confirm:$false
    Remove-NetRoute -InterfaceIndex $idx -Confirm:$false
    New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw
    Write-Log "Dat IP tinh $ip/$prefix gw $gw tren interface $idx"
    Write-Host "Da dat IP tinh." -ForegroundColor Green
    Pause-Return
}

function Set-StaticDNS {
    Clear-Host
    Write-Host "=== DAT DNS TINH ===" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceIndex -AutoSize
    $idx = Read-Host "Nhap InterfaceIndex muon cau hinh"
    $dns1 = Read-Host "Nhap DNS uu tien (vd 8.8.8.8)"
    $dns2 = Read-Host "Nhap DNS thay the (de trong = bo qua)"

    $dnsList = @($dns1)
    if ($dns2 -ne "") { $dnsList += $dns2 }

    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $dnsList
    Write-Log "Dat DNS $($dnsList -join ', ') tren interface $idx"
    Write-Host "Da dat DNS tinh." -ForegroundColor Green
    Pause-Return
}

function Reset-NetworkFull {
    Clear-Host
    Write-Host "=== RESET MANG VE MAC DINH ===" -ForegroundColor Cyan
    if (-not (Confirm-Action "Se xoa cau hinh mang, Data Usage, log, va dat mang ve mac dinh. KHONG THE HOAN TAC.")) { return }

    netsh winsock reset
    netsh int ip reset
    netsh advfirewall reset
    # Xoa Data Usage
    Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\NetworkList" -ErrorAction SilentlyContinue | Out-Null
    net stop dosvc 2>$null
    Remove-Item "$env:ProgramData\Microsoft\Windows\FileHistory\*" -Recurse -Force -ErrorAction SilentlyContinue
    net start dosvc 2>$null
    Write-Log "Reset toan bo cau hinh mang ve mac dinh"
    Write-Host "Da reset. Khuyen nghi khoi dong lai may." -ForegroundColor Green
    Pause-Return
}

function Menu-Network {
    do {
        Clear-Host
        Write-Host "===== 1. NETWORK TROUBLESHOOT =====" -ForegroundColor Cyan
        Write-Host "1. Kiem tra thong tin mang hien tai"
        Write-Host "2. Dat lai ten may (Hostname/Domain)"
        Write-Host "3. Xoa IP cu, nhan IP moi"
        Write-Host "4. Dat IP tinh"
        Write-Host "5. Dat DNS tinh"
        Write-Host "6. Reset mang ve mac dinh"
        Write-Host "0. Back"
        $c = Read-Host "Chon"
        switch ($c) {
            "1" { Show-NetworkInfo }
            "2" { Set-ComputerNameDomain }
            "3" { Reset-IPAddress }
            "4" { Set-StaticIP }
            "5" { Set-StaticDNS }
            "6" { Reset-NetworkFull }
        }
    } while ($c -ne "0")
}

# ============================================================
# 2. PRINTER & FILE SHARING
# ============================================================

function Test-FileSharingLan {
    Clear-Host
    Write-Host "=== CHAN DOAN CHIA SE FILE QUA LAN ===" -ForegroundColor Cyan
    Write-Host "-- Network Discovery / File Sharing profile --"
    Get-NetFirewallRule -DisplayGroup "Network Discovery" | Select-Object DisplayName, Enabled | Format-Table -AutoSize
    Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | Select-Object DisplayName, Enabled | Format-Table -AutoSize
    Write-Host "-- Service Server (chia se file) --"
    Get-Service LanmanServer | Format-Table Name, Status, StartType -AutoSize
    Write-Host "-- Service Workstation --"
    Get-Service LanmanWorkstation | Format-Table Name, Status, StartType -AutoSize
    Write-Host "-- SMB Server Configuration (SMB1/2/3) --"
    Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol | Format-List
    Write-Log "Chan doan file sharing LAN"
    Pause-Return
}

function Test-PrinterPipeline {
    Clear-Host
    Write-Host "=== CHAN DOAN MAY IN (Server -> RPC -> SMB -> Spooler -> Firewall -> Share -> Driver -> Port -> Policy) ===" -ForegroundColor Cyan

    Write-Host "`n[1] Server service (LanmanServer):"
    Get-Service LanmanServer | Format-Table Name, Status, StartType -AutoSize

    Write-Host "[2] RPC service:"
    Get-Service RpcSs, RpcEptMapper | Format-Table Name, Status, StartType -AutoSize

    Write-Host "[3] SMB client/server config:"
    Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol | Format-List

    Write-Host "[4] Print Spooler service:"
    Get-Service Spooler | Format-Table Name, Status, StartType -AutoSize

    Write-Host "[5] Firewall rules lien quan may in:"
    Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | Select-Object DisplayName, Enabled | Format-Table -AutoSize

    Write-Host "[6] Printer share hien co:"
    Get-Printer | Where-Object Shared -eq $true | Format-Table Name, ShareName -AutoSize

    Write-Host "[7] Driver may in da cai:"
    Get-PrinterDriver | Format-Table Name, Manufacturer -AutoSize

    Write-Host "[8] Port may in:"
    Get-PrinterPort | Format-Table Name, PrinterHostAddress -AutoSize

    Write-Host "[9] Group Policy lien quan Point and Print:"
    $ppKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
    if (Test-Path $ppKey) { Get-ItemProperty $ppKey } else { Write-Host "  (Khong co policy tuy chinh)" }

    Write-Log "Chan doan pipeline may in"
    Pause-Return
}

function Run-PrinterFixTool {
    Clear-Host
    Write-Host "=== TAI VA CHAY PrinterFixTool.exe (Admin) ===" -ForegroundColor Cyan

    # TODO: thay bang URL host thuc te (vd https://haiit.theworkpc.com/tools/PrinterFixTool.exe)
    $toolUrl  = "https://haiit.theworkpc.com/tools/PrinterFixTool.exe"
    $toolPath = "$env:TEMP\PrinterFixTool_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"

    try {
        Invoke-WebRequest -Uri $toolUrl -OutFile $toolPath -UseBasicParsing -ErrorAction Stop

        # Kiem tra toan ven file truoc khi chay (khuyen nghi: so sanh SHA256 voi hash da biet)
        $hash = (Get-FileHash -Path $toolPath -Algorithm SHA256).Hash
        Write-Log "Da tai PrinterFixTool.exe, SHA256=$hash"

        Start-Process -FilePath $toolPath -Verb RunAs -Wait
        Write-Log "Da chay PrinterFixTool.exe voi quyen admin"
    } catch {
        Write-Host "Loi khi tai/chay file: $_" -ForegroundColor Red
    } finally {
        if (Test-Path $toolPath) {
            Remove-Item $toolPath -Force -ErrorAction SilentlyContinue
            Write-Log "Da xoa PrinterFixTool.exe sau khi chay"
        }
    }
    Pause-Return
}

function Menu-PrinterSharing {
    do {
        Clear-Host
        Write-Host "===== 2. PRINTER & FILE SHARING =====" -ForegroundColor Cyan
        Write-Host "1. Chan doan chia se file qua LAN"
        Write-Host "2. Chan doan cai dat may in (pipeline)"
        Write-Host "3. Chay PrinterFixTool.exe (tai va chay quyen admin, tu xoa)"
        Write-Host "0. Back"
        $c = Read-Host "Chon"
        switch ($c) {
            "1" { Test-FileSharingLan }
            "2" { Test-PrinterPipeline }
            "3" { Run-PrinterFixTool }
        }
    } while ($c -ne "0")
}

# ============================================================
# 3. SYSTEM INFO & ACTIVATION
# ============================================================

function Show-SoftwareInfo {
    Clear-Host
    Write-Host "=== THONG TIN PHAN MEM ===" -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "Ten may       : $($cs.Name)"
    Write-Host "User dang dung: $env:USERNAME"
    Write-Host "Windows       : $($os.Caption) - Build $($os.BuildNumber)"
    Write-Host "Domain/WG     : $($cs.Domain)  (PartOfDomain: $($cs.PartOfDomain))"

    $officeReg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\*\Common\ProductVersion" -ErrorAction SilentlyContinue
    if ($officeReg) { Write-Host "Office version: $($officeReg.LastProduct)" }

    Get-NetIPConfiguration | ForEach-Object {
        Write-Host "IP ($($_.InterfaceAlias)): $($_.IPv4Address.IPAddress)  GW: $($_.IPv4DefaultGateway.NextHop)  DNS: $($_.DNSServer.ServerAddresses -join ', ')"
    }
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
        Write-Host "MAC ($($_.Name)): $($_.MacAddress)"
    }
    Write-Log "Xem thong tin phan mem"
    Pause-Return
}

function Show-HardwareInfo {
    Clear-Host
    Write-Host "=== THONG TIN PHAN CUNG ===" -ForegroundColor Cyan
    $cpu = Get-CimInstance Win32_Processor
    $ram = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $csProd = Get-CimInstance Win32_ComputerSystemProduct
    $os = Get-CimInstance Win32_OperatingSystem

    Write-Host "CPU        : $($cpu.Name)"
    Write-Host "RAM        : $([math]::Round($ram.TotalPhysicalMemory/1GB,2)) GB"
    Write-Host "Model may  : $($csProd.Vendor) $($csProd.Name)"
    Write-Host "Serial     : $($csProd.IdentifyingNumber)"
    Write-Host "BIOS ver   : $($bios.SMBIOSBIOSVersion)"

    Get-CimInstance Win32_DiskDrive | ForEach-Object {
        Write-Host "O cung     : $($_.Model) - $([math]::Round($_.Size/1GB,2)) GB"
    }

    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Host "Uptime     : $($uptime.Days) ngay $($uptime.Hours) gio $($uptime.Minutes) phut"
    Write-Log "Xem thong tin phan cung"
    Pause-Return
}

function Show-LicenseInfo {
    Clear-Host
    Write-Host "=== THONG TIN BAN QUYEN (Windows / Office) ===" -ForegroundColor Cyan
    Write-Host "-- Windows --"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli

    Write-Host "`n-- Office (neu co OSPP.VBS) --"
    $ospp = Get-ChildItem "C:\Program Files\Microsoft Office\Office*\ospp.vbs", "C:\Program Files (x86)\Microsoft Office\Office*\ospp.vbs" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ospp) {
        cscript //nologo $ospp.FullName /dstatus
    } else {
        Write-Host "  (Khong tim thay OSPP.VBS - co the Office dung Click-to-Run, dung 'cscript ospp.vbs' trong thu muc cai dat)"
    }
    Write-Log "Xem thong tin ban quyen"
    Pause-Return
}

function Check-LicenseKeyByMachine {
    Clear-Host
    Write-Host "=== KIEM TRA KEY BAN QUYEN THEO MAY (chi tiet) ===" -ForegroundColor Cyan
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dlv
    Write-Log "Kiem tra chi tiet key ban quyen theo may"
    Pause-Return
}

function Remove-LicenseExceptMachine {
    Clear-Host
    Write-Host "=== GO BO BAN QUYEN (giu lai ban quyen theo may / OEM digital license) ===" -ForegroundColor Cyan
    Write-Host "Thao tac nay se GO product key dang cai (vd MAK/KMS/Retail)." -ForegroundColor Yellow
    Write-Host "Neu may co OEM digital license gan voi phan cung, may se tu dong quay ve trang thai kich hoat do sau khi go key va ket noi internet." -ForegroundColor Yellow

    Write-Host "`nTrang thai truoc khi go:"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli

    if (-not (Confirm-Action "Ban chac chan muon GO product key Windows dang cai tren may nay?")) { return }

    Write-Log "Truoc khi go key: $(cscript //nologo "$env:windir\System32\slmgr.vbs" /dli)"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /upk
    cscript //nologo "$env:windir\System32\slmgr.vbs" /cpky
    Write-Log "Da go product key Windows (giu lai digital license neu co)"

    Write-Host "`nTrang thai sau khi go:"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    Pause-Return
}

function Menu-SystemInfo {
    do {
        Clear-Host
        Write-Host "===== 3. SYSTEM INFO & ACTIVATION =====" -ForegroundColor Cyan
        Write-Host "1. Thong tin phan mem"
        Write-Host "2. Thong tin phan cung"
        Write-Host "3. Thong tin ban quyen (Windows/Office)"
        Write-Host "4. Kiem tra key ban quyen theo may"
        Write-Host "5. Go bo ban quyen (giu lai theo may)"
        Write-Host "0. Back"
        $c = Read-Host "Chon"
        switch ($c) {
            "1" { Show-SoftwareInfo }
            "2" { Show-HardwareInfo }
            "3" { Show-LicenseInfo }
            "4" { Check-LicenseKeyByMachine }
            "5" { Remove-LicenseExceptMachine }
        }
    } while ($c -ne "0")
}

# ============================================================
# 4. SYSTEM MAINTENANCE
# ============================================================

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $size) { return 0 }
    return [math]::Round($size / 1MB, 2)
}

function Invoke-QuickClean {
    Clear-Host
    Write-Host "=== DON QUA (Quick Clean) ===" -ForegroundColor Cyan
    $targets = @(
        "$env:TEMP",
        "$env:windir\Temp",
        "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:APPDATA\Mozilla\Firefox\Profiles\*\cache2"
    )
    $totalBefore = 0
    foreach ($t in $targets) { $totalBefore += (Get-FolderSizeMB $t) }

    foreach ($t in $targets) {
        Remove-Item "$t\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    Write-Log "Don qua: xoa temp user/windows, cache trinh duyet, Recycle Bin"
    Write-Host "Da don xong. Uoc tinh da giai phong: ~$totalBefore MB" -ForegroundColor Green
    Pause-Return
}

function Invoke-DeepClean {
    Clear-Host
    Write-Host "=== DON KY (Deep Clean) ===" -ForegroundColor Cyan
    if (-not (Confirm-Action "Don ky se xoa Packages, LocalLow, SRUM, Data Usage, Event Log. Nen dong ung dung dang mo truoc khi tiep tuc.")) { return }

    $targets = @(
        "$env:TEMP",
        "$env:windir\Temp",
        "$env:LOCALAPPDATA\Packages",
        "$env:LOCALAPPDATA\Temp",
        "$env:USERPROFILE\AppData\LocalLow"
    )
    $totalBefore = 0
    foreach ($t in $targets) { $totalBefore += (Get-FolderSizeMB $t) }

    foreach ($t in $targets) {
        Remove-Item "$t\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue

    # Tat va xoa SRU (System Resource Usage), roi bat lai
    Stop-Service -Name DPS -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:windir\System32\sru\*" -Force -ErrorAction SilentlyContinue
    Start-Service -Name DPS -ErrorAction SilentlyContinue

    # Xoa Data Usage
    net stop dosvc 2>$null
    net start dosvc 2>$null

    # Xoa Event Log
    wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }

    Write-Log "Don ky: xoa temp/Packages/LocalLow/SRU/DataUsage/EventLog"
    Write-Host "Da don xong. Uoc tinh da giai phong: ~$totalBefore MB" -ForegroundColor Green
    Pause-Return
}

function Update-GPAndTimezone {
    Clear-Host
    Write-Host "=== CAP NHAT GROUP POLICY & TIMEZONE ===" -ForegroundColor Cyan
    gpupdate /force
    tzutil /s "SE Asia Standard Time"
    Write-Log "Cap nhat Group Policy va timezone (SE Asia Standard Time)"
    Write-Host "Da cap nhat xong." -ForegroundColor Green
    Pause-Return
}

function Menu-Maintenance {
    do {
        Clear-Host
        Write-Host "===== 4. SYSTEM MAINTENANCE =====" -ForegroundColor Cyan
        Write-Host "1. Don qua (Quick Clean)"
        Write-Host "2. Don ky (Deep Clean)"
        Write-Host "3. Cap nhat Group Policy va Timezone"
        Write-Host "0. Back"
        $c = Read-Host "Chon"
        switch ($c) {
            "1" { Invoke-QuickClean }
            "2" { Invoke-DeepClean }
            "3" { Update-GPAndTimezone }
        }
    } while ($c -ne "0")
}

# ============================================================
# 5. SOFTWARE
# ============================================================

function Download-LicensedSoftware {
    Clear-Host
    Write-Host "=== TAI PHAN MEM VE THU MUC DOWNLOAD ===" -ForegroundColor Cyan
    Write-Host "Luu y: chi tai tu nguon noi bo / co ban quyen hop le cua cong ty." -ForegroundColor Yellow

    # TODO: thay cac URL "REPLACE_..." bang nguon noi bo hop phap cua anh
    $items = [ordered]@{
        "1" = @{ Name = "Office AIO 2016-2024"; Url = "REPLACE_WITH_INTERNAL_LICENSED_URL" }
        "2" = @{ Name = "Office 365";           Url = "REPLACE_WITH_INTERNAL_LICENSED_URL" }
        "3" = @{ Name = "WPS Office";           Url = "https://www.wps.com/download/" }
        "4" = @{ Name = "LibreOffice";          Url = "https://www.libreoffice.org/download/download/" }
        "5" = @{ Name = "AutoCAD 2021";         Url = "REPLACE_WITH_INTERNAL_LICENSED_URL" }
        "6" = @{ Name = "SolidWorks";           Url = "REPLACE_WITH_INTERNAL_LICENSED_URL" }
    }

    foreach ($k in $items.Keys) { Write-Host "$k. $($items[$k].Name)" }
    Write-Host "0. Back"
    $c = Read-Host "Chon phan mem can tai"
    if ($c -eq "0" -or -not $items.Contains($c)) { return }

    $sel = $items[$c]
    if ($sel.Url -like "REPLACE_*") {
        Write-Host "Chua cau hinh URL noi bo cho '$($sel.Name)'. Vui long cap nhat trong script." -ForegroundColor Red
        Pause-Return
        return
    }

    $downloadDir = "$env:USERPROFILE\Downloads"
    $dest = Join-Path $downloadDir ($sel.Name -replace '\s','_')
    Invoke-WebRequest -Uri $sel.Url -OutFile $dest -UseBasicParsing
    Write-Log "Tai phan mem: $($sel.Name) -> $dest"
    Write-Host "Da tai ve: $dest" -ForegroundColor Green
    Pause-Return
}

function Install-App {
    param([string]$DisplayName, [string]$WingetId, [string]$FallbackUrl = "")
    Write-Host "Dang cai $DisplayName ..."
    $installed = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id $WingetId -e --accept-source-agreements --accept-package-agreements --silent
        if ($LASTEXITCODE -eq 0) { $installed = $true }
    }
    if (-not $installed -and $FallbackUrl -ne "") {
        $tmp = "$env:TEMP\$($DisplayName -replace '\s','')_installer.exe"
        try {
            Invoke-WebRequest -Uri $FallbackUrl -OutFile $tmp -UseBasicParsing
            Start-Process -FilePath $tmp -ArgumentList "/S" -Wait
            $installed = $true
        } catch {
            Write-Host "  Khong the cai $DisplayName tu dong. Vui long tai/cai thu cong." -ForegroundColor Red
        } finally {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log "Cai dat $DisplayName - Ket qua: $(if ($installed) {'OK'} else {'THAT BAI'})"
}

function Install-CommonApps {
    Clear-Host
    Write-Host "=== TU DONG CAI PHAN MEM PHO BIEN ===" -ForegroundColor Cyan
    # Winget ID can duoc kiem tra lai bang 'winget search <ten>' tren may that
    $apps = [ordered]@{
        "1"  = @{ Name = "WinRAR";        Id = "RARLab.WinRAR" }
        "2"  = @{ Name = "Google Chrome"; Id = "Google.Chrome" }
        "3"  = @{ Name = "Coc Coc";       Id = "CocCoc.CocCocBrowser" }
        "4"  = @{ Name = "Zalo PC";       Id = "VNGCorp.Zalo" }
        "5"  = @{ Name = "Zoom";          Id = "Zoom.Zoom" }
        "6"  = @{ Name = "Telegram";      Id = "Telegram.TelegramDesktop" }
        "7"  = @{ Name = "WeChat";        Id = "Tencent.WeChat" }
        "8"  = @{ Name = "KakaoTalk";     Id = "Kakao.KakaoTalk" }
        "9"  = @{ Name = "Foxit PDF Reader"; Id = "Foxit.FoxitReader" }
        "10" = @{ Name = "ImageGlass";    Id = "DuongDieuPhap.ImageGlass" }
        "11" = @{ Name = "AnyDesk";       Id = "AnyDeskSoftwareGmbH.AnyDesk" }
        "12" = @{ Name = "UltraViewer";   Id = "DucFabulous.UltraViewer" }
        "13" = @{ Name = "Unikey";        Id = "" }
        "14" = @{ Name = "Fliqlo (Man hinh cho)"; Id = "" }
        "15" = @{ Name = "Bing Wallpaper"; Id = "Microsoft.BingWallpaper" }
        "16" = @{ Name = "Tat ca (1-15)"; Id = "ALL" }
    }
    foreach ($k in $apps.Keys) { Write-Host "$k. $($apps[$k].Name)" }
    Write-Host "0. Back"
    $c = Read-Host "Chon (co the go nhieu so cach nhau dau phay, vd 1,2,5)"
    if ($c -eq "0") { return }

    $choices = if ($c -eq "16" -or $c -match "16") { 1..15 | ForEach-Object { "$_" } } else { $c -split "," | ForEach-Object { $_.Trim() } }

    foreach ($choice in $choices) {
        if (-not $apps.Contains($choice)) { continue }
        $app = $apps[$choice]
        if ($app.Id -eq "" ) {
            Write-Host "  '$($app.Name)' chua co Winget ID xac nhan - vui long cai thu cong hoac cap nhat URL trong script." -ForegroundColor Yellow
            Write-Log "Bo qua cai dat $($app.Name): chua co nguon cai xac dinh"
            continue
        }
        Install-App -DisplayName $app.Name -WingetId $app.Id
    }
    Pause-Return
}

function Menu-Software {
    do {
        Clear-Host
        Write-Host "===== 5. SOFTWARE =====" -ForegroundColor Cyan
        Write-Host "1. Tai va luu tai thu muc Download"
        Write-Host "2. Tu dong cai (winget)"
        Write-Host "0. Back"
        $c = Read-Host "Chon"
        switch ($c) {
            "1" { Download-LicensedSoftware }
            "2" { Install-CommonApps }
        }
    } while ($c -ne "0")
}

# ============================================================
# 6. WINDOWS SETTING
# ============================================================

function Disable-WinUpdate {
    Clear-Host
    Write-Host "=== TAT WINDOWS UPDATE ===" -ForegroundColor Cyan
    Write-Host "CANH BAO BAO MAT: tat cap nhat khien may khong duoc va loi bao mat." -ForegroundColor Red
    if (-not (Confirm-Action "Ban chac chan muon tat Windows Update?")) { return }

    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
    Set-Service wuauserv -StartupType Disabled
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1 -Type DWord
    Write-Log "Da tat Windows Update (service disabled + policy)"
    Write-Host "Da tat Windows Update." -ForegroundColor Green
    Pause-Return
}

function Enable-WinUpdate {
    Clear-Host
    Write-Host "=== BAT LAI WINDOWS UPDATE ===" -ForegroundColor Cyan
    Set-Service wuauserv -StartupType Manual
    Start-Service wuauserv -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
    Write-Log "Da bat lai Windows Update"
    Write-Host "Da bat lai Windows Update." -ForegroundColor Green
    Pause-Return
}

function Menu-WindowsSetting {
    do {
        Clear-Host
        Write-Host "===== 6. WINDOWS SETTING =====" -ForegroundColor Cyan
        Write-Host "1. Disable Windows Update"
        Write-Host "2. Enable Windows Update"
        Write-Host "0. Back"
        $c = Read-Host "Chon"
        switch ($c) {
            "1" { Disable-WinUpdate }
            "2" { Enable-WinUpdate }
        }
    } while ($c -ne "0")
}

# ============================================================
# MAIN MENU
# ============================================================

function Show-MainMenu {
    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " BO CONG CU DA DUNG CHO WINDOWS"
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "1. Network Troubleshoot"
        Write-Host "2. Printer & File Sharing"
        Write-Host "3. System Info & Activation"
        Write-Host "4. System Maintenance"
        Write-Host "5. Software"
        Write-Host "6. Windows Setting"
        Write-Host "7. Exit"
        $c = Read-Host "Chon muc"
        switch ($c) {
            "1" { Menu-Network }
            "2" { Menu-PrinterSharing }
            "3" { Menu-SystemInfo }
            "4" { Menu-Maintenance }
            "5" { Menu-Software }
            "6" { Menu-WindowsSetting }
        }
    } while ($c -ne "7")

    Write-Log "Nguoi dung thoat toolkit"
    Write-Host "Cam on da su dung. Dang don dep..." -ForegroundColor Cyan
}

Show-MainMenu
