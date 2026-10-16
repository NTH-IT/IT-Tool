# ============================================================
#  BO CONG CU DA DUNG CHO WINDOWS - Phat trien boi Mr.Hai 2026
# ============================================================
if (-not $env:TOOLKIT_SESSION_ID) {
    $env:TOOLKIT_SESSION_ID = [guid]::NewGuid().ToString('N').Substring(0,8)
}
$ErrorActionPreference = "Continue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$LogFile = "$env:TEMP\toolkit_actions_$(Get-Date -Format yyyyMMdd_HHmmss).log"
$Global:ESC = "##ESC##"
$Global:NavPath = [System.Collections.Generic.List[string]]::new()
$Global:SmartctlPath = $null
$Global:SmartctlUrl  = "https://www.dropbox.com/scl/fi/ojakqjmj8ub6129idfnaz/smartctl.exe?rlkey=uibu2rdkzaejjqnfg5vml8sea&st=zs8zh3f9&dl=1"
function Write-Nav {
    if ($Global:NavPath.Count -gt 0) {
        Write-Host ("  [" + ($Global:NavPath -join ">") + "]") -ForegroundColor DarkCyan
        Write-Host ""
    }
}

function Write-Log { 
    param([string]$M)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $env:USERNAME | $M`r`n"
    try { [System.IO.File]::AppendAllText($LogFile, $line) } catch {}
}

function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ($Host.Name -eq 'Windows PowerShell ISE Host') {
    Write-Host "Khong ho tro PowerShell ISE. Hay chay bang Command Prompt / PowerShell." -ForegroundColor Red
    Read-Host
    exit
}

if (-not (Test-IsAdmin)) {
    Write-Host "Can quyen Administrator." -ForegroundColor Red
    Read-Host
    exit
}

# Canh bao khi tai khoan admin dang chay khac voi nguoi dung dang dang nhap (anh huong cac muc HKCU)
$Global:SessionUserNote = ""
try {
    $loggedUser = (Get-CimInstance Win32_ComputerSystem -EA Stop).UserName
    $curUser = "$env:USERDOMAIN\$env:USERNAME"
    if ($loggedUser -and ($loggedUser -ine $curUser)) {
        $Global:SessionUserNote = "Luu y: dang chay bang '$curUser', nguoi dung dang nhap la '$loggedUser'. Cac muc chinh HKCU se ap dung cho '$curUser'."
    }
} catch {}

try {
    $rawui = $Host.UI.RawUI
    $buf = $rawui.BufferSize
    $buf.Width = [Math]::Max($buf.Width, 62)
    $buf.Height = 3000
    $rawui.BufferSize = $buf
    $ws = $rawui.WindowSize
    $ws.Width = 62
    $ws.Height = 42
    $rawui.WindowSize = $ws
} catch {}

# ============================================================
# NHAP LIEU
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
            if ($buf.Length -gt 0) { 
                $buf = $buf.Substring(0, $buf.Length - 1)
                Write-Host -NoNewline "`b `b"
            }
            continue
        }
        if (-not [char]::IsControl($k.KeyChar)) { 
            $buf += $k.KeyChar
            Write-Host -NoNewline $k.KeyChar 
        }
    }
}

function Read-IPEsc {
    param([string]$Label = "IP")
    while ($true) {
        $v = (Read-Esc "${Label}: ").Trim()
        if ($v -eq $Global:ESC) { return $Global:ESC }
        if ($v -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') {
            $ok = $true
            foreach ($oct in @($Matches[1], $Matches[2], $Matches[3], $Matches[4])) {
                if ([int]$oct -gt 255) { $ok = $false; break }
            }
            if ($ok) { return $v }
            Write-Host "Moi phan phai trong khoang 0-255. Nhap lai." -ForegroundColor Red
        } else {
            Write-Host "IP khong hop le. Vi du: 192.168.1.1. Nhap lai." -ForegroundColor Red
        }
    }
}

function Get-PrefixLength {
    param([string]$Value)
    $s = $Value.Trim()
    if ($s -eq "") { return 24 }
    if ($s -match '^\d+$' -and [int]$s -ge 0 -and [int]$s -le 32) { return [int]$s }
    if ($s -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        $parts = $s -split '\.'
        $bin = ($parts | ForEach-Object { [Convert]::ToString([int]$_, 2).PadLeft(8, '0') }) -join ''
        return ($bin.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    return -1
}

function Select-NetIdx {
    $adapters = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    Write-Host ""
    Write-Host ("  {0,-5} {1,-22} {2}" -f "Idx", "Name", "Description") -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 56))
    foreach ($a in $adapters) {
        Write-Host ("  {0,-5} {1,-22} {2}" -f $a.InterfaceIndex, $a.Name, ($a.InterfaceDescription -replace '^\s+', ''))
    }
    Write-Host ""
    while ($true) {
        $idxStr = Read-Esc "Nhap InterfaceIndex: "
        if ($idxStr -eq $Global:ESC) { return $null }
        [int]$idxNum = 0
        if (-not [int]::TryParse($idxStr.Trim(), [ref]$idxNum)) {
            Write-Host "Vui long nhap so nguyen." -ForegroundColor Red; continue
        }
        $ad = $adapters | Where-Object InterfaceIndex -eq $idxNum
        if ($ad) {
            Write-Host ">> [$idxNum] $($ad.Name) - $($ad.InterfaceDescription)" -ForegroundColor Yellow
            $cv = Read-Esc "Tiep tuc voi card nay? [Y/N]: "
            if ($cv -eq $Global:ESC) { return $null }
            if ($cv.ToUpper() -eq "Y") { return $idxNum }
        } else {
            Write-Host "Khong tim thay InterfaceIndex $idxNum. Nhap lai." -ForegroundColor Red
        }
    }
}

function Confirm-Action {
    param([string]$Prompt)
    Write-Host "`nCANH BAO: $Prompt" -ForegroundColor Yellow
    $r = Read-Esc "Xac nhan? [Y/N] (ESC de huy): "
    return ($r.ToUpper() -eq "Y")
}

function Pause-Return {
    Write-Host ""
    Write-Host -NoNewline "Nhan Enter de quay lai"
    while ([Console]::ReadKey($true).Key -ne [ConsoleKey]::Enter) {}
    Write-Host ""
}

