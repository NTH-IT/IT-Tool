# ============================================================
#  BO CONG CU DA DUNG CHO WINDOWS - CORE SCRIPT (PowerShell)
#  Phat trien boi Mr.Hai
#  Luu y: script thuc hien nhieu thay doi he thong. Chi chay
#  tren may duoc phep quan tri, da xac thuc boi launcher.cmd.
# ============================================================

$ErrorActionPreference = "SilentlyContinue"
$LogFile = "$env:TEMP\toolkit_actions_$(Get-Date -Format yyyyMMdd_HHmmss).log"
$Global:ESC = "##ESC##"

function Write-Log {
    param([string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $env:USERNAME | $Message"
    Add-Content -Path $LogFile -Value $line
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) {
    Write-Host "Script can chay voi quyen Administrator." -ForegroundColor Red
    Read-Host "Nhan Enter de thoat"
    exit
}

# ---- Kich thuoc cua so console theo ty le doc (xap xi 9:16) ----
# Luu y: console la luoi ky tu (text grid), khong the dat ty le pixel
# chinh xac 9:16 nhu man hinh dien thoai. Day la xap xi gan nhat bang
# cach thu hep so cot va tang so dong hien thi.
try {
    $w = 54; $h = 42
    $rawui = $Host.UI.RawUI
    $buf = $rawui.BufferSize
    $buf.Width = [Math]::Max($buf.Width, $w)
    $buf.Height = 3000
    $rawui.BufferSize = $buf
    $winsize = $rawui.WindowSize
    $winsize.Width = $w
    $winsize.Height = $h
    $rawui.WindowSize = $winsize
} catch {}

# ============================================================
# HAM DIEU KHIEN NHAP LIEU (ho tro ESC de huy / quay lai)
# ============================================================

function Read-Esc {
    param([string]$Prompt = "")
    if ($Prompt -ne "") { Write-Host -NoNewline $Prompt }
    $buffer = ""
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Escape') { Write-Host ""; return $Global:ESC }
        if ($key.Key -eq 'Enter') { Write-Host ""; return $buffer }
        if ($key.Key -eq 'Backspace') {
            if ($buffer.Length -gt 0) {
                $buffer = $buffer.Substring(0, $buffer.Length - 1)
                Write-Host -NoNewline ([char]8 + " " + [char]8)
            }
            continue
        }
        if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
            $buffer += $key.KeyChar
            Write-Host -NoNewline $key.KeyChar
        }
    }
}

function Read-IPEsc {
    param([string]$Label = "IP")
    Write-Host -NoNewline "$($Label): "
    $octets = @("","","","")
    $idx = 0
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Escape') { Write-Host ""; return $Global:ESC }
        if ($key.Key -eq 'Enter') {
            if ($idx -eq 3 -and $octets[3] -ne "") { Write-Host ""; break } else { continue }
        }
        if ($key.Key -eq 'Backspace') {
            if ($octets[$idx].Length -gt 0) {
                $octets[$idx] = $octets[$idx].Substring(0, $octets[$idx].Length - 1)
                Write-Host -NoNewline ([char]8 + " " + [char]8)
            } elseif ($idx -gt 0) {
                $idx--
                Write-Host -NoNewline ([char]8 + " " + [char]8)
            }
            continue
        }
        if ($key.KeyChar -match '^[0-9]$' -and $octets[$idx].Length -lt 3 -and $idx -le 3) {
            $cand = $octets[$idx] + $key.KeyChar
            if ([int]$cand -le 255) {
                $octets[$idx] = $cand
                Write-Host -NoNewline $key.KeyChar
                if ($cand.Length -eq 3 -and $idx -lt 3) {
                    $idx++
                    Write-Host -NoNewline "."
                }
            }
        }
    }
    return ($octets -join ".")
}

function Confirm-Action {
    param([string]$Prompt)
    Write-Host ""
    Write-Host "CANH BAO: $Prompt" -ForegroundColor Yellow
    $resp = Read-Esc "Go YES de xac nhan (ESC de huy): "
    return ($resp -eq "YES")
}

function Pause-Return {
    Write-Host ""
    Read-Host "Nhan Enter de quay lai menu (ESC khong ho tro o day)" | Out-Null
}

function Run-Task {
    param([string]$Title, [scriptblock]$Action, [bool]$NeedConfirm = $false, [string]$ConfirmMsg = "")
    Clear-Host
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    if ($NeedConfirm) {
        if (-not (Confirm-Action $ConfirmMsg)) { return }
    }
    try {
        & $Action
        Write-Log "$Title - OK"
        Write-Host "`nHoan tat." -ForegroundColor Green
    } catch {
        Write-Log "$Title - LOI: $_"
        Write-Host "`nLoi: $_" -ForegroundColor Red
    }
    Pause-Return
}

# Menu tong quat: $Options la [ordered]@{ "1"=@{Label="..";Action={...}} }
function Show-Menu {
    param([string]$Title, $Options)
    do {
        Clear-Host
        Write-Host "===== $Title =====" -ForegroundColor Cyan
        foreach ($k in $Options.Keys) { Write-Host "$k. $($Options[$k].Label)" }
        Write-Host "0. Back (hoac nhan ESC)"
        $c = Read-Esc "Chon: "
        if ($c -eq $Global:ESC -or $c -eq "0") { return }
        if ($Options.Contains($c)) { & $Options[$c].Action }
    } while ($true)
}

# ============================================================
# 1. NETWORK TROUBLESHOOT
# ============================================================

function Show-NetworkInfo {
    Clear-Host
    Write-Host "=== THONG TIN MANG HIEN TAI ===" -ForegroundColor Cyan
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "Hostname          : $($cs.Name)"
    Write-Host "Domain/Workgroup  : $($cs.Domain)"
    Write-Host "PartOfDomain      : $($cs.PartOfDomain)"
    Write-Host ""
    Get-NetIPConfiguration | ForEach-Object {
        Write-Host "-- Adapter: $($_.InterfaceAlias) --"
        Write-Host "  IPv4    : $($_.IPv4Address.IPAddress)"
        Write-Host "  Gateway : $($_.IPv4DefaultGateway.NextHop)"
        Write-Host "  DNS     : $($_.DNSServer.ServerAddresses -join ', ')"
    }
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
        Write-Host "  MAC ($($_.Name)): $($_.MacAddress)"
    }
    Write-Log "Xem thong tin mang"
    Pause-Return
}

