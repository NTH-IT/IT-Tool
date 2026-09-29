# ============================================================
#  BO CONG CU DA DUNG CHO WINDOWS - Phat trien boi Mr.Hai
# ============================================================
$ErrorActionPreference = "SilentlyContinue"
$LogFile = "$env:TEMP\toolkit_actions_$(Get-Date -Format yyyyMMdd_HHmmss).log"
$Global:ESC = "##ESC##"
$Global:NavPath = [System.Collections.Generic.List[string]]::new()
function Write-Nav {
    if ($Global:NavPath.Count -gt 0) {
        Write-Host ("  [" + ($Global:NavPath -join ">") + "]") -ForegroundColor DarkCyan
        Write-Host ""
    }
}

function Write-Log { param([string]$M); Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $env:USERNAME | $M" }
function Test-IsAdmin {
    $p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (-not (Test-IsAdmin)) { Write-Host "Can quyen Administrator." -ForegroundColor Red; Read-Host; exit }

try {
    $rawui = $Host.UI.RawUI; $buf = $rawui.BufferSize
    $buf.Width = [Math]::Max($buf.Width, 62); $buf.Height = 3000; $rawui.BufferSize = $buf
    $ws = $rawui.WindowSize; $ws.Width = 62; $ws.Height = 42; $rawui.WindowSize = $ws
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
            if ($buf.Length -gt 0) { $buf=$buf.Substring(0,$buf.Length-1); Write-Host -NoNewline ([char]8+" "+[char]8) }
            continue
        }
        if (-not [char]::IsControl($k.KeyChar)) { $buf+=$k.KeyChar; Write-Host -NoNewline $k.KeyChar }
    }
}

