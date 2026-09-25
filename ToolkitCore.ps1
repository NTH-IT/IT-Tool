# ============================================================
#  BO CONG CU DA DUNG CHO WINDOWS - CORE SCRIPT
#  Phat trien boi Mr.Hai
# ============================================================
$ErrorActionPreference = "SilentlyContinue"
$LogFile = "$env:TEMP\toolkit_actions_$(Get-Date -Format yyyyMMdd_HHmmss).log"
$Global:ESC = "##ESC##"

function Write-Log { param([string]$M); Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $env:USERNAME | $M" }
function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) { Write-Host "Can quyen Administrator." -ForegroundColor Red; Read-Host; exit }

try {
    $rawui = $Host.UI.RawUI; $buf = $rawui.BufferSize
    $buf.Width = [Math]::Max($buf.Width, 60); $buf.Height = 3000; $rawui.BufferSize = $buf
    $ws = $rawui.WindowSize; $ws.Width = 60; $ws.Height = 42; $rawui.WindowSize = $ws
} catch {}

# ============================================================
# HO TRO NHAP LIEU (ESC = quay lai/huy)
# ============================================================
function Read-Esc {
    param([string]$Prompt = "")
    if ($Prompt) { Write-Host -NoNewline $Prompt }
    $buf = ""
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Escape') { Write-Host ""; return $Global:ESC }
        if ($k.Key -eq 'Enter') { Write-Host ""; return $buf }
        if ($k.Key -eq 'Backspace') {
            if ($buf.Length -gt 0) { $buf=$buf.Substring(0,$buf.Length-1); Write-Host -NoNewline ([char]8+" "+[char]8) }
            continue
        }
        if (-not [char]::IsControl($k.KeyChar)) { $buf+=$k.KeyChar; Write-Host -NoNewline $k.KeyChar }
    }
}

function Read-IPEsc {
    param([string]$Label = "IP")
    while ($true) {
        $v = Read-Esc "${Label} (vd: 192.168.1.1): "
        if ($v -eq $Global:ESC) { return $Global:ESC }
        $v = $v.Trim()
        if ($v -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') {
            $parts = $v -split '\\.'
            $invalid = $parts | Where-Object { [int]$_ -gt 255 }
            if (-not $invalid) { return $v }
        }
        Write-Host "IP khong hop le. Vi du: 192.168.1.1 (moi phan 0-255). Nhap lai." -ForegroundColor Red
    }
}

function Confirm-Action {
    param([string]$Prompt)
    Write-Host "`nCANH BAO: $Prompt" -ForegroundColor Yellow
    $r = Read-Esc "Xac nhan? [Y/N] (ESC de huy): "
    return ($r.ToUpper() -eq "Y")
}
function Pause-Return { Write-Host ""; Read-Host "Nhan Enter de quay lai" | Out-Null }