function Download-WithProgress {
    param([string]$Url, [string]$Dest, [string]$Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    try {
        $uri = New-Object System.Uri($Url)
        $task = $wc.DownloadFileTaskAsync($uri, $Dest)
        $spin = @('|', '/', '-', '\'); $si = 0
        $cancelled = $false
        while (-not $task.IsCompleted) {
            # Cho phep ESC de skip
            if ([Console]::KeyAvailable) {
                $k = [Console]::ReadKey($true)
                if ($k.Key -eq 'Escape') {
                    $cancelled = $true
                    try { $wc.CancelAsync() } catch {}
                    break
                }
            }
            if ($sw.Elapsed.TotalSeconds -gt 120) {
                try { $wc.CancelAsync() } catch {}
                throw "Timeout sau 120 giay, khong the tai $Name."
            }
            $sz = if (Test-Path $Dest) { [math]::Round((Get-Item $Dest).Length / 1MB, 1) } else { 0 }
            Write-Host -NoNewline "`rDang tai $Name`: $($spin[$si % 4]) $sz MB - $([math]::Round($sw.Elapsed.TotalSeconds,1))s  (ESC de huy)  "
            $si++; Start-Sleep -Milliseconds 200
        }
        Write-Host ""
        if ($cancelled) {
            Start-Sleep -Milliseconds 300
            Write-Host "Da huy tai $Name." -ForegroundColor Yellow
            Remove-Item $Dest -Force -EA SilentlyContinue
            return $false
        }
        if ($task.IsFaulted) { throw $task.Exception.InnerException }
        if ($task.IsCanceled) { throw "Qua trinh tai bi huy." }
        $sw.Stop()
        if ((Test-Path $Dest) -and (Get-Item $Dest).Length -gt 100000) {
            Write-Host "Da tai xong: $([math]::Round((Get-Item $Dest).Length/1MB,1)) MB" -ForegroundColor Green
            return $true
        }
        Write-Host "Loi: file tai ve khong hop le (co the link het han)." -ForegroundColor Red
        Remove-Item $Dest -Force -EA SilentlyContinue
        return $false
    } catch {
        Write-Host ""
        Write-Host "Loi: $_" -ForegroundColor Red
        Remove-Item $Dest -Force -EA SilentlyContinue
        return $false
    } finally {
        $wc.Dispose()
    }
}

function Show-Menu {
    param(
        [string]$Title,
        $Options,
        [string]$NavEntry = ""
    )
    if ($NavEntry) { [void]$Global:NavPath.Add($NavEntry) }
    try {
        do {
            Clear-Host
            Write-Nav
            Write-Host "===== $Title =====" -ForegroundColor Cyan

            foreach ($k in $Options.Keys) {
                # Dong tieu de nhom: __HEADER__xxxxx
                if ($k -like '__HEADER__*') {
                    Write-Host ""
                    Write-Host ("--- {0} ---" -f $Options[$k].Label) -ForegroundColor Yellow
                    continue
                }
                # Dong ngan cach: __SEP__xxxxx
                if ($k -like '__SEP__*') {
                    Write-Host ("  " + ("-" * 56)) -ForegroundColor DarkGray
                    continue
                }
                # Muc chon binh thuong
                Write-Host "$k. $($Options[$k].Label)"
            }

            Write-Host "0. Back"
            $c = Read-Esc "Chon: "
            if ($c -eq $Global:ESC -or $c -eq "0") { break }

            # Bo qua key header/separator khi nguoi dung nhap
            if ($Options.Contains($c) -and -not ($c -like '__HEADER__*') -and -not ($c -like '__SEP__*')) {
                [void]$Global:NavPath.Add($c)
                try {
                    & $Options[$c].Action
                } catch {
                    Write-Log "Menu $c LOI: $_"
                    Write-Host "`nLoi: $_" -ForegroundColor Red
                    Pause-Return
                } finally {
                    if ($Global:NavPath.Count -gt 0) { $Global:NavPath.RemoveAt($Global:NavPath.Count - 1) }
                }
            }
        } while ($true)
    } finally {
        if ($NavEntry -and $Global:NavPath.Count -gt 0) {
            $Global:NavPath.RemoveAt($Global:NavPath.Count - 1)
        }
    }
}

function Run-Task {
    param(
        [Parameter(Position=0, Mandatory=$true)][string]$Title,
        [Parameter(Position=1, Mandatory=$true)][scriptblock]$Action,
        [switch]$NeedConfirm,
        [string]$ConfirmMsg = ""
    )
    Clear-Host; Write-Nav; Write-Host "=== $Title ===" -ForegroundColor Cyan
    if ($NeedConfirm -and (-not (Confirm-Action $ConfirmMsg))) { $Global:TaskExit = 1; Pause-Return; return }
    $exitCode = 0
    $Global:LASTEXITCODE = 0
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Stop'
    try {
        & $Action | Out-Host
        if ($LASTEXITCODE -ne 0) { $exitCode = $LASTEXITCODE }
        if ($exitCode -eq 0) {
            Write-Log "$Title - OK"
            Write-Host "`nHoan tat." -ForegroundColor Green
        } else {
            Write-Log "$Title - HOAN TAT (ExitCode: $exitCode)"
            Write-Host "`nHoan tat (ma thoat: $exitCode - xem ket qua o tren)." -ForegroundColor Yellow
        }
    }
    catch {
        $exitCode = if ($LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
        Write-Log "$Title - LOI: $_ (ExitCode: $exitCode)"
        Write-Host "`nLoi: $_" -ForegroundColor Red
    }
    finally { $ErrorActionPreference = $prevEAP }
    $Global:TaskExit = $exitCode
    Pause-Return
}

function Set-RegValue {
    [CmdletBinding()]
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Get-PingMs {
    param([string]$Target, [int]$Timeout = 1000)
    $p = $null
    try {
        $p = New-Object System.Net.NetworkInformation.Ping
        $r = $p.Send($Target, $Timeout)
        if ($r.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) { return [int]$r.RoundtripTime }
        return -1
    } catch { return -1 }
    finally { if ($p) { $p.Dispose() } }
}
function Get-SmartctlPath {
    if ($Global:SmartctlPath -and (Test-Path $Global:SmartctlPath)) { return $Global:SmartctlPath }
    $local = "$env:TEMP\smartctl_toolkit.exe"
    if (Test-Path $local) { $Global:SmartctlPath = $local; return $local }
    Write-Host "Chua co smartctl, dang tai tu Dropbox..." -ForegroundColor Yellow
    $ok = Download-WithProgress -Url $Global:SmartctlUrl -Dest $local -Name "smartctl.exe"
    if ($ok -and (Test-Path $local)) {
        $Global:SmartctlPath = $local
        return $local
    }
    return $null
}

function Invoke-Smartctl {
    param([string[]]$Arguments)
    $exe = Get-SmartctlPath
    if (-not $exe) { return $null }
    try {
        $out = & $exe @Arguments 2>&1 | Out-String
        return $out
    } catch {
        return "ERROR: $_"
    }
}

# Goi smartctl theo DiskNumber, tu dong them -d <type>
function Invoke-SmartctlDisk {
    param([int]$DiskNumber, [string[]]$ExtraArgs)
    $exe = Get-SmartctlPath
    if (-not $exe) { return $null }

    $map = $Global:SmartctlDiskMap
    if (-not $map) {
        $map = Get-SmartctlScanMap
        $Global:SmartctlDiskMap = $map
    }

    if (-not $map.ContainsKey($DiskNumber)) {
        # Fallback: thu \\.\PhysicalDriveN truc tiep
        $args2 = $ExtraArgs + "\\.\PhysicalDrive$DiskNumber"
        return Invoke-Smartctl -Arguments $args2
    }

    $info = $map[$DiskNumber]
    # Cau truc lenh: <args> <device> -d <type>
    $args2 = $ExtraArgs + $info.Dev + @('-d', $info.Type)
    return Invoke-Smartctl -Arguments $args2
}

# Tra ve hashtable: DiskNumber (int) -> @{ Dev = '/dev/sda'; Type = 'nvme' }
function Get-SmartctlScanMap {
    $exe = Get-SmartctlPath
    if (-not $exe) { return @{} }

    $map = @{}

    # 1. Lay danh sach device tu --scan
    $scan = & $exe --scan 2>&1 | Out-String
    if (-not $scan) { return @{} }

    $devices = @()
    foreach ($line in ($scan -split "`n")) {
        # Dang: /dev/sda -d nvme # /dev/sda, NVMe device
        if ($line -match '^(/dev/\w+)\s+-d\s+(\w+)') {
            $devices += @{ Dev = $Matches[1]; Type = $Matches[2] }
        }
    }
    if ($devices.Count -eq 0) { return @{} }

    # 2. Voi moi device, doc serial + model
    $infoList = @()
    foreach ($d in $devices) {
        $out = & $exe -i $d.Dev -d $d.Type 2>&1 | Out-String
        $serial = ""
        $model  = ""
        $capacity = 0
        foreach ($ln in ($out -split "`n")) {
            if ($ln -match 'Serial Number:\s*([^\r\n]+)') { $serial = $Matches[1].Trim() }
            if ($ln -match 'Device Model:\s*([^\r\n]+)')  { $model  = $Matches[1].Trim() }
            if ($ln -match 'Model Number:\s*([^\r\n]+)')  { $model  = $Matches[1].Trim() }
            if ($ln -match 'User Capacity:\s*([\d,]+)')   { $capacity = [long]($Matches[1] -replace ',','') }
        }
        $infoList += @{
            Dev      = $d.Dev
            Type     = $d.Type
            Serial   = $serial
            Model    = $model
            Capacity = $capacity
        }
    }

    # 3. Lay danh sach PhysicalDisk cua Windows
    $pdList = @(Get-PhysicalDisk | Sort-Object DeviceId)

    # 4. Map theo Serial truoc, fallback theo Model
    foreach ($pd in $pdList) {
        $diskNum = [int]$pd.DeviceId
        $pdSerial = "$($pd.SerialNumber)".Trim()
        $pdModel  = "$($pd.FriendlyName)".Trim()
        $pdSize   = [long]$pd.Size

        # Uu tien khop Serial
        $match = $infoList | Where-Object {
            $_.Serial -and $pdSerial -and ($_.Serial -ieq $pdSerial)
        } | Select-Object -First 1

        # Fallback: khop Model + Capacity gan dung
        if (-not $match) {
            $match = $infoList | Where-Object {
                $_.Model -and $pdModel -and
                ($_.Model -like "*$pdModel*" -or $pdModel -like "*$_.Model*") -and
                ([math]::Abs($_.Capacity - $pdSize) -lt 1GB)
            } | Select-Object -First 1
        }

        # Fallback cuoi: map theo thu tu
        if (-not $match -and $infoList.Count -eq $pdList.Count) {
            $match = $infoList[[array]::IndexOf($pdList, $pd)]
        }

        if ($match) {
            $map[$diskNum] = @{ Dev = $match.Dev; Type = $match.Type; Serial = $match.Serial; Model = $match.Model }
        }
    }

    return $map
}

# ============================================================
# 1. NETWORK TROUBLESHOOT
# ============================================================
function Show-NetworkInfo {
    Clear-Host; Write-Nav; Write-Host "=== THONG TIN MANG & QUICK NETWORK TEST ===" -ForegroundColor Cyan
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "Hostname          : $($cs.Name)"
    Write-Host "Domain/Workgroup  : $($cs.Domain)"
    Write-Host "PartOfDomain      : $($cs.PartOfDomain)"
    Write-Host ""

    $allAdapters = @(Get-NetAdapter -EA SilentlyContinue)
    $upAdapters  = @($allAdapters | Where-Object Status -eq 'Up')

    Get-NetIPConfiguration -EA SilentlyContinue | ForEach-Object {
        $curIdx = $_.InterfaceIndex
        $adp = $upAdapters | Where-Object { $_.InterfaceIndex -eq $curIdx } | Select-Object -First 1
        Write-Host "-- Adapter: $($_.InterfaceAlias) --"
        Write-Host "  IPv4    : $($_.IPv4Address.IPAddress)"
        Write-Host "  Gateway : $($_.IPv4DefaultGateway.NextHop)"
        Write-Host "  DNS     : $($_.DNSServer.ServerAddresses -join ', ')"
        if ($adp) { Write-Host "  MAC     : $($adp.MacAddress)" }
    }

    Write-Host "`n--- DANG CHAY QUICK NETWORK TEST ---" -ForegroundColor Cyan
    if ($upAdapters.Count -eq 0) {
        Write-Host "[X] KHONG CO ADAPTER MANG NAO DANG KET NOI!" -ForegroundColor Red
        Write-Log "Xem thong tin mang & Quick Test - No Adapter Up"
        Pause-Return
        return
    }

    # Uu tien adapter co Default Gateway (tranh chon nham card ao / VPN)
    $adapter = $null
    $cfg = Get-NetIPConfiguration -EA SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if ($cfg) { $adapter = $upAdapters | Where-Object { $_.InterfaceIndex -eq $cfg.InterfaceIndex } | Select-Object -First 1 }
    if (-not $adapter) {
        $adapter = $upAdapters[0]
        $cfg = Get-NetIPConfiguration -InterfaceIndex $adapter.InterfaceIndex -EA SilentlyContinue
    }
    $idxNum = $adapter.InterfaceIndex
    $adIP   = @($cfg.IPv4Address.IPAddress)[0]
    $adGW   = @($cfg.IPv4DefaultGateway.NextHop)[0]

    # 1. Adapter
    $ok1 = $adapter.Status -eq 'Up'
    Write-Host ("[{0}] Adapter    : {1} ({2})" -f $(if($ok1){"OK"}else{"X"}), $adapter.Name, $adapter.Status) -ForegroundColor $(if($ok1){'Green'}else{'Red'})

    # 2. IP
    $ok2 = $null -ne $adIP
    Write-Host ("[{0}] IP Address : {1}" -f $(if($ok2){"OK"}else{"X"}), $(if($ok2){$adIP}else{"Khong co IP"})) -ForegroundColor $(if($ok2){'Green'}else{'Red'})

    # 3. Gateway ping
    $ok3 = $false; $gwMs = -1
    if ($adGW) {
        $gwMs = Get-PingMs $adGW
        $ok3 = $gwMs -ge 0
        Write-Host ("[{0}] Gateway    : {1} {2}" -f $(if($ok3){"OK"}else{"X"}), $adGW, $(if($ok3){"-> Ping ${gwMs}ms"}else{"-> KHONG PING DUOC"})) -ForegroundColor $(if($ok3){'Green'}else{'Yellow'})
    } else {
        Write-Host "[!] Gateway    : Khong co Gateway" -ForegroundColor Yellow
    }

    # 4. DNS
    $ok4 = $false; $dnsIp = ""
    try {
        $r4 = [System.Net.Dns]::GetHostAddresses("google.com")
        $ok4 = $r4.Count -gt 0
        $dnsIp = $r4[0].IPAddressToString
    } catch {}
    Write-Host ("[{0}] DNS        : {1}" -f $(if($ok4){"OK"}else{"X"}), $(if($ok4){"Resolve google.com -> $dnsIp"}else{"KHONG RESOLVE DUOC -> kiem tra DNS"})) -ForegroundColor $(if($ok4){'Green'}else{'Red'})

    # 5. Internet
    $ms5 = Get-PingMs "8.8.8.8"
    $ok5 = $ms5 -ge 0
    Write-Host ("[{0}] Internet   : {1}" -f $(if($ok5){"OK"}else{"X"}), $(if($ok5){"8.8.8.8 -> Reachable (${ms5}ms)"}else{"KHONG KET NOI INTERNET"})) -ForegroundColor $(if($ok5){'Green'}else{'Red'})

    Write-Host ""; Write-Host ("-" * 48) -ForegroundColor Cyan
    $allOk = $ok1 -and $ok2 -and $ok4 -and $ok5
    if ($allOk) { Write-Host "  Ket qua : TAT CA BINH THUONG" -ForegroundColor Green }
    else        { Write-Host "  Ket qua : CO LOI - Xem cac muc [X] o tren" -ForegroundColor Red }

    Write-Log "Xem thong tin mang & Quick Test - interface $idxNum"
    Pause-Return
}

function Set-ComputerNameDomain {
    Clear-Host; Write-Nav; Write-Host "=== THIET LAP TEN MAY / DOMAIN / WORKGROUP ===" -ForegroundColor Cyan
    Write-Host "1. Doi ten may (Hostname)"
    Write-Host "2. Gia nhap Domain (Join Domain)"
    Write-Host "3. Doi Workgroup"
    Write-Host "0. Quay lai"
    Write-Host ""
    $c = Read-Esc "Chon chuc nang: "
    if ($c -eq $Global:ESC -or $c -eq "0") { return }

    switch ($c) {
        "1" {
            $newName = Read-Esc "Hostname moi (ESC de huy): "
            if ($newName -eq $Global:ESC -or [string]::IsNullOrWhiteSpace($newName)) { return }
            if (-not (Confirm-Action "Doi ten may sang '$newName' (can khoi dong lai)?")) { return }
            try {
                Rename-Computer -NewName $newName.Trim() -Force -ErrorAction Stop
                Write-Log "Doi hostname: $newName"
                Write-Host "Da doi ten may thanh cong. Vui long khoi dong lai may." -ForegroundColor Green
            } catch {
                Write-Log "Doi hostname $newName LOI: $_"
                Write-Host "Loi doi ten may: $_" -ForegroundColor Red
            }
        }
        "2" {
            $newDom = Read-Esc "Ten Domain moi (ESC de huy): "
            if ($newDom -eq $Global:ESC -or [string]::IsNullOrWhiteSpace($newDom)) { return }
            $cred = Get-Credential -Message "Nhap tai khoan quan tri Domain de join '$newDom'"
            if ($null -eq $cred) { return }
            if (-not (Confirm-Action "Gia nhap domain '$newDom' (can khoi dong lai)?")) { return }
            try {
                Add-Computer -DomainName $newDom.Trim() -Credential $cred -Force -ErrorAction Stop
                Write-Log "Join domain: $newDom"
                Write-Host "Da join domain $newDom thanh cong. Vui long khoi dong lai may." -ForegroundColor Green
            } catch {
                Write-Log "Join domain $newDom LOI: $_"
                Write-Host "Loi join domain: $_" -ForegroundColor Red
            }
        }
        "3" {
            $newWg = Read-Esc "Ten Workgroup moi (ESC de huy): "
            if ($newWg -eq $Global:ESC -or [string]::IsNullOrWhiteSpace($newWg)) { return }
            if (-not (Confirm-Action "Doi Workgroup sang '$newWg' (can khoi dong lai)?")) { return }
            try {
                Add-Computer -WorkgroupName $newWg.Trim() -Force -ErrorAction Stop
                Write-Log "Doi workgroup: $newWg"
                Write-Host "Da doi Workgroup thanh cong. Vui long khoi dong lai may." -ForegroundColor Green
            } catch {
                Write-Log "Doi workgroup $newWg LOI: $_"
                Write-Host "Loi doi workgroup: $_" -ForegroundColor Red
            }
        }
    }
    Pause-Return
}

function Reset-IPAddress {
    Run-Task -Title "XOA IP CU / NHAN IP MOI" -Action {
        ipconfig /release; ipconfig /flushdns; ipconfig /registerdns
        netsh winsock reset; netsh int ip reset; ipconfig /renew
    }
}

function Set-StaticIP {
    Clear-Host; Write-Nav; Write-Host "=== DAT IP TINH ===" -ForegroundColor Cyan
    $idx = Select-NetIdx; if ($null -eq $idx) { return }
    $ip = Read-IPEsc "Dia chi IP (vd: 192.168.1.50)"; if ($ip -eq $Global:ESC) { return }
    $prefixRaw = Read-Esc "Prefix / Subnet mask (mac dinh 24 / 255.255.255.0, Enter dung mac dinh): "
    if ($prefixRaw -eq $Global:ESC) { return }
    $prefix = Get-PrefixLength $prefixRaw
    if ($prefix -lt 0) { Write-Host "Gia tri khong hop le."; Pause-Return; return }
    $gw = Read-IPEsc "Default Gateway (vd: 192.168.1.1)"; if ($gw -eq $Global:ESC) { return }
    Write-Host "`nSe dat: $ip /$prefix  GW: $gw  tren interface$idx" -ForegroundColor Yellow
    if (-not (Confirm-Action "Tiep tuc?")) { return }
    try {
        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled -EA SilentlyContinue
        Get-NetRoute -InterfaceIndex $idx -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue | Remove-NetRoute -Confirm:$false -EA SilentlyContinue
        Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -EA SilentlyContinue | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
        New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw -EA Stop | Out-Null
        Write-Log "Dat IP tinh $ip/$prefix gw $gw tren if$idx"
        Write-Host "Da dat IP tinh thanh cong." -ForegroundColor Green
    } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    Pause-Return
}

function Set-StaticDNS {
    Clear-Host; Write-Nav; Write-Host "=== DAT DNS TINH ===" -ForegroundColor Cyan
    $idx = Select-NetIdx; if ($null -eq $idx) { return }
    $dns1 = Read-IPEsc "DNS uu tien (vd: 1.1.1.1)"; if ($dns1 -eq $Global:ESC) { return }
    $dns2 = Read-IPEsc "DNS thay the (vd: 8.8.8.8, ESC bo qua)"
    $dnsList = @($dns1)
    if ($dns2 -ne $Global:ESC -and $dns2 -ne "") { $dnsList += $dns2 }
    try {
        Set-DnsClientServerAddress -InterfaceIndex $idx -ServerAddresses $dnsList -EA Stop
        Write-Log "Dat DNS $($dnsList -join ', ') tren if$idx"
        Write-Host "Da dat DNS: $($dnsList -join ', ')" -ForegroundColor Green
    } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    Pause-Return
}

function Reset-NetworkFull {
    Clear-Host; Write-Nav; Write-Host "=== RESET MANG ===" -ForegroundColor Cyan
    $adapters = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    Write-Host ""
    Write-Host ("  {0,-5} {1,-22} {2}" -f "Idx", "Name", "Description") -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 56))
    Write-Host ("  {0,-5} {1,-22} {2}" -f "ALL", "--- TAT CA ---", "Reset toan bo mang")
    foreach ($a in $adapters) {
        Write-Host ("  {0,-5} {1,-22} {2}" -f $a.InterfaceIndex, $a.Name, $a.InterfaceDescription)
    }
    Write-Host ""
    $choice = Read-Esc "Nhap InterfaceIndex hoac ALL (Enter = tat ca): "
    if ($choice -eq $Global:ESC) { return }
    $isAll = ($choice -eq "" -or $choice.ToUpper() -eq "ALL")

    if ($isAll) {
        if (-not (Confirm-Action "Se reset TOAN BO mang: winsock, int ip, DNS, Data Usage. KHONG THE HOAN TAC.")) { return }
        Write-Host "[1] winsock reset..."; netsh winsock reset
        Write-Host "[2] int ip reset..."; netsh int ip reset
        Write-Host "[3] advfirewall reset..."; netsh advfirewall reset
        Write-Host "[4] flushdns..."; ipconfig /flushdns
        Write-Host "[5] Reset DNS tren tat ca adapter..."
        Get-NetAdapter | ForEach-Object {
            Set-DnsClientServerAddress -InterfaceIndex $_.InterfaceIndex -ResetServerAddresses -EA SilentlyContinue
        }
        net stop dosvc 2>$null; net start dosvc 2>$null
        Write-Log "Reset toan bo mang (ALL)"
    } else {
        [int]$idxNum = 0
        if (-not [int]::TryParse($choice.Trim(), [ref]$idxNum)) {
            Write-Host "Gia tri khong hop le." -ForegroundColor Red; Pause-Return; return
        }
        $ad = $adapters | Where-Object InterfaceIndex -eq $idxNum
        if (-not $ad) { Write-Host "Khong tim thay interface $idxNum." -ForegroundColor Red; Pause-Return; return }
        Write-Host ">> [$idxNum] $($ad.Name)" -ForegroundColor Yellow
        if (-not (Confirm-Action "Reset interface nay: FlushDNS + Release + Winsock + IntIP + Renew. Can restart.")) { return }
        Write-Host "[1/5] Flush DNS..."; ipconfig /flushdns
        Write-Host "[2/5] Release IP ($($ad.Name))..."; ipconfig /release $ad.Name 2>$null
        Write-Host "[3/5] Winsock reset (toan cuc)..."; netsh winsock reset
        Write-Host "[4/5] Int IP reset..."; netsh int ip reset
        Write-Host "[5/5] Renew IP ($($ad.Name))..."; ipconfig /renew $ad.Name 2>$null
        Set-DnsClientServerAddress -InterfaceIndex $idxNum -ResetServerAddresses -EA SilentlyContinue
        Write-Log "Reset interface $idxNum ($($ad.Name))"
    }
    Write-Host "`nHoan tat. Khuyen nghi khoi dong lai may." -ForegroundColor Green
    Pause-Return
}

function Invoke-PingTool {
    Clear-Host; Write-Nav; Write-Host "=== PING ===" -ForegroundColor Cyan
    Write-Host ""
    $target = Read-Esc "Nhap target (IP hoac domain): "
    if ($target -eq $Global:ESC -or $target -eq "") { return }
    $cntStr = Read-Esc "So goi (mac dinh 10, Enter = 10): "
    if ($cntStr -eq $Global:ESC) { return }
    [int]$cnt = if ($cntStr -match "^\d+$" -and [int]$cntStr -gt 0) { [int]$cntStr } else { 10 }

    $isLAN = ($target -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') -or ($target -match '^(localhost|127\.)') -or ($target -notmatch '\.')

    Clear-Host; Write-Nav; Write-Host "=== PING ===" -ForegroundColor Cyan
    Write-Host "Target : $target  [$(if($isLAN){'LAN'}else{'WAN/Internet'})]"
    Write-Host "Count  : $cnt"; Write-Host ""

    $pingLines = [System.Collections.Generic.List[string]]::new()
    & ping.exe -n $cnt $target | ForEach-Object {
        Write-Host $_
        [void]$pingLines.Add([string]$_)
    }
    $pingRaw = $pingLines.ToArray()

    $sent = $cnt; $lost = 0; $minMs = -1; $avgMs = -1; $maxMs = -1
    $summaryLines = if ($pingRaw.Count -ge 6) { $pingRaw[-6..-1] } else { $pingRaw }

    foreach ($line in $summaryLines) {
        if ($line -match '\bSent\s*=\s*(\d+)')    { $sent  = [int]$Matches[1] }
        if ($line -match '\bLost\s*=\s*(\d+)')    { $lost  = [int]$Matches[1] }
        if ($line -match '\bMinimum\s*=\s*(\d+)') { $minMs = [int]$Matches[1] }
        if ($line -match '\bMaximum\s*=\s*(\d+)') { $maxMs = [int]$Matches[1] }
        if ($line -match '\bAverage\s*=\s*(\d+)') { $avgMs = [int]$Matches[1] }

        if ($line -match '\bDa\s*gui\s*=\s*(\d+)')    { $sent  = [int]$Matches[1] }
        if ($line -match '\bMat\s*=\s*(\d+)')          { $lost  = [int]$Matches[1] }
        if ($line -match '\bToi\s*thieu\s*=\s*(\d+)') { $minMs = [int]$Matches[1] }
        if ($line -match '\bToi\s*da\s*=\s*(\d+)')    { $maxMs = [int]$Matches[1] }
        if ($line -match '\bTrung\s*binh\s*=\s*(\d+)'){ $avgMs = [int]$Matches[1] }
    }

    if ($minMs -eq -1) {
        $times = [System.Collections.Generic.List[int]]::new()
        foreach ($line in $pingRaw) {
            if ($line -match '(?i)(?:time|thoi\s*gian)[=<](\d+)ms') {
                $times.Add([int]$Matches[1])
            }
        }
        if ($times.Count -gt 0) {
            $minMs = ($times | Measure-Object -Minimum).Minimum
            $maxMs = ($times | Measure-Object -Maximum).Maximum
            $avgMs = [math]::Round(($times | Measure-Object -Average).Average, 0)
            $lost  = $cnt - $times.Count
        }
    }
    if ($sent -le 0) { $sent = $cnt }
    $lostPct = [math]::Round([math]::Max(0, $lost) / [math]::Max(1, $sent) * 100, 1)

    Write-Host ""
    Write-Host ("-" * 42) -ForegroundColor Cyan
    Write-Host ("Packets   : $sent sent")
    Write-Host ("Lost      : $([math]::Max(0,$lost)) ($lostPct%)")
    if ($minMs -ge 0) {
        Write-Host ("Min       : $minMs ms")
        Write-Host ("Avg       : $avgMs ms")
        Write-Host ("Max       : $maxMs ms")
    }
    Write-Host ""

    $effAvg = if ($avgMs -ge 0) { $avgMs } else { 9999 }
    $ratingText, $ratingColor =
        if ($isLAN) {
            if ($lostPct -eq 0 -and $effAvg -le 5)       { "[OK] GOOD  - LAN on dinh (avg ${effAvg}ms)",               "Green"  }
            elseif ($lostPct -lt 5 -and $effAvg -le 50)  { "[!] FAIR  - LAN co van de nhe (loss=$lostPct%)",            "Yellow" }
            else                                           { "[X] POOR  - LAN gap su co nghiem trong",                   "Red"    }
        } else {
            if ($lostPct -lt 2 -and $effAvg -le 150)     { "[OK] GOOD  - Ket noi on dinh (avg ${effAvg}ms)",            "Green"  }
            elseif ($lostPct -lt 10 -and $effAvg -le 300){ "[!] FAIR  - Co the lag (loss=$lostPct% avg=${effAvg}ms)",   "Yellow" }
            else                                           { "[X] POOR  - Ket noi yeu hoac mat goi nhieu",               "Red"    }
        }
    Write-Host $ratingText -ForegroundColor $ratingColor
    Write-Log "Ping $target x$cnt [$(if($isLAN){'LAN'}else{'WAN'})] Loss=$lostPct% Avg=${avgMs}ms"
    Pause-Return
}

function Invoke-NetworkQuality {
    Clear-Host; Write-Nav; Write-Host "=== NETWORK QUALITY (60 giay) ===" -ForegroundColor Cyan
    Write-Host "Ping xen ke 8.8.8.8 va 1.1.1.1 trong 60 giay + Speed Test..." -ForegroundColor Gray
    Write-Host ""
    $targets   = @("8.8.8.8", "1.1.1.1")
    $latencies = [System.Collections.Generic.List[int]]::new()
    $jitters   = [System.Collections.Generic.List[double]]::new()
    $lost = 0; $total = 0; $prevMs = -1; $ti = 0; $duration = 60
    $pinger = [System.Net.NetworkInformation.Ping]::new()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        while ($sw.Elapsed.TotalSeconds -lt $duration) {
            $tgt = $targets[$ti % 2]; $ti++; $total++
            $elapsedS = [int]$sw.Elapsed.TotalSeconds
            $pct  = [math]::Min(100, [math]::Round($elapsedS / $duration * 100))
            $fill = [int]($pct / 5)
            $bar  = "#" * $fill + "-" * (20 - $fill)

            try {
                $task = $pinger.SendPingAsync($tgt, 500)
                if ($task.Wait(500) -and $task.Result.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                    $ms = [int]$task.Result.RoundtripTime
                    $latencies.Add($ms)
                    if ($prevMs -ge 0) { $jitters.Add([math]::Abs($ms - $prevMs)) }
                    $prevMs = $ms
                    Write-Host -NoNewline ("`r  [{0}] {1}%  {2} goi  {3}:{4}ms     " -f $bar, $pct,$total, $tgt,$ms)
                } else {
                    $lost++
                    Write-Host -NoNewline ("`r  [{0}] {1}%  {2} goi  {3}: TIMEOUT    " -f $bar, $pct, $total, $tgt)
                }
            } catch {
                $lost++
                Write-Host -NoNewline ("`r  [{0}] {1}%  {2} goi  {3}: TIMEOUT    " -f $bar,$pct, $total,$tgt)
            }
            Start-Sleep -Milliseconds 700
        }
    } finally {
        $pinger.Dispose()
    }
    Write-Host ""; Write-Host ""

    Write-Host "Dang do toc do download (Cloudflare 5MB)..." -ForegroundColor Yellow
    $dlMbps = -1
    try {
        $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc2  = New-Object System.Net.WebClient
        try {
            $wc2.Headers.Add("User-Agent", "Mozilla/5.0")
            $data = $wc2.DownloadData("https://speed.cloudflare.com/__down?bytes=5000000")
            $dlSw.Stop()
            if ($data.Length -gt 0) { $dlMbps = [math]::Round(($data.Length / 1MB) / $dlSw.Elapsed.TotalSeconds, 2) }
        } finally { $wc2.Dispose() }
    } catch {}

    $lossPct   = if ($total -gt 0) { [math]::Round($lost / $total * 100, 1) } else { 100 }
    $avgLat    = if ($latencies.Count -gt 0) { [math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 999 }
    $minLat    = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Minimum).Minimum } else { 0 }
    $maxLat    = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Maximum).Maximum } else { 0 }
    $avgJitter = if ($jitters.Count -gt 0)   { [math]::Round(($jitters | Measure-Object -Average).Average, 1) } else { 0 }

    Write-Host "=== KET QUA ===" -ForegroundColor Cyan
    Write-Host ("  Latency (Avg)  : {0,8} ms" -f $avgLat)
    Write-Host ("  Packet Loss    : {0,8} %"  -f $lossPct)
    Write-Host ("  Jitter         : {0,8} ms" -f $avgJitter)
    Write-Host ("  Min            : {0,8} ms" -f $minLat)
    Write-Host ("  Max            : {0,8} ms" -f $maxLat)
    if ($dlMbps -gt 0) { Write-Host ("  Download Speed : {0,6} MB/s" -f $dlMbps) -ForegroundColor Cyan }
    else               { Write-Host "  Download Speed : (Khong do duoc)" -ForegroundColor Gray }
    Write-Host ""

    $ratingText,$ratingColor =
        if    ($avgLat -lt 60  -and $lossPct -eq 0 -and $avgJitter -lt 10) {
            "[OK] EXCELLENT - Rat tot (gaming / video call 4K)",             "Green" }
        elseif($avgLat -lt 120 -and $lossPct -lt 1 -and $avgJitter -lt 25) {
            "[OK] GOOD      - On dinh, dung cho streaming va lam viec",      "Green" }
        elseif($avgLat -lt 200 -and $lossPct -lt 5) {
            "[!] FAIR       - Co the lag nhe, nen kiem tra lai router/ISP",  "Yellow" }
        else {
            "[X] POOR       - Ket noi yeu, nhieu mat goi hoac do tre cao",   "Red"   }

    Write-Host $ratingText -ForegroundColor $ratingColor
    Write-Log "NetworkQuality: Lat=${avgLat}ms Loss=${lossPct}% Jitter=${avgJitter}ms DL=${dlMbps}MB/s"
    Pause-Return
}

function Menu-Network {
    Show-Menu -Title "1. NETWORK TROUBLESHOOT" -NavEntry "1" -Options ([ordered]@{
        "1"=@{Label="Kiem tra thong tin mang & Quick Network Test";Action={Show-NetworkInfo}}
        "2"=@{Label="Dat lai ten may (Hostname/Domain/Workgroup)";Action={Set-ComputerNameDomain}}
        "3"=@{Label="Xoa IP cu, nhan IP moi";Action={Reset-IPAddress}}
        "4"=@{Label="Dat IP tinh";Action={Set-StaticIP}}
        "5"=@{Label="Dat DNS tinh";Action={Set-StaticDNS}}
        "6"=@{Label="Reset mang (chon Interface / ALL)";Action={Reset-NetworkFull}}
        "7"=@{Label="Ping";Action={Invoke-PingTool}}
        "8"=@{Label="Network Quality (60s + Speed Test)";Action={Invoke-NetworkQuality}}
    })
}

# ============================================================
# 2. PRINTER & FILE SHARING
# ============================================================
function Add-CheckRow { param($L, [string]$N, [bool]$P, [string]$D = ""); [void]$L.Add([PSCustomObject]@{Hang_muc=$N; Ket_qua=$(if($P){"[OK]"}else{"[LOI]"}); Chi_tiet=$D}) }

