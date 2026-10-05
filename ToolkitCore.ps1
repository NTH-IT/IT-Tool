# ============================================================
#  BO CONG CU DA DUNG CHO WINDOWS - Phat trien boi Mr.Hai 2026
# ============================================================
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
    [System.IO.File]::AppendAllText($LogFile, $line)
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
            foreach ($k in $Options.Keys) { Write-Host "$k. $($Options[$k].Label)" }
            Write-Host "0. Back"
            $c = Read-Esc "Chon: "
            if ($c -eq $Global:ESC -or $c -eq "0") { break }
            if ($Options.Contains($c)) {
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
    param([string]$Args)
    $exe = Get-SmartctlPath
    if (-not $exe) { return $null }
    try {
        $out = & $exe $Args.Split(' ') 2>&1 | Out-String
        return $out
    } catch {
        return $null
    }
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
    $smartInfo = Invoke-Smartctl "-i \\.\PhysicalDrive$DiskNumber"
    if ($smartInfo) {
        if ($smartInfo -match 'Firmware Version:\s*(.+)') { $fw = $Matches[1].Trim() }
        if ($smartInfo -match 'Serial Number:\s*(.+)')     { $serial = $Matches[1].Trim() }
    }
    $smartAll = Invoke-Smartctl "-A \\.\PhysicalDrive$DiskNumber"
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

    $smart = Invoke-Smartctl "-A \\.\PhysicalDrive$DiskNumber"
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
            $out = Invoke-Smartctl "-l seltest \\.\PhysicalDrive$DiskNumber"
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
            $out = Invoke-Smartctl "-x \\.\PhysicalDrive$DiskNumber"
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
    $trigger = Invoke-Smartctl "-t short \\.\PhysicalDrive$DiskNumber"
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

        $selftest = Invoke-Smartctl "-l seltest \\.\PhysicalDrive$DiskNumber"
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
        $final = Invoke-Smartctl "-l seltest \\.\PhysicalDrive$DiskNumber"
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

function Menu-SystemInfo {
    Show-Menu -Title "3. SYSTEM INFO & ACTIVATION" -NavEntry "3" -Options ([ordered]@{
        "1"=@{Label="Thong tin phan mem";Action={Show-SoftwareInfo}}
        "2"=@{Label="Thong tin phan cung";Action={Show-HardwareInfoFull}}
        "3"=@{Label="Thong tin ban quyen (Windows/Office)";Action={Show-LicenseInfo}}
        "4"=@{Label="Kiem tra key ban quyen theo may";Action={Clear-Host;cscript //nologo "$env:windir\System32\slmgr.vbs" /dlv;Pause-Return}}
        "5"=@{Label="Go bo ban quyen (giu lai theo may)";Action={Remove-LicenseExceptMachine}}
        "6"=@{Label="Thiet lap Office (CanchinhOffice.exe)";Action={Run-CanchinhOffice}}
        "7"=@{Label="Tool Hardware Check / Cong cu Kiem tra phan cung";Action={Run-HardwareTest}}
        "8"=@{Label="DISK / SSD DIAGNOSTIC / Chan doan o cung";Action={Show-DiskDiagnostic}}
    })
}

# ============================================================
# 4. SYSTEM MAINTENANCE
# ============================================================
function Get-FolderSizeMB {
    param([string]$P)
    if ([string]::IsNullOrWhiteSpace($P) -or -not (Test-Path -LiteralPath $P -EA SilentlyContinue)) { return 0 }
    $totalBytes = 0L
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($P)
    while ($stack.Count -gt 0) {
        $cur = $stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo($cur)
            foreach ($fi in $di.GetFiles()) { $totalBytes += $fi.Length }
            foreach ($sub in $di.GetDirectories()) {
                if (-not ($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) { $stack.Push($sub.FullName) }
            }
        } catch {}
    }
    return [math]::Round($totalBytes / 1MB, 2)
}

function Invoke-CleanupFlow {
    param([bool]$Deep)
    $quickFolders = [ordered]@{
        "User Temp"         = "$env:TEMP"
        "Windows Temp"      = "$env:windir\Temp"
        "Windows Update DL" = "$env:windir\SoftwareDistribution\Download"
        "Error Reports"     = "$env:LOCALAPPDATA\Microsoft\Windows\WER"
        "Chrome Cache"      = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
        "Edge Cache"        = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    }
    $deepExtra = [ordered]@{
        "UWP Packages" = "$env:LOCALAPPDATA\Packages"
        "LocalLow"     = "$env:USERPROFILE\AppData\LocalLow"
        "Prefetch"     = "$env:windir\Prefetch"
        "Minidump"     = "$env:windir\Minidump"
    }
    Clear-Host; Write-Nav; Write-Host "=== CLEANUP ANALYSIS ===" -ForegroundColor Cyan

    # ---- Dictionary luu (Y position, ten, size) cua tung dong de update sau ----
    $rowPos   = [ordered]@{}   # key = ten -> @{ Y = int; Size = double }
    $total    = 0
    $nameCol  = 26             # do rong cot ten (khop voi "{0,-24}" + khoang trang)

    function Write-AnalysisRow {
        param([string]$Name, [double]$SizeMB)
        $y = [Console]::CursorTop
        Write-Host ("{0,-24} {1,8:F2} MB" -f $Name, $SizeMB)
        return $y
    }

    # In tung dong Quick
    foreach ($k in $quickFolders.Keys) {
        $sz = Get-FolderSizeMB $quickFolders[$k]
        $total += $sz
        $y = Write-AnalysisRow $k $sz
        $rowPos[$k] = @{ Y = $y; Size = $sz }
    }
    # Firefox
    $ffProfiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -EA SilentlyContinue
    $ffSize = 0
    if ($ffProfiles) { $ffProfiles | ForEach-Object { $ffSize += Get-FolderSizeMB "$($_.FullName)\cache2" } }
    if ($ffSize -gt 0) {
        $total += $ffSize
        $y = Write-AnalysisRow "Firefox Cache" $ffSize
        $rowPos["Firefox Cache"] = @{ Y = $y; Size = $ffSize }
    }
    # Thumbnail
    $thumbDir   = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
    $thumbFiles = @(Get-Item "$thumbDir\thumbcache_*.db", "$thumbDir\iconcache_*.db" -EA SilentlyContinue)
    $thumbMB    = [math]::Round(($thumbFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
    if ($thumbMB -gt 0) {
        $total += $thumbMB
        $y = Write-AnalysisRow "Thumbnail Cache" $thumbMB
        $rowPos["Thumbnail Cache"] = @{ Y = $y; Size = $thumbMB }
    }
    # Deep items
    if ($Deep) {
        foreach ($k in $deepExtra.Keys) {
            $sz = Get-FolderSizeMB $deepExtra[$k]
            $total += $sz
            $y = Write-AnalysisRow $k $sz
            $rowPos[$k] = @{ Y = $y; Size = $sz }
        }
        $rbMB = Get-FolderSizeMB "$($env:SystemDrive)\`$Recycle.Bin"
        $total += $rbMB
        $y = Write-AnalysisRow "Recycle Bin" $rbMB
        $rowPos["Recycle Bin"] = @{ Y = $y; Size = $rbMB }

        $dumpMB = 0
        if (Test-Path "$env:windir\MEMORY.DMP") {
            $dumpMB = [math]::Round((Get-Item "$env:windir\MEMORY.DMP").Length / 1MB, 2)
        }
        if ($dumpMB -gt 0) {
            $total += $dumpMB
            $y = Write-AnalysisRow "Memory Dump" $dumpMB
            $rowPos["Memory Dump"] = @{ Y = $y; Size = $dumpMB }
        }
    }

    Write-Host ("-" * 34)
    Write-Host ("{0,-24} {1,8:F2} MB" -f "Potentially removable", [math]::Round($total, 2)) -ForegroundColor Yellow

    # Luu vi tri dong "Potentially removable" de co the ghi de sau khi xoa xong
    $totalRowY = [Console]::CursorTop - 1

    $ans = Read-Esc "`nClean selected items? [Y/N] (ESC de huy): "
    if ($ans -eq $Global:ESC -or $ans.ToUpper() -ne "Y") { Pause-Return; return }

    Write-Host ""
    Write-Host "Dang don dep..." -ForegroundColor Cyan

    # ---- Helper cap nhat trang thai 1 dong ----
    function Set-RowStatus {
        param([string]$Name, [string]$Status, [string]$Color = "Green")
        if (-not $rowPos.Contains($Name)) { return }
        $savedY = [Console]::CursorTop
        $savedX = [Console]::CursorLeft
        try {
            # Dat con tro vao cuoi dong cua muc nay, cot 36
            [Console]::SetCursorPosition(36, $rowPos[$Name].Y)
            Write-Host ("  [{0}]" -f $Status) -ForegroundColor $Color -NoNewline
        } catch {}
        # Tra con tro ve vi tri cu
        try { [Console]::SetCursorPosition($savedX, $savedY) } catch {}
    }

    # ---- Xoa tung muc + cap nhat trang thai ----
    foreach ($k in $quickFolders.Keys) {
        try {
            Remove-Item "$($quickFolders[$k])\*" -Recurse -Force `
                -Exclude 'toolkit_actions_*.log','ToolkitCore_*.ps1' -EA SilentlyContinue
            Set-RowStatus $k "Da xoa" "Green"
        } catch {
            Set-RowStatus $k "Loi" "Red"
        }
    }

    if ($ffProfiles) {
        try {
            $ffProfiles | ForEach-Object {
                Remove-Item "$($_.FullName)\cache2\*" -Recurse -Force -EA SilentlyContinue
            }
            Set-RowStatus "Firefox Cache" "Da xoa" "Green"
        } catch {
            Set-RowStatus "Firefox Cache" "Loi" "Red"
        }
    }

    if ($thumbMB -gt 0) {
        try {
            $thumbFiles | ForEach-Object { Remove-Item $_.FullName -Force -EA SilentlyContinue }
            Set-RowStatus "Thumbnail Cache" "Da xoa" "Green"
        } catch {
            Set-RowStatus "Thumbnail Cache" "Loi" "Red"
        }
    }

    ipconfig /flushdns | Out-Null

    if ($Deep) {
        foreach ($k in $deepExtra.Keys) {
            try {
                Remove-Item "$($deepExtra[$k])\*" -Recurse -Force -EA SilentlyContinue
                Set-RowStatus $k "Da xoa" "Green"
            } catch {
                Set-RowStatus $k "Loi" "Red"
            }
        }
        # Recycle Bin
        try {
            Clear-RecycleBin -Force -EA SilentlyContinue
            Set-RowStatus "Recycle Bin" "Da xoa" "Green"
        } catch {
            Set-RowStatus "Recycle Bin" "Loi" "Red"
        }
        # Memory Dump
        if ($dumpMB -gt 0) {
            try {
                Remove-Item "$env:windir\MEMORY.DMP" -Force -EA SilentlyContinue
                Set-RowStatus "Memory Dump" "Da xoa" "Green"
            } catch {
                Set-RowStatus "Memory Dump" "Loi" "Red"
            }
        }
        # SRU + Event Logs
        Stop-Service -Name DPS -Force -EA SilentlyContinue
        Remove-Item "$env:windir\System32\sru\*" -Force -EA SilentlyContinue
        Start-Service -Name DPS -EA SilentlyContinue
        wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
    }

    # ---- Tinh lai dung luong sau khi don ----
    $after = 0
    foreach ($k in $quickFolders.Keys) { $after += Get-FolderSizeMB $quickFolders[$k] }
    if ($Deep) {
        foreach ($k in $deepExtra.Keys) { $after += Get-FolderSizeMB $deepExtra[$k] }
        $after += Get-FolderSizeMB "$($env:SystemDrive)\`$Recycle.Bin"
        if (Test-Path "$env:windir\MEMORY.DMP") {
            $after += [math]::Round((Get-Item "$env:windir\MEMORY.DMP").Length / 1MB, 2)
        }
    }
    $freed = [math]::Round($total - $after, 2)
    if ($freed -lt 0) { $freed = 0 }

    # ---- Cap nhat dong "Potentially removable" thanh "Da giai phong" ----
    try {
        [Console]::SetCursorPosition(0, $totalRowY)
        Write-Host ("{0,-24} {1,8:F2} MB" -f "Da giai phong", $freed) -ForegroundColor Green
    } catch {}

    # Di chuyen con tro xuong cuoi
    try { [Console]::SetCursorPosition(0, [Math]::Min([Console]::BufferHeight - 2, $totalRowY + 2)) } catch {}
    Write-Host ""
    Write-Host "Da don xong. Da giai phong khoang: $freed MB" -ForegroundColor Green
    Write-Log "$(if($Deep){'Deep'}else{'Quick'}) Clean - freed ~$freed MB"
    Pause-Return
}

function Menu-Cleanup {
    Show-Menu -Title "Windows Cleanup / Don dep Windows" -Options ([ordered]@{
        "1"=@{Label="Don qua / Quick Clean";Action={Invoke-CleanupFlow -Deep $false}}
        "2"=@{Label="Don ky / Deep Clean";Action={Invoke-CleanupFlow -Deep $true}}
    })
}

function Show-PerformanceDiag {
    Clear-Host; Write-Nav; Write-Host "=== CHAN DOAN HIEU NANG HE THONG ===" -ForegroundColor Cyan
    
    $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
    $cpuLoad = [math]::Round($cpu.Average, 1)
    Write-Host "CPU Load Average  : $cpuLoad%" -ForegroundColor $(if($cpuLoad -gt 80){'Red'}elseif($cpuLoad -gt 50){'Yellow'}else{'Green'})
    
    $os = Get-CimInstance Win32_OperatingSystem
    $totalRamMB = [math]::Round($os.TotalVisibleMemorySize / 1KB, 2)
    $freeRamMB  = [math]::Round($os.FreePhysicalMemory / 1KB, 2)
    $usedRamMB  = [math]::Round($totalRamMB - $freeRamMB, 2)
    $ramPct     = if ($totalRamMB -gt 0) { [math]::Round(($usedRamMB / $totalRamMB) * 100, 1) } else { 0 }
    Write-Host "RAM Usage         : $usedRamMB MB / $totalRamMB MB ($ramPct%)" -ForegroundColor $(if($ramPct -gt 85){'Red'}elseif($ramPct -gt 70){'Yellow'}else{'Green'})

    Write-Host "`n--- DUNG LUONG O DIA ---" -ForegroundColor Yellow
    Get-Volume | Where-Object DriveLetter | ForEach-Object {
        $letter = $_.DriveLetter
        $free   = [math]::Round($_.SizeRemaining / 1GB, 2)
        $total  = [math]::Round($_.Size / 1GB, 2)
        $pct    = if ($total -gt 0) { [math]::Round((($total - $free) / $total) * 100, 1) } else { 0 }
        Write-Host ("  Drive {0}: {1,6} GB Free / {2,6} GB Total ({3}% used)" -f $letter, $free,$total, $pct) -ForegroundColor $(if($pct -gt 90){'Red'}elseif($pct -gt 75){'Yellow'}else{'Green'})
    }

    Write-Host "`n--- TOP 5 TIEN TRINH CHIEM RAM ---" -ForegroundColor Yellow
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 5 | ForEach-Object {
        $memMB = [math]::Round($_.WorkingSet64 / 1MB, 2)
        Write-Host ("  {0,-25} PID: {1,-6} RAM: {2,8} MB" -f $_.ProcessName, $_.Id, $memMB)
    }

    Write-Host "`n--- TOP 5 TIEN TRINH CHIEM CPU ---" -ForegroundColor Yellow
    Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 | ForEach-Object {
        $cpuSec = [math]::Round($_.CPU, 1)
        Write-Host ("  {0,-25} PID: {1,-6} CPU Time: {2,6}s" -f $_.ProcessName, $_.Id, $cpuSec)
    }

    Write-Log "Chan doan hieu nang system"
    Pause-Return
}

function Menu-Performance {
    Show-Menu -Title "Performance / Hieu nang" -Options ([ordered]@{
        "1"=@{Label="Disable Visual Effects / Tat hieu ung hinh anh";Action={Run-Task "Disable Visual Effects" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" VisualFXSetting 2}}}
        "2"=@{Label="Disable Transparency / Tat trong suot";Action={Run-Task "Disable Transparency" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" EnableTransparency 0}}}
        "3"=@{Label="Disable Animations / Tat hoat hinh";Action={Run-Task "Disable Animations" {Set-RegValue "HKCU:\Control Panel\Desktop\WindowMetrics" MinAnimate "0" String}}}
        "4"=@{Label="Adjust Virtual Memory / Dieu chinh bo nho ao";Action={Start-Process SystemPropertiesAdvanced.exe}}
        "5"=@{Label="Manage Startup / Quan ly ung dung khoi dong";Action={Start-Process taskmgr.exe}}
        "6"=@{Label="Performance Diagnostic / Chan doan hieu nang";Action={Show-PerformanceDiag}}
    })
}

function Menu-PowerManagement {
    Show-Menu -Title "Power Management / Quan ly nguon dien" -Options ([ordered]@{
        "1"=@{Label="Power Plan Settings / Che do nguon dien";Action={Start-Process powercfg.cpl}}
        "2"=@{Label="Screen Timeout / Thoi gian tat man hinh";Action={Run-Task "Screen Timeout" {
            $m = Read-Esc "So phut (0=khong bao gio, ESC huy): "
            if ($m -eq $Global:ESC) { Write-Host "Da huy."; return }
            if ($m -notmatch '^\d{1,4}$') { throw "Gia tri khong hop le: chi nhap so phut (0-9999)." }
            powercfg /change monitor-timeout-ac $m
            powercfg /change monitor-timeout-dc $m
            Write-Host "Da dat tat man hinh sau $m phut."
        }}}
        "3"=@{Label="Sleep Timeout / Thoi gian ngu";Action={Run-Task "Sleep Timeout" {
            $m = Read-Esc "So phut (0=khong bao gio, ESC huy): "
            if ($m -eq $Global:ESC) { Write-Host "Da huy."; return }
            if ($m -notmatch '^\d{1,4}$') { throw "Gia tri khong hop le: chi nhap so phut (0-9999)." }
            powercfg /change standby-timeout-ac $m
            powercfg /change standby-timeout-dc $m
            Write-Host "Da dat ngu sau $m phut."
        }}}
        "4"=@{Label="Lid Close Action / Hanh dong gap man hinh";Action={Start-Process control.exe -ArgumentList '/name Microsoft.PowerOptions /page pageGlobalSettings'}}
        "5"=@{Label="Power Button Action / Hanh dong nut nguon";Action={Start-Process control.exe -ArgumentList '/name Microsoft.PowerOptions /page pageGlobalSettings'}}
        "6"=@{Label="Battery Report / Bao cao pin";Action={Run-Task "Battery Report" {
            Write-Host "Se tao file battery-report.html tren Desktop."
            $c = Read-Esc "Tao bao cao? [Y/N]: "
            if ($c.ToUpper() -ne "Y") { return }
            $out = [IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'battery-report.html')
            if (Test-Path $out) { Remove-Item $out -Force -EA SilentlyContinue }
            Write-Host "Dang tao bao cao pin..." -ForegroundColor Yellow
            & powercfg /batteryreport /output $out | Out-Null
            if (Test-Path $out) { Write-Host "Da xuat: $out" -ForegroundColor Green; Start-Process $out }
            else { Write-Host "Khong xuat duoc. May co the la PC ban (khong co pin)." -ForegroundColor Yellow }
        }}}
        "7"=@{Label="Power Efficiency Report / Bao cao hieu qua nguon";Action={Run-Task "Power Efficiency Report" {
            Write-Host "Se tao file energy-report.html tren Desktop (~25 giay)."
            $c = Read-Esc "Tao bao cao? [Y/N]: "
            if ($c.ToUpper() -ne "Y") { return }
            $out = [IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'energy-report.html')
            if (Test-Path $out) { Remove-Item $out -Force -EA SilentlyContinue }
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $argLine = "/energy /duration 20 /output `"$out`""
            $pp = Start-Process -FilePath powercfg.exe -ArgumentList $argLine -WindowStyle Hidden -PassThru
            while (-not $pp.HasExited) {
                $pct = [math]::Min(99, [math]::Round($sw.Elapsed.TotalSeconds / 25 * 100))
                Write-Host -NoNewline "`r  Dang phan tich: $pct% - $([math]::Round($sw.Elapsed.TotalSeconds,0))s  "
                Start-Sleep -Milliseconds 500
            }
            Write-Host ""
            $sw.Stop()
            if (Test-Path $out) { Write-Host "Da xuat: $out ($([math]::Round($sw.Elapsed.TotalSeconds,0))s)" -ForegroundColor Green; Start-Process $out }
            else { Write-Host "Khong xuat duoc." -ForegroundColor Yellow }
        }}}
    })
}

function Menu-ExplorerTweaks {
    Show-Menu -Title "Explorer Tweaks / Tinh chinh Explorer" -Options ([ordered]@{
        "1"=@{Label="Show File Extensions / Hien duoi file";Action={Run-Task "Show Extensions" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0}}}
        "2"=@{Label="Show Hidden Files / Hien file an";Action={Run-Task "Show Hidden" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Hidden 1}}}
        "3"=@{Label="Show Protected OS Files / Hien file he thong";Action={Run-Task "Show OS Files" -NeedConfirm -ConfirmMsg "Hien file he thong co the gay xoa nham." {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" ShowSuperHidden 1}}}
        "4"=@{Label="Show Full Path / Hien duong dan day du";Action={Run-Task "Full Path" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" FullPath 1}}}
        "5"=@{Label="Open This PC / Mo This PC";Action={Run-Task "Open This PC" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" LaunchTo 1}}}
        "6"=@{Label="Disable Recent Files / Tat file gan day";Action={Run-Task "Disable Recent Files" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" Start_TrackDocs 0}}}
        "7"=@{Label="Disable Recent Folders / Tat thu muc gan day";Action={Run-Task "Disable Recent Folders" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" NoRecentDocsHistory 1}}}
        "8"=@{Label="Clear Explorer History / Xoa lich su Explorer";Action={Run-Task "Clear History" {Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Force -EA SilentlyContinue}}}
        "9"=@{Label="Restart Explorer / Khoi dong lai Explorer";Action={Run-Task "Restart Explorer" {Stop-Process -Name explorer -Force; Start-Sleep 1; Start-Process explorer.exe}}}
        "10"=@{Label="Disable Thumbnails / Tat xem truoc anh nho";Action={Run-Task "Disable Thumbnails" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" IconsOnly 1}}}
        "11"=@{Label="Enable Thumbnails / Bat xem truoc anh nho";Action={Run-Task "Enable Thumbnails" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" IconsOnly 0}}}
    })
}

function Menu-WindowsStandard {
    Show-Menu -Title "Windows Standard / Cai dat chuan Windows" -Options ([ordered]@{
        "1"=@{Label="Taskbar Left / Thanh tac vu sang trai";Action={Run-Task "Taskbar Left" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarAl 0}}}
        "2"=@{Label="Show File Extensions / Hien duoi file";Action={Run-Task "Show Extensions" {Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" HideFileExt 0}}}
        "3"=@{Label="Hide Widgets/Search/Chat / An Widget/Tim kiem/Chat";Action={Run-Task "Hide Widgets/Search/Chat" {
            Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarDa 0 -EA SilentlyContinue
            Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" SearchboxTaskbarMode 0 -EA SilentlyContinue
            Set-RegValue "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" TaskbarMn 0 -EA SilentlyContinue
        }}}
        "4"=@{Label="Hide Unnecessary Icons / An bieu tuong thua";Action={Start-Process ms-settings:taskbar}}
        "5"=@{Label="Standard Start Menu / Menu Start chuan";Action={Start-Process ms-settings:personalization-start}}
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
    } else {
        Write-Host "Da huy hoac tai that bai." -ForegroundColor Yellow
    }
}

function Menu-WindowsUpdate {
    Show-Menu -Title "Windows Update / Cap nhat Windows" -Options ([ordered]@{
        "1"=@{Label="Check Update / Kiem tra cap nhat";Action={Run-Task "Check Update" {
            $svc = Get-Service wuauserv -EA SilentlyContinue
            Write-Host "Trang thai dich vu: $($svc.Status)"
            if ($svc.Status -ne 'Running') { Write-Host "Dang khoi dong dich vu..." -ForegroundColor Yellow; Start-Service wuauserv -EA SilentlyContinue; Start-Sleep 2 }
            Write-Host "Dang gui lenh quet (UsoClient + wuauclt)..." -ForegroundColor Yellow
            Start-Process -FilePath UsoClient.exe -ArgumentList "StartScan" -WindowStyle Hidden -Wait -EA SilentlyContinue
            Start-Process -FilePath wuauclt.exe -ArgumentList "/detectnow" -WindowStyle Hidden -Wait -EA SilentlyContinue
            Write-Host "Da gui lenh quet thanh cong." -ForegroundColor Green
            Write-Host "Ket qua se hien tai: Cai dat -> Windows Update." -ForegroundColor Cyan
            Start-Process ms-settings:windowsupdate
        }}}
        "2"=@{Label="Open Windows Update / Mo cap nhat Windows";Action={Start-Process ms-settings:windowsupdate}}
        "3"=@{Label="Windows Update Status / Trang thai cap nhat";Action={Run-Task "Update Status" {Get-Service wuauserv | Format-Table Name,Status,StartType}}}
        "4"=@{Label="Restart Update Services / Khoi dong lai dich vu";Action={Run-Task "Restart Services" {Restart-Service wuauserv,bits,cryptsvc -Force}}}
        "5"=@{Label="Reset Update Components / Dat lai thanh phan";Action={Run-Task "Reset Components" -NeedConfirm -ConfirmMsg "Se dat lai cache Windows Update." {
            Stop-Service wuauserv,bits,cryptsvc -Force -EA SilentlyContinue
            Rename-Item "$env:windir\SoftwareDistribution" "SoftwareDistribution.bak_$(Get-Date -Format yyyyMMddHHmmss)" -EA SilentlyContinue
            Rename-Item "$env:windir\System32\catroot2" "catroot2.bak_$(Get-Date -Format yyyyMMddHHmmss)" -EA SilentlyContinue
            Start-Service wuauserv,bits,cryptsvc
        }}}
        "6"=@{Label="Clear Update Cache / Xoa cache cap nhat";Action={Run-Task "Clear Cache" {Stop-Service wuauserv -Force; Remove-Item "$env:windir\SoftwareDistribution\Download\*" -Recurse -Force -EA SilentlyContinue; Start-Service wuauserv}}}
        "7"=@{Label="Check Pending Reboot / Kiem tra cho khoi dong lai";Action={Run-Task "Pending Reboot" {
            $cbs = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
            $wu  = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
            Write-Host "Can restart (CBS)           : $cbs"
            Write-Host "Can restart (Windows Update): $wu"
        }}}
        "8"=@{Label="Update History / Lich su cap nhat";Action={Run-Task "Update History" {Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 20 | Format-Table}}}
        "9"=@{Label="Set Windows Update / Quan ly (UC20.exe)";Action={Clear-Host; Write-Host "=== SET WINDOWS UPDATE ===" -ForegroundColor Cyan; Run-UC20; Pause-Return}}
    })
}

function Menu-Audio {
    Show-Menu -Title "Audio / Am thanh" -Options ([ordered]@{
        "1"=@{Label="Restart Windows Audio / Khoi dong lai am thanh";Action={Run-Task "Restart Audio" {Restart-Service Audiosrv -Force}}}
        "2"=@{Label="Restart Audio Endpoint Builder";Action={Run-Task "Restart Endpoint" {Restart-Service AudioEndpointBuilder -Force}}}
        "3"=@{Label="List Playback Devices / Thiet bi phat";Action={Run-Task "Playback Devices" {Get-CimInstance Win32_SoundDevice | Format-Table Name,Status}}}
        "4"=@{Label="List Recording Devices / Thiet bi ghi";Action={Run-Task "Recording Devices" {Get-PnpDevice -Class AudioEndpoint | Format-Table FriendlyName,Status}}}
        "5"=@{Label="Default Playback/Microphone / Thiet bi mac dinh";Action={Start-Process mmsys.cpl}}
        "6"=@{Label="Check Audio Driver / Kiem tra driver am thanh";Action={Run-Task "Audio Driver" {Get-CimInstance Win32_PnPSignedDriver | Where-Object{$_.DeviceClass -eq "MEDIA"} | Format-Table DeviceName,DriverVersion,DriverDate}}}
        "7"=@{Label="Open Sound Settings / Mo cai dat am thanh";Action={Start-Process ms-settings:sound}}
        "8"=@{Label="Audio Troubleshooter / Chan doan am thanh";Action={Start-Process ms-settings:troubleshoot}}
    })
}

function Run-HardwareTest {
    Clear-Host; Write-Nav; Write-Host "=== TOOL HARDWARE CHECK (HardwareTest.exe) ===" -ForegroundColor Cyan
    $url = "https://www.dropbox.com/scl/fi/obzvj7tsrkfo3mpsxnb90/HardwareTest.exe?rlkey=i8s0kiwzugbxpzflzm1bd6bmn&st=9iecy4sc&dl=1"
    $path = "$env:TEMP\HardwareTest_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "HardwareTest.exe"
    if ($ok -and (Test-Path $path)) {
        Write-Host "Dang chay HardwareTest.exe (quyen admin)..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait
        Write-Log "Da chay HardwareTest.exe"
        Remove-Item $path -Force -EA SilentlyContinue
    } else {
        Write-Host "Da huy hoac tai that bai." -ForegroundColor Yellow
    }
    Pause-Return
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
    Clear-Host; Write-Nav; Write-Host "=== LAM MOI HE THONG / SYSTEM REFRESH ===" -ForegroundColor Cyan
    Write-Host "[1/5] Cap nhat Group Policy..." -ForegroundColor Yellow; gpupdate /force
    Write-Host "[2/5] Dong bo thoi gian + Timezone..." -ForegroundColor Yellow
    tzutil /s "SE Asia Standard Time"; w32tm /resync /force 2>$null
    Write-Host "[3/5] Lam moi card mang (FlushDNS + NetBIOS + ARP)..." -ForegroundColor Yellow
    ipconfig /flushdns; nbtstat -R 2>$null; arp -d * 2>$null
    Write-Host "[4/5] Khoi dong lai Explorer..." -ForegroundColor Yellow
    Stop-Process -Name explorer -Force -EA SilentlyContinue; Start-Sleep 1; Start-Process explorer.exe
    Write-Host "[5/5] Xoa Credential Cache (Kerberos Ticket Purge)..." -ForegroundColor Yellow
    klist purge 2>$null
    Write-Host "`nHoan tat lam moi he thong!" -ForegroundColor Green
    Write-Log "Lam moi he thong: GP+Timezone+Network+Explorer+Kerberos"; Pause-Return
}

function Menu-Maintenance {
    Show-Menu -Title "4. SYSTEM MAINTENANCE / BAO TRI HE THONG" -NavEntry "4" -Options ([ordered]@{
        "1"=@{Label="Windows Cleanup / Don dep Windows";Action={Menu-Cleanup}}
        "2"=@{Label="Performance / Hieu nang";Action={Menu-Performance}}
        "3"=@{Label="Power Management / Quan ly nguon dien";Action={Menu-PowerManagement}}
        "4"=@{Label="Explorer Tweaks / Tinh chinh Explorer";Action={Menu-ExplorerTweaks}}
        "5"=@{Label="Windows Standard / Cai dat chuan Windows";Action={Menu-WindowsStandard}}
        "6"=@{Label="Windows Update / Cap nhat Windows";Action={Menu-WindowsUpdate}}
        "7"=@{Label="Audio / Am thanh";Action={Menu-Audio}}
        "8"=@{Label="Advanced Tools / Cong cu nang cao";Action={Menu-AdvancedTools}}
        "9"=@{Label="Lam moi he thong / System Refresh";Action={Invoke-SystemRefresh}}
    })
}

# ============================================================
# 5. SOFTWARE
# ============================================================
function Open-Site {
    param([string]$Name, [string]$Url, [bool]$IsPlaceholder = $false)
    Clear-Host; Write-Nav; Write-Host "=== $Name ===" -ForegroundColor Cyan
    if ($IsPlaceholder) {
        Write-Host "Chua cau hinh URL cho '$Name'." -ForegroundColor Yellow
        Write-Host "Cap nhat link trong script (Menu-OtherSoftware)." -ForegroundColor Yellow
        Pause-Return; return
    }
    Write-Host "URL: $Url" -ForegroundColor Gray
    Start-Process $Url
    Write-Host "Da mo trang tai trong trinh duyet." -ForegroundColor Green
    Write-Log "Mo trang tai: $Name"
    Pause-Return
}

function Run-FontViet {
    Clear-Host; Write-Nav; Write-Host "=== CAI DAT FONT CHU TIENG VIET (1398.exe) ===" -ForegroundColor Cyan
    $url = "https://www.dropbox.com/scl/fi/nhg1tmopwvtumeukloelt/1398.exe?rlkey=lesaybeoat6h0rv6rvzzj8oif&st=k6qfnmd0&dl=1"
    $path = "$env:TEMP\1398_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "1398.exe"
    if ($ok -and (Test-Path $path)) {
        Write-Host "Dang chay 1398.exe (quyen admin)..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait
        Write-Log "Da chay 1398.exe (font tieng Viet)"
        Remove-Item $path -Force -EA SilentlyContinue
    } else {
        Write-Host "Da huy hoac tai that bai." -ForegroundColor Yellow
    }
    Pause-Return
}

function Menu-OtherSoftware {
    Show-Menu -Title "PHAN MEM KHAC / OTHER SOFTWARE" -Options ([ordered]@{
        "1"=@{Label="Office AIO 2016-2024";Action={Open-Site "Office AIO 2016-2024" "https://shrinkme.click/1PyGgj"}}
        "2"=@{Label="AutoCAD 2021";Action={Open-Site "AutoCAD 2021" "https://shrinkme.click/m7Wrh"}}
        "3"=@{Label="WinToHDD";Action={Open-Site "WinToHDD" "https://shrinkme.click/YYtjuj"}}
    })
}

function Menu-Software {
    Show-Menu -Title "5. SOFTWARE / PHAN MEM" -NavEntry "5" -Options ([ordered]@{
        "1"  =@{Label="Zalo PC"; Action={Open-Site "Zalo PC" "https://zalo.me/pc"}}
        "2"  =@{Label="Zoom"; Action={Open-Site "Zoom" "https://zoom.us/download"}}
        "3"  =@{Label="Telegram"; Action={Open-Site "Telegram" "https://telegram.org/dl/desktop/win"}}
        "4"  =@{Label="WeChat"; Action={Open-Site "WeChat" "https://www.wechat.com/en/"}}
        "5"  =@{Label="KakaoTalk"; Action={Open-Site "KakaoTalk" "https://www.kakaocorp.com/page/service/all?lang=ENG"}}
        "6"  =@{Label="Google Chrome"; Action={Open-Site "Google Chrome" "https://www.google.com/chrome/"}}
        "7"  =@{Label="Coc Coc"; Action={Open-Site "Coc Coc" "https://coccoc.com/download"}}
        "8"  =@{Label="Cai dat font chu Viet Nam (1398.exe)"; Action={Run-FontViet}}
        "9"  =@{Label="Unikey"; Action={Open-Site "Unikey" "https://www.unikey.org/download.html"}}
        "10" =@{Label="Office 365"; Action={Open-Site "Office 365" "https://www.microsoft.com/en-us/microsoft-365/try"}}
        "11" =@{Label="WPS Office"; Action={Open-Site "WPS Office" "https://www.wps.com/download/"}}
        "12" =@{Label="LibreOffice"; Action={Open-Site "LibreOffice" "https://www.libreoffice.org/download/download/"}}
        "13" =@{Label="Foxit PDF Reader"; Action={Open-Site "Foxit PDF Reader" "https://www.foxit.com/pdf-reader/"}}
        "14" =@{Label="PDFgear (Edit PDF)"; Action={Open-Site "PDFgear" "https://pdfgear.com/pdfgear-for-windows/"}}
        "15" =@{Label="VLC"; Action={Open-Site "VLC" "https://www.videolan.org/vlc/download-windows.html"}}
        "16" =@{Label="CapCut"; Action={Open-Site "CapCut" "https://www.capcut.com/tools/pc-video-editor"}}
        "17" =@{Label="OBS Studio"; Action={Open-Site "OBS Studio" "https://obsproject.com/download"}}
        "18" =@{Label="WinRAR"; Action={Open-Site "WinRAR" "https://www.rarlab.com/download.htm"}}
        "19" =@{Label="ImageGlass"; Action={Open-Site "ImageGlass" "https://imageglass.org/"}}
        "20" =@{Label="AnyDesk"; Action={Open-Site "AnyDesk" "https://anydesk.com/en/downloads/windows"}}
        "21" =@{Label="UltraViewer"; Action={Open-Site "UltraViewer" "https://www.ultraviewer.net/en/download.html"}}
        "22" =@{Label="Fliqlo Screensaver"; Action={Open-Site "Fliqlo Screensaver" "https://fliqlo.com/screensaver/"}}
        "23" =@{Label="Bing Wallpaper"; Action={Open-Site "Bing Wallpaper" "https://www.microsoft.com/en-us/bing/bing-wallpaper"}}
        "24" =@{Label="Crystal Disk Info"; Action={Open-Site "Crystal Disk Info" "https://crystalmark.info/en/download/"}}
        "25" =@{Label="Recoverit"; Action={Open-Site "Recoverit" "https://recoverit.wondershare.com/"}}
        "26" =@{Label="MiniTool Partition Wizard"; Action={Open-Site "MiniTool Partition Wizard" "https://www.partitionwizard.com/free-partition-manager.html"}}
        "27" =@{Label="Double Driver"; Action={Open-Site "Double Driver" "https://download.com.vn/double-driver-25157"}}
        "99" =@{Label="Office AIO / AutoCAD / WinToHDD"; Action={Menu-OtherSoftware}}
    })
}

# ============================================================
# MAIN MENU
# ============================================================
function Show-MainMenu {
    do {
        Clear-Host
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host " BO CONG CU DA DUNG CHO WINDOWS"
        Write-Host " Phat trien boi Mr.Hai 2026"
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "1. Network Troubleshoot     / Xu ly su co mang"
        Write-Host "2. Printer & File Sharing   / May in va chia se file"
        Write-Host "3. System Info & Activation / Thong tin he thong"
        Write-Host "4. System Maintenance       / Bao tri he thong"
        Write-Host "5. Software                 / Phan mem"
        Write-Host "6. Exit                     / Thoat"
        if ($Global:SessionUserNote) { Write-Host $Global:SessionUserNote -ForegroundColor Yellow }
        $c = Read-Esc "Chon muc: "
        if ($c -eq $Global:ESC) {
            $confirm = Read-Esc "Ban co chac muon thoat? [Y/N]: "
            if ($confirm.ToUpper() -eq "Y") {
                Write-Log "Nguoi dung thoat toolkit (ESC)"
                Write-Host ""
                Write-Host "Cam on da su dung." -ForegroundColor Cyan
                Write-Host ""
                return
            }
            continue
        }
        switch ($c) {
            "1" { Menu-Network }
            "2" { Menu-PrinterSharing }
            "3" { Menu-SystemInfo }
            "4" { Menu-Maintenance }
            "5" { Menu-Software }
            "6" {
                $confirm = Read-Esc "Ban co chac muon thoat? [Y/N]: "
                if ($confirm.ToUpper() -eq "Y") {
                    Write-Log "Nguoi dung thoat toolkit"
                    Write-Host ""
                    Write-Host "Cam on da su dung." -ForegroundColor Cyan
                    Write-Host ""
                    return
                }
            }
        }
    } while ($true)
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
        "$env:TEMP\PrinterFixTool_*.exe",
        "$env:TEMP\UC20_*.exe",
        "$env:TEMP\CanchinhOffice_*.exe",
        "$env:TEMP\HardwareTest_*.exe",
        "$env:TEMP\1398_*.exe",
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