function Read-IPEsc {
    param([string]$Label = "IP")
    while ($true) {
        $v = (Read-Esc "${Label}: ").Trim()
        if ($v -eq $Global:ESC) { return $Global:ESC }
        if ($v -match '^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$') {
            $ok = $true
            foreach ($oct in @($Matches[1],$Matches[2],$Matches[3],$Matches[4])) {
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
    param([string]$Input)
    $s = $Input.Trim()
    if ($s -eq "") { return 24 }
    if ($s -match '^\d+$' -and [int]$s -ge 0 -and [int]$s -le 32) { return [int]$s }
    if ($s -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        $parts = $s -split '\.'
        $bin = ($parts | ForEach-Object { [Convert]::ToString([int]$_,2).PadLeft(8,'0') }) -join ''
        return ($bin.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    return -1
}

function Select-NetIdx {
    $adapters = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    Write-Host ""
    Write-Host ("  {0,-5} {1,-22} {2}" -f "Idx","Name","Description") -ForegroundColor Cyan
    Write-Host ("  " + ("-"*56))
    foreach ($a in $adapters) {
        Write-Host ("  {0,-5} {1,-22} {2}" -f $a.InterfaceIndex, $a.Name, ($a.InterfaceDescription -replace '^\s+',''))
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
    param([string]$Url,[string]$Dest,[string]$Name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $job = Start-Job -ScriptBlock {
            param($u,$d)
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("User-Agent","Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            $wc.DownloadFile($u,$d)
        } -ArgumentList $Url,$Dest
        $spin = @('|','/','-','\'); $si = 0
        while ($job.State -eq 'Running') {
            $sz = if (Test-Path $Dest) { [math]::Round((Get-Item $Dest).Length/1MB,1) } else { 0 }
            Write-Host -NoNewline "`rDang tai $Name`: $($spin[$si%4]) $sz MB - $([math]::Round($sw.Elapsed.TotalSeconds,1))s  "
            $si++; Start-Sleep -Milliseconds 300
        }
        Write-Host ""; Receive-Job $job -EA SilentlyContinue | Out-Null; Remove-Job $job -Force -EA SilentlyContinue; $sw.Stop()
        if ((Test-Path $Dest) -and (Get-Item $Dest).Length -gt 100000) {
            Write-Host "Da tai xong: $([math]::Round((Get-Item $Dest).Length/1MB,1)) MB" -ForegroundColor Green; return $true
        }
        Write-Host "Loi: file tai ve khong hop le (co the link het han)." -ForegroundColor Red; return $false
    } catch {
        Get-Job -EA SilentlyContinue | Remove-Job -Force -EA SilentlyContinue
        Write-Host "Loi: $_" -ForegroundColor Red; return $false
    }
}

function Show-Menu {
    param([string]$Title, $Options, [string]$NavEntry = "")
    if ($NavEntry) { [void]$Global:NavPath.Add($NavEntry) }
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
            & $Options[$c].Action
            if ($Global:NavPath.Count -gt 0) { $Global:NavPath.RemoveAt($Global:NavPath.Count-1) }
        }
    } while ($true)
    if ($NavEntry -and $Global:NavPath.Count -gt 0) { $Global:NavPath.RemoveAt($Global:NavPath.Count-1) }
}

function Run-Task {
    param([string]$Title,[scriptblock]$Action,[bool]$NeedConfirm=$false,[string]$ConfirmMsg="")
    Clear-Host; Write-Nav; Write-Host "=== $Title ===" -ForegroundColor Cyan
    if ($NeedConfirm -and (-not (Confirm-Action $ConfirmMsg))) { return }
    try { & $Action; Write-Log "$Title - OK"; Write-Host "`nHoan tat." -ForegroundColor Green }
    catch { Write-Log "$Title - LOI: $_"; Write-Host "`nLoi: $_" -ForegroundColor Red }
    Pause-Return
}

# ============================================================
# 1. NETWORK TROUBLESHOOT
# ============================================================
function Show-NetworkInfo {
    Clear-Host; Write-Nav; Write-Host "=== THONG TIN MANG HIEN TAI ===" -ForegroundColor Cyan
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
    Clear-Host; Write-Nav; Write-Host "=== DOI TEN MAY / DOMAIN ===" -ForegroundColor Cyan
    Write-Host "1. Chi doi Hostname"
    Write-Host "2. Join Domain"
    Write-Host "3. Doi Workgroup"
    Write-Host "0. Quay lai"
    $c = Read-Esc "Chon: "
    if ($c -eq $Global:ESC -or $c -eq "0") { return }

    switch ($c) {
        "1" {
            $newName = Read-Esc "Hostname moi (ESC huy): "
            if ($newName -eq $Global:ESC -or $newName -eq "") { return }
            if (-not (Confirm-Action "Doi hostname can KHOI DONG LAI may.")) { return }
            Rename-Computer -NewName $newName -Force
            Write-Log "Doi hostname: $newName"
            Write-Host "Hoan tat. Vui long khoi dong lai may." -ForegroundColor Green
        }
        "2" {
            $dom = Read-Esc "Domain (vd: company.local, ESC huy): "
            if ($dom -eq $Global:ESC -or $dom -eq "") { return }
            $cred = Get-Credential -Message "Tai khoan join domain"
            if (-not $cred) { return }
            if (-not (Confirm-Action "Join domain '$dom'? Can KHOI DONG LAI may.")) { return }
            try {
                Add-Computer -DomainName $dom -Credential $cred -Force -EA Stop
                Write-Log "Join domain: $dom"
                Write-Host "Join domain thanh cong. Khoi dong lai may." -ForegroundColor Green
            } catch {
                Write-Host "Join domain THAT BAI: $_" -ForegroundColor Red
            }
        }
        "3" {
            $wg = Read-Esc "Workgroup moi (ESC huy): "
            if ($wg -eq $Global:ESC -or $wg -eq "") { return }
            if (-not (Confirm-Action "Doi workgroup sang '$wg'? Can KHOI DONG LAI may.")) { return }
            Add-Computer -WorkgroupName $wg -Force
            Write-Log "Doi workgroup: $wg"
            Write-Host "Hoan tat. Khoi dong lai may." -ForegroundColor Green
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
    Write-Host "`nSe dat: $ip /$prefix  GW: $gw  tren interface $idx" -ForegroundColor Yellow
    if (-not (Confirm-Action "Tiep tuc?")) { return }
    try {
        Set-NetIPInterface -InterfaceIndex $idx -Dhcp Disabled -EA SilentlyContinue
        Get-NetRoute -InterfaceIndex $idx -EA SilentlyContinue | Remove-NetRoute -Confirm:$false -EA SilentlyContinue
        Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -EA SilentlyContinue | Remove-NetIPAddress -Confirm:$false -EA SilentlyContinue
        New-NetIPAddress -InterfaceIndex $idx -IPAddress $ip -PrefixLength $prefix -DefaultGateway $gw -EA Stop
        Write-Log "Dat IP tinh $ip/$prefix gw $gw tren if $idx"
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
        Write-Log "Dat DNS $($dnsList -join ', ') tren if $idx"
        Write-Host "Da dat DNS: $($dnsList -join ', ')" -ForegroundColor Green
    } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    Pause-Return
}

function Reset-NetworkFull {
    Clear-Host; Write-Nav; Write-Host "=== RESET MANG ===" -ForegroundColor Cyan
    $adapters = @(Get-NetAdapter | Where-Object Status -eq 'Up')
    Write-Host ""
    Write-Host ("  {0,-5} {1,-22} {2}" -f "Idx","Name","Description") -ForegroundColor Cyan
    Write-Host ("  " + ("-"*56))
    Write-Host ("  {0,-5} {1,-22} {2}" -f "ALL","--- TAT CA ---","Reset toan bo mang")
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
        if (-not [int]::TryParse($choice.Trim(),[ref]$idxNum)) {
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


function Invoke-QuickNetworkTest {
    Clear-Host; Write-Nav; Write-Host "=== QUICK NETWORK TEST ===" -ForegroundColor Cyan
    $idxNum = Select-NetIdx
    if ($null -eq $idxNum) { return }
    $adapter   = Get-NetAdapter | Where-Object InterfaceIndex -eq $idxNum
    $ipConfig  = Get-NetIPConfiguration -InterfaceIndex $idxNum
    $adIP      = $ipConfig.IPv4Address.IPAddress
    $adGW      = $ipConfig.IPv4DefaultGateway.NextHop
    Write-Host ""; Write-Host "Dang kiem tra..." -ForegroundColor Cyan; Write-Host ""

    # 1. Adapter
    $ok1 = $adapter.Status -eq 'Up'
    Write-Host ("[{0}] Adapter    : {1} ({2})" -f $(if($ok1){"OK"}else{"X"}), $adapter.Name, $adapter.Status) -ForegroundColor $(if($ok1){'Green'}else{'Red'})
    if (-not $ok1) { Write-Host "  Nguyen nhan: Adapter tat hoac cap khong cam." -ForegroundColor Yellow; Pause-Return; return }

    # 2. IP
    $ok2 = $adIP -ne $null
    Write-Host ("[{0}] IP Address : {1}" -f $(if($ok2){"OK"}else{"X"}), $(if($ok2){$adIP}else{"Khong co IP"})) -ForegroundColor $(if($ok2){'Green'}else{'Red'})
    if (-not $ok2) { Write-Host "  Nguyen nhan: Chua nhan duoc IP. Thu Renew IP (menu 3)." -ForegroundColor Yellow; Pause-Return; return }

    # 3. Gateway ping
    $ok3 = $false; $gwMs = 0
    if ($adGW) {
        $r = Test-Connection -ComputerName $adGW -Count 1 -EA SilentlyContinue
        $ok3 = $null -ne $r; $gwMs = if($ok3){$r.ResponseTime}else{0}
        Write-Host ("[{0}] Gateway    : {1} {2}" -f $(if($ok3){"OK"}else{"X"}), $adGW, $(if($ok3){"→ Ping ${gwMs}ms"}else{"→ KHONG PING DUOC"})) -ForegroundColor $(if($ok3){'Green'}else{'Yellow'})
    } else {
        Write-Host "[!] Gateway    : Khong co Gateway" -ForegroundColor Yellow
    }

    # 4. DNS
    $ok4 = $false; $dnsIp = ""
    try { $r4=[System.Net.Dns]::GetHostAddresses("google.com"); $ok4=$r4.Count-gt 0; $dnsIp=$r4[0].IPAddressToString } catch {}
    Write-Host ("[{0}] DNS        : {1}" -f $(if($ok4){"OK"}else{"X"}), $(if($ok4){"Resolve google.com → $dnsIp"}else{"KHONG RESOLVE DUOC → kiem tra DNS"})) -ForegroundColor $(if($ok4){'Green'}else{'Red'})

    # 5. Internet
    $r5 = Test-Connection -ComputerName "8.8.8.8" -Count 1 -EA SilentlyContinue
    $ok5 = $null -ne $r5
    Write-Host ("[{0}] Internet   : {1}" -f $(if($ok5){"OK"}else{"X"}), $(if($ok5){"8.8.8.8 → Reachable ($($r5.ResponseTime)ms)"}else{"KHONG KET NOI INTERNET"})) -ForegroundColor $(if($ok5){'Green'}else{'Red'})

    Write-Host ""; Write-Host ("─"*48) -ForegroundColor Cyan
    $allOk = $ok1 -and $ok2 -and $ok4 -and $ok5
    if ($allOk) { Write-Host "  Ket qua : TAT CA BINH THUONG" -ForegroundColor Green }
    else        { Write-Host "  Ket qua : CO LOI - Xem huong dan tren" -ForegroundColor Red }
    Write-Log "Quick Network Test - interface $idxNum"
    Pause-Return
}

function Invoke-PingTool {
    Clear-Host; Write-Nav; Write-Host "=== PING ===" -ForegroundColor Cyan
    Write-Host ""
    $target = Read-Esc "Nhap target (IP hoac domain): "
    if ($target -eq $Global:ESC -or $target -eq "") { return }
    $target = $target.Trim()

    # Phân loại target để chọn ngưỡng phù hợp
    $isLan = $target -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|localhost$)' `
             -or $target -match '^\d+\.\d+\.\d+\.\d+$' -and (
                 [System.Net.IPAddress]::TryParse($target, [ref]$null) -and
                 ([System.Net.IPAddress]::Parse($target).GetAddressBytes()[0] -in 10,127,192) -or
                 ([System.Net.IPAddress]::Parse($target).GetAddressBytes()[0] -eq 172 -and
                  [System.Net.IPAddress]::Parse($target).GetAddressBytes()[1] -ge 16 -and
                  [System.Net.IPAddress]::Parse($target).GetAddressBytes()[1] -le 31)
             )

    $cntStr = Read-Esc "So goi (mac dinh 10, Enter = 10): "
    if ($cntStr -eq $Global:ESC) { return }
    [int]$cnt = if ($cntStr -match "^\d+$" -and [int]$cntStr -gt 0 -and [int]$cntStr -le 200) { [int]$cntStr } else { 10 }

    Clear-Host; Write-Nav; Write-Host "=== PING ===" -ForegroundColor Cyan
    Write-Host "Target : $target $(if($isLan){'(LAN)'}else{'(Internet/WAN)'})"
    Write-Host "Count  : $cnt"; Write-Host ""

    $pingOut = @(& ping.exe -n $cnt $target 2>$null | ForEach-Object { Write-Host $_; $_ })

    # Parse chính xác: ưu tiên dòng summary, fallback từng reply
    $sent = $cnt; $lost = 0; $minMs = -1; $avgMs = -1; $maxMs = -1
    $times = @()
    foreach ($line in $pingOut) {
        if ($line -match "(?i)(?:time|thoi gian)[=<]\s*(\d+)\s*ms") { $times += [int]$Matches[1] }
        # Summary EN
        if ($line -match "(?i)Sent\s*=\s*(\d+).*?Lost\s*=\s*(\d+)")  { $sent=[int]$Matches[1]; $lost=[int]$Matches[2] }
        if ($line -match "(?i)Minimum\s*=\s*(\d+)ms.*?Maximum\s*=\s*(\d+)ms.*?Average\s*=\s*(\d+)ms") {
            $minMs=[int]$Matches[1]; $maxMs=[int]$Matches[2]; $avgMs=[int]$Matches[3] }
        # Summary VI
        if ($line -match "(?i)Da gui\s*=\s*(\d+).*?Mat\s*=\s*(\d+)") { $sent=[int]$Matches[1]; $lost=[int]$Matches[2] }
        if ($line -match "(?i)Toi thieu\s*=\s*(\d+)ms.*?Toi da\s*=\s*(\d+)ms.*?Trung binh\s*=\s*(\d+)ms") {
            $minMs=[int]$Matches[1]; $maxMs=[int]$Matches[2]; $avgMs=[int]$Matches[3] }
    }
    if ($times.Count -gt 0 -and $minMs -eq -1) {
        $minMs = ($times | Measure-Object -Minimum).Minimum
        $maxMs = ($times | Measure-Object -Maximum).Maximum
        $avgMs = [math]::Round(($times | Measure-Object -Average).Average, 0)
    }
    if ($lost -eq 0) {
        $timeoutCount = @($pingOut | Where-Object { $_ -match "(?i)timed out|het thoi gian|General failure|unreachable|khong the truy cap" }).Count
        if ($timeoutCount -gt 0) { $lost = $timeoutCount }
    }

    $lostPct = if ($sent -gt 0) { [math]::Round($lost / $sent * 100, 0) } else { 100 }
    Write-Host ""; Write-Host ("-" * 38) -ForegroundColor Cyan
    Write-Host ("Packets   : $sent sent, $lost lost")
    Write-Host ("Loss      : $lostPct%")
    if ($minMs -ge 0) {
        Write-Host ("Min/Avg/Max: $minMs / $avgMs / $maxMs ms")
    }
    Write-Host ""

    # Rating linh hoạt: 2 mức GOOD/POOR dựa trên loss + latency tương đối
    $ratingText, $ratingColor =
        if ($lostPct -eq 0 -and $avgMs -ge 0) {
            if ($isLan) {
                if ($avgMs -le 5)   { "[OK] GOOD - LAN on dinh", "Green" }
                elseif ($avgMs -le 20) { "[!] FAIR - LAN hoi cao", "Yellow" }
                else                { "[X] POOR - LAN bat thuong", "Red" }
            } else {
                if ($avgMs -lt 150)  { "[OK] GOOD - Internet on dinh", "Green" }
                elseif ($avgMs -lt 300){ "[!] FAIR - Internet hoi lag", "Yellow" }
                else                 { "[X] POOR - Internet cham", "Red" }
            }
        } elseif ($lostPct -lt 5) { "[!] FAIR - Co mat goi nhe", "Yellow" }
        else                       { "[X] POOR - Mat nhieu goi (>5%)", "Red" }

    Write-Host $ratingText -ForegroundColor $ratingColor
    Write-Log "Ping $target x$cnt -> Sent=$sent Lost=$lostPct% Avg=${avgMs}ms"
    Pause-Return
}

function Invoke-NetworkQuality {
    Clear-Host; Write-Nav; Write-Host "=== NETWORK QUALITY (60 giay) ===" -ForegroundColor Cyan
    Write-Host "Ping xen ke 8.8.8.8 va 1.1.1.1 trong 60s + Speed Test..." -ForegroundColor Gray
    Write-Host ""

    $targets   = @("8.8.8.8", "1.1.1.1")
    $latencies = [System.Collections.Generic.List[int]]::new()
    $jitters   = [System.Collections.Generic.List[double]]::new()
    $lost = 0; $total = 0; $prevMs = -1; $ti = 0
    $duration = 60
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.Elapsed.TotalSeconds -lt $duration) {
        $tgt = $targets[$ti % 2]; $ti++; $total++
        $r = Test-Connection -ComputerName $tgt -Count 1 -EA SilentlyContinue
        $elapsedS = [int]$sw.Elapsed.TotalSeconds
        $pct  = [math]::Min(100, [math]::Round($elapsedS / $duration * 100))
        $fill = [int]($pct / 5)
        $bar  = "#" * $fill + "-" * (20 - $fill)
        if ($r) {
            $ms = $r.ResponseTime
            $latencies.Add($ms)
            if ($prevMs -ge 0) { $jitters.Add([math]::Abs($ms - $prevMs)) }
            $prevMs = $ms
            Write-Host -NoNewline "`r  [$bar] $pct%  $total goi  ${tgt}: ${ms}ms     "
        } else {
            $lost++
            Write-Host -NoNewline "`r  [$bar] $pct%  $total goi  ${tgt}: TIMEOUT    "
        }
        Start-Sleep -Milliseconds 600
    }
    Write-Host ""; Write-Host ""

    # Speed test (Cloudflare 5MB)
    Write-Host "Dang do toc do download (Cloudflare 5MB)..." -ForegroundColor Yellow
    $dlMbps = -1
    try {
        $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
        $wc2 = New-Object System.Net.WebClient
        $wc2.Headers.Add("User-Agent", "Mozilla/5.0")
        $wc2.Proxy = [System.Net.WebRequest]::DefaultWebProxy
        $data = $wc2.DownloadData("https://speed.cloudflare.com/__down?bytes=5000000")
        $dlSw.Stop()
        if ($data.Length -gt 0) { $dlMbps = [math]::Round(($data.Length / 1MB) / $dlSw.Elapsed.TotalSeconds, 2) }
    } catch {}

    $lossPct   = if ($total -gt 0) { [math]::Round($lost / $total * 100, 1) } else { 100 }
    $avgLat    = if ($latencies.Count -gt 0) { [math]::Round(($latencies | Measure-Object -Average).Average, 1) } else { 999 }
    $minLat    = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Minimum).Minimum } else { 0 }
    $maxLat    = if ($latencies.Count -gt 0) { ($latencies | Measure-Object -Maximum).Maximum } else { 0 }
    $avgJitter = if ($jitters.Count -gt 0)   { [math]::Round(($jitters | Measure-Object -Average).Average, 1) } else { 0 }

    Write-Host "=== KET QUA ===" -ForegroundColor Cyan
    Write-Host ("  Latency (Avg)  : {0,8} ms" -f $avgLat)
    Write-Host ("  Packet Loss    : {0,8} %" -f $lossPct)
    Write-Host ("  Jitter         : {0,8} ms" -f $avgJitter)
    Write-Host ("  Min / Max      : {0} / {1} ms" -f $minLat, $maxLat)
    if ($dlMbps -gt 0) { Write-Host ("  Download Speed : {0,6} MB/s" -f $dlMbps) -ForegroundColor Cyan }
    else               { Write-Host "  Download Speed : (Khong do duoc)" -ForegroundColor Gray }
    Write-Host ""

    # Rating linh hoạt: GOOD nếu loss thấp + jitter thấp + latency chấp nhận được
    # Target 8.8.8.8/1.1.1.1 từ VN thường 20-80ms → không dùng ngưỡng tuyệt đối cứng
    $ratingText, $ratingColor =
        if ($lossPct -eq 0 -and $avgJitter -lt 15 -and $avgLat -lt 150)      { "[OK] GOOD - On dinh (gaming/call OK)", "Green" }
        elseif ($lossPct -lt 2 -and $avgJitter -lt 40 -and $avgLat -lt 250)  { "[!] FAIR - Co lag nhe", "Yellow" }
        else                                                                  { "[X] POOR - Ket noi yeu/khong on dinh", "Red" }
    Write-Host $ratingText -ForegroundColor $ratingColor
    Write-Log "Network Quality: Lat=${avgLat}ms Loss=${lossPct}% Jitter=${avgJitter}ms DL=${dlMbps}MB/s"
    Pause-Return
}

function Menu-Network {
    Show-Menu -Title "1. NETWORK TROUBLESHOOT" -NavEntry "1" -Options ([ordered]@{
        "1"=@{Label="Kiem tra thong tin mang";Action={Show-NetworkInfo}}
        "2"=@{Label="Dat lai ten may (Hostname/Domain)";Action={Set-ComputerNameDomain}}
        "3"=@{Label="Xoa IP cu, nhan IP moi";Action={Reset-IPAddress}}
        "4"=@{Label="Dat IP tinh";Action={Set-StaticIP}}
        "5"=@{Label="Dat DNS tinh";Action={Set-StaticDNS}}
        "6"=@{Label="Reset mang (chon Interface / ALL)";Action={Reset-NetworkFull}}
        "7"=@{Label="Quick Network Test";Action={Invoke-QuickNetworkTest}}
        "8"=@{Label="Ping ";Action={Invoke-PingTool}}
        "9"=@{Label="Network Quality (60s + Speed Test)";Action={Invoke-NetworkQuality}}
    })
}

# ============================================================
# 2. PRINTER & FILE SHARING
# ============================================================
function Add-CheckRow { param($L,[string]$N,[bool]$P,[string]$D=""); $L.Add([PSCustomObject]@{Hang_muc=$N;Ket_qua=$(if($P){"[OK]"}else{"[LOI]"});Chi_tiet=$D}) }

function Test-FileSharingLan {
    Clear-Host; Write-Nav; Write-Host "=== CHAN DOAN CAI DAT CHIA SE FILE QUA LAN ===" -ForegroundColor Cyan
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
    Clear-Host; Write-Nav; Write-Host "=== CHAN DOAN CAI DAT MAY IN ===" -ForegroundColor Cyan
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

function Show-SoftwareInfo {
    Clear-Host; Write-Nav; Write-Host "=== THONG TIN PHAN MEM ===" -ForegroundColor Cyan
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
        Write-Host "  IP    : $($_.IPv4Address.IPAddress)"
        Write-Host "  GW    : $($_.IPv4DefaultGateway.NextHop)"
        Write-Host "  DNS   : $($_.DNSServer.ServerAddresses -join ', ')"
    }
    Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object { Write-Host "  MAC ($($_.Name)): $($_.MacAddress)" }
    Write-Log "Xem thong tin phan mem"; Pause-Return
}

function Show-HardwareInfoFull {
    Clear-Host; Write-Nav; Write-Host "=== THONG TIN PHAN CUNG ===" -ForegroundColor Cyan
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
        Write-Host "  Drive ${letter}: | Free: ${free} / ${total} GB | Type: $($part.Type)"
    }
    Write-Host "`n--- GPU / VGA ---" -ForegroundColor Yellow
    Get-CimInstance Win32_VideoController | ForEach-Object {
        Write-Host "Ten: $($_.Name) | Mfr: $($_.AdapterCompatibility) | VRAM: $([math]::Round($_.AdapterRAM/1GB,2)) GB | Driver: $($_.DriverVersion)"; Write-Host ""
    }
    Write-Host "--- MAN HINH ---" -ForegroundColor Yellow
    try {
        Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -EA Stop | ForEach-Object {
            $name=($_.UserFriendlyName|Where-Object{$_ -ne 0}|ForEach-Object{[char]$_})-join""
            $sn=($_.SerialNumberID|Where-Object{$_ -ne 0}|ForEach-Object{[char]$_})-join""
            Write-Host "EDID: $name | Serial: $sn"
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
        foreach ($bx in $bat) {
            $st=if($BAT_MAP.ContainsKey([int]$bx.BatteryStatus)){$BAT_MAP[[int]$bx.BatteryStatus]}else{"Code=$($bx.BatteryStatus)"}
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
    $ospp = Get-ChildItem "C:\Program Files\Microsoft Office\Office*\ospp.vbs","C:\Program Files (x86)\Microsoft Office\Office*\ospp.vbs" -EA SilentlyContinue | Select-Object -First 1
    if ($ospp) { Write-Host "`n-- Office --"; cscript //nologo $ospp.FullName /dstatus }
    else { Write-Host "(Khong tim thay OSPP.VBS)" }
    Write-Log "Xem ban quyen"; Pause-Return
}

function Remove-LicenseExceptMachine {
    Clear-Host; Write-Nav; Write-Host "=== GO BO BAN QUYEN (giu lai OEM digital license) ===" -ForegroundColor Cyan
    Write-Host "Se GO product key dang cai (MAK/KMS/Retail)." -ForegroundColor Yellow
    cscript //nologo "$env:windir\System32\slmgr.vbs" /dli
    # Xac nhan lan 1: Y/N
    if (-not (Confirm-Action "Ban chac chan muon GO product key Windows?")) { return }
    # Xac nhan lan 2: Enter
    Write-Host ""
    Write-Host "XAC NHAN LAN 2: Nhan Enter de TIEP TUC, ESC de HUY." -ForegroundColor Red
    $r2 = Read-Esc ""
    if ($r2 -eq $Global:ESC) { Write-Host "Da huy."; Pause-Return; return }
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
    }
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
    })
}

# ============================================================
# 4. SYSTEM MAINTENANCE
# ============================================================
function Get-FolderSizeMB { param([string]$P); if(-not(Test-Path $P)){return 0}; $s=(Get-ChildItem $P -Recurse -Force -EA SilentlyContinue|Measure-Object -Property Length -Sum).Sum; if($null-eq$s){return 0}; return [math]::Round($s/1MB,2) }

function Invoke-CleanupFlow {
    param([bool]$Deep)
    Clear-Host; Write-Nav
    Write-Host "=== CLEANUP ANALYSIS ===" -ForegroundColor Cyan
    Write-Host "Dang quet..." -ForegroundColor Gray
    Write-Host ""

    $total = [double]0
    function Write-ItemRow([string]$Name,[double]$Sz) {
        $script:total += $Sz
        Write-Host ("{0,-24} {1,8:F1} MB" -f $Name, $Sz)
    }

    # ── QUICK items ──
    Write-Host "--- DON QUA ---" -ForegroundColor Yellow
    Write-ItemRow "User Temp"        (Get-FolderSizeMB $env:TEMP)
    Write-ItemRow "Windows Temp"     (Get-FolderSizeMB "$env:windir\Temp")
    Write-ItemRow "Windows Update"   (Get-FolderSizeMB "$env:windir\SoftwareDistribution\Download")
    Write-ItemRow "Error Reports"    (Get-FolderSizeMB "$env:LOCALAPPDATA\Microsoft\Windows\WER")
    $bsz = 0
    foreach ($bp in @(
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache")) { $bsz += Get-FolderSizeMB $bp }
    try {
        Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -EA Stop | ForEach-Object {
            $bsz += Get-FolderSizeMB "$($_.FullName)\cache2" }
    } catch {}
    Write-ItemRow "Browser Cache"    $bsz
    $thumbSz = [math]::Round((Get-ChildItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -EA SilentlyContinue | Measure-Object Length -Sum).Sum/1MB,1)
    Write-ItemRow "Thumbnail Cache"  $thumbSz
    Write-ItemRow "D3D Shader Cache" (Get-FolderSizeMB "$env:LOCALAPPDATA\D3DSCache")
    Write-ItemRow "DNS Cache"        0

    # ── DEEP items ──
    if ($Deep) {
        Write-Host ""
        Write-Host "--- DON KY (them) ---" -ForegroundColor Yellow
        Write-ItemRow "Recycle Bin"  (Get-FolderSizeMB "$env:SystemDrive\`$Recycle.Bin")
        Write-ItemRow "UWP Packages" (Get-FolderSizeMB "$env:LOCALAPPDATA\Packages")
        Write-ItemRow "LocalLow"     (Get-FolderSizeMB "$env:USERPROFILE\AppData\LocalLow")
        Write-ItemRow "SRU Database" (Get-FolderSizeMB "$env:windir\System32\sru")
        $dSz = 0
        if (Test-Path "$env:windir\MEMORY.DMP") { $dSz += [math]::Round((Get-Item "$env:windir\MEMORY.DMP").Length/1MB,1) }
        $dSz += Get-FolderSizeMB "$env:windir\Minidump"
        Write-ItemRow "Memory Dumps" $dSz
        Write-ItemRow "Prefetch"     (Get-FolderSizeMB "$env:windir\Prefetch")
        $evSz = 0
        try { $evSz = [math]::Round((Get-WinEvent -ListLog * -EA Stop | Where-Object FileSize | Measure-Object FileSize -Sum).Sum/1MB,1) } catch {}
        Write-ItemRow "Event Logs"   $evSz
    }

    Write-Host ("─"*34) -ForegroundColor Cyan
    Write-Host ("{0,-24} {1,8:F1} MB" -f "Potentially removable", $total) -ForegroundColor Yellow

    $ch = Read-Esc "`nClean selected items? [Y/N] (ESC de huy): "
    if ($ch -eq $Global:ESC -or $ch.ToUpper() -ne "Y") { Pause-Return; return }

    # ── Thực hiện xóa Quick ──
    foreach ($p in @(
        "$env:TEMP",
        "$env:windir\Temp",
        "$env:windir\SoftwareDistribution\Download",
        "$env:LOCALAPPDATA\Microsoft\Windows\WER",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache",
        "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache",
        "$env:LOCALAPPDATA\D3DSCache")) {
        if (Test-Path $p) { Remove-Item "$p\*" -Recurse -Force -EA SilentlyContinue }
    }
    try {
        Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -Directory -EA Stop | ForEach-Object {
            Remove-Item "$($_.FullName)\cache2\*" -Recurse -Force -EA SilentlyContinue }
    } catch {}
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -EA SilentlyContinue
    ipconfig /flushdns | Out-Null

    # ── Thực hiện xóa Deep ──
    if ($Deep) {
        Clear-RecycleBin -Force -EA SilentlyContinue
        Remove-Item "$env:LOCALAPPDATA\Packages\*"        -Recurse -Force -EA SilentlyContinue
        Remove-Item "$env:USERPROFILE\AppData\LocalLow\*" -Recurse -Force -EA SilentlyContinue
        Stop-Service DPS -Force -EA SilentlyContinue
        Remove-Item "$env:windir\System32\sru\*" -Force -EA SilentlyContinue
        Start-Service DPS -EA SilentlyContinue
        Remove-Item "$env:windir\MEMORY.DMP"        -Force -EA SilentlyContinue
        Remove-Item "$env:windir\Minidump\*" -Recurse -Force -EA SilentlyContinue
        Remove-Item "$env:windir\Prefetch\*"        -Force -EA SilentlyContinue
        wevtutil el | ForEach-Object { wevtutil cl "$_" 2>$null }
    }

    Write-Log "$(if($Deep){'Deep'}else{'Quick'}) Clean - pre-scan ~$([math]::Round($total,1)) MB"
    Write-Host "`nDa don xong. Da giai phong uoc tinh: ~$([math]::Round($total,1)) MB" -ForegroundColor Green
    Pause-Return
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
        "6"=@{Label="Performance Diagnostic / Chan doan hieu nang";Action={Show-PerformanceDiag}}
    })
}

function Menu-PowerManagement {
    Show-Menu -Title "Power Management / Quan ly nguon dien" -Options ([ordered]@{
        "1"=@{Label="Power Plan Settings / Che do nguon dien";Action={Start-Process powercfg.cpl}}
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
            Write-Host "Se tao file battery-report.html tren Desktop."
            $c = Read-Esc "Tao bao cao? [Y/N]: "
            if ($c.ToUpper() -ne "Y") { return }
            $out = [IO.Path]::Combine([Environment]::GetFolderPath('Desktop'), 'battery-report.html')
            if (Test-Path $out) { Remove-Item $out -Force -EA SilentlyContinue }
            Write-Host "Dang tao bao cao pin..." -ForegroundColor Yellow
            Push-Location ([Environment]::GetFolderPath('Desktop'))
            cmd /c "powercfg /batteryreport" 2>&1 | Out-Null
            Pop-Location
            Start-Sleep 2
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
            $rs = [RunspaceFactory]::CreateRunspace(); $rs.Open()
            $psEnergy = [PowerShell]::Create(); $psEnergy.Runspace = $rs
            [void]$psEnergy.AddScript({
                param($desk)
                Push-Location $desk
                cmd /c "powercfg /energy /duration 20" 2>&1 | Out-Null
                Pop-Location
            }).AddArgument([Environment]::GetFolderPath('Desktop'))
            $handle = $psEnergy.BeginInvoke()
            while (-not $handle.IsCompleted) {
                $pct = [math]::Min(99, [math]::Round($sw.Elapsed.TotalSeconds / 25 * 100))
                Write-Host -NoNewline "`r  Dang phan tich: $pct% - $([math]::Round($sw.Elapsed.TotalSeconds,0))s  "
                Start-Sleep -Milliseconds 500
            }
            Write-Host ""
            try { $psEnergy.EndInvoke($handle) | Out-Null } catch {}
            $psEnergy.Dispose(); $rs.Dispose(); $sw.Stop()
            if (Test-Path $out) { Write-Host "Da xuat: $out ($([math]::Round($sw.Elapsed.TotalSeconds,0))s)" -ForegroundColor Green; Start-Process $out }
            else { Write-Host "Khong xuat duoc." -ForegroundColor Yellow }
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
            Write-Host "Trang thai dich vu: $($svc.Status)"
            if ($svc.Status -ne 'Running') { Write-Host "Dang khoi dong dich vu..." -ForegroundColor Yellow; Start-Service wuauserv -EA SilentlyContinue; Start-Sleep 2 }
            Write-Host "Dang gui lenh quet (UsoClient + wuauclt)..." -ForegroundColor Yellow
            & UsoClient.exe StartScan 2>&1 | Out-Null
            & wuauclt.exe /detectnow 2>&1 | Out-Null
            Write-Host "Da gui lenh quet thanh cong." -ForegroundColor Green
            Write-Host "Ket qua se hien tai: Cai dat -> Windows Update." -ForegroundColor Cyan
            Start-Process ms-settings:windowsupdate
        }}}
        "2"=@{Label="Open Windows Update / Mo cap nhat Windows";Action={Start-Process ms-settings:windowsupdate}}
        "3"=@{Label="Windows Update Status / Trang thai cap nhat";Action={Run-Task "Update Status" {Get-Service wuauserv|Format-Table Name,Status,StartType}}}
        "4"=@{Label="Restart Update Services / Khoi dong lai dich vu";Action={Run-Task "Restart Services" {Restart-Service wuauserv,bits,cryptsvc -Force}}}
        "5"=@{Label="Reset Update Components / Dat lai thanh phan";Action={Run-Task "Reset Components" -NeedConfirm $true -ConfirmMsg "Se dat lai cache Windows Update." {
            Stop-Service wuauserv,bits,cryptsvc -Force -EA SilentlyContinue
            Rename-Item "$env:windir\SoftwareDistribution" "SoftwareDistribution.bak_$(Get-Date -Format yyyyMMddHHmmss)" -EA SilentlyContinue
            Rename-Item "$env:windir\System32\catroot2" "catroot2.bak_$(Get-Date -Format yyyyMMddHHmmss)" -EA SilentlyContinue
            Start-Service wuauserv,bits,cryptsvc
        }}}
        "6"=@{Label="Clear Update Cache / Xoa cache cap nhat";Action={Run-Task "Clear Cache" {Stop-Service wuauserv -Force; Remove-Item "$env:windir\SoftwareDistribution\Download\*" -Recurse -Force -EA SilentlyContinue; Start-Service wuauserv}}}
        "7"=@{Label="Check Pending Reboot / Kiem tra cho khoi dong lai";Action={Run-Task "Pending Reboot" {Write-Host "Can restart: $(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')"}}}
        "8"=@{Label="Update History / Lich su cap nhat";Action={Run-Task "Update History" {Get-HotFix|Sort-Object InstalledOn -Desc|Select-Object -First 20|Format-Table}}}
        "9"=@{Label="Set Windows Update / Quan ly (UC20.exe)";Action={Clear-Host;Write-Host "=== SET WINDOWS UPDATE ===" -ForegroundColor Cyan;Run-UC20;Pause-Return}}
    })
}

function Menu-Audio {
    Show-Menu -Title "Audio / Am thanh" -Options ([ordered]@{
        "1"=@{Label="Restart Windows Audio / Khoi dong lai am thanh";Action={Run-Task "Restart Audio" {Restart-Service Audiosrv -Force}}}
        "2"=@{Label="Restart Audio Endpoint Builder";Action={Run-Task "Restart Endpoint" {Restart-Service AudioEndpointBuilder -Force}}}
        "3"=@{Label="List Playback Devices / Thiet bi phat";Action={Run-Task "Playback Devices" {Get-CimInstance Win32_SoundDevice|Format-Table Name,Status}}}
        "4"=@{Label="List Recording Devices / Thiet bi ghi";Action={Run-Task "Recording Devices" {Get-PnpDevice -Class AudioEndpoint|Format-Table FriendlyName,Status}}}
        "5"=@{Label="Default Playback/Microphone / Thiet bi mac dinh";Action={Start-Process mmsys.cpl}}
        "6"=@{Label="Check Audio Driver / Kiem tra driver am thanh";Action={Run-Task "Audio Driver" {Get-CimInstance Win32_PnPSignedDriver|Where-Object{$_.DeviceClass -eq "MEDIA"}|Format-Table DeviceName,DriverVersion,DriverDate}}}
        "7"=@{Label="Open Sound Settings / Mo cai dat am thanh";Action={Start-Process ms-settings:sound}}
        "8"=@{Label="Audio Diagnostic / Chan doan am thanh";Action={Start-Process msdt.exe -ArgumentList "/id AudioPlaybackDiagnostic"}}
    })
}

function Run-HardwareTest {
    Clear-Host; Write-Nav; Write-Host "=== HARDWARE CHECK (HardwareTest.exe) ===" -ForegroundColor Cyan
    $url = "https://www.dropbox.com/scl/fi/obzvj7tsrkfo3mpsxnb90/HardwareTest.exe?rlkey=i8s0kiwzugbxpzflzm1bd6bmn&st=9iecy4sc&dl=1"
    $path = "$env:TEMP\HardwareTest_$([guid]::NewGuid().ToString('N').Substring(0,8)).exe"
    $ok = Download-WithProgress -Url $url -Dest $path -Name "HardwareTest.exe"
    if ($ok -and (Test-Path $path)) {
        Write-Host "Dang chay HardwareTest.exe (quyen admin)..." -ForegroundColor Yellow
        Start-Process -FilePath $path -Verb RunAs -Wait
        Write-Log "Da chay HardwareTest.exe"
        Remove-Item $path -Force -EA SilentlyContinue
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
        "8"=@{Label="Hardware Check / Kiem tra phan cung";Action={Run-HardwareTest}}
        "9"=@{Label="Advanced Tools / Cong cu nang cao";Action={Menu-AdvancedTools}}
        "10"=@{Label="Lam moi he thong / System Refresh";Action={Invoke-SystemRefresh}}
    })
}

# ============================================================
# 5. SOFTWARE
# ============================================================
function Open-Site {
    param([string]$Name,[string]$Url,[bool]$IsPlaceholder=$false)
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
    [void]$Global:NavPath.Add("5")
    do {
        Clear-Host
        Write-Nav
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
        Write-Host "-- OFFICE / VAN PHONG --" -ForegroundColor Yellow
        Write-Host "8.  Cai dat font chu Viet Nam (1398.exe)"
        Write-Host "9.  Unikey"
        Write-Host "10. Office 365"
        Write-Host "11. WPS Office"
        Write-Host "12. LibreOffice"
        Write-Host "13. Foxit PDF Reader"
        Write-Host "14. PDFgear (Edit PDF)"
        Write-Host ""
        Write-Host "-- MEDIA & TRUYEN THONG --" -ForegroundColor Yellow
        Write-Host "15. VLC"
        Write-Host "16. CapCut"
        Write-Host "17. OBS Studio"
        Write-Host ""
        Write-Host "-- CONG CU HE THONG / SYSTEM TOOLS --" -ForegroundColor Yellow
        Write-Host "18. WinRAR"
        Write-Host "19. ImageGlass"
        Write-Host "20. AnyDesk"
        Write-Host "21. UltraViewer"
        Write-Host "22. Man hinh cho Fliqlo"
        Write-Host "23. Bing Wallpaper"
        Write-Host "24. Crystal Disk Info"
        Write-Host "25. Recoverit"
        Write-Host "26. MiniTool Partition Wizard"
        Write-Host "27. Double Driver"
        Write-Host ""
        Write-Host "-- PHAN MEM KHAC / OTHER --" -ForegroundColor Yellow
        Write-Host "99. Office AIO / AutoCAD / WinToHDD"
        Write-Host ""
        Write-Host "0. Back"
        $c = Read-Esc "Chon: "
        if ($c -eq $Global:ESC -or $c -eq "0") { break }
        [void]$Global:NavPath.Add($c)
        switch ($c) {
            "1"  { Open-Site "Zalo PC"                   "https://zalo.me/pc" }
            "2"  { Open-Site "Zoom"                      "https://zoom.us/download" }
            "3"  { Open-Site "Telegram"                  "https://telegram.org/dl/desktop/win" }
            "4"  { Open-Site "WeChat"                    "https://www.wechat.com/en/" }
            "5"  { Open-Site "KakaoTalk"                 "https://www.kakaocorp.com/page/service/all?lang=ENG" }
            "6"  { Open-Site "Google Chrome"             "https://www.google.com/chrome/" }
            "7"  { Open-Site "Coc Coc"                   "https://coccoc.com/download" }
            "8"  { Run-FontViet }
            "9"  { Open-Site "Unikey"                    "https://www.unikey.org/download.html" }
            "10" { Open-Site "Office 365"                "https://www.microsoft.com/en-us/microsoft-365/try" }
            "11" { Open-Site "WPS Office"                "https://www.wps.com/download/" }
            "12" { Open-Site "LibreOffice"               "https://www.libreoffice.org/download/download/" }
            "13" { Open-Site "Foxit PDF Reader"          "https://www.foxit.com/pdf-reader/" }
            "14" { Open-Site "PDFgear"                   "https://pdfgear.com/pdfgear-for-windows/" }
            "15" { Open-Site "VLC"                       "https://www.videolan.org/vlc/download-windows.html" }
            "16" { Open-Site "CapCut"                    "https://www.capcut.com/tools/pc-video-editor" }
            "17" { Open-Site "OBS Studio"                "https://obsproject.com/download" }
            "18" { Open-Site "WinRAR"                    "https://www.rarlab.com/download.htm" }
            "19" { Open-Site "ImageGlass"                "https://imageglass.org/" }
            "20" { Open-Site "AnyDesk"                   "https://anydesk.com/en/downloads/windows" }
            "21" { Open-Site "UltraViewer"               "https://www.ultraviewer.net/en/download.html" }
            "22" { Open-Site "Fliqlo Screensaver"        "https://fliqlo.com/screensaver/" }
            "23" { Open-Site "Bing Wallpaper"            "https://www.microsoft.com/en-us/bing/bing-wallpaper" }
            "24" { Open-Site "Crystal Disk Info"         "https://crystalmark.info/en/download/" }
            "25" { Open-Site "Recoverit"                 "https://recoverit.wondershare.com/" }
            "26" { Open-Site "MiniTool Partition Wizard" "https://www.partitionwizard.com/free-partition-manager.html" }
            "27" { Open-Site "Double Driver"             "https://download.com.vn/double-driver-25157" }
            "99" { Menu-OtherSoftware }
            default {
                Write-Host "Lua chon khong hop le. Nhap lai." -ForegroundColor Red
                Start-Sleep -Milliseconds 800
            }
        }
        if ($Global:NavPath.Count -gt 0) { $Global:NavPath.RemoveAt($Global:NavPath.Count-1) }
    } while ($true)
    if ($Global:NavPath.Count -gt 0) { $Global:NavPath.RemoveAt($Global:NavPath.Count-1) }
}


# ============================================================
# MAIN MENU
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
                    Write-Host ""
                    Write-Host "Cam on da su dung." -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host "Dang don dep file tam..." -ForegroundColor Gray
                    $SID = $env:TOOLKIT_SESSION_ID
                    $patterns = @(
                        "$env:TEMP\ToolkitCore_$SID.ps1",
                        "$env:TEMP\PrinterFixTool_*.exe",
                        "$env:TEMP\UC20_*.exe",
                        "$env:TEMP\CanchinhOffice_*.exe",
                        "$env:TEMP\HardwareTest_*.exe",
                        "$env:TEMP\1398_*.exe"
                    )
                    $deleted = @()
                    foreach ($pat in $patterns) {
                        Get-Item $pat -EA SilentlyContinue | ForEach-Object {
                            $deleted += $_.Name
                            Remove-Item $_.FullName -Force -EA SilentlyContinue
                        }
                    }
                    if ($deleted.Count -gt 0) {
                        Write-Host "Da xoa $($deleted.Count) file:" -ForegroundColor Green
                        $deleted | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
                    } else {
                        Write-Host "Khong co file tam can xoa." -ForegroundColor Gray
                    }
                    Start-Sleep 2
                    exit
                }
            }
        }
    } while ($true)
}

Show-MainMenu