function Get-EnabledFwRules {
    param([string]$GroupResId, [string]$DisplayGroup)
    $rules = @(Get-NetFirewallRule -Group $GroupResId -EA SilentlyContinue)
    if ($rules.Count -eq 0) { $rules = @(Get-NetFirewallRule -DisplayGroup $DisplayGroup -EA SilentlyContinue) }
    return @($rules | Where-Object { $_.Enabled -eq 'True' })
}

function Test-FileSharingLan {
    Clear-Host; Write-Nav; Write-Host "=== CHAN DOAN CAI DAT CHIA SE FILE QUA LAN ===" -ForegroundColor Cyan
    $r = New-Object System.Collections.ArrayList
    $s = Get-Service LanmanServer -EA SilentlyContinue; Add-CheckRow $r "Service Server" ($s.Status -eq 'Running') $s.Status
    $w = Get-Service LanmanWorkstation -EA SilentlyContinue; Add-CheckRow $r "Service Workstation" ($w.Status -eq 'Running') $w.Status
    $nd = @(Get-EnabledFwRules "@FirewallAPI.dll,-32752" "Network Discovery")
    Add-CheckRow $r "Firewall Network Discovery" ($nd.Count -gt 0) "$($nd.Count) rule bat"
    $fs = @(Get-EnabledFwRules "@FirewallAPI.dll,-28502" "File and Printer Sharing")
    Add-CheckRow $r "Firewall File Sharing" ($fs.Count -gt 0) "$($fs.Count) rule bat"
    $smb = Get-SmbServerConfiguration -EA SilentlyContinue; Add-CheckRow $r "SMB2 Enabled" ([bool]$smb.EnableSMB2Protocol) "SMB1=$($smb.EnableSMB1Protocol)"
    $r | Format-Table -AutoSize | Out-Host
    Write-Log "Chan doan file sharing LAN"; Pause-Return
}