function Download-WithProgress {
    param([string]$Url, [string]$Dest, [string]$Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $job = Start-Job -ScriptBlock {
            param($u, $d)
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $wc.DownloadFile($u, $d)
        } -ArgumentList $Url, $Dest

        $spin = @('|', '/', '-', '\'); $si = 0
        while ($job.State -eq 'Running') {
            $sz = if (Test-Path $Dest) { [math]::Round((Get-Item $Dest).Length / 1MB, 1) } else { 0 }
            Write-Host -NoNewline "`rDang tai $Name`: $($spin[$si % 4]) $sz MB - $([math]::Round($sw.Elapsed.TotalSeconds, 1))s  "
            $si++; Start-Sleep -Milliseconds 300
        }
        Write-Host ""
        $err = Receive-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        $sw.Stop()

        if ((Test-Path $Dest) -and (Get-Item $Dest).Length -gt 100000) {
            $sz = [math]::Round((Get-Item $Dest).Length / 1MB, 1)
            Write-Host "Da tai xong: $sz MB / $([math]::Round($sw.Elapsed.TotalSeconds, 1))s" -ForegroundColor Green
            return $true
        }
        Write-Host "Loi: file tai ve khong hop le (co the link het han hoac bi redirect)." -ForegroundColor Red
        return $false
    } catch {
        if (Get-Job -ErrorAction SilentlyContinue) { Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue }
        Write-Host "Loi: $_" -ForegroundColor Red; return $false
    }
}

function Show-Menu {
    param([string]$Title,$Options)
    do {
        Clear-Host
        Write-Host "===== $Title =====" -ForegroundColor Cyan
        foreach ($k in $Options.Keys) { Write-Host "$k. $($Options[$k].Label)" }
        Write-Host "0. Back"
        $c = Read-Esc "Chon: "
        if ($c -eq $Global:ESC -or $c -eq "0") { return }
        if ($Options.Contains($c)) { & $Options[$c].Action }
    } while ($true)
}

function Run-Task {
    param([string]$Title,[scriptblock]$Action,[bool]$NeedConfirm=$false,[string]$ConfirmMsg="")
    Clear-Host; Write-Host "=== $Title ===" -ForegroundColor Cyan
    if ($NeedConfirm -and (-not (Confirm-Action $ConfirmMsg))) { return }
    try { & $Action; Write-Log "$Title - OK"; Write-Host "`nHoan tat." -ForegroundColor Green }
    catch { Write-Log "$Title - LOI: $_"; Write-Host "`nLoi: $_" -ForegroundColor Red }
    Pause-Return
}

# ============================================================
# 1. NETWORK TROUBLESHOOT
# ============================================================
function Show-NetworkInfo {
    Clear-Host; Write-Host "=== THONG TIN MANG HIEN TAI ===" -ForegroundColor Cyan
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
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { Write-Host "  MAC ($($_.Name)): $($_.MacAddress)" }
    Write-Log "Xem thong tin mang"; Pause-Return
}

function Set-ComputerNameDomain {
    Clear-Host; Write-Host "=== DOI TEN MAY / DOMAIN ===" -ForegroundColor Cyan
    $newName = Read-Esc "Hostname moi (Enter bo qua, ESC huy): "
    if ($newName -eq $Global:ESC) { return }
    $newDom = Read-Esc "Domain/Workgroup moi (Enter bo qua, ESC huy): "
    if ($newDom -eq $Global:ESC) { return }
    if ($newName -eq "" -and $newDom -eq "") { return }
    if (-not (Confirm-Action "Doi ten may/domain can KHOI DONG LAI may.")) { return }
    if ($newName -ne "") { Rename-Computer -NewName $newName -Force; Write-Log "Doi hostname: $newName" }
    if ($newDom -ne "") {
        $cred = Get-Credential -Message "Tai khoan join domain (bo qua neu doi workgroup)"
        try { Add-Computer -DomainName $newDom -Credential $cred -Force; Write-Log "Join domain: $newDom" }
        catch { Add-Computer -WorkgroupName $newDom -Force; Write-Log "Doi workgroup: $newDom" }
    }
    Write-Host "Hoan tat. Vui long khoi dong lai may." -ForegroundColor Green; Pause-Return
}

function Reset-IPAddress {
    Run-Task -Title "XOA IP CU / NHAN IP MOI" -Action {
        ipconfig /release; ipconfig /flushdns; ipconfig /registerdns
        netsh winsock reset; netsh int ip reset; ipconfig /renew
    }
}

function Set-StaticIP {
    Clear-Host; Write-Host "=== DAT IP TINH ===" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceIndex -AutoSize
    $idx = Read-Esc "InterfaceIndex: "; if ($idx -eq $Global:ESC) { return }
    $ip = Read-IPEsc "Dia chi IP"; if ($ip -eq $Global:ESC) { return }
    $prefix = Read-Esc "Prefix length (vd 24): "; if ($prefix -eq $Global:ESC) { return }
    $gw = Read-IPEsc "Default Gateway"; if ($gw -eq $Global:ESC) { return }
    if (-not (Confirm-Action "Se xoa IP cu va dat IP tinh moi tren interface $idx.")) { return }
    try {
        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled -ErrorAction SilentlyContinue
        Get-NetRoute -InterfaceIndex $idx -ErrorAction SilentlyContinue | Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
        Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength ([int]$prefix) -DefaultGateway $gw -ErrorAction Stop
        Write-Log "Dat IP tinh $ip/$prefix gw $gw tren if $idx"
        Write-Host "Da dat IP tinh thanh cong." -ForegroundColor Green
    } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    Pause-Return
}

function Set-StaticDNS {
    Clear-Host; Write-Host "=== DAT DNS TINH ===" -ForegroundColor Cyan
    Get-NetAdapter | Where-Object Status -eq 'Up' | Format-Table Name, InterfaceIndex -AutoSize
    $idx = Read-Esc "InterfaceIndex: "; if ($idx -eq $Global:ESC) { return }
    $dns1 = Read-IPEsc "DNS uu tien"; if ($dns1 -eq $Global:ESC) { return }
    $dns2 = Read-IPEsc "DNS thay the (ESC bo qua)"; 
    $dnsList = @($dns1)
    if ($dns2 -ne $Global:ESC -and $dns2 -ne "") { $dnsList += $dns2 }
    try {
        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $dnsList -ErrorAction Stop
        Write-Log "Dat DNS $($dnsList -join ', ') tren if $idx"
        Write-Host "Da dat DNS: $($dnsList -join ', ')" -ForegroundColor Green
    } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    Pause-Return
}

function Reset-NetworkFull {
    Run-Task -Title "RESET MANG VE MAC DINH" -NeedConfirm $true `
      -ConfirmMsg "Xoa cau hinh mang, DNS, Data Usage. KHONG THE HOAN TAC." -Action {
        netsh winsock reset; netsh int ip reset; netsh advfirewall reset
        ipconfig /flushdns
        Get-NetAdapter | ForEach-Object {
            Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses -ErrorAction SilentlyContinue
        }
        net stop dosvc 2>$null; net start dosvc 2>$null
    }
}

function Menu-Network {
    Show-Menu -Title "1. NETWORK TROUBLESHOOT" -Options ([ordered]@{
        "1"=@{Label="Kiem tra thong tin mang";Action={Show-NetworkInfo}}
        "2"=@{Label="Dat lai ten may (Hostname/Domain)";Action={Set-ComputerNameDomain}}
        "3"=@{Label="Xoa IP cu, nhan IP moi";Action={Reset-IPAddress}}
        "4"=@{Label="Dat IP tinh";Action={Set-StaticIP}}
        "5"=@{Label="Dat DNS tinh";Action={Set-StaticDNS}}
        "6"=@{Label="Reset mang ve mac dinh";Action={Reset-NetworkFull}}
    })
}

# ============================================================
# 2. PRINTER & FILE SHARING
# ============================================================
function Add-CheckRow { param($L,[string]$N,[bool]$P,[string]$D=""); $L.Add([PSCustomObject]@{Hang_muc=$N;Ket_qua=$(if($P){"[OK]"}else{"[LOI]"});Chi_tiet=$D}) }

function Test-FileSharingLan {
    Clear-Host; Write-Host "=== CHAN DOAN CAI DAT CHIA SE FILE QUA LAN ===" -ForegroundColor Cyan
    $r = New-Object System.Collections.ArrayList
    $s = Get-Service LanmanServer; Add-CheckRow $r "Service Server" ($s.Status -eq 'Running') $s.Status
    $w = Get-Service LanmanWorkstation; Add-CheckRow $r "Service Workstation" ($w.Status -eq 'Running') $w.Status
    $nd = Get-NetFirewallRule -DisplayGroup "Network Discovery" | Where-Object Enabled -eq $true
    Add-CheckRow $r "Firewall Network Discovery" ($nd.Count -gt 0) "$($nd.Count) rule bat"
    $fs = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | Where-Object Enabled -eq $true
    Add-CheckRow $r "Firewall File Sharing" ($fs.Count -gt 0) "$($fs.Count) rule bat"
    $smb = Get-SmbServerConfiguration; Add-CheckRow $r "SMB2 Enabled" $smb.EnableSMB2Protocol "SMB1=$($smb.EnableSMB1Protocol)"
    $r | Format-Table -AutoSize
    Write-Log "Chan doan file sharing LAN"; Pause-Return
}

function Test-PrinterPipeline {
    Clear-Host; Write-Host "=== CHAN DOAN CAI DAT MAY IN ===" -ForegroundColor Cyan
    $r = New-Object System.Collections.ArrayList
    $s = Get-Service LanmanServer; Add-CheckRow $r "Server (LanmanServer)" ($s.Status -eq 'Running') $s.Status
    $rpc = Get-Service RpcSs; Add-CheckRow $r "RPC (RpcSs)" ($rpc.Status -eq 'Running') $rpc.Status
    $smb = Get-SmbServerConfiguration; Add-CheckRow $r "SMB" $smb.EnableSMB2Protocol "SMB2=$($smb.EnableSMB2Protocol)"
    $spl = Get-Service Spooler; Add-CheckRow $r "Print Spooler" ($spl.Status -eq 'Running') $spl.Status
    $fw = Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" | Where-Object Enabled -eq $true
    Add-CheckRow $r "Firewall" ($fw.Count -gt 0) "$($fw.Count) rule bat"
    $sh = Get-Printer | Where-Object Shared -eq $true; Add-CheckRow $r "Printer Share" ($sh.Count -gt 0) "$($sh.Count) may in share"
    $drv = Get-PrinterDriver; Add-CheckRow $r "Driver" ($drv.Count -gt 0) "$($drv.Count) driver"
    $port = Get-PrinterPort; Add-CheckRow $r "Port" ($port.Count -gt 0) "$($port.Count) port"
    $pp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
    Add-CheckRow $r "Point&Print Policy" (Test-Path $pp) $(if(Test-Path $pp){"Co tuy chinh"}else{"Mac dinh"})
    $r | Format-Table -AutoSize
    Write-Log "Chan doan may in"; Pause-Return
}

function Run-PrinterFixTool {
    Clear-Host; Write-Host "=== CHAY PrinterFixTool.exe ===" -ForegroundColor Cyan
    $url = "https://www.dropbox.com/scl/fi/dcikx3xca62823quaeuua/PrinterFixTool.exe?rlkey=4hcris5xdgp0x4syv9tpp87la&st=yk97weqx&dl=1"
    $path = "$env:TEMP\PrinterFixTool_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "PrinterFixTool.exe"
    if ($ok -and (Test-Path $path)) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Host "Dang chay PrinterFixTool.exe (quyen admin)..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait
        $sw.Stop()
        Write-Host "Thoi gian chay: $([math]::Round($sw.Elapsed.TotalSeconds,1)) giay" -ForegroundColor Green
        Write-Log "Chay PrinterFixTool.exe - $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
        Remove-Item $path -Force -ErrorAction SilentlyContinue
    }
    Pause-Return
}

function Menu-PrinterSharing {
    Show-Menu -Title "2. PRINTER & FILE SHARING" -Options ([ordered]@{
        "1"=@{Label="Chan doan cai dat chia se file qua LAN";Action={Test-FileSharingLan}}
        "2"=@{Label="Chan doan cai dat may in";Action={Test-PrinterPipeline}}
        "3"=@{Label="Chay PrinterFixTool.exe";Action={Run-PrinterFixTool}}
    })
}

# ============================================================
# 3. SYSTEM INFO & ACTIVATION
# ============================================================
$DDR_MAP  = @{17="SDRAM";18="SGRAM";19="RDRAM";20="DDR";21="DDR2";22="DDR2 FB-DIMM";24="DDR3";26="DDR4";27="LPDDR";28="LPDDR2";29="LPDDR3";30="LPDDR4";32="LPDDR4X";34="DDR5";35="LPDDR5"}
$FF_MAP   = @{7="SIMM";8="DIMM";12="SODIMM";13="SRIMM";14="FBDIMM"}
$BAT_MAP  = @{1="Dang xa pin (Discharging)";2="Dang sac / AC";3="Day pin (Full)";4="Pin yeu (Low)";5="Pin toi han (Critical)";6="Dang sac (Charging)";7="Sac + Day (High)";8="Sac + Pin yeu";9="Sac + Toi han";10="Khong xac dinh";11="Sac mot phan"}

function Show-SoftwareInfo {
    Clear-Host; Write-Host "=== THONG TIN PHAN MEM ===" -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "Ten may           : $($cs.Name)"
    Write-Host "User dang dung    : $env:USERNAME"
    Write-Host "He dieu hanh      : $($os.Caption)"
    Write-Host "Build             : $($os.BuildNumber)"
    Write-Host "Domain/Workgroup  : $($cs.Domain)"
    Write-Host "PartOfDomain      : $($cs.PartOfDomain)"
    $off = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\*\Common\ProductVersion" -EA SilentlyContinue
    if ($off) { Write-Host "Office version    : $($off.LastProduct)" }
    Get-NetIPConfiguration | ForEach-Object {
        Write-Host "--- $($_.InterfaceAlias) ---"
        Write-Host "  IP              : $($_.IPv4Address.IPAddress)"
        Write-Host "  Gateway         : $($_.IPv4DefaultGateway.NextHop)"
        Write-Host "  DNS             : $($_.DNSServer.ServerAddresses -join ', ')"
    }
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { Write-Host "  MAC ($($_.Name)): $($_.MacAddress)" }
    Write-Log "Xem thong tin phan mem"; Pause-Return
}

function Show-HardwareInfoFull {
    Clear-Host; Write-Host "=== THONG TIN PHAN CUNG ===" -ForegroundColor Cyan
    $cs=Get-CimInstance Win32_ComputerSystem; $p=Get-CimInstance Win32_ComputerSystemProduct
    $b=Get-CimInstance Win32_BIOS; $os=Get-CimInstance Win32_OperatingSystem
    Write-Host "Hang san xuat : $($cs.Manufacturer)"
    Write-Host "Model may     : $($p.Name)"
    Write-Host "Serial number : $($p.IdentifyingNumber)"
    Write-Host "UUID          : $($p.UUID)"
    Write-Host "BIOS Version  : $($b.SMBIOSBIOSVersion)"
    Write-Host "BIOS Date     : $($b.ReleaseDate)"
    $up=(Get-Date)-$os.LastBootUpTime; Write-Host "Uptime        : $($up.Days)d $($up.Hours)h $($up.Minutes)m"

    Write-Host "`n--- CPU ---" -ForegroundColor Yellow
    $cpu=Get-CimInstance Win32_Processor
    Write-Host "Ten             : $($cpu.Name)"
    Write-Host "So core         : $($cpu.NumberOfCores)"
    Write-Host "Logical Proc.   : $($cpu.NumberOfLogicalProcessors)"
    Write-Host "Toc do hien tai : $($cpu.CurrentClockSpeed) MHz"
    Write-Host "Toc do toi da   : $($cpu.MaxClockSpeed) MHz"
    Write-Host "Socket          : $($cpu.SocketDesignation)"
    Write-Host "CPU Load        : $($cpu.LoadPercentage)%"
    Write-Host "Architecture    : $($cpu.AddressWidth)-bit"
    Write-Host "Family/Model    : $($cpu.Description)"

    Write-Host "`n--- RAM ---" -ForegroundColor Yellow
    $slotUsed = 0
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $slotUsed++
        $ddrName = if ($DDR_MAP.ContainsKey([int]$_.SMBIOSMemoryType)) { $DDR_MAP[[int]$_.SMBIOSMemoryType] } else { "Unknown(code=$($_.SMBIOSMemoryType))" }
        $ffName  = if ($FF_MAP.ContainsKey([int]$_.FormFactor)) { $FF_MAP[[int]$_.FormFactor] } else { "Code=$($_.FormFactor)" }
        Write-Host "Slot $($_.DeviceLocator): $([math]::Round($_.Capacity/1GB,2)) GB | $ddrName | $($_.Speed) MHz | $ffName | Mfr: $($_.Manufacturer)"
    }
    Write-Host "Slot dang dung  : $slotUsed"

    Write-Host "`n--- O CUNG ---" -ForegroundColor Yellow
    Get-PhysicalDisk | ForEach-Object { Write-Host "O dia : $($_.FriendlyName) | Health: $($_.HealthStatus) | $([math]::Round($_.Size/1GB,2)) GB" }
    Get-Volume | Where-Object DriveLetter | ForEach-Object {
        $letter=$_.DriveLetter; $free=[math]::Round($_.SizeRemaining/1GB,2); $total=[math]::Round($_.Size/1GB,2)
        $part = Get-Partition | Where-Object DriveLetter -eq $letter | Select-Object -First 1
        Write-Host "  Drive ${letter}: | Free: ${free} / ${total} GB | Partition Type: $($part.Type)"
    }

    Write-Host "`n--- GPU / VGA ---" -ForegroundColor Yellow
    Get-CimInstance Win32_VideoController | ForEach-Object {
        Write-Host "Ten         : $($_.Name)"
        Write-Host "Manufacturer: $($_.AdapterCompatibility)"
        Write-Host "VRAM        : $([math]::Round($_.AdapterRAM/1GB,2)) GB"
        Write-Host "Driver Ver  : $($_.DriverVersion)"
        Write-Host "Driver Date : $($_.DriverDate)"; Write-Host ""
    }

    Write-Host "--- MAN HINH ---" -ForegroundColor Yellow
    try {
        Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -EA Stop | ForEach-Object {
            $name=($_.UserFriendlyName|Where-Object{$_ -ne 0}|ForEach-Object{[char]$_})-join""
            $sn=($_.SerialNumberID|Where-Object{$_ -ne 0}|ForEach-Object{[char]$_})-join""
            Write-Host "EDID Name : $name | Serial: $sn"
        }
    } catch { Write-Host "(Khong doc WmiMonitorID)" }
    Get-CimInstance Win32_VideoController | ForEach-Object { Write-Host "Resolution: $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution) | Refresh: $($_.CurrentRefreshRate) Hz" }

    Write-Host "`n--- CARD MANG ---" -ForegroundColor Yellow
    Get-NetAdapter | ForEach-Object {
        $type=if($_.Name -match 'Wi-?Fi|Wireless|WLAN'){'Wi-Fi'}else{'Ethernet'}
        Write-Host "$type | $($_.Name) | MAC: $($_.MacAddress) | Status: $($_.Status) | Speed: $($_.LinkSpeed)"
    }

    Write-Host "`n--- PIN LAPTOP ---" -ForegroundColor Yellow
    $bat=Get-CimInstance Win32_Battery
    if ($bat) {
        foreach ($b in $bat) {
            $st=if($BAT_MAP.ContainsKey([int]$b.BatteryStatus)){$BAT_MAP[[int]$b.BatteryStatus]}else{"Code=$($b.BatteryStatus)"}
            Write-Host "Ten  : $($b.Name)"
            Write-Host "Sac  : $($b.EstimatedChargeRemaining)%"
            Write-Host "Trang thai: $st"
        }
        try {
            Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -EA Stop | ForEach-Object {
                Write-Host "Design Capacity: $($_.DesignedCapacity) mWh | Serial: $($_.SerialNumber)"
            }
        } catch { Write-Host "(Khong doc BatteryStaticData chi tiet)" }
    } else { Write-Host "(May khong co pin)" }

    Write-Log "Xem thong tin phan cung"; Pause-Return
}