function Set-ComputerNameDomain {
    Clear-Host
    Write-Host "=== DOI TEN MAY / DOMAIN (ESC de huy) ===" -ForegroundColor Cyan
    $newName = Read-Esc "Nhap Hostname moi (de trong = bo qua): "
    if ($newName -eq $Global:ESC) { return }
    $newDomainOrWorkgroup = Read-Esc "Nhap Domain/Workgroup moi (de trong = bo qua): "
    if ($newDomainOrWorkgroup -eq $Global:ESC) { return }

    if ($newName -eq "" -and $newDomainOrWorkgroup -eq "") { return }
    if (-not (Confirm-Action "Doi ten may/domain se yeu cau KHOI DONG LAI may.")) { return }

    if ($newName -ne "") {
        Rename-Computer -NewName $newName -Force
        Write-Log "Doi hostname thanh $newName"
    }
    if ($newDomainOrWorkgroup -ne "") {
        $cred = Get-Credential -Message "Tai khoan co quyen join domain (bo trong neu doi workgroup)"
        try {
            Add-Computer -DomainName $newDomainOrWorkgroup -Credential $cred -Force -ErrorAction Stop
            Write-Log "Join domain $newDomainOrWorkgroup"
        } catch {
            Add-Computer -WorkgroupName $newDomainOrWorkgroup -Force
            Write-Log "Doi workgroup thanh $newDomainOrWorkgroup"
        }
    }
    Write-Host "Hoan tat. Vui long khoi dong lai may." -ForegroundColor Green
    Pause-Return
}

function Reset-IPAddress {
    Run-Task -Title "XOA IP CU / NHAN IP MOI" -Action {
        ipconfig /release; ipconfig /flushdns; ipconfig /registerdns
        netsh winsock reset; netsh int ip reset; ipconfig /renew
    }
}

function Set-StaticIP {
    Clear-Host
    Write-Host "=== DAT IP TINH (chi nhap so, tu dong them dau cham, ESC de huy) ===" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceIndex -AutoSize
    $idx = Read-Esc "Nhap InterfaceIndex: "
    if ($idx -eq $Global:ESC) { return }
    $ip = Read-IPEsc "Dia chi IP"
    if ($ip -eq $Global:ESC) { return }
    $prefix = Read-Esc "Prefix length (vd 24): "
    if ($prefix -eq $Global:ESC) { return }
    $gw = Read-IPEsc "Default Gateway"
    if ($gw -eq $Global:ESC) { return }

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
    Write-Host "=== DAT DNS TINH (chi nhap so, tu dong them dau cham, ESC de huy) ===" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceIndex -AutoSize
    $idx = Read-Esc "Nhap InterfaceIndex: "
    if ($idx -eq $Global:ESC) { return }
    $dns1 = Read-IPEsc "DNS uu tien"
    if ($dns1 -eq $Global:ESC) { return }
    $dns2 = Read-IPEsc "DNS thay the (Enter voi 0.0.0.0 de bo qua)"
    $dnsList = @($dns1)
    if ($dns2 -ne $Global:ESC -and $dns2 -ne "0.0.0.0") { $dnsList += $dns2 }

    Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $dnsList
    Write-Log "Dat DNS $($dnsList -join ', ') tren interface $idx"
    Write-Host "Da dat DNS tinh." -ForegroundColor Green
    Pause-Return
}