function Test-PrinterPipeline {
    Clear-Host; Write-Nav; Write-Host "=== CHAN DOAN CAI DAT MAY IN ===" -ForegroundColor Cyan
    $r = New-Object System.Collections.ArrayList
    $s = Get-Service LanmanServer -EA SilentlyContinue; Add-CheckRow $r "Server (LanmanServer)" ($s.Status -eq 'Running') $s.Status
    $rpc = Get-Service RpcSs -EA SilentlyContinue; Add-CheckRow $r "RPC (RpcSs)" ($rpc.Status -eq 'Running') $rpc.Status
    $smb = Get-SmbServerConfiguration -EA SilentlyContinue; Add-CheckRow $r "SMB" ([bool]$smb.EnableSMB2Protocol) "SMB2=$($smb.EnableSMB2Protocol)"
    $spl = Get-Service Spooler -EA SilentlyContinue; Add-CheckRow $r "Print Spooler" ($spl.Status -eq 'Running') $spl.Status
    $fw = @(Get-EnabledFwRules "@FirewallAPI.dll,-28502" "File and Printer Sharing")
    Add-CheckRow $r "Firewall" ($fw.Count -gt 0) "$($fw.Count) rule bat"
    $sh = @(Get-Printer -EA SilentlyContinue | Where-Object Shared -eq $true); Add-CheckRow $r "Printer Share" ($sh.Count -gt 0) "$($sh.Count) may in share"
    $drv = @(Get-PrinterDriver -EA SilentlyContinue); Add-CheckRow $r "Driver" ($drv.Count -gt 0) "$($drv.Count) driver"
    $port = @(Get-PrinterPort -EA SilentlyContinue); Add-CheckRow $r "Port" ($port.Count -gt 0) "$($port.Count) port"
    $pp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers\PointAndPrint"
    Add-CheckRow $r "Point&Print Policy" (Test-Path $pp) $(if(Test-Path $pp){"Co tuy chinh"}else{"Mac dinh"})
    $r | Format-Table -AutoSize | Out-Host
    Write-Log "Chan doan may in"; Pause-Return
}

function Run-PrinterFixTool {
    Clear-Host; Write-Nav; Write-Host "=== CHAY PrinterFixTool.exe ===" -ForegroundColor Cyan
    $url = "https://www.dropbox.com/scl/fi/dcikx3xca62823quaeuua/PrinterFixTool.exe?rlkey=4hcris5xdgp0x4syv9tpp87la&st=yk97weqx&dl=1"
    $path = "$env:TEMP\PrinterFixTool_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "PrinterFixTool.exe"
    if ($ok -and (Test-Path $path)) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Host "Dang chay PrinterFixTool.exe (quyen admin)..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait; $sw.Stop()
        Write-Host "Thoi gian chay: $([math]::Round($sw.Elapsed.TotalSeconds,1)) giay" -ForegroundColor Green
        Write-Log "Chay PrinterFixTool.exe - $([math]::Round($sw.Elapsed.TotalSeconds,1))s"
        Remove-Item $path -Force -EA SilentlyContinue
    } else {
        Write-Host "Da huy hoac tai that bai." -ForegroundColor Yellow
    }
    Pause-Return
}