function Show-LicenseInfo {
    Clear-Host; Write-Host "=== BAN QUYEN WINDOWS / OFFICE ===" -ForegroundColor Cyan
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    $ospp = Get-ChildItem "C:\Program Files\Microsoft Office\Office*\ospp.vbs","C:\Program Files (x86)\Microsoft Office\Office*\ospp.vbs" -EA SilentlyContinue | Select-Object -First 1
    if ($ospp) { Write-Host "`n-- Office --"; cscript //nologo $ospp.FullName /dstatus }
    else { Write-Host "(Khong tim thay OSPP.VBS)" }
    Write-Log "Xem ban quyen"; Pause-Return
}

function Remove-LicenseExceptMachine {
    Clear-Host; Write-Host "=== GO BAN QUYEN (giu OEM digital license) ===" -ForegroundColor Cyan
    Write-Host "Se GO product key dang cai (MAK/KMS/Retail)." -ForegroundColor Yellow
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    if (-not (Confirm-Action "Ban chac chan muon GO product key Windows?")) { return }
    cscript //nologo "$env:windir\System32\slmgr.vbs" /upk
    cscript //nologo "$env:windir\System32\slmgr.vbs" /cpky
    Write-Log "Da go product key Windows"
    Write-Host "Trang thai moi:"; cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    Pause-Return
}

function Menu-SystemInfo {
    Show-Menu -Title "3. SYSTEM INFO & ACTIVATION" -Options ([ordered]@{
        "1"=@{Label="Thong tin phan mem";Action={Show-SoftwareInfo}}
        "2"=@{Label="Thong tin phan cung";Action={Show-HardwareInfoFull}}
        "3"=@{Label="Thong tin ban quyen (Windows/Office)";Action={Show-LicenseInfo}}
        "4"=@{Label="Kiem tra key ban quyen theo may";Action={Clear-Host;cscript //nologo "$env:windir\System32\slmgr.vbs" /dlv;Pause-Return}}
        "5"=@{Label="Go bo ban quyen (giu lai theo may)";Action={Remove-LicenseExceptMachine}}
    })
}

# ============================================================
# 4. SYSTEM MAINTENANCE
# ============================================================
function Get-FolderSizeMB { param([string]$P); if(-not(Test-Path $P)){return 0}; $s=(Get-ChildItem $P -Recurse -Force -EA SilentlyContinue|Measure-Object -Property Length -Sum).Sum; if($null-eq$s){return 0}; return [math]::Round($s/1MB,2) }

function Invoke-CleanupFlow {
    param([bool]$Deep)
    $items=[ordered]@{"User Temp"="$env:TEMP";"Windows Temp"="$env:windir\Temp";"Windows Update"="$env:windir\SoftwareDistribution\Download";"Recycle Bin"="$env:SystemDrive\`$Recycle.Bin";"Error Reports"="$env:LOCALAPPDATA\Microsoft\Windows\WER"}
    if ($Deep) { $items["Packages"]="$env:LOCALAPPDATA\Packages"; $items["LocalLow"]="$env:USERPROFILE\AppData\LocalLow" }
    Clear-Host; Write-Host "=== CLEANUP ANALYSIS ===" -ForegroundColor Cyan
    $total=0
    foreach ($k in $items.Keys) { $sz=Get-FolderSizeMB $items[$k]; $total+=$sz; Write-Host ("{0,-18} {1,10} MB" -f $k,$sz) }
    Write-Host "────────────────────────────"
    Write-Host ("{0,-18} {1,10} MB" -f "Potentially removable",[math]::Round($total,2)) -ForegroundColor Yellow
    $c = Read-Esc "`nClean selected items? [Y/N] (ESC de huy): "
    if ($c -eq $Global:ESC -or $c.ToUpper() -ne "Y") { Pause-Return; return }
    foreach ($k in $items.Keys) {
        if ($k -eq "Recycle Bin") { Clear-RecycleBin -Force -EA SilentlyContinue; continue }
        Remove-Item "$($items[$k])\*" -Recurse -Force -EA SilentlyContinue
    }
    if ($Deep) {
        Stop-Service DPS -Force -EA SilentlyContinue
        Remove-Item "$env:windir\System32\sru\*" -Force -EA SilentlyContinue
        Start-Service DPS -EA SilentlyContinue
        wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
    }
    Write-Log "$(if($Deep){'Deep'}else{'Quick'}) Clean - $total MB"
    $actual=0; foreach($k in $items.Keys){$actual+=Get-FolderSizeMB $items[$k]}
    Write-Host "`nDa don xong. Da giai phong: $([math]::Round($total-$actual,2)) MB" -ForegroundColor Green; Pause-Return
}

function Menu-Cleanup {
    Show-Menu -Title "Windows Cleanup / Don dep Windows" -Options ([ordered]@{
        "1"=@{Label="Don qua / Quick Clean";Action={Invoke-CleanupFlow -Deep $false}}
        "2"=@{Label="Don ky / Deep Clean";Action={Invoke-CleanupFlow -Deep $true}}
    })
}

function Menu-Performance {
    Show-Menu -Title "Performance / Hieu nang" -Options ([ordered]@{
        "1"=@{Label="Disable Visual Effects / Tat hieu ung hinh anh";Action={Run-Task "Disable Visual Effects" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" VisualFXSetting 2 -Force}}}
        "2"=@{Label="Disable Transparency / Tat trong suot";Action={Run-Task "Disable Transparency" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" EnableTransparency 0 -Force}}}
        "3"=@{Label="Disable Animations / Tat hoat hinh";Action={Run-Task "Disable Animations" {Set-ItemProperty "HKCU:\Control Panel\Desktop\WindowMetrics" MinAnimate 0 -Force}}}
        "4"=@{Label="Adjust Virtual Memory / Dieu chinh bo nho ao";Action={Start-Process SystemPropertiesAdvanced.exe}}
        "5"=@{Label="Manage Startup / Quan ly ung dung khoi dong";Action={Start-Process taskmgr.exe}}
        "6"=@{Label="Performance Diagnostic / Chan doan hieu nang";Action={Run-Task "Performance Diagnostic" {
            $cpu=(Get-CimInstance Win32_Processor).LoadPercentage
            $os=Get-CimInstance Win32_OperatingSystem
            $ramPct=[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1)
            Write-Host "CPU Load : $cpu%"; Write-Host "RAM Used : $ramPct%"
        }}}
    })
}

function Menu-PowerManagement {
    Show-Menu -Title "Power Management / Quan ly nguon dien" -Options ([ordered]@{
        "1"=@{Label="Power Plan Settings / Che do nguon dien (Balanced/High/Saver)";Action={Start-Process powercfg.cpl}}
        "2"=@{Label="Screen Timeout / Thoi gian tat man hinh";Action={Run-Task "Screen Timeout" {
            $m=Read-Esc "So phut (0=khong bao gio, ESC huy): "
            if($m -ne $Global:ESC){powercfg /change monitor-timeout-ac $m; powercfg /change monitor-timeout-dc $m}
        }}}
        "3"=@{Label="Sleep Timeout / Thoi gian ngu";Action={Run-Task "Sleep Timeout" {
            $m=Read-Esc "So phut (0=khong bao gio, ESC huy): "
            if($m -ne $Global:ESC){powercfg /change standby-timeout-ac $m; powercfg /change standby-timeout-dc $m}
        }}}
        "4"=@{Label="Lid Close Action / Hanh dong gap man hinh";Action={Start-Process powercfg.cpl}}
        "5"=@{Label="Power Button Action / Hanh dong nut nguon";Action={Start-Process powercfg.cpl}}
        "6"=@{Label="Battery Report / Bao cao pin";Action={Run-Task "Battery Report" {
            $out = "$env:USERPROFILE\Desktop\battery-report.html"
            if (Test-Path $out) { Remove-Item $out -Force -EA SilentlyContinue }
            $r = & powercfg /batteryreport /output $out 2>&1
            Start-Sleep 1
            if (Test-Path $out) {
                Write-Host "Da xuat: $out" -ForegroundColor Green
                Start-Process $out
            } else {
                Write-Host "Khong xuat duoc. May co the la PC ban (khong co pin)." -ForegroundColor Yellow
                Write-Host "Chi tiet: $r" -ForegroundColor Gray
            }
        }}}
        "7"=@{Label="Power Efficiency Report / Bao cao hieu qua nguon";Action={Run-Task "Power Efficiency Report" {
            $out = "$env:USERPROFILE\Desktop\energy-report.html"
            if (Test-Path $out) { Remove-Item $out -Force -EA SilentlyContinue }
            Write-Host "Dang phan tich (60 giay)..." -ForegroundColor Yellow
            $r = & powercfg /energy /output $out /duration 20 2>&1
            Start-Sleep 2
            if (Test-Path $out) {
                Write-Host "Da xuat: $out" -ForegroundColor Green
                Start-Process $out
            } else {
                Write-Host "Khong xuat duoc." -ForegroundColor Yellow
                Write-Host "Chi tiet: $r" -ForegroundColor Gray
            }
        }}}
    })
}

function Menu-ExplorerTweaks {
    Show-Menu -Title "Explorer Tweaks / Tinh chinh Explorer" -Options ([ordered]@{
        "1"=@{Label="Show File Extensions / Hien duoi file";Action={Run-Task "Show Extensions" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0}}}
        "2"=@{Label="Show Hidden Files / Hien file an";Action={Run-Task "Show Hidden" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Hidden 1}}}
        "3"=@{Label="Show Protected OS Files / Hien file he thong";Action={Run-Task "Show OS Files" -NeedConfirm $true -ConfirmMsg "Hien file he thong co the gay xoa nham." {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ShowSuperHidden 1}}}
        "4"=@{Label="Show Full Path / Hien duong dan day du";Action={Run-Task "Full Path" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" FullPath 1}}}
        "5"=@{Label="Open This PC / Mo This PC";Action={Run-Task "Open This PC" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" LaunchTo 1}}}
        "6"=@{Label="Disable Recent Files / Tat file gan day";Action={Run-Task "Disable Recent Files" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_TrackDocs 0}}}
        "7"=@{Label="Disable Recent Folders / Tat thu muc gan day";Action={Run-Task "Disable Recent Folders" {New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoRecentDocsHistory -Value 1 -PropertyType DWord -Force | Out-Null}}}
        "8"=@{Label="Clear Explorer History / Xoa lich su Explorer";Action={Run-Task "Clear History" {Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -EA SilentlyContinue}}}
        "9"=@{Label="Restart Explorer / Khoi dong lai Explorer";Action={Run-Task "Restart Explorer" {Stop-Process -Name explorer -Force; Start-Sleep 1; Start-Process explorer.exe}}}
        "10"=@{Label="Disable Thumbnails / Tat xem truoc anh nho";Action={Run-Task "Disable Thumbnails" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" IconsOnly 1}}}
        "11"=@{Label="Enable Thumbnails / Bat xem truoc anh nho";Action={Run-Task "Enable Thumbnails" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" IconsOnly 0}}}
    })
}

function Menu-WindowsStandard {
    Show-Menu -Title "Windows Standard / Cai dat chuan Windows" -Options ([ordered]@{
        "1"=@{Label="Taskbar Left / Thanh tac vu sang trai";Action={Run-Task "Taskbar Left" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarAl 0}}}
        "2"=@{Label="Show File Extensions / Hien duoi file";Action={Run-Task "Show Extensions" {Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0}}}
        "3"=@{Label="Hide Widgets/Search/Chat / An Widget/Tim kiem/Chat";Action={Run-Task "Hide Widgets/Search/Chat" {
            Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarDa 0 -EA SilentlyContinue
            Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" SearchboxTaskbarMode 0 -EA SilentlyContinue
            Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarMn 0 -EA SilentlyContinue
        }}}
        "4"=@{Label="Hide Unnecessary Icons / An bieu tuong thua";Action={Start-Process ms-settings:taskbar}}
        "5"=@{Label="Standard Start Menu / Menu Start chuan";Action={Start-Process ms-settings:personalization-start}}
        "6"=@{Label="Restart Explorer / Khoi dong lai Explorer";Action={Run-Task "Restart Explorer" {Stop-Process -Name explorer -Force; Start-Sleep 1; Start-Process explorer.exe}}}
    })
}

function Run-UC20 {
    $url  = "https://www.dropbox.com/scl/fi/zje6jt1dx8dv1xkwnqtbi/UC20.exe?rlkey=aukmj3hkeglfj1nmu8goz3r75&st=cet0ktzf&dl=1"
    $path = "$env:TEMP\UC20_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "UC20.exe"
    if ($ok -and (Test-Path $path)) {
        Write-Host "Dang chay UC20.exe..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait
        Write-Log "Da chay UC20.exe"
        Remove-Item $path -Force -EA SilentlyContinue
    }
}

function Menu-WindowsUpdate {
    Show-Menu -Title "Windows Update / Cap nhat Windows" -Options ([ordered]@{
        "1"=@{Label="Check Update / Kiem tra cap nhat";Action={Run-Task "Check Update" {
            $svc = Get-Service wuauserv -EA SilentlyContinue
            Write-Host "Trang thai dich vu Windows Update: $($svc.Status)"
            if ($svc.Status -ne 'Running') {
                Write-Host "Dang khoi dong dich vu..." -ForegroundColor Yellow
                Start-Service wuauserv -EA SilentlyContinue
                Start-Sleep 2
            }
            Write-Host "Dang gui lenh quet cap nhat (UsoClient + wuauclt)..." -ForegroundColor Yellow
            & UsoClient.exe StartScan 2>&1 | Out-Null
            & wuauclt.exe /detectnow 2>&1 | Out-Null
            Write-Host "Da gui lenh quet thanh cong." -ForegroundColor Green
            Write-Host "Ket qua se hien tai: Cai dat -> Windows Update." -ForegroundColor Cyan
            Start-Process ms-settings:windowsupdate
        }}}
        "2"=@{Label="Open Windows Update / Mo cap nhat Windows";Action={Start-Process ms-settings:windowsupdate}}
        "3"=@{Label="Windows Update Status / Trang thai cap nhat";Action={Run-Task "Update Status" {Get-Service wuauserv|Format-Table Name,Status,StartType}}}
        "4"=@{Label="Restart Update Services / Khoi dong lai dich vu cap nhat";Action={Run-Task "Restart Services" {Restart-Service wuauserv,bits,cryptsvc -Force}}}
        "5"=@{Label="Reset Update Components / Dat lai thanh phan cap nhat";Action={Run-Task "Reset Components" -NeedConfirm $true -ConfirmMsg "Se dat lai cache Windows Update." {
            Stop-Service wuauserv,bits,cryptsvc -Force -EA SilentlyContinue
            Rename-Item "$env:windir\SoftwareDistribution" "SoftwareDistribution.bak_$(Get-Date -Format yyyyMMddHHmmss)" -EA SilentlyContinue
            Rename-Item "$env:windir\System32\catroot2" "catroot2.bak_$(Get-Date -Format yyyyMMddHHmmss)" -EA SilentlyContinue
            Start-Service wuauserv,bits,cryptsvc
        }}}
        "6"=@{Label="Clear Update Cache / Xoa cache cap nhat";Action={Run-Task "Clear Cache" {Stop-Service wuauserv -Force; Remove-Item "$env:windir\SoftwareDistribution\Download\*" -Recurse -Force -EA SilentlyContinue; Start-Service wuauserv}}}
        "7"=@{Label="Check Pending Reboot / Kiem tra cho khoi dong lai";Action={Run-Task "Pending Reboot" {Write-Host "Can restart: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')"}}}
        "8"=@{Label="Update History / Lich su cap nhat";Action={Run-Task "Update History" {Get-HotFix|Sort-Object InstalledOn -Desc|Select-Object -First 20|Format-Table}}}
        "9"=@{Label="Set Windows Update / Quan ly Windows Update (UC20.exe)";Action={Clear-Host;Write-Host "=== SET WINDOWS UPDATE (UC20.exe) ===" -ForegroundColor Cyan;Run-UC20;Pause-Return}}
    })
}

function Menu-Audio {
    Show-Menu -Title "Audio / Am thanh" -Options ([ordered]@{
        "1"=@{Label="Restart Windows Audio / Khoi dong lai am thanh";Action={Run-Task "Restart Audio" {Restart-Service Audiosrv -Force}}}
        "2"=@{Label="Restart Audio Endpoint Builder / Khoi dong lai endpoint";Action={Run-Task "Restart Endpoint" {Restart-Service AudioEndpointBuilder -Force}}}
        "3"=@{Label="List Playback Devices / Danh sach thiet bi phat";Action={Run-Task "Playback Devices" {Get-CimInstance Win32_SoundDevice|Format-Table Name,Status}}}
        "4"=@{Label="List Recording Devices / Danh sach thiet bi ghi";Action={Run-Task "Recording Devices" {Get-PnpDevice -Class AudioEndpoint|Format-Table FriendlyName,Status}}}
        "5"=@{Label="Default Playback / Thiet bi phat mac dinh";Action={Start-Process mmsys.cpl}}
        "6"=@{Label="Default Microphone / Micro mac dinh";Action={Start-Process mmsys.cpl}}
        "7"=@{Label="Check Audio Driver / Kiem tra driver am thanh";Action={Run-Task "Audio Driver" {Get-CimInstance Win32_PnPSignedDriver|Where-Object{$_.DeviceClass -eq "MEDIA"}|Format-Table DeviceName,DriverVersion,DriverDate}}}
        "8"=@{Label="Open Sound Settings / Mo cai dat am thanh";Action={Start-Process ms-settings:sound}}
        "9"=@{Label="Audio Diagnostic / Chan doan am thanh";Action={Start-Process msdt.exe -ArgumentList "/id AudioPlaybackDiagnostic"}}
    })
}

function Menu-Startup {
    Show-Menu -Title "Startup / Khoi dong" -Options ([ordered]@{
        "1"=@{Label="List Startup Apps / Danh sach ung dung khoi dong";Action={Run-Task "Startup Apps" {Get-CimInstance Win32_StartupCommand|Format-Table Name,Command,Location -AutoSize}}}
        "2"=@{Label="Disable Startup / Tat ung dung khoi dong";Action={Start-Process taskmgr.exe}}
        "3"=@{Label="Enable Startup / Bat ung dung khoi dong";Action={Start-Process taskmgr.exe}}
        "4"=@{Label="Scheduled Tasks / Nhiem vu theo lich";Action={Run-Task "Scheduled Tasks" {Get-ScheduledTask|Where-Object State -eq 'Ready'|Select-Object -First 30|Format-Table TaskName,State}}}
        "5"=@{Label="Background Services / Dich vu nen";Action={Run-Task "Background Services" {Get-Service|Where-Object StartType -eq 'Automatic'|Format-Table Name,Status}}}
        "6"=@{Label="Startup Diagnostic / Chan doan khoi dong";Action={Run-Task "Startup Diagnostic" {$os=Get-CimInstance Win32_OperatingSystem;Write-Host "Lan khoi dong gan nhat: $($os.LastBootUpTime)"}}}
    })
}

function Menu-AdvancedTools {
    Show-Menu -Title "Advanced Tools / Cong cu nang cao" -Options ([ordered]@{
        "1"=@{Label="Registry Editor / Trinh chinh sua Registry";Action={Start-Process regedit.exe}}
        "2"=@{Label="Local Group Policy / Chinh sach nhom";Action={Start-Process gpedit.msc}}
        "3"=@{Label="Services / Dich vu he thong";Action={Start-Process services.msc}}
        "4"=@{Label="Task Scheduler / Trinh quan ly lich";Action={Start-Process taskschd.msc}}
        "5"=@{Label="Event Viewer / Xem su kien";Action={Start-Process eventvwr.msc}}
        "6"=@{Label="Device Manager / Quan ly thiet bi";Action={Start-Process devmgmt.msc}}
        "7"=@{Label="Computer Management / Quan ly may tinh";Action={Start-Process compmgmt.msc}}
        "8"=@{Label="System Properties / Thuoc tinh he thong";Action={Start-Process sysdm.cpl}}
        "9"=@{Label="Environment Variables / Bien moi truong";Action={Start-Process rundll32.exe -ArgumentList "sysdm.cpl,EditEnvironmentVariables"}}
        "10"=@{Label="Disk Management / Quan ly o dia";Action={Start-Process diskmgmt.msc}}
        "11"=@{Label="Resource Monitor / Giam sat tai nguyen";Action={Start-Process resmon.exe}}
    })
}

function Invoke-SystemRefresh {
    Clear-Host; Write-Host "=== LAM MOI HE THONG / SYSTEM REFRESH ===" -ForegroundColor Cyan
    Write-Host "[1/5] Cap nhat Group Policy..." -ForegroundColor Yellow; gpupdate /force
    Write-Host "[2/5] Dong bo thoi gian + Timezone..." -ForegroundColor Yellow
    tzutil /s "SE Asia Standard Time"
    w32tm /resync /force 2>$null
    Write-Host "[3/5] Lam moi card mang (FlushDNS + NetBIOS + ARP)..." -ForegroundColor Yellow
    ipconfig /flushdns; nbtstat -R 2>$null; arp -d * 2>$null
    Write-Host "[4/5] Khoi dong lai Explorer..." -ForegroundColor Yellow
    Stop-Process -Name explorer -Force -EA SilentlyContinue; Start-Sleep 1; Start-Process explorer.exe
    Write-Host "[5/5] Xoa Credential Cache (Kerberos Ticket Purge)..." -ForegroundColor Yellow
    klist purge 2>$null
    Write-Host "`nHoan tat lam moi he thong!" -ForegroundColor Green
    Write-Log "Lam moi he thong: GP+Timezone+Network+Explorer+Kerberos"
    Pause-Return
}

function Menu-Maintenance {
    Show-Menu -Title "4. SYSTEM MAINTENANCE / BAO TRI HE THONG" -Options ([ordered]@{
        "1"=@{Label="Windows Cleanup / Don dep Windows";Action={Menu-Cleanup}}
        "2"=@{Label="Performance / Hieu nang";Action={Menu-Performance}}
        "3"=@{Label="Power Management / Quan ly nguon dien";Action={Menu-PowerManagement}}
        "4"=@{Label="Explorer Tweaks / Tinh chinh Explorer";Action={Menu-ExplorerTweaks}}
        "5"=@{Label="Windows Standard / Cai dat chuan Windows";Action={Menu-WindowsStandard}}
        "6"=@{Label="Windows Update / Cap nhat Windows";Action={Menu-WindowsUpdate}}
        "7"=@{Label="Audio / Am thanh";Action={Menu-Audio}}
        "8"=@{Label="Startup / Background / Khoi dong va ung dung nen";Action={Menu-Startup}}
        "9"=@{Label="Advanced Tools / Cong cu nang cao";Action={Menu-AdvancedTools}}
        "10"=@{Label="Lam moi he thong / System Refresh";Action={Invoke-SystemRefresh}}
    })
}

# ============================================================
# 5. SOFTWARE (nhom theo chuc nang, chi chon 1 moi lan)
# ============================================================
function Open-OfficialSite {
    param([string]$Name,[string]$Url,[bool]$IsPlaceholder=$false)
    Clear-Host; Write-Host "=== $Name ===" -ForegroundColor Cyan
    if ($IsPlaceholder) {
        Write-Host "Chua cau hinh URL cho '$Name'." -ForegroundColor Yellow
        Write-Host "Vui long cap nhat bien `$url trong script tai ham Menu-OtherSoftware." -ForegroundColor Yellow
        Pause-Return; return
    }
    Write-Host "URL: $Url" -ForegroundColor Gray
    if (-not (Confirm-Action "Mo trang tai chinh thuc cua '$Name'?")) { return }
    Start-Process $Url
    Write-Host "Da mo trinh duyet. Tai file .exe va chay de cai dat." -ForegroundColor Green
    Write-Log "Mo trang tai: $Name -> $Url"; Pause-Return
}

function Menu-OtherSoftware {
    Show-Menu -Title "PHAN MEM KHAC / OTHER SOFTWARE" -Options ([ordered]@{
        "1"=@{Label="Office AIO 2016-2024  [Chua co link - tu nhap]";Action={Open-OfficialSite "Office AIO 2016-2024" "" $true}}
        "2"=@{Label="Office 365            [Chua co link - tu nhap]";Action={Open-OfficialSite "Office 365" "" $true}}
        "3"=@{Label="WPS Office";Action={Open-OfficialSite "WPS Office" "https://www.wps.com/download/"}}
        "4"=@{Label="LibreOffice";Action={Open-OfficialSite "LibreOffice" "https://www.libreoffice.org/download/download/"}}
        "5"=@{Label="AutoCAD 2021          [Chua co link - tu nhap]";Action={Open-OfficialSite "AutoCAD 2021" "" $true}}
    })
}

function Menu-Software {
    do {
        Clear-Host
        Write-Host "===== 5. SOFTWARE / PHAN MEM =====" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "-- LIEN LAC / COMMUNICATION --" -ForegroundColor Yellow
        Write-Host "1. Zalo PC"
        Write-Host "2. Zoom"
        Write-Host "3. Telegram"
        Write-Host "4. WeChat"
        Write-Host "5. KakaoTalk"
        Write-Host ""
        Write-Host "-- TRINH DUYET / BROWSER --" -ForegroundColor Yellow
        Write-Host "6. Google Chrome"
        Write-Host "7. Coc Coc"
        Write-Host ""
        Write-Host "-- CONG CU HE THONG / SYSTEM TOOLS --" -ForegroundColor Yellow
        Write-Host "8.  WinRAR"
        Write-Host "9.  Foxit PDF Reader"
        Write-Host "10. PDFgear (Edit file PDF)"
        Write-Host "11. ImageGlass"
        Write-Host "12. AnyDesk"
        Write-Host "13. UltraViewer"
        Write-Host "14. Unikey"
        Write-Host "15. Man hinh cho Fliqlo"
        Write-Host "16. Bing Wallpaper"
        Write-Host ""
        Write-Host "-- PHAN MEM KHAC / OTHER SOFTWARE --" -ForegroundColor Yellow
        Write-Host "17. Office / CAD / Phan mem khac..."
        Write-Host ""
        Write-Host "0. Back"
        $c = Read-Esc "Chon (chi chon 1 muc): "
        if ($c -eq $Global:ESC -or $c -eq "0") { return }
        switch ($c) {
            "1"  { Open-OfficialSite "Zalo PC"       "https://zalo.me/pc" }
            "2"  { Open-OfficialSite "Zoom"           "https://zoom.us/download" }
            "3"  { Open-OfficialSite "Telegram"       "https://telegram.org/dl/desktop/win" }
            "4"  { Open-OfficialSite "WeChat"         "https://www.wechat.com/en/" }
            "5"  { Open-OfficialSite "KakaoTalk"      "https://www.kakaocorp.com/page/service/all?lang=ENG" }
            "6"  { Open-OfficialSite "Google Chrome"  "https://www.google.com/chrome/" }
            "7"  { Open-OfficialSite "Coc Coc"        "https://coccoc.com/download" }
            "8"  { Open-OfficialSite "WinRAR"         "https://www.rarlab.com/download.htm" }
            "9"  { Open-OfficialSite "Foxit PDF Reader" "https://www.foxit.com/pdf-reader/" }
            "10" { Open-OfficialSite "PDFgear"        "https://pdfgear.com/pdfgear-for-windows/" }
            "11" { Open-OfficialSite "ImageGlass"     "https://imageglass.org/" }
            "12" { Open-OfficialSite "AnyDesk"        "https://anydesk.com/en/downloads/windows" }
            "13" { Open-OfficialSite "UltraViewer"    "https://www.ultraviewer.net/en/download.html" }
            "14" { Open-OfficialSite "Unikey"         "https://www.unikey.org/download.html" }
            "15" { Open-OfficialSite "Fliqlo Screensaver" "https://fliqlo.com/screensaver/" }
            "16" { Open-OfficialSite "Bing Wallpaper" "https://www.microsoft.com/en-us/bing/bing-wallpaper" }
            "17" { Menu-OtherSoftware }
        }
    } while ($true)
}

# ============================================================
# MAIN MENU (khong cho ESC thoat, xac nhan Y/N khi thoat)
# ============================================================
function Show-MainMenu {
    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " BO CONG CU DA DUNG CHO WINDOWS"
        Write-Host " Phat trien boi Mr.Hai"
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "1. Network Troubleshoot     / Xu ly su co mang"
        Write-Host "2. Printer & File Sharing   / May in va chia se file"
        Write-Host "3. System Info & Activation / Thong tin he thong"
        Write-Host "4. System Maintenance       / Bao tri he thong"
        Write-Host "5. Software                 / Phan mem"
        Write-Host "6. Exit                     / Thoat"
        $c = Read-Host "Chon muc"
        switch ($c) {
            "1" { Menu-Network }
            "2" { Menu-PrinterSharing }
            "3" { Menu-SystemInfo }
            "4" { Menu-Maintenance }
            "5" { Menu-Software }
            "6" {
                $confirm = Read-Host "Ban co chac muon thoat? [Y/N]"
                if ($confirm.ToUpper() -eq "Y") {
                    Write-Log "Nguoi dung thoat toolkit"
                    Write-Host "Cam on da su dung." -ForegroundColor Cyan
                    Start-Sleep 1
                    exit
                }
            }
        }
    } while ($true)
}

Show-MainMenu