function Reset-NetworkFull {
    Run-Task -Title "RESET MANG VE MAC DINH" -NeedConfirm $true `
        -ConfirmMsg "Se xoa cau hinh mang, Data Usage, log, dat mang ve mac dinh. KHONG THE HOAN TAC." -Action {
        netsh winsock reset; netsh int ip reset; netsh advfirewall reset
        net stop dosvc 2>$null; net start dosvc 2>$null
    }
}

function Menu-Network {
    $opts = [ordered]@{
        "1" = @{ Label = "Kiem tra thong tin mang hien tai"; Action = { Show-NetworkInfo } }
        "2" = @{ Label = "Dat lai ten may (Hostname/Domain)"; Action = { Set-ComputerNameDomain } }
        "3" = @{ Label = "Xoa IP cu, nhan IP moi"; Action = { Reset-IPAddress } }
        "4" = @{ Label = "Dat IP tinh"; Action = { Set-StaticIP } }
        "5" = @{ Label = "Dat DNS tinh"; Action = { Set-StaticDNS } }
        "6" = @{ Label = "Reset mang ve mac dinh"; Action = { Reset-NetworkFull } }
    }
    Show-Menu -Title "1. NETWORK TROUBLESHOOT" -Options $opts
}

# ============================================================
# 2. PRINTER & FILE SHARING
# ============================================================

function Add-CheckResult {
    param($List, [string]$Name, [bool]$Pass, [string]$Detail = "")
    $List.Add([PSCustomObject]@{ Hang_muc = $Name; Ket_qua = $(if($Pass){"OK"}else{"LOI"}); Chi_tiet = $Detail })
}

function Test-FileSharingLan {
    Clear-Host
    Write-Host "=== BANG TOM TAT: CHAN DOAN CHIA SE FILE QUA LAN ===" -ForegroundColor Cyan
    $r = New-Object System.Collections.ArrayList
    $svr = Get-Service LanmanServer
    Add-CheckResult $r "Service Server (LanmanServer)" ($svr.Status -eq 'Running') $svr.Status
    $wks = Get-Service LanmanWorkstation
    Add-CheckResult $r "Service Workstation" ($wks.Status -eq 'Running') $wks.Status
    $fwND = Get-NetFirewallRule -DisplayGroup "Network Discovery" | Where-Object Enabled -eq $true
    Add-CheckResult $r "Firewall Network Discovery" ($fwND.Count -gt 0) "$($fwND.Count) rule bat"
    $fwFS = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | Where-Object Enabled -eq $true
    Add-CheckResult $r "Firewall File/Printer Sharing" ($fwFS.Count -gt 0) "$($fwFS.Count) rule bat"
    $smb = Get-SmbServerConfiguration
    Add-CheckResult $r "SMB2/3 Enabled" $smb.EnableSMB2Protocol "SMB1=$($smb.EnableSMB1Protocol)"
    $r | Format-Table -AutoSize
    Write-Log "Chan doan file sharing LAN (bang tom tat)"
    Pause-Return
}

function Test-PrinterPipeline {
    Clear-Host
    Write-Host "=== BANG TOM TAT: CHAN DOAN MAY IN ===" -ForegroundColor Cyan
    $r = New-Object System.Collections.ArrayList
    $svrSvc = Get-Service LanmanServer
    Add-CheckResult $r "Server (LanmanServer)" ($svrSvc.Status -eq 'Running') $svrSvc.Status
    $rpc = Get-Service RpcSs
    Add-CheckResult $r "RPC (RpcSs)" ($rpc.Status -eq 'Running') $rpc.Status
    $smb = Get-SmbServerConfiguration
    Add-CheckResult $r "SMB" $smb.EnableSMB2Protocol "SMB2=$($smb.EnableSMB2Protocol)"
    $spl = Get-Service Spooler
    Add-CheckResult $r "Print Spooler" ($spl.Status -eq 'Running') $spl.Status
    $fw = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | Where-Object Enabled -eq $true
    Add-CheckResult $r "Firewall" ($fw.Count -gt 0) "$($fw.Count) rule bat"
    $shared = Get-Printer | Where-Object Shared -eq $true
    Add-CheckResult $r "Printer Share" ($shared.Count -gt 0) "$($shared.Count) may in dang share"
    $drv = Get-PrinterDriver
    Add-CheckResult $r "Driver may in" ($drv.Count -gt 0) "$($drv.Count) driver da cai"
    $port = Get-PrinterPort
    Add-CheckResult $r "Port may in" ($port.Count -gt 0) "$($port.Count) port"
    $ppKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
    Add-CheckResult $r "Group Policy Point&Print" (Test-Path $ppKey) $(if(Test-Path $ppKey){"Co policy tuy chinh"}else{"Mac dinh"})
    $r | Format-Table -AutoSize
    Write-Log "Chan doan pipeline may in (bang tom tat)"
    Pause-Return
}

function Run-PrinterFixTool {
    Clear-Host
    Write-Host "=== TAI VA CHAY PrinterFixTool.exe (Admin) ===" -ForegroundColor Cyan

    $toolUrl  = "https://cdn.jsdelivr.net/gh/NTH-IT/IT-Tool@main/PrinterFixTool.exe"
    $toolPath = "$env:TEMP\PrinterFixTool_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"

    try {
        $wc = New-Object System.Net.WebClient
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $script:dlDone = $false
        $script:dlPercent = 0
        Register-ObjectEvent -InputObject $wc -EventName DownloadProgressChanged -SourceIdentifier PFT_Progress -Action {
            $Global:dlPercent = $Event.SourceEventArgs.ProgressPercentage
        } | Out-Null
        Register-ObjectEvent -InputObject $wc -EventName DownloadFileCompleted -SourceIdentifier PFT_Done -Action {
            $Global:dlDone = $true
        } | Out-Null
        $Global:dlDone = $false
        $Global:dlPercent = 0
        $wc.DownloadFileAsync([Uri]$toolUrl, $toolPath)
        while (-not $Global:dlDone) {
            Write-Host -NoNewline "`rDang tai: $($Global:dlPercent)%  -  Thoi gian: $([math]::Round($sw.Elapsed.TotalSeconds,1))s   "
            Start-Sleep -Milliseconds 300
        }
        Write-Host ""
        Unregister-Event -SourceIdentifier PFT_Progress -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier PFT_Done -ErrorAction SilentlyContinue
        $sw.Stop()

        $hash = (Get-FileHash -Path $toolPath -Algorithm SHA256).Hash
        Write-Log "Da tai PrinterFixTool.exe, SHA256=$hash"

        Write-Host "Dang chay PrinterFixTool.exe (quyen admin)..."
        $runSw = [System.Diagnostics.Stopwatch]::StartNew()
        Start-Process -FilePath $toolPath -Verb RunAs -Wait
        $runSw.Stop()
        Write-Host "Thoi gian chay: $([math]::Round($runSw.Elapsed.TotalSeconds,1)) giay" -ForegroundColor Green
        Write-Log "Da chay PrinterFixTool.exe - thoi gian $([math]::Round($runSw.Elapsed.TotalSeconds,1))s"
    } catch {
        Write-Host "Loi khi tai/chay file: $_" -ForegroundColor Red
    } finally {
        Remove-Item $toolPath -Force -ErrorAction SilentlyContinue
    }
    Pause-Return
}

function Menu-PrinterSharing {
    $opts = [ordered]@{
        "1" = @{ Label = "Bang tom tat chia se file qua LAN"; Action = { Test-FileSharingLan } }
        "2" = @{ Label = "Bang tom tat chan doan may in"; Action = { Test-PrinterPipeline } }
        "3" = @{ Label = "Chay PrinterFixTool.exe (tai + chay admin)"; Action = { Run-PrinterFixTool } }
    }
    Show-Menu -Title "2. PRINTER & FILE SHARING" -Options $opts
}

# ============================================================
# 3. SYSTEM INFO & ACTIVATION
# ============================================================

function Show-SoftwareInfo {
    Clear-Host
    Write-Host "=== THONG TIN PHAN MEM (moi dong 1 thong tin) ===" -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "Ten may           : $($cs.Name)"
    Write-Host "User dang dung    : $env:USERNAME"
    Write-Host "He dieu hanh      : $($os.Caption)"
    Write-Host "Build             : $($os.BuildNumber)"
    Write-Host "Domain/Workgroup  : $($cs.Domain)"
    Write-Host "PartOfDomain      : $($cs.PartOfDomain)"
    $officeReg = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\*\Common\ProductVersion" -ErrorAction SilentlyContinue
    if ($officeReg) { Write-Host "Office version    : $($officeReg.LastProduct)" }
    Get-NetIPConfiguration | ForEach-Object {
        Write-Host "Adapter           : $($_.InterfaceAlias)"
        Write-Host "  IP              : $($_.IPv4Address.IPAddress)"
        Write-Host "  Gateway         : $($_.IPv4DefaultGateway.NextHop)"
        Write-Host "  DNS             : $($_.DNSServer.ServerAddresses -join ', ')"
    }
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
        Write-Host "  MAC ($($_.Name)) : $($_.MacAddress)"
    }
    Write-Log "Xem thong tin phan mem"
    Pause-Return
}

function Show-CPUInfo {
    Write-Host "`n--- CPU ---" -ForegroundColor Yellow
    $cpu = Get-CimInstance Win32_Processor
    Write-Host "Ten             : $($cpu.Name)"
    Write-Host "So core         : $($cpu.NumberOfCores)"
    Write-Host "Logical Proc.   : $($cpu.NumberOfLogicalProcessors)"
    Write-Host "Toc do hien tai : $($cpu.CurrentClockSpeed) MHz"
    Write-Host "Toc do toi da   : $($cpu.MaxClockSpeed) MHz"
    Write-Host "Socket          : $($cpu.SocketDesignation)"
    Write-Host "CPU Load        : $($cpu.LoadPercentage)%"
    Write-Host "Architecture    : $($cpu.AddressWidth)-bit"
    Write-Host "Family/Model    : Family $($cpu.Family) / $($cpu.Description)"
}

function Show-RAMInfo {
    Write-Host "`n--- RAM ---" -ForegroundColor Yellow
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        Write-Host "Slot $($_.DeviceLocator): $([math]::Round($_.Capacity/1GB,2)) GB - Manufacturer: $($_.Manufacturer) - Speed: $($_.Speed) MHz - Form Factor code: $($_.FormFactor)"
    }
    $ddr = Get-CimInstance Win32_PhysicalMemory | Select-Object -First 1 -ExpandProperty SMBIOSMemoryType
    Write-Host "Memory Type code: $ddr (SMBIOS: 26=DDR4, 34=DDR5, 24=DDR3)"
}

function Show-DiskInfo {
    Write-Host "`n--- O CUNG ---" -ForegroundColor Yellow
    Get-PhysicalDisk | ForEach-Object {
        Write-Host "O dia: $($_.FriendlyName) - Health: $($_.HealthStatus) - Size: $([math]::Round($_.Size/1GB,2)) GB"
    }
    Get-Volume | Where-Object DriveLetter | ForEach-Object {
        Write-Host "  Drive $($_.DriveLetter): - Free: $([math]::Round($_.SizeRemaining/1GB,2)) GB / $([math]::Round($_.Size/1GB,2)) GB"
    }
    Get-Partition | Where-Object DriveLetter | ForEach-Object {
        Write-Host "  Partition Drive $($_.DriveLetter): Type=$($_.Type)"
    }
}

function Show-GPUInfo {
    Write-Host "`n--- GPU / VGA ---" -ForegroundColor Yellow
    Get-CimInstance Win32_VideoController | ForEach-Object {
        Write-Host "Ten            : $($_.Name)"
        Write-Host "Manufacturer   : $($_.AdapterCompatibility)"
        Write-Host "VRAM           : $([math]::Round($_.AdapterRAM/1GB,2)) GB"
        Write-Host "Driver Version : $($_.DriverVersion)"
        Write-Host "Driver Date    : $($_.DriverDate)"
        Write-Host ""
    }
}

function Show-DisplayInfo {
    Write-Host "`n--- MAN HINH ---" -ForegroundColor Yellow
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        foreach ($m in $monitors) {
            $name = ($m.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            $serial = ($m.SerialNumberID | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            Write-Host "Ten (EDID) : $name"
            Write-Host "Serial     : $serial"
        }
    } catch { Write-Host "Khong doc duoc WmiMonitorID (co the do driver)." }
    Get-CimInstance Win32_VideoController | ForEach-Object {
        Write-Host "Resolution : $($_.CurrentHorizontalResolution) x $($_.CurrentVerticalResolution)"
        Write-Host "Refresh    : $($_.CurrentRefreshRate) Hz"
    }
}

function Show-NICInfo {
    Write-Host "`n--- CARD MANG ---" -ForegroundColor Yellow
    Get-NetAdapter | ForEach-Object {
        Write-Host "Adapter        : $($_.Name)  ($($_.InterfaceDescription))"
        Write-Host "  Loai         : $(if($_.Name -match 'Wi-?Fi|Wireless'){'Wi-Fi'}else{'Ethernet'})"
        Write-Host "  MAC          : $($_.MacAddress)"
        Write-Host "  Trang thai   : $($_.Status)"
        Write-Host "  Link Speed   : $($_.LinkSpeed)"
        $drv = Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceName -eq $_.InterfaceDescription } | Select-Object -First 1
        if ($drv) {
            Write-Host "  Driver Ver   : $($drv.DriverVersion)"
            Write-Host "  Driver Date  : $($drv.DriverDate)"
        }
        Write-Host ""
    }
}

function Show-BatteryInfo {
    Write-Host "`n--- PIN LAPTOP ---" -ForegroundColor Yellow
    $bat = Get-CimInstance Win32_Battery
    if (-not $bat) { Write-Host "May khong co pin (PC ban)."; return }
    foreach ($b in $bat) {
        Write-Host "Ten            : $($b.Name)"
        Write-Host "Manufacturer   : $($b.DeviceID)"
        Write-Host "Status code    : $($b.BatteryStatus)  (1=Discharging,2=AC,6=Charging...)"
        Write-Host "Estimate charge: $($b.EstimatedChargeRemaining)%"
    }
    try {
        $static = Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop
        foreach ($s in $static) {
            Write-Host "Design Capacity: $($s.DesignedCapacity) mWh"
            Write-Host "Serial         : $($s.SerialNumber)"
        }
    } catch { Write-Host "Khong doc duoc BatteryStaticData chi tiet (tuy dong may)." }
}

function Show-HardwareInfoFull {
    Clear-Host
    Write-Host "=== THONG TIN PHAN CUNG (day du) ===" -ForegroundColor Cyan
    $csProd = Get-CimInstance Win32_ComputerSystemProduct
    $bios = Get-CimInstance Win32_BIOS
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "Hang san xuat  : $($cs.Manufacturer)"
    Write-Host "Model may      : $($csProd.Name)"
    Write-Host "Serial         : $($csProd.IdentifyingNumber)"
    Write-Host "UUID           : $($csProd.UUID)"
    Write-Host "BIOS Version   : $($bios.SMBIOSBIOSVersion)"
    Write-Host "BIOS Date      : $($bios.ReleaseDate)"
    $uptime = (Get-Date) - $os.LastBootUpTime
    Write-Host "Uptime         : $($uptime.Days) ngay $($uptime.Hours) gio $($uptime.Minutes) phut"

    Show-CPUInfo
    Show-RAMInfo
    Show-DiskInfo
    Show-GPUInfo
    Show-DisplayInfo
    Show-NICInfo
    Show-BatteryInfo

    Write-Log "Xem thong tin phan cung day du"
    Pause-Return
}

function Show-LicenseInfo {
    Clear-Host
    Write-Host "=== THONG TIN BAN QUYEN (Windows / Office) ===" -ForegroundColor Cyan
    Write-Host "-- Windows --"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    Write-Host "`n-- Office (neu co OSPP.VBS) --"
    $ospp = Get-ChildItem "C:\Program Files\Microsoft Office\Office*\ospp.vbs", "C:\Program Files (x86)\Microsoft Office\Office*\ospp.vbs" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ospp) { cscript //nologo $ospp.FullName /dstatus }
    else { Write-Host "  (Khong tim thay OSPP.VBS - Office co the dung Click-to-Run)" }
    Write-Log "Xem thong tin ban quyen"
    Pause-Return
}

function Check-LicenseKeyByMachine {
    Clear-Host
    Write-Host "=== KIEM TRA KEY BAN QUYEN THEO MAY ===" -ForegroundColor Cyan
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dlv
    Write-Log "Kiem tra chi tiet key ban quyen"
    Pause-Return
}

function Remove-LicenseExceptMachine {
    Clear-Host
    Write-Host "=== GO BO BAN QUYEN (giu lai theo may / OEM digital license) ===" -ForegroundColor Cyan
    Write-Host "Se GO product key dang cai (MAK/KMS/Retail). May se ve trang thai OEM digital license neu co." -ForegroundColor Yellow
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    if (-not (Confirm-Action "Ban chac chan muon GO product key Windows dang cai?")) { return }
    Write-Log "Truoc khi go key: trang thai da hien thi o tren"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /upk
    cscript //nologo "$env:windir\System32\slmgr.vbs" /cpky
    Write-Log "Da go product key Windows"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    Pause-Return
}

function Menu-SystemInfo {
    $opts = [ordered]@{
        "1" = @{ Label = "Thong tin phan mem"; Action = { Show-SoftwareInfo } }
        "2" = @{ Label = "Thong tin phan cung (CPU/RAM/O cung/GPU/Man hinh/Mang/Pin)"; Action = { Show-HardwareInfoFull } }
        "3" = @{ Label = "Thong tin ban quyen (Windows/Office)"; Action = { Show-LicenseInfo } }
        "4" = @{ Label = "Kiem tra key ban quyen theo may"; Action = { Check-LicenseKeyByMachine } }
        "5" = @{ Label = "Go bo ban quyen (giu lai theo may)"; Action = { Remove-LicenseExceptMachine } }
    }
    Show-Menu -Title "3. SYSTEM INFO & ACTIVATION" -Options $opts
}

# ============================================================
# 4. SYSTEM MAINTENANCE (gop Windows Setting cu vao day)
# ============================================================

function Get-FolderSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $size) { return 0 }
    return [math]::Round($size / 1MB, 2)
}

function Show-CleanupAnalysis {
    param([bool]$Deep)
    $items = [ordered]@{
        "User Temp"      = "$env:TEMP"
        "Windows Temp"   = "$env:windir\Temp"
        "Windows Update" = "$env:windir\SoftwareDistribution\Download"
        "Recycle Bin"    = "$env:SystemDrive\`$Recycle.Bin"
        "Error Reports"  = "$env:LOCALAPPDATA\Microsoft\Windows\WER"
    }
    if ($Deep) {
        $items["Packages"] = "$env:LOCALAPPDATA\Packages"
        $items["LocalLow"] = "$env:USERPROFILE\AppData\LocalLow"
    }
    Clear-Host
    Write-Host "=== CLEANUP ANALYSIS ===" -ForegroundColor Cyan
    $total = 0
    $sizes = [ordered]@{}
    foreach ($k in $items.Keys) {
        $sz = Get-FolderSizeMB $items[$k]
        $sizes[$k] = $sz
        $total += $sz
        Write-Host ("{0,-18} {1,10} MB" -f $k, $sz)
    }
    Write-Host "────────────────────────────"
    Write-Host ("{0,-18} {1,10} MB" -f "Potentially removable", [math]::Round($total,2)) -ForegroundColor Yellow
    return @{ Items = $items; Sizes = $sizes; Total = $total }
}

function Invoke-CleanupFlow {
    param([bool]$Deep)
    $analysis = Show-CleanupAnalysis -Deep $Deep
    $c = Read-Esc "`nClean selected items? [Y/N] (ESC de huy): "
    if ($c -eq $Global:ESC -or $c.ToUpper() -ne "Y") { Pause-Return; return }

    foreach ($k in $analysis.Items.Keys) {
        $p = $analysis.Items[$k]
        if ($k -eq "Recycle Bin") { Clear-RecycleBin -Force -ErrorAction SilentlyContinue; continue }
        Remove-Item "$p\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($Deep) {
        Stop-Service -Name DPS -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:windir\System32\sru\*" -Force -ErrorAction SilentlyContinue
        Start-Service -Name DPS -ErrorAction SilentlyContinue
        wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
    }
    Write-Log "$(if($Deep){'Deep'}else{'Quick'}) Clean - uoc tinh giai phong $($analysis.Total) MB"
    Write-Host "`nDa don xong. Da giai phong khoang: $($analysis.Total) MB" -ForegroundColor Green
    Pause-Return
}

function Menu-WindowsCleanup {
    $opts = [ordered]@{
        "1" = @{ Label = "Don qua (Quick Clean)"; Action = { Invoke-CleanupFlow -Deep $false } }
        "2" = @{ Label = "Don ky (Deep Clean)"; Action = { Invoke-CleanupFlow -Deep $true } }
    }
    Show-Menu -Title "WINDOWS CLEANUP" -Options $opts
}

function Menu-Performance {
    $opts = [ordered]@{
        "1"  = @{ Label = "High Performance Power Plan"; Action = { Run-Task "High Performance" { powercfg /s SCHEME_MIN } } }
        "2"  = @{ Label = "Ultimate Performance"; Action = { Run-Task "Ultimate Performance" { powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 } } }
        "3"  = @{ Label = "Disable Visual Effects"; Action = { Run-Task "Disable Visual Effects" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name VisualFXSetting -Value 2 -Force } } }
        "4"  = @{ Label = "Optimize for Performance"; Action = { Run-Task "Optimize for Performance" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name VisualFXSetting -Value 2 -Force } } }
        "5"  = @{ Label = "Disable Transparency"; Action = { Run-Task "Disable Transparency" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name EnableTransparency -Value 0 -Force } } }
        "6"  = @{ Label = "Disable Animations"; Action = { Run-Task "Disable Animations" { Set-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" -Name MinAnimate -Value 0 -Force } } }
        "7"  = @{ Label = "Adjust Virtual Memory (mo hop thoai)"; Action = { Run-Task "Virtual Memory" { Start-Process SystemPropertiesAdvanced.exe } } }
        "8"  = @{ Label = "Optimize Startup Apps (xem danh sach)"; Action = { Run-Task "Startup Apps" { Get-CimInstance Win32_StartupCommand | Format-Table Name, Command, Location -AutoSize } } }
        "9"  = @{ Label = "Disable Unnecessary Startup (mo Task Manager)"; Action = { Run-Task "Disable Startup" { Start-Process taskmgr.exe } } }
        "10" = @{ Label = "Performance Diagnostic (CPU/RAM hien tai)"; Action = { Run-Task "Performance Diagnostic" {
                    $cpu = (Get-CimInstance Win32_Processor).LoadPercentage
                    $os = Get-CimInstance Win32_OperatingSystem
                    $ramUsed = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1)
                    Write-Host "CPU Load: $cpu%   RAM Used: $ramUsed%"
                } } }
    }
    Show-Menu -Title "PERFORMANCE" -Options $opts
}

function Menu-PowerManagement {
    $opts = [ordered]@{
        "1"  = @{ Label = "Balanced"; Action = { Run-Task "Balanced" { powercfg /s SCHEME_BALANCED } } }
        "2"  = @{ Label = "Best Performance"; Action = { Run-Task "Best Performance" { powercfg /s SCHEME_MIN } } }
        "3"  = @{ Label = "Power Saver"; Action = { Run-Task "Power Saver" { powercfg /s SCHEME_MAX } } }
        "4"  = @{ Label = "Screen Timeout"; Action = { Run-Task "Screen Timeout" {
                    $m = Read-Esc "So phut (0=khong bao gio): "
                    if ($m -ne $Global:ESC) { powercfg /change monitor-timeout-ac $m }
                } } }
        "5"  = @{ Label = "Sleep Timeout"; Action = { Run-Task "Sleep Timeout" {
                    $m = Read-Esc "So phut (0=khong bao gio): "
                    if ($m -ne $Global:ESC) { powercfg /change standby-timeout-ac $m }
                } } }
        "6"  = @{ Label = "Hibernate (bat)"; Action = { Run-Task "Hibernate On" { powercfg /hibernate on } } }
        "7"  = @{ Label = "Disable Hibernate"; Action = { Run-Task "Hibernate Off" { powercfg /hibernate off } } }
        "8"  = @{ Label = "Lid Close Action (mo cai dat)"; Action = { Run-Task "Lid Close Action" { Start-Process powercfg.cpl } } }
        "9"  = @{ Label = "Power Button Action (mo cai dat)"; Action = { Run-Task "Power Button Action" { Start-Process powercfg.cpl } } }
        "10" = @{ Label = "Battery Report"; Action = { Run-Task "Battery Report" { powercfg /batteryreport /output "$env:USERPROFILE\Desktop\battery-report.html"; Write-Host "Da xuat: $env:USERPROFILE\Desktop\battery-report.html" } } }
        "11" = @{ Label = "Power Efficiency Report"; Action = { Run-Task "Power Efficiency Report" { powercfg /energy /output "$env:USERPROFILE\Desktop\energy-report.html"; Write-Host "Da xuat: $env:USERPROFILE\Desktop\energy-report.html" } } }
    }
    Show-Menu -Title "POWER MANAGEMENT" -Options $opts
}

function Menu-ExplorerTweaks {
    $opts = [ordered]@{
        "1"  = @{ Label = "Show File Extensions"; Action = { Run-Task "Show Extensions" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0 } } }
        "2"  = @{ Label = "Show Hidden Files"; Action = { Run-Task "Show Hidden" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Hidden 1 } } }
        "3"  = @{ Label = "Show Protected OS Files"; Action = { Run-Task "Show OS Files" -NeedConfirm $true -ConfirmMsg "Hien file he thong co the gay nham lan/xoa nham." { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ShowSuperHidden 1 } } }
        "4"  = @{ Label = "Show Full Path in Title Bar"; Action = { Run-Task "Full Path" { Set-ItemProperty "HKCU:\Software\Classes\CLSID\{9WPFB1EE-2E3E-4EBC-9536-53F0A00F3F27}" -Name FullPath -Value 1 -ErrorAction SilentlyContinue; Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" FullPath 1 } } }
        "5"  = @{ Label = "Open File Explorer to: This PC"; Action = { Run-Task "Open This PC" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" LaunchTo 1 } } }
        "6"  = @{ Label = "Disable Recent Files"; Action = { Run-Task "Disable Recent Files" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_TrackDocs 0 } } }
        "7"  = @{ Label = "Disable Recent Folders"; Action = { Run-Task "Disable Recent Folders" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" NoRecentDocsHistory 1 } } }
        "8"  = @{ Label = "Clear Explorer History"; Action = { Run-Task "Clear History" { Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -ErrorAction SilentlyContinue } } }
        "9"  = @{ Label = "Restart Explorer"; Action = { Run-Task "Restart Explorer" { Stop-Process -Name explorer -Force; Start-Process explorer.exe } } }
        "10" = @{ Label = "Disable Thumbnails"; Action = { Run-Task "Disable Thumbnails" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" IconsOnly 1 } } }
        "11" = @{ Label = "Enable Thumbnails"; Action = { Run-Task "Enable Thumbnails" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" IconsOnly 0 } } }
    }
    Show-Menu -Title "EXPLORER TWEAKS" -Options $opts
}

function Menu-WindowsStandard {
    $opts = [ordered]@{
        "1" = @{ Label = "Taskbar Left"; Action = { Run-Task "Taskbar Left" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarAl 0 } } }
        "2" = @{ Label = "Show File Extensions"; Action = { Run-Task "Show Extensions" { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0 } } }
        "3" = @{ Label = "Hide Widgets/Search/Chat"; Action = { Run-Task "Hide Widgets/Search/Chat" {
                    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarDa 0
                    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" SearchboxTaskbarMode 0
                    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarMn 0
                } } }
        "4" = @{ Label = "Hide unnecessary icons (Notification Area)"; Action = { Run-Task "Hide Icons" { Start-Process ms-settings:taskbar } } }
        "5" = @{ Label = "Standard Start Menu (chi mo cai dat - Win11 khong ho tro Start co dien qua registry)"; Action = { Run-Task "Start Menu" { Start-Process ms-settings:personalization-start } } }
        "6" = @{ Label = "Restart Explorer"; Action = { Run-Task "Restart Explorer" { Stop-Process -Name explorer -Force; Start-Process explorer.exe } } }
    }
    Show-Menu -Title "WINDOWS STANDARD" -Options $opts
}

function Menu-WindowsUpdate {
    $opts = [ordered]@{
        "1" = @{ Label = "Check Update"; Action = { Run-Task "Check Update" { UsoClient StartScan } } }
        "2" = @{ Label = "Open Windows Update"; Action = { Run-Task "Open Windows Update" { Start-Process ms-settings:windowsupdate } } }
        "3" = @{ Label = "Windows Update Status"; Action = { Run-Task "Update Status" { Get-Service wuauserv | Format-Table Name, Status, StartType } } }
        "4" = @{ Label = "Restart Update Services"; Action = { Run-Task "Restart Services" { Restart-Service wuauserv, bits, cryptsvc -Force } } }
        "5" = @{ Label = "Reset Update Components"; Action = { Run-Task "Reset Components" -NeedConfirm $true -ConfirmMsg "Se dat lai toan bo cache Windows Update." {
                    Stop-Service wuauserv, bits, cryptsvc -Force
                    Rename-Item "$env:windir\SoftwareDistribution" "SoftwareDistribution.bak_$(Get-Date -Format yyyyMMddHHmmss)" -ErrorAction SilentlyContinue
                    Rename-Item "$env:windir\System32\catroot2" "catroot2.bak_$(Get-Date -Format yyyyMMddHHmmss)" -ErrorAction SilentlyContinue
                    Start-Service wuauserv, bits, cryptsvc
                } } }
        "6" = @{ Label = "Clear Update Cache"; Action = { Run-Task "Clear Cache" { Stop-Service wuauserv -Force; Remove-Item "$env:windir\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue; Start-Service wuauserv } } }
        "7" = @{ Label = "Check Pending Reboot"; Action = { Run-Task "Pending Reboot" {
                    $pending = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
                    Write-Host "Can khoi dong lai: $pending"
                } } }
        "8" = @{ Label = "Update History"; Action = { Run-Task "Update History" { Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20 | Format-Table } } }
        "9" = @{ Label = "Disable Windows Update (service)"; Action = { Run-Task "Disable Update" -NeedConfirm $true -ConfirmMsg "CANH BAO BAO MAT: may se khong duoc va loi." {
                    Stop-Service wuauserv -Force
                    Set-Service wuauserv -StartupType Disabled
                    New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Force | Out-Null
                    Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" NoAutoUpdate 1 -Type DWord
                } } }
        "10" = @{ Label = "Enable Windows Update (service)"; Action = { Run-Task "Enable Update" {
                    Set-Service wuauserv -StartupType Manual
                    Start-Service wuauserv
                    Remove-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" NoAutoUpdate -ErrorAction SilentlyContinue
                } } }
    }
    Show-Menu -Title "WINDOWS UPDATE" -Options $opts
}

function Menu-Audio {
    $opts = [ordered]@{
        "1" = @{ Label = "Restart Windows Audio"; Action = { Run-Task "Restart Audio" { Restart-Service Audiosrv -Force } } }
        "2" = @{ Label = "Restart Audio Endpoint Builder"; Action = { Run-Task "Restart Endpoint Builder" { Restart-Service AudioEndpointBuilder -Force } } }
        "3" = @{ Label = "List Playback Devices"; Action = { Run-Task "Playback Devices" { Get-CimInstance Win32_SoundDevice | Format-Table Name, Status } } }
        "4" = @{ Label = "List Recording Devices"; Action = { Run-Task "Recording Devices" { Get-PnpDevice -Class AudioEndpoint | Format-Table FriendlyName, Status } } }
        "5" = @{ Label = "Set Default Playback (mo Sound Settings)"; Action = { Run-Task "Default Playback" { Start-Process mmsys.cpl } } }
        "6" = @{ Label = "Set Default Microphone (mo Sound Settings)"; Action = { Run-Task "Default Microphone" { Start-Process mmsys.cpl } } }
        "7" = @{ Label = "Check Audio Driver"; Action = { Run-Task "Audio Driver" { Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq "MEDIA" } | Format-Table DeviceName, DriverVersion, DriverDate } } }
        "8" = @{ Label = "Open Sound Settings"; Action = { Run-Task "Sound Settings" { Start-Process ms-settings:sound } } }
        "9" = @{ Label = "Audio Diagnostic"; Action = { Run-Task "Audio Diagnostic" { Start-Process msdt.exe -ArgumentList "/id AudioPlaybackDiagnostic" } } }
    }
    Show-Menu -Title "AUDIO" -Options $opts
}

function Menu-Startup {
    $opts = [ordered]@{
        "1" = @{ Label = "List Startup Apps"; Action = { Run-Task "Startup Apps" { Get-CimInstance Win32_StartupCommand | Format-Table Name, Command, Location -AutoSize } } }
        "2" = @{ Label = "Disable Startup App (mo Task Manager)"; Action = { Run-Task "Disable Startup" { Start-Process taskmgr.exe } } }
        "3" = @{ Label = "Enable Startup App (mo Task Manager)"; Action = { Run-Task "Enable Startup" { Start-Process taskmgr.exe } } }
        "4" = @{ Label = "Scheduled Tasks"; Action = { Run-Task "Scheduled Tasks" { Get-ScheduledTask | Where-Object State -eq 'Ready' | Select-Object -First 30 | Format-Table TaskName, State } } }
        "5" = @{ Label = "Background Services"; Action = { Run-Task "Background Services" { Get-Service | Where-Object StartType -eq 'Automatic' | Format-Table Name, Status } } }
        "6" = @{ Label = "Startup Diagnostic"; Action = { Run-Task "Startup Diagnostic" {
                    $os = Get-CimInstance Win32_OperatingSystem
                    Write-Host "Lan khoi dong gan nhat: $($os.LastBootUpTime)"
                } } }
    }
    Show-Menu -Title "STARTUP / BACKGROUND APPS" -Options $opts
}

function Menu-AdvancedTools {
    $opts = [ordered]@{
        "1"  = @{ Label = "Registry Editor"; Action = { Start-Process regedit.exe } }
        "2"  = @{ Label = "Local Group Policy"; Action = { Start-Process gpedit.msc } }
        "3"  = @{ Label = "Services"; Action = { Start-Process services.msc } }
        "4"  = @{ Label = "Task Scheduler"; Action = { Start-Process taskschd.msc } }
        "5"  = @{ Label = "Event Viewer"; Action = { Start-Process eventvwr.msc } }
        "6"  = @{ Label = "Device Manager"; Action = { Start-Process devmgmt.msc } }
        "7"  = @{ Label = "Computer Management"; Action = { Start-Process compmgmt.msc } }
        "8"  = @{ Label = "System Properties"; Action = { Start-Process sysdm.cpl } }
        "9"  = @{ Label = "Environment Variables"; Action = { Start-Process rundll32.exe -ArgumentList "sysdm.cpl,EditEnvironmentVariables" } }
        "10" = @{ Label = "Disk Management"; Action = { Start-Process diskmgmt.msc } }
        "11" = @{ Label = "Resource Monitor"; Action = { Start-Process resmon.exe } }
    }
    Show-Menu -Title "ADVANCED / DEVELOPER TOOLS" -Options $opts
}

function Update-GPAndTimezone {
    Run-Task -Title "CAP NHAT GROUP POLICY & TIMEZONE" -Action {
        gpupdate /force
        tzutil /s "SE Asia Standard Time"
    }
}

function Menu-Maintenance {
    $opts = [ordered]@{
        "1" = @{ Label = "Windows Cleanup (Quick/Deep Clean)"; Action = { Menu-WindowsCleanup } }
        "2" = @{ Label = "Performance"; Action = { Menu-Performance } }
        "3" = @{ Label = "Power Management"; Action = { Menu-PowerManagement } }
        "4" = @{ Label = "Explorer Tweaks"; Action = { Menu-ExplorerTweaks } }
        "5" = @{ Label = "Windows Standard"; Action = { Menu-WindowsStandard } }
        "6" = @{ Label = "Windows Update"; Action = { Menu-WindowsUpdate } }
        "7" = @{ Label = "Audio"; Action = { Menu-Audio } }
        "8" = @{ Label = "Startup / Background Apps"; Action = { Menu-Startup } }
        "9" = @{ Label = "Advanced / Developer Tools"; Action = { Menu-AdvancedTools } }
        "10" = @{ Label = "Cap nhat Group Policy va Timezone"; Action = { Update-GPAndTimezone } }
    }
    Show-Menu -Title "4. SYSTEM MAINTENANCE" -Options $opts
}

# ============================================================
# 5. SOFTWARE (tai ve + tu mo cai dat, CHI CHON 1 MOI LAN)
# ============================================================

function Download-AndOpen {
    param([string]$Name, [string]$Url, [bool]$IsPage = $false)
    Clear-Host
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    if (-not (Confirm-Action "Tai/mo trang tai '$Name' tu: $Url ?")) { return }

    if ($IsPage) {
        # Mo trang tai chinh thuc de nguoi dung tu bam Download (an toan hon vi
        # link file truc tiep cua nha cung cap hay thay doi theo phien ban)
        Start-Process $Url
        Write-Log "Mo trang tai chinh thuc: $Name -> $Url"
        Write-Host "Da mo trang tai chinh thuc trong trinh duyet. Vui long bam Download va chay file sau khi tai xong." -ForegroundColor Green
    } else {
        $dest = "$env:USERPROFILE\Downloads\$($Name -replace '\s','_').exe"
        try {
            Invoke-WebRequest -Uri $Url -OutFile $dest -UseBasicParsing
            Write-Log "Da tai $Name -> $dest"
            Write-Host "Da tai xong. Dang mo file cai dat..." -ForegroundColor Green
            Start-Process $dest
        } catch {
            Write-Host "Loi khi tai: $_" -ForegroundColor Red
        }
    }
    Pause-Return
}

function Menu-Software {
    # Luu y: da chuyen sang MO TRANG TAI CHINH THUC (khong cai silent) vi:
    # 1) Yeu cau moi cua anh la "tai ve exe va mo file sau khi hoan tat"
    # 2) Link file .exe truc tiep cua tung hang thay doi theo tung ban cap nhat,
    #    trong khi trang tai chinh thuc luon on dinh -> giam rui ro link chet/gia mao.
    $opts = [ordered]@{
        "1"  = @{ Label = "WinRAR";        Action = { Download-AndOpen "WinRAR" "https://www.rarlab.com/download.htm" $true } }
        "2"  = @{ Label = "Google Chrome"; Action = { Download-AndOpen "Google_Chrome" "https://www.google.com/chrome/" $true } }
        "3"  = @{ Label = "Coc Coc";       Action = { Download-AndOpen "CocCoc" "https://coccoc.com/download" $true } }
        "4"  = @{ Label = "Zalo PC";       Action = { Download-AndOpen "Zalo" "https://zalo.me/pc" $true } }
        "5"  = @{ Label = "Zoom";          Action = { Download-AndOpen "Zoom" "https://zoom.us/download" $true } }
        "6"  = @{ Label = "Telegram";      Action = { Download-AndOpen "Telegram" "https://telegram.org/dl/desktop/win" $true } }
        "7"  = @{ Label = "WeChat";        Action = { Download-AndOpen "WeChat" "https://www.wechat.com/en/" $true } }
        "8"  = @{ Label = "KakaoTalk (link chua xac minh - xem ghi chu)"; Action = { Download-AndOpen "KakaoTalk" "https://www.kakaocorp.com/page/service/service/KakaoTalk" $true } }
        "9"  = @{ Label = "Foxit PDF Reader"; Action = { Download-AndOpen "Foxit_PDF_Reader" "https://www.foxit.com/pdf-reader/" $true } }
        "10" = @{ Label = "ImageGlass";    Action = { Download-AndOpen "ImageGlass" "https://imageglass.org/" $true } }
        "11" = @{ Label = "AnyDesk";       Action = { Download-AndOpen "AnyDesk" "https://anydesk.com/en/downloads/windows" $true } }
        "12" = @{ Label = "UltraViewer";   Action = { Download-AndOpen "UltraViewer" "https://www.ultraviewer.net/en/download" $true } }
        "13" = @{ Label = "Unikey (link chua xac minh - xem ghi chu)"; Action = { Download-AndOpen "Unikey" "https://www.unikey.org/" $true } }
        "14" = @{ Label = "Man hinh cho Fliqlo"; Action = { Download-AndOpen "Fliqlo" "https://fliqlo.com/screensaver/" $true } }
        "15" = @{ Label = "Bing Wallpaper"; Action = { Download-AndOpen "Bing_Wallpaper" "https://www.microsoft.com/en-us/bing/bing-wallpaper" $true } }
        "16" = @{ Label = "PDFgear (Edit file PDF)"; Action = { Download-AndOpen "PDFgear" "https://pdfgear.com/pdfgear-for-windows/" $true } }
    }
    Show-Menu -Title "5. SOFTWARE (chi chon 1 muc moi lan)" -Options $opts
}

# ============================================================
# MAIN MENU
# ============================================================

function Show-MainMenu {
    $opts = [ordered]@{
        "1" = @{ Label = "Network Troubleshoot"; Action = { Menu-Network } }
        "2" = @{ Label = "Printer & File Sharing"; Action = { Menu-PrinterSharing } }
        "3" = @{ Label = "System Info & Activation"; Action = { Menu-SystemInfo } }
        "4" = @{ Label = "System Maintenance"; Action = { Menu-Maintenance } }
        "5" = @{ Label = "Software"; Action = { Menu-Software } }
    }
    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " BO CONG CU DA DUNG CHO WINDOWS"
        Write-Host " Phat trien boi Mr.Hai"
        Write-Host "========================================" -ForegroundColor Cyan
        foreach ($k in $opts.Keys) { Write-Host "$k. $($opts[$k].Label)" }
        Write-Host "6. Exit (hoac nhan ESC)"
        $c = Read-Esc "Chon muc: "
        if ($c -eq $Global:ESC -or $c -eq "6") { break }
        if ($opts.Contains($c)) { & $opts[$c].Action }
    } while ($true)

    Write-Log "Nguoi dung thoat toolkit"
    Write-Host "Cam on da su dung." -ForegroundColor Cyan
}

Show-MainMenu