function Menu-PrinterSharing {
    Show-Menu -Title "2. PRINTER & FILE SHARING" -NavEntry "2" -Options ([ordered]@{
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
$BAT_MAP  = @{1="Dang xa pin (Discharging)";2="Dang sac / AC";3="Day pin (Full)";4="Pin yeu (Low)";5="Pin toi han (Critical)";6="Dang sac (Charging)";7="Sac+Day";8="Sac+Pin yeu";9="Sac+Toi han";10="Khong xac dinh";11="Sac mot phan"}

function Get-GpuVramGB {
    param([string]$Name, $AdapterRam)
    try {
        $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
        foreach ($k in (Get-ChildItem -LiteralPath $base -EA SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -EA SilentlyContinue
            if ($p -and $p.DriverDesc -eq $Name -and $p.'HardwareInformation.qwMemorySize') {
                return [math]::Round([double]$p.'HardwareInformation.qwMemorySize' / 1GB, 2)
            }
        }
    } catch {}
    return [math]::Round([double]$AdapterRam / 1GB, 2)
}

function Show-SoftwareInfo {
    Clear-Host; Write-Nav; Write-Host "=== THONG TIN PHAN MEM ===" -ForegroundColor Cyan
    $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem
    Write-Host "Ten may           : $($cs.Name)"
    Write-Host "User dang dung    : $env:USERNAME"
    Write-Host "He dieu hanh      : $($os.Caption)"
    Write-Host "Build             : $($os.BuildNumber)"
    Write-Host "Domain/Workgroup  : $($cs.Domain)"
    Write-Host "PartOfDomain      : $($cs.PartOfDomain)"
    $off = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Office\*\Common\ProductVersion" -EA SilentlyContinue |
       Select-Object -First 1
    if ($off) { Write-Host "Office version    : $($off.LastProduct)" }
    Get-NetIPConfiguration | ForEach-Object {
        Write-Host "--- $($_.InterfaceAlias) ---"
        Write-Host "  IP    : $($_.IPv4Address.IPAddress)"
        Write-Host "  GW    : $($_.IPv4DefaultGateway.NextHop)"
        Write-Host "  DNS   : $($_.DNSServer.ServerAddresses -join ', ')"
    }
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { Write-Host "  MAC ($($_.Name)): $($_.MacAddress)" }
    Write-Log "Xem thong tin phan mem"; Pause-Return
}

function Show-HardwareInfoFull {
    Clear-Host; Write-Nav; Write-Host "=== THONG TIN PHAN CUNG ===" -ForegroundColor Cyan
    $cs = Get-CimInstance Win32_ComputerSystem
    $p  = Get-CimInstance Win32_ComputerSystemProduct
    $b  = Get-CimInstance Win32_BIOS
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "Hang san xuat : $($cs.Manufacturer)"
    Write-Host "Model may     : $($p.Name)"
    Write-Host "Serial number : $($p.IdentifyingNumber)"
    Write-Host "UUID          : $($p.UUID)"
    Write-Host "BIOS Version  : $($b.SMBIOSBIOSVersion)"
    Write-Host "BIOS Date     : $($b.ReleaseDate)"
    $up = (Get-Date) - $os.LastBootUpTime; Write-Host "Uptime        : $($up.Days)d $($up.Hours)h $($up.Minutes)m"
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
    Write-Host "Family/Model    : $($cpu.Description)"
    Write-Host "`n--- RAM ---" -ForegroundColor Yellow
    $slotUsed = 0
    Get-CimInstance Win32_PhysicalMemory | ForEach-Object {
        $slotUsed++
        $ddrName = if ($DDR_MAP.ContainsKey([int]$_.SMBIOSMemoryType)) { $DDR_MAP[[int]$_.SMBIOSMemoryType] } else { "Unknown(code=$($_.SMBIOSMemoryType))" }
        $ffName  = if ($FF_MAP.ContainsKey([int]$_.FormFactor)) { $FF_MAP[[int]$_.FormFactor] } else { "Code=$($_.FormFactor)" }
        Write-Host "Slot $($_.DeviceLocator): $([math]::Round($_.Capacity/1GB,2)) GB | $ddrName |$($_.Speed) MHz |$ffName | Mfr: $($_.Manufacturer)"
    }
    Write-Host "Slot dang dung  : $slotUsed"
    Write-Host "`n--- O CUNG ---" -ForegroundColor Yellow
    Get-PhysicalDisk | ForEach-Object { Write-Host "O dia : $($_.FriendlyName) | Health: $($_.HealthStatus) | $([math]::Round($_.Size/1GB,2)) GB" }
    Get-Volume | Where-Object DriveLetter | ForEach-Object {
        $letter = $_.DriveLetter; $free = [math]::Round($_.SizeRemaining/1GB,2); $total = [math]::Round($_.Size/1GB,2)
        $part = Get-Partition | Where-Object DriveLetter -eq $letter | Select-Object -First 1
        Write-Host "  Drive ${letter}: | Free: ${free} / ${total} GB | Type: $($part.Type)"
    }
    Write-Host "`n--- GPU / VGA ---" -ForegroundColor Yellow
    Get-CimInstance Win32_VideoController | ForEach-Object {
        Write-Host "Ten: $($_.Name) | Mfr: $($_.AdapterCompatibility) | VRAM: $(Get-GpuVramGB $_.Name $_.AdapterRAM) GB | Driver: $($_.DriverVersion)"; Write-Host ""
    }
    Write-Host "--- MAN HINH ---" -ForegroundColor Yellow
    try {
        Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -EA Stop | ForEach-Object {
            $name = ($_.UserFriendlyName | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            $sn   = ($_.SerialNumberID     | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) -join ""
            Write-Host "EDID: $name | Serial:$sn"
        }
    } catch { Write-Host "(Khong doc WmiMonitorID)" }
    Get-CimInstance Win32_VideoController | ForEach-Object { Write-Host "Resolution: $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution) | Refresh: $($_.CurrentRefreshRate) Hz" }
    Write-Host "`n--- CARD MANG ---" -ForegroundColor Yellow
    Get-NetAdapter | ForEach-Object {
        $type = if ($_.Name -match 'Wi-?Fi|Wireless|WLAN') { 'Wi-Fi' } else { 'Ethernet' }
        Write-Host "$type | $($_.Name) | MAC: $($_.MacAddress) | Status: $($_.Status) | Speed: $($_.LinkSpeed)"
    }
    Write-Host "`n--- PIN LAPTOP ---" -ForegroundColor Yellow
    $bat = Get-CimInstance Win32_Battery
    if ($bat) {
        foreach ($bx in $bat) {
            $st = if ($BAT_MAP.ContainsKey([int]$bx.BatteryStatus)) { $BAT_MAP[[int]$bx.BatteryStatus] } else { "Code=$($bx.BatteryStatus)" }
            Write-Host "Ten: $($bx.Name) | Sac: $($bx.EstimatedChargeRemaining)% | Trang thai: $st"
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
    Clear-Host; Write-Nav; Write-Host "=== BAN QUYEN WINDOWS / OFFICE ===" -ForegroundColor Cyan
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    $ospp = Get-ChildItem "C:\Program Files\Microsoft Office\Office*\ospp.vbs", "C:\Program Files (x86)\Microsoft Office\Office*\ospp.vbs" -EA SilentlyContinue | Select-Object -First 1
    if ($ospp) { Write-Host "`n-- Office --"; cscript //nologo $ospp.FullName /dstatus }
    else { Write-Host "(Khong tim thay OSPP.VBS)" }
    Write-Log "Xem ban quyen"; Pause-Return
}

function Remove-LicenseExceptMachine {
    Clear-Host; Write-Nav; Write-Host "=== GO BO BAN QUYEN (giu lai OEM digital license) ===" -ForegroundColor Cyan
    Write-Host "Se GO product key dang cai (MAK/KMS/Retail)." -ForegroundColor Yellow
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    if (-not (Confirm-Action "Ban chac chan muon GO product key Windows?")) { return }
    Write-Host ""
    Write-Host "XAC NHAN LAN 2: Nhan Enter de TIEP TUC, ESC de HUY." -ForegroundColor Red
    $r2 = Read-Esc ""
    if ($r2 -ne "") { Write-Host "Da huy (chi nhan Enter moi tiep tuc)."; Pause-Return; return }
    cscript //nologo "$env:windir\System32\slmgr.vbs" /upk
    cscript //nologo "$env:windir\System32\slmgr.vbs" /cpky
    Write-Log "Da go product key Windows"
    Write-Host "`nTrang thai sau khi go:"
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    Pause-Return
}

function Run-CanchinhOffice {
    Clear-Host; Write-Nav; Write-Host "=== THIET LAP OFFICE (CanchinhOffice.exe) ===" -ForegroundColor Cyan
    $url = "https://www.dropbox.com/scl/fi/5mrj2a0mikqnlw7ioaxm1/CanchinhOffice.exe?rlkey=x21xpu6osowzz1oqyg2sryeg6&st=3zvg6nye&dl=1"
    $path = "$env:TEMP\CanchinhOffice_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "CanchinhOffice.exe"
    if ($ok -and (Test-Path $path)) {
        Write-Host "Dang chay CanchinhOffice.exe (quyen admin)..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait
        Write-Log "Da chay CanchinhOffice.exe"
        Remove-Item $path -Force -EA SilentlyContinue
    } else {
        Write-Host "Da huy hoac tai that bai." -ForegroundColor Yellow
    }
    Pause-Return
}

function Get-DiskTypeInfo {
    param($PhysicalDisk)
    $busType = $PhysicalDisk.BusType
    $mediaType = $PhysicalDisk.MediaType
    $typeStr = switch ($busType) {
        'NVMe' { 'NVMe SSD' }
        'SATA' { if ($mediaType -eq 'SSD') { 'SATA SSD' } else { 'SATA HDD' } }
        'USB'  { 'USB' }
        default { "$busType / $mediaType" }
    }
    return $typeStr
}

function Show-DiskList {
    $disks = @(Get-PhysicalDisk | Sort-Object DeviceId)
    if ($disks.Count -eq 0) {
        Write-Host "Khong tim thay o cung nao." -ForegroundColor Red
        return ,@()
    }
    Write-Host ""
    Write-Host ("  {0,-4} {1,-28} {2,-10} {3,12} {4,-10}" -f "Idx", "Model", "Type", "Size(GB)", "Health") -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 72))
    $i = 1
    foreach ($d in $disks) {
        $sizeGB = [math]::Round($d.Size / 1GB, 2)
        $typeStr = Get-DiskTypeInfo $d
        $health = $d.HealthStatus
        $color = if ($health -eq 'Healthy') { 'Green' } elseif ($health -eq 'Warning') { 'Yellow' } else { 'Red' }
        Write-Host ("  {0,-4} {1,-28} {2,-10} {3,12} {4,-10}" -f $i, $d.FriendlyName, $typeStr, $sizeGB, $health) -ForegroundColor $color
        $i++
    }
    Write-Host ""
    return ,$disks
}

function Show-DiskInfoBlock {
    param($Disk, $DiskNumber)
    $pd = Get-PhysicalDisk | Where-Object DeviceId -eq $DiskNumber | Select-Object -First 1
    if (-not $pd) { return }

    $sizeGB = [math]::Round($pd.Size / 1GB, 2)
    $partStyle = try { (Get-Disk -Number $DiskNumber -EA Stop).PartitionStyle } catch { "Unknown" }

    $fw = "N/A"; $serial = "N/A"; $temp = "N/A"
    $smartInfo = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-i')
    if ($smartInfo) {
        if ($smartInfo -match 'Firmware Version:\s*([^\r\n]+)') { $fw = $Matches[1].Trim() }
        if ($smartInfo -match 'Serial Number:\s*([^\r\n]+)')     { $serial = $Matches[1].Trim() }
    }
    $smartAll = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-A')
    if ($smartAll -match 'Temperature:\s*(\d+)') { $temp = "$($Matches[1]) C" }	

    Write-Host "--- Disk Information ---" -ForegroundColor Cyan
    Write-Host ("  Model            : {0}" -f $pd.FriendlyName)
    Write-Host ("  Serial Number    : {0}" -f $serial)
    Write-Host ("  Firmware         : {0}" -f $fw)
    Write-Host ("  Disk Type        : {0}" -f (Get-DiskTypeInfo $pd))
    Write-Host ("  Bus Type         : {0}" -f $pd.BusType)
    Write-Host ("  Interface        : {0}" -f $pd.BusType)
    Write-Host ("  Capacity         : {0} GB" -f $sizeGB)
    Write-Host ("  Partition Style  : {0}" -f $partStyle)
    $sectorSize = try { (Get-Disk -Number $DiskNumber).LogicalSectorSize } catch { "N/A" }
    $physSector = try { (Get-Disk -Number $DiskNumber).PhysicalSectorSize } catch { "N/A" }
    Write-Host ("  Sector size      : {0} bytes" -f $sectorSize)
    Write-Host ("  Logical sector   : {0} bytes" -f $sectorSize)
    Write-Host ("  Physical sector  : {0} bytes" -f $physSector)
    Write-Host ("  Temperature      : {0}" -f $temp)
    Write-Host ""

    Write-Host "--- Partition / Free Space ---" -ForegroundColor Cyan
    Write-Host ("  {0,-6} {1,-12} {2,10} {3,10} {4,10} {5,10}" -f "Drive", "FileSystem", "Size(GB)", "Used(GB)", "Free(GB)", "% Free")
    Write-Host ("  " + ("-" * 66))
    $parts = Get-Partition -DiskNumber $DiskNumber -EA SilentlyContinue
    foreach ($p in $parts) {
        if (-not $p.DriveLetter) { continue }
        $vol = Get-Volume -DriveLetter $p.DriveLetter -EA SilentlyContinue
        if (-not $vol) { continue }
        $szGB = [math]::Round($vol.Size / 1GB, 2)
        $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
        $usedGB = [math]::Round($szGB - $freeGB, 2)
        $pctFree = if ($szGB -gt 0) { [math]::Round(($freeGB / $szGB) * 100, 1) } else { 0 }
        Write-Host ("  {0,-6} {1,-12} {2,10} {3,10} {4,10} {5,10}" -f "$($p.DriveLetter):", $vol.FileSystem, $szGB, $usedGB, $freeGB, "$pctFree%")
    }
    Write-Host ""
}

function Show-SmartAttributes {
    param($Disk, $DiskNumber)
    $pd = Get-PhysicalDisk | Where-Object DeviceId -eq $DiskNumber | Select-Object -First 1
    $isNvme = $pd.BusType -eq 'NVMe'
    $isSsd  = $pd.MediaType -eq 'SSD'
    $isHdd  = -not $isSsd -and -not $isNvme

    $smart = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-A')
    if (-not $smart) {
        Write-Host "Khong doc duoc SMART (can smartctl hoac o khong ho tro)." -ForegroundColor Yellow
        return
    }

    Write-Host "--- SMART Information ---" -ForegroundColor Cyan

    $poh = $null; $pc = $null; $used = $null; $spare = $null; $spareThr = $null
    $dur = $null; $duw = $null; $unsafe = $null; $mediaErr = $null; $errLog = $null
    $realloc = $null; $pending = $null; $offline = $null; $reportUnc = $null
    $seekErr = $null; $spinRetry = $null; $startStop = $null

    foreach ($line in ($smart -split "`n")) {
        if ($line -match 'Percentage Used:\s*(\d+)%') { $used = "$($Matches[1])%" }
        if ($line -match 'Available Spare:\s*(\d+)%') { $spare = "$($Matches[1])%" }
        if ($line -match 'Available Spare Threshold:\s*(\d+)%') { $spareThr = "$($Matches[1])%" }
        if ($line -match 'Data Units Read:\s*([\d,]+)') { $dur = $Matches[1] }
        if ($line -match 'Data Units Written:\s*([\d,]+)') { $duw = $Matches[1] }
        if ($line -match 'Power Cycles:\s*([\d,]+)') { $pc = $Matches[1] }
        if ($line -match 'Power On Hours:\s*([\d,]+)') { $poh = $Matches[1] }
        if ($line -match 'Unsafe Shutdowns:\s*([\d,]+)') { $unsafe = $Matches[1] }
        if ($line -match 'Media and Data Integrity Errors:\s*([\d,]+)') { $mediaErr = $Matches[1] }
        if ($line -match 'Error Information Log Entries:\s*([\d,]+)') { $errLog = $Matches[1] }
        if ($line -match 'Reallocated_Sector_Ct.*?\s(\d+)$') { $realloc = $Matches[1] }
        if ($line -match 'Current_Pending_Sector.*?\s(\d+)$') { $pending = $Matches[1] }
        if ($line -match 'Offline_Uncorrectable.*?\s(\d+)$') { $offline = $Matches[1] }
        if ($line -match 'Reported_Uncorrect.*?\s(\d+)$') { $reportUnc = $Matches[1] }
        if ($line -match 'Seek_Error_Rate.*?\s(\d+)$') { $seekErr = $Matches[1] }
        if ($line -match 'Spin_Retry_Count.*?\s(\d+)$') { $spinRetry = $Matches[1] }
        if ($line -match 'Start_Stop_Count.*?\s(\d+)$') { $startStop = $Matches[1] }
        if ($line -match 'Power_Cycle_Count.*?\s(\d+)$') { $pc = $Matches[1] }
        if ($line -match 'Power_On_Hours.*?\s(\d+)$') { $poh = $Matches[1] }
    }

    if ($isNvme) {
        Write-Host ("  Percentage Used          : {0}" -f $used)
        Write-Host ("  Available Spare          : {0}" -f $spare)
        Write-Host ("  Available Spare Thresh.  : {0}" -f $spareThr)
        Write-Host ("  Data Units Read          : {0}" -f $dur)
        Write-Host ("  Data Units Written       : {0}" -f $duw)
        Write-Host ("  Power Cycles             : {0}" -f $pc)
        Write-Host ("  Power On Hours           : {0} h" -f $poh)
        Write-Host ("  Unsafe Shutdowns         : {0}" -f $unsafe)
        Write-Host ("  Media Errors             : {0}" -f $mediaErr)
        Write-Host ("  Error Info Log Entries   : {0}" -f $errLog)
    } elseif ($isSsd) {
        Write-Host ("  Percentage Used          : {0}" -f $used)
        Write-Host ("  Available Spare          : {0}" -f $spare)
        Write-Host ("  Available Spare Thresh.  : {0}" -f $spareThr)
        Write-Host ("  Data Units Read          : {0}" -f $dur)
        Write-Host ("  Data Units Written       : {0}" -f $duw)
        Write-Host ("  Power Cycles             : {0}" -f $pc)
        Write-Host ("  Power On Hours           : {0} h" -f $poh)
        Write-Host ("  Unsafe Shutdowns         : {0}" -f $unsafe)
        Write-Host ("  Media Errors             : {0}" -f $mediaErr)
    } else {
        Write-Host ("  Reallocated Sector Count    : {0}" -f $realloc)
        Write-Host ("  Current Pending Sector      : {0}" -f $pending)
        Write-Host ("  Offline Uncorrectable       : {0}" -f $offline)
        Write-Host ("  Reported Uncorrectable Errs : {0}" -f $reportUnc)
        Write-Host ("  Seek Error Rate             : {0}" -f $seekErr)
        Write-Host ("  Spin Retry Count            : {0}" -f $spinRetry)
        Write-Host ("  Start/Stop Count            : {0}" -f $startStop)
        Write-Host ("  Power-On Hours              : {0}" -f $poh)
        Write-Host ("  Power Cycle Count           : {0}" -f $pc)
    }
    Write-Host ""

    Write-Host "--- Thong so quan trong ---" -ForegroundColor Cyan
    $pohNum = 0
    if ($poh) { $pohNum = [int]($poh -replace ',','') }
    $pcNum = 0
    if ($pc) { $pcNum = [int]($pc -replace ',','') }

    $days = [math]::Round($pohNum / 24, 1)
    $months = [math]::Round($days / 30, 1)
    $years = [math]::Round($days / 365, 2)
    Write-Host ("  Power On Hours (POH)       : {0} h  (~{1} ngay / {2} thang / {3} nam)" -f $pohNum, $days, $months, $years)
    Write-Host ("  Power Cycle Count          : {0}" -f $pcNum)
    if ($pcNum -gt 0) {
        $avgHours = [math]::Round($pohNum / $pcNum, 2)
        Write-Host ("  Average usage per power cyc: {0} h/lan" -f $avgHours)
    } else {
        Write-Host "  Average usage per power cyc: N/A"
    }
    Write-Host ""
}

function Show-SmartExtras {
    param($DiskNumber)
    while ($true) {
        Write-Host "--- SMART Extras ---" -ForegroundColor Cyan
        Write-Host "  1. Xem lich su Self-Test (smartctl -l seltest)"
        Write-Host "  2. Xem Full SMART (smartctl -x)"
        Write-Host "  0. Quay lai"
        $c = Read-Esc "Chon: "
        if ($c -eq $Global:ESC -or $c -eq "0") { return }

        if ($c -eq "1") {
            Clear-Host
            Write-Host "=== Self-Test Log ===" -ForegroundColor Cyan
			$out = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-l', 'selftest')
            if ($out) { Write-Host $out } else { Write-Host "(Khong doc duoc)" -ForegroundColor Yellow }
            Pause-Return
        }
        elseif ($c -eq "2") {
            Clear-Host
            Write-Host "=== Full SMART (-x) ===" -ForegroundColor Cyan
            Write-Host "  [1] View on screen"
            Write-Host "  [2] Save to TXT"
            Write-Host "  [3] Back"
            $cc = Read-Esc "Chon: "
            if ($cc -eq $Global:ESC -or $cc -eq "3") { continue }
			$out = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-x') 
            if (-not $out) { Write-Host "(Khong doc duoc)" -ForegroundColor Yellow; Pause-Return; continue }
            if ($cc -eq "1") {
                Clear-Host
                Write-Host "=== Full SMART (-x) ===" -ForegroundColor Cyan
                Write-Host $out
                Pause-Return
            }
            elseif ($cc -eq "2") {
                $dest = [IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), "smartctl_disk$DiskNumber`_$(Get-Date -Format yyyyMMdd_HHmmss).txt")
                try {
                    [System.IO.File]::WriteAllText($dest, $out)
                    Write-Host "Da luu: $dest" -ForegroundColor Green
                    Write-Log "Luu smartctl -x disk$DiskNumber vao $dest"
                } catch {
                    Write-Host "Loi luu file: $_" -ForegroundColor Red
                }
                Pause-Return
            }
        }
    }
}

function Invoke-SurfaceTest {
    param($DiskNumber, $DiskType)
    Write-Host ""
    Write-Host "=== SURFACE TEST - QUICK (READ-ONLY) ===" -ForegroundColor Cyan
    Write-Host "Test nay kich hoat short self-test cua firmware o cung."
    Write-Host "Doc lap, khong ghi du lieu. Thoi gian: 1-3 phut tuy loai o."
    Write-Host ""

    $c = Read-Esc "Tiep tuc kiem tra be mat? [Y/N]: "
    if ($c.ToUpper() -ne "Y") { return }

    Write-Host ""
    Write-Host "Dang kich hoat short test..." -ForegroundColor Yellow
	$trigger = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-t', 'short')
    if ($trigger) {
        # Chi hien dong dau de tranh roi man hinh
        $firstLines = ($trigger -split "`n") | Select-Object -First 5
        foreach ($l in $firstLines) { Write-Host $l -ForegroundColor Gray }
    }

    Write-Host ""
    Write-Host "Dang theo doi tien do (ESC de dung theo doi)..." -ForegroundColor Cyan
    Write-Host ""

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $maxWait = 300    # toi da 5 phut
    $readErr = 0
    $stopPolling = $false
    $lastPct = 0
    $done = $false

    while ($sw.Elapsed.TotalSeconds -lt $maxWait -and -not $stopPolling -and -not $done) {
        # Cho phep ESC de dung
        if ([Console]::KeyAvailable) {
            $k = [Console]::ReadKey($true)
            if ($k.Key -eq 'Escape') {
                $stopPolling = $true
                break
            }
        }
        $selftest = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-l', 'selftest')
        $remainPct = $null
        $statusLine = ""
        $isDone = $false
        $errCount = 0

        if ($selftest) {
            foreach ($line in ($selftest -split "`n")) {
                # % remaining: vd "90% of test remaining"
                if ($line -match '(\d+)%\s+of\s+test\s+remaining') {
                    $remainPct = [int]$Matches[1]
                }
                if ($line -match 'Self-test execution status:\s*(.+)') {
                    $statusLine = $Matches[1].Trim()
                }
                if ($line -match 'without error|completed successfully|Self-test routine in progress') {
                    if ($line -match 'without error|completed successfully') { $isDone = $true }
                }
                # Loi doc trong log
                if ($line -match 'Error\s+(\d+)\s+occurred') { $errCount++ }
            }
        }

        if ($isDone) { $done = $true; $remainPct = 0 }

        # Tinh % hoan thanh
        $pct = if ($null -ne $remainPct) { 100 - $remainPct } else { $lastPct }
        if ($pct -gt $lastPct) { $lastPct = $pct }
        if ($pct -lt 0) { $pct = 0 }
        if ($pct -gt 100) { $pct = 100 }

        # Ve thanh 100 o
        $filled = [int]($pct)          # 1% = 1 o
        if ($filled -gt 100) { $filled = 100 }
        $bar = ("#" * $filled) + ("-" * (100 - $filled))

        Write-Host -NoNewline ("`rProgress : {0,3}%   Read Error : {1}   [{2}]" -f $pct, $readErr, $bar)
        if ($statusLine) {
            Write-Host -NoNewline ("   $statusLine" + " " * 10)
        }

        if ($done) { break }
        Start-Sleep -Milliseconds 3000
    }

    Write-Host ""
    Write-Host ""

    if ($stopPolling) {
        Write-Host "Da dung theo doi (test van co the dang chay trong nen o cung)." -ForegroundColor Yellow
        Write-Host "Co the xem lai ket qua bang muc 'SMART Extras > 1. Self-Test Log'." -ForegroundColor Gray
    } elseif ($done) {
        Write-Host "=== KET QUA SURFACE TEST ===" -ForegroundColor Cyan
        $final = Invoke-SmartctlDisk -DiskNumber $DiskNumber -ExtraArgs @('-l', 'selftest')		
        if ($final) {
            $lines = ($final -split "`n") | Where-Object { $_ -match '\S' }
            foreach ($l in $lines) { Write-Host $l }
        }
        Write-Host ""
        Write-Host "Read Error: $readErr" -ForegroundColor $(if($readErr -eq 0){'Green'}else{'Red'})
        if ($readErr -eq 0) {
            Write-Host "Ket qua: Be mat o cung KHONG phat hien loi doc." -ForegroundColor Green
        } else {
            Write-Host "Ket qua: Phat hien $readErr loi doc. Nen backup du lieu ngay!" -ForegroundColor Red
        }
    } else {
        Write-Host "Het thoi gian theo doi (5 phut). Test co the van dang chay." -ForegroundColor Yellow
    }
    Write-Log "Surface Test disk$DiskNumber (readErr=$readErr)"
}

function Show-DiskDiagnostic {
    Clear-Host; Write-Nav; Write-Host "=== DISK / SSD DIAGNOSTIC ===" -ForegroundColor Cyan
    Write-Host "Cong cu chan doan o cung (HDD/SSD/NVMe) - Su dung smartctl." -ForegroundColor Gray
    Write-Host ""

    # Kiem tra smartctl
    $smart = Get-SmartctlPath
    if (-not $smart) {
        Write-Host "Khong tai duoc smartctl.exe. Khong the chan doan chi tiet." -ForegroundColor Red
        Pause-Return
        return
    }
    Write-Host "Da co smartctl: $smart" -ForegroundColor Green

    # Reset cache map device
    $Global:SmartctlDiskMap = $null
    Write-Host ""

    # Buoc 1: Liet ke o cung
    $disks = Show-DiskList
    if (-not $disks) { Pause-Return; return }

    # Nhap lua chon. Cho phep nhap lai neu sai, khong thoat ra ngoai
	$disk = $null
	$sel  = 0
	$maxIdx = @($disks).Count
while ($true) {
    $choice = Read-Esc "Nhap Index o cung can kiem tra (ESC de huy): "
    if ($choice -eq $Global:ESC) { return }

    # Loai bo moi ky tu khong phai chu so
    $clean = ($choice -replace '[^\d]', '').Trim()
    if ($clean -eq "") {
        Write-Host "Vui long nhap so tu 1 den $maxIdx." -ForegroundColor Red
        continue
    }
    [int]$num = 0
    if (-not [int]::TryParse($clean, [ref]$num)) {
        Write-Host "Khong phai so hop le." -ForegroundColor Red
        continue
    }
    if ($num -lt 1 -or $num -gt $maxIdx) {
        Write-Host "Ngoai pham vi. Chi chap nhan 1..$maxIdx." -ForegroundColor Red
        continue
    }
    $sel  = $num
    $disk = @($disks)[$sel - 1]
    break
}
	$diskNumber = [int]$disk.DeviceId
	$diskType = Get-DiskTypeInfo $disk

    # Buoc 2: Hien Disk Information + Partition/Free Space
    Clear-Host; Write-Nav; Write-Host "=== DISK / SSD DIAGNOSTIC ===" -ForegroundColor Cyan
    Write-Host ">> Da chon: [$sel] $($disk.FriendlyName) - $diskType" -ForegroundColor Yellow
    Write-Host ""
    Show-DiskInfoBlock -Disk $disk -DiskNumber $diskNumber

    # Buoc 3: Xac nhan xem SMART
    Write-Host "Nhan Enter de xem thong tin SMART (ESC de thoat)..." -ForegroundColor Cyan
    $k = [Console]::ReadKey($true)
    if ($k.Key -eq 'Escape') { return }

    # Buoc 4: Hien SMART attributes
    Clear-Host; Write-Nav; Write-Host "=== SMART INFORMATION ===" -ForegroundColor Cyan
    Write-Host ">> Disk: $($disk.FriendlyName) - $diskType" -ForegroundColor Yellow
    Write-Host ""
    Show-SmartAttributes -Disk $disk -DiskNumber $diskNumber

    # Buoc 5: SMART Extras
    Show-SmartExtras -DiskNumber $diskNumber

    # Buoc 6: Surface Test
    Invoke-SurfaceTest -DiskNumber $diskNumber -DiskType $diskType
    Write-Host ""
    Write-Host "Hoan tat chan doan o cung." -ForegroundColor Green
    Write-Log "Disk Diagnostic: disk$diskNumber ($diskType)"
    Pause-Return
}

# ============================================================
# BITLOCKER HELPERS
# ============================================================

# ============================================================
# MICROSOFT ACTIVATION SCRIPTS (MAS) & LICENSE KEY CONVERTER
# ============================================================
function Invoke-MAS {
    Clear-Host; Write-Nav; Write-Host "=== MICROSOFT ACTIVATION SCRIPTS (MAS) ===" -ForegroundColor Cyan
    Write-Host "Cong cu kich hoat Windows/Office (open source)." -ForegroundColor Gray
    Write-Host "Nguon: https://get.activated.win" -ForegroundColor Gray
    Write-Host ""
    Write-Host "CANH BAO: Chi su dung cho muc dich hoc tap / kich hoat hop phap." -ForegroundColor Yellow
    Write-Host ""

    if (-not (Confirm-Action "Ban chac chan muon chay MAS?")) { return }

    Write-Host ""
    Write-Host "[1/3] Dang thu cach 1: irm https://get.activated.win | iex" -ForegroundColor Yellow
    $ok = $false
    try {
        Invoke-RestMethod "https://get.activated.win" -EA Stop | Invoke-Expression
        $ok = $true
        Write-Log "MAS lan 1 - OK"
    } catch {
        Write-Host "Cach 1 loi: $_" -ForegroundColor Red
        Write-Log "MAS lan 1 - LOI: $_"
    }

    if (-not $ok) {
        Write-Host ""
        Write-Host "[2/3] Dang thu cach 2 (fallback qua Cloudflare DoH)..." -ForegroundColor Yellow
        try {
            $script = (curl.exe -s --doh-url https://1.1.1.1/dns-query https://get.activated.win | Out-String)
            if ([string]::IsNullOrWhiteSpace($script)) { throw "Khong lay duoc noi dung script." }
            Invoke-Expression $script
            $ok = $true
            Write-Log "MAS lan 2 - OK"
        } catch {
            Write-Host "Cach 2 loi: $_" -ForegroundColor Red
            Write-Log "MAS lan 2 - LOI: $_"
        }
    }

    if (-not $ok) {
        Write-Host ""
        Write-Host "[3/3] Ca 2 cach deu that bai." -ForegroundColor Red
        Write-Host "Kiem tra ket noi Internet hoac DNS, sau do thu lai." -ForegroundColor Yellow
        Write-Log "MAS - that bai ca 2 cach"
    }
    Pause-Return
}

function Run-LicenseKeyConverter {
    Clear-Host; Write-Nav; Write-Host "=== LICENSE KEY CONVERTER 1.0.0 ===" -ForegroundColor Cyan
    Write-Host "Cong cu chuyen doi / kiem tra ban quyen Windows." -ForegroundColor Gray
    Write-Host ""
    $url = "https://www.dropbox.com/scl/fi/4tx2dpe2k9igum9nakojw/LKC1.0.exe?rlkey=xjr6m4w9mcq44nv9zhkcm2sg1&st=zqnr3kyl&dl=1"
    $path = "$env:TEMP\LKC1.0_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "LKC1.0.exe"
    if ($ok -and (Test-Path $path)) {
        Write-Host "Dang chay LKC1.0.exe (quyen admin)..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait
        Write-Log "Da chay LKC1.0.exe"
        Remove-Item $path -Force -EA SilentlyContinue
    } else {
        Write-Host "Da huy hoac tai that bai." -ForegroundColor Yellow
    }
    Pause-Return
}

function Menu-SystemInfo {
    Show-Menu -Title "3. SYSTEM INFO & ACTIVATION" -NavEntry "3" -Options ([ordered]@{
        "1" =@{Label="Thong tin phan mem";Action={Show-SoftwareInfo}}
        "2" =@{Label="Thong tin phan cung";Action={Show-HardwareInfoFull}}
        "3" =@{Label="Thong tin ban quyen (Windows/Office)";Action={Show-LicenseInfo}}
        "4" =@{Label="Kiem tra key ban quyen theo may";Action={Clear-Host;cscript //nologo "$env:windir\System32\slmgr.vbs" /dlv;Pause-Return}}
        "5" =@{Label="Go bo ban quyen (giu lai theo may)";Action={Remove-LicenseExceptMachine}}
        "6" =@{Label="Thiet lap Office (CanchinhOffice.exe)";Action={Run-CanchinhOffice}}
        "7" =@{Label="Tool Hardware Check / Cong cu Kiem tra phan cung";Action={Run-HardwareTest}}
        "8" =@{Label="DISK / SSD DIAGNOSTIC / Chan doan o cung";Action={Show-DiskDiagnostic}}
        "9" =@{Label="Microsoft Activation Scripts (MAS)";Action={Invoke-MAS}}
        "10"=@{Label="License Key Converter 1.0.0";Action={Run-LicenseKeyConverter}}
    })
}

# ============================================================

# ============================================================
#  MODULE LOADER - Tu dong tai module khi can
# ============================================================
$Global:LoadedModules = @{}
$Global:ModuleFiles = @{
    'Maintenance' = "https://cdn.jsdelivr.net/gh/NTH-IT/IT-Tool@main/Maintenance.ps1"
    'Software'    = "https://cdn.jsdelivr.net/gh/NTH-IT/IT-Tool@main/Software.ps1"
    'BitLocker'   = "https://cdn.jsdelivr.net/gh/NTH-IT/IT-Tool@main/BitLocker.ps1"
}

function Install-Module {
    param([string]$Name)
    $path = "$env:TEMP\${Name}_$($env:TOOLKIT_SESSION_ID).ps1"
    Write-Host "  Dang tai module $Name ..." -ForegroundColor Yellow
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Global:ModuleFiles[$Name] -OutFile $path -UseBasicParsing -EA Stop
        return $path
    } catch {
        Write-Host "  Loi tai module ${Name}: $_" -ForegroundColor Red
        return $null
    }
}

# ⭐ Load tất cả module ở TOP-LEVEL, KHÔNG bọc trong function
foreach ($mod in @('Maintenance', 'Software', 'BitLocker')) {
    $path = Install-Module -Name $mod
    if ($path) {
        try {
            . $path
            $Global:LoadedModules[$mod] = $true
            Write-Host "  Module $mod san sang." -ForegroundColor Green
        } catch {
            Write-Host "  Loi dot-source module ${mod}: $_" -ForegroundColor Red
        }
    }
}

function Show-MainMenu {
    do {
        Clear-Host
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "  BO CONG CU DA DUNG CHO WINDOWS - Mr.Hai 2026" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host "  [1] Network TroubleShoot (Chan doan & Sua loi mang)"
        Write-Host "  [2] Printer & File Sharing (Chia se file & May in)"
        Write-Host "  [3] System Info & Activation (Thong tin & Ban quyen)"
        Write-Host "  [4] System Maintenance (Bao tri he thong & Don dep)"
        Write-Host "  [5] Software (Cai dat phan mem tien ich)"
        Write-Host "  [6] BitLocker Management (Quan ly ma hoa o dia)"
        Write-Host "  [7] Thoat (Exit)"
        Write-Host "============================================================" -ForegroundColor Cyan
        
        $c = Read-Esc "Chon chuc nang [1-7]: "

        if ($c -eq $Global:ESC -or $c -eq "7") {
            $confirm = Read-Esc "Ban co chac muon thoat? [Y/N]: "
            if ($confirm.ToUpper() -eq "Y") {
                Write-Log "Nguoi dung thoat toolkit"
                Write-Host ""
                Write-Host "Cam on da su dung." -ForegroundColor Cyan
                Write-Host ""
                return
            }
            continue
        }

        switch ($c) {
            "1" { try { Menu-Network } catch { Write-Host "Loi: $_" -ForegroundColor Red; Pause-Return } }
            "2" { try { Menu-PrinterSharing } catch { Write-Host "Loi: $_" -ForegroundColor Red; Pause-Return } }
            "3" { try { Menu-SystemInfo } catch { Write-Host "Loi: $_" -ForegroundColor Red; Pause-Return } }
            "4" { try { _Menu-Maintenance } catch { Write-Host "Loi: $_" -ForegroundColor Red; Pause-Return } }
            "5" { try { _Menu-Software }    catch { Write-Host "Loi: $_" -ForegroundColor Red; Pause-Return } }
            "6" { try { _Menu-BitLocker }   catch { Write-Host "Loi: $_" -ForegroundColor Red; Pause-Return } }
            default { 
                Write-Host "Lua chon khong hop le. Vui long chon tu 1 den 7." -ForegroundColor Yellow
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}

try {
    Show-MainMenu
} finally {
    Write-Host "Dang don dep file tam..." -ForegroundColor Gray
    $SID = $env:TOOLKIT_SESSION_ID
    $patterns = @(
        "$env:TEMP\ToolkitCore_$SID.ps1",
        "$env:TEMP\Maintenance_$SID.ps1",
        "$env:TEMP\Software_$SID.ps1",
        "$env:TEMP\BitLocker_$SID.ps1",
        "$env:TEMP\PrinterFixTool_*.exe",
        "$env:TEMP\UC20_*.exe",
        "$env:TEMP\CanchinhOffice_*.exe",
        "$env:TEMP\HardwareTest_*.exe",
        "$env:TEMP\1398_*.exe",
        "$env:TEMP\LKC1.0_*.exe",
        "$env:TEMP\smartctl_toolkit.exe"
    )
    $deleted = [System.Collections.Generic.List[string]]::new()
    foreach ($pat in $patterns) {
        Get-Item $pat -EA SilentlyContinue | ForEach-Object {
            [void]$deleted.Add($_.Name)
            Remove-Item $_.FullName -Force -EA SilentlyContinue
        }
    }
    if ($deleted.Count -gt 0) {
        Write-Host "Da xoa $($deleted.Count) file tam." -ForegroundColor Green
    }
    Start-Sleep 1
}

try {
    Show-MainMenu
} finally {
    # Cleanup
}


# ============================================================
# EXECUTION & CLEANUP WRAPPER
# ============================================================
try {
    Show-MainMenu
} finally {
    Write-Host "Dang don dep file tam..." -ForegroundColor Gray
    $SID = $env:TOOLKIT_SESSION_ID
    $patterns = @(
        "$env:TEMP\ToolkitCore_$SID.ps1",
        "$env:TEMP\Maintenance_$SID.ps1",
        "$env:TEMP\Software_$SID.ps1",
        "$env:TEMP\BitLocker_$SID.ps1",
        "$env:TEMP\PrinterFixTool_*.exe",
        "$env:TEMP\UC20_*.exe",
        "$env:TEMP\CanchinhOffice_*.exe",
        "$env:TEMP\HardwareTest_*.exe",
        "$env:TEMP\1398_*.exe",
        "$env:TEMP\LKC1.0_*.exe",
        "$env:TEMP\smartctl_toolkit.exe"
    )
    $deleted = [System.Collections.Generic.List[string]]::new()
    foreach ($pat in $patterns) {
        Get-Item $pat -EA SilentlyContinue | ForEach-Object {
            [void]$deleted.Add($_.Name)
            Remove-Item $_.FullName -Force -EA SilentlyContinue
        }
    }
    if ($deleted.Count -gt 0) {
        Write-Host "Da xoa $($deleted.Count) file:" -ForegroundColor Green
        foreach ($d in $deleted) { Write-Host "  - $d" -ForegroundColor Gray }
    } else {
        Write-Host "Khong co file tam can xoa." -ForegroundColor Gray
    }
    Start-Sleep 2
}