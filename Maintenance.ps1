# ============================================================
#  MAINTENANCE.PS1 - Module 4: System Maintenance / Bao tri he thong
#  Duoc dot-source boi ToolkitCore.ps1 khi nguoi dung chon muc 4
#  Cac ham Write-Nav, Run-Task, Show-Menu, Download-WithProgress, v.v.
#  da duoc khai bao trong ToolkitCore.ps1 truoc khi module nay duoc tai.
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

function _Menu-Maintenance {
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