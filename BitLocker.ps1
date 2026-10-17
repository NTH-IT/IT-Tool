# ============================================================
#  BITLOCKER.PS1 - Module 6: Quan ly BitLocker
#  Duoc dot-source boi ToolkitCore.ps1 khi nguoi dung chon muc 6
# ============================================================

function Test-BitLockerAvailable {
    try {
        $null = Get-Command Get-BitLockerVolume -EA Stop
        return $true
    } catch {
        return $false
    }
}

function Get-BitLockerVolumesSafe {
    try {
        return @(Get-BitLockerVolume -EA Stop)
    } catch {
        return @()
    }
}

function Show-BitLockerStatusTable {
    param($Volumes)
    Write-Host ""
    Write-Host ("  {0,-6} {1,-16} {2,-12} {3,-16} {4,-8} {5,4}" -f "Drive", "Label", "Status", "Method", "Locked", "%") -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 70))
    foreach ($v in $Volumes) {$mp = "$($v.MountPoint)"
        $label = if ($v.VolumeLabel) {$v.VolumeLabel } else { "(none)" }
        $status = "$($v.ProtectionStatus)"
        $method = if ($v.EncryptionMethod -and$v.EncryptionMethod -ne 'None') { "$($v.EncryptionMethod)" } else { "None" }
        $locked = "$($v.LockStatus)"
        $pct    = "$($v.EncryptionPercentage)"
        $color = if ($status -eq 'On') { 'Green' } elseif ($status -eq 'Off') { 'Gray' } else { 'Yellow' }
        Write-Host ("  {0,-6} {1,-16} {2,-12} {3,-16} {4,-8} {5,4}" -f $mp, $label,$status, $method,$locked, $pct) -ForegroundColor$color
    }
    Write-Host ""
}

function Get-BitLockerDriveList {
    param($Volumes)
    # Đã sửa lỗi \vert{} thành |
    return @($Volumes \vert{} Where-Object {$_.ProtectionStatus -eq 'On' -or
        ($_.EncryptionMethod -and$_.EncryptionMethod -ne 'None')
    })
}

function Select-BitLockerVolume {
    param($Volumes)
    if (-not $Volumes -or$Volumes.Count -eq 0) {
        Write-Host "Khong co volume nao." -ForegroundColor Yellow
        return $null
    }
    Write-Host ""
    Write-Host "  Danh sach volume:" -ForegroundColor Cyan
    $i = 1
    foreach ($v in$Volumes) {
        Write-Host ("  [{0}] {1} - {2} ({3})" -f $i, $v.MountPoint, $v.VolumeLabel, $v.ProtectionStatus)$i++
    }
    Write-Host ""
    while ($true) {$c = Read-Esc "Chon volume (so thu tu, ESC de huy): "
        if ($c -eq$Global:ESC) { return $null }$n = 0
        if ([int]::TryParse(($c -replace '[^\d]',''), [ref]$n) -and$n -ge 1 -and $n -le$Volumes.Count) {
            return $Volumes[$n - 1]
        }
        Write-Host "Lua chon khong hop le." -ForegroundColor Red
    }
}

function Get-RecoveryKeysOfVolume {
    param($Volume)$keys = @()
    foreach ($kp in$Volume.KeyProtector) {
        if ($kp.KeyProtectorType -eq 'RecoveryPassword' -and $kp.RecoveryPassword) {$keys += @{
                Id    = $kp.KeyProtectorId
                Value = $kp.RecoveryPassword
            }
        }
    }
    return $keys
}

function Show-RecoveryKeyWithConfirm {
    param($Volume, [switch]$ReturnInsteadOfPrint)
    $keys = Get-RecoveryKeysOfVolume$Volume
    if ($keys.Count -eq 0) {
        Write-Host "Volume nay khong co Recovery Key (co the chi dung TPM)." -ForegroundColor Yellow
        return $null
    }
    Write-Host ""
    Write-Host "CANH BAO BAO MAT:" -ForegroundColor Red
    Write-Host "  Recovery Key la 48 chu so dung de mo khoa o dia." -ForegroundColor Yellow
    Write-Host "  Khong chia se, khong chup anh, khong stream man hinh." -ForegroundColor Yellow
    Write-Host "  Neu lo key, nguoi khac co the doc du lieu cua ban." -ForegroundColor Yellow
    Write-Host ""
    $c = Read-Esc "Ban co chac muon hien thi Recovery Key? [Y/N]: "
    if ($c.ToUpper() -ne "Y") { Write-Host "Da huy."; return $null }

    if ($ReturnInsteadOfPrint) { return$keys }

    Write-Host ""
    Write-Host "=== RECOVERY KEY CUA $($Volume.MountPoint) ===" -ForegroundColor Cyan
    foreach ($k in$keys) {
        Write-Host ("  ID    : {0}" -f $k.Id)
        Write-Host ("  Key   : {0}" -f $k.Value) -ForegroundColor Green
        Write-Host ""
    }
    return $keys
}

function Export-RecoveryKeysToFile {
    param($Volumes)$allKeys = @()
    foreach ($v in$Volumes) {
        $keys = Get-RecoveryKeysOfVolume$v
        foreach ($k in $keys) {$allKeys += [PSCustomObject]@{
                Drive    = "$($v.MountPoint)"
                Label    = "$($v.VolumeLabel)"
                KeyId    = "$($k.Id)"
                KeyValue = "$($k.Value)"
            }
        }
    }
    if ($allKeys.Count -eq 0) {
        Write-Host "Khong co Recovery Key nao de xuat." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "Se xuat $($allKeys.Count) Recovery Key ra Desktop." -ForegroundColor Yellow
    Write-Host "CANH BAO: File chua key rat nhay cam, nen xoa sau khi ghi ra giay." -ForegroundColor Red
    $c = Read-Esc "Tiep tuc? [Y/N]: "
    if ($c.ToUpper() -ne "Y") { Write-Host "Da huy."; return }

    $dest = [IO.Path]::Combine([Environment]::GetFolderPath('Desktop'),
        "BitLocker_RecoveryKeys_$(Get-Date -Format yyyyMMdd_HHmmss).txt")
    $lines = @()$lines += "BitLocker Recovery Keys"
    $lines += "Xuat luc: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    # Đã sửa lỗi \vert{} thành |
    $lines += "May: $env:COMPUTERNAME  \vert{}  User:$env:USERNAME"
    $lines += ("=" * 60)
    $lines += ""
    foreach ($k in $allKeys) {$lines += "Drive : $($k.Drive)"
        $lines += "Label : $($k.Label)"
        $lines += "Key ID: $($k.KeyId)"
        $lines += "Key   : $($k.KeyValue)"
        $lines += ("-" * 60)
    }
    try {
        [System.IO.File]::WriteAllLines($dest,$lines)
        Write-Host "Da xuat: $dest" -ForegroundColor Green
        Write-Log "Xuat BitLocker Recovery Key ra $dest"
        Start-Process notepad.exe $dest
    } catch {
        Write-Host "Loi xuat file: $_" -ForegroundColor Red
    }
}

function Disable-BitLockerVolumeWithProgress {
    param($Volume)$mp = "$($Volume.MountPoint)"
    Write-Host ""
    Write-Host "CANH BAO:" -ForegroundColor Red
    Write-Host "  Se GIAI MA hoan toan o $mp. Qua trinh co the mat 30 phut -> vai gio." -ForegroundColor Yellow
    Write-Host "  KHONG duoc tat may, rut dien, sleep trong qua trinh giai ma." -ForegroundColor Yellow
    Write-Host "  Sau khi xong KHONG THE hoan tac (phai ma hoa lai tu dau)." -ForegroundColor Yellow
    Write-Host ""
    $c = Read-Esc "Ban chac chan? Nhap 'DISABLE' de xac nhan: "
    if ($c -ne "DISABLE") { Write-Host "Da huy."; return }

    try {
        Write-Host ""
        Write-Host "Dang tat BitLocker tren $mp ..." -ForegroundColor Yellow
        Disable-BitLocker -MountPoint $mp -EA Stop | Out-Null
        Write-Log "Disable BitLocker $mp - bat dau"

        $sw = [System.Diagnostics.Stopwatch]::StartNew()$maxWait = 7200
        while ($sw.Elapsed.TotalSeconds -lt$maxWait) {
            Start-Sleep -Seconds 5
            try {
                $v = Get-BitLockerVolume -MountPoint$mp -EA Stop
                $pct = [int]$v.EncryptionPercentage
                $status = "$($v.ProtectionStatus)"
                $pctLeft = 100 -$pct
                $fill = [int]($pctLeft / 2)
                if ($fill -gt 50) {$fill = 50 }
                if ($fill -lt 0)  { $fill = 0 }$bar = ("#" * $fill) + ("-" * (50 - $fill))
                Write-Host -NoNewline ("`r  [Giai ma] {0,3}%  (con lai {1,3}%)  [{2}]  Trang thai: {3}   " -f $pctLeft, $pct, $bar, $status)
                if ($pct -eq 0 -or $status -eq 'Off') {
                    Write-Host ""
                    Write-Host "Da giai ma xong $mp." -ForegroundColor Green
                    Write-Log "Disable BitLocker $mp - OK ($([math]::Round($sw.Elapsed.TotalSeconds,0))s)"
                    return
                }
            } catch {
                Write-Host ""
                Write-Host "Loi doc trang thai: $_" -ForegroundColor Red
                return
            }
        }
        Write-Host ""
        Write-Host "Het thoi gian theo doi (2 gio). Kiem tra lai bang muc [7]." -ForegroundColor Yellow
    } catch {
        Write-Host "Loi disable BitLocker: $_" -ForegroundColor Red
        Write-Log "Disable BitLocker $mp - LOI: $_"
    }
}

function Suspend-BitLockerVolumeWithConfirm {
    param($Volume)
    $mp = "$($Volume.MountPoint)"
    Write-Host ""
    Write-Host "Suspend se tam ngung bao ve $mp. Du lieu van con ma hoa." -ForegroundColor Yellow
    Write-Host "Co the Resume lai bat cu luc nao. Thuong dung khi update BIOS/firmware." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [1] Suspend 1 lan (tu dong Resume sau khi reboot)"
    Write-Host "  [2] Suspend khong gioi han (Resume thu cong)"
    Write-Host "  [3] Resume (bat lai bao ve)"
    Write-Host "  [0] Huy"
    $c = Read-Esc "Chon: "
    if ($c -eq "1") {
        try {
            Suspend-BitLocker -MountPoint $mp -RebootCount 1 -EA Stop | Out-Null
            Write-Host "Da suspend $mp (1 reboot)." -ForegroundColor Green
            Write-Log "Suspend BitLocker $mp (1 reboot)"
        } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    } elseif ($c -eq "2") {
        try {
            Suspend-BitLocker -MountPoint $mp -RebootCount 0 -EA Stop | Out-Null
            Write-Host "Da suspend $mp (khong gioi han)." -ForegroundColor Green
            Write-Log "Suspend BitLocker $mp (khong gioi han)"
        } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    } elseif ($c -eq "3") {
        try {
            Resume-BitLocker -MountPoint $mp -EA Stop | Out-Null
            Write-Host "Da resume bao ve $mp." -ForegroundColor Green
            Write-Log "Resume BitLocker $mp"
        } catch { Write-Host "Loi: $_" -ForegroundColor Red }
    }
}

function Show-BitLockerMenu {
    Clear-Host; Write-Nav; Write-Host "=== 6. BITLOCKER / MA HOA O DIA ===" -ForegroundColor Cyan
    Write-Host ""

    if (-not (Test-BitLockerAvailable)) {
        Write-Host "May nay khong ho tro BitLocker (hoac khong phai Windows Pro/Enterprise)." -ForegroundColor Red
        Pause-Return
        return
    }

    $volumes = Get-BitLockerVolumesSafe
    if ($volumes.Count -eq 0) {
        Write-Host "Khong doc duoc thong tin BitLocker (co the chua bat)." -ForegroundColor Yellow
        Pause-Return
        return
    }

    Show-BitLockerStatusTable $volumes

    $encryptedVols = Get-BitLockerDriveList $volumes
    if ($encryptedVols.Count -eq 0) {
        Write-Host ">> BitLocker: TAT (khong co volume nao duoc ma hoa)." -ForegroundColor Yellow
        Write-Host "Khong co gi de kiem tra." -ForegroundColor Gray
        Pause-Return
        return
    }

    Write-Host ">> BitLocker: CO BAT ($($encryptedVols.Count) volume dang ma hoa)" -ForegroundColor Green

    do {
        Write-Host ""
        Write-Host "  [1] Xem chi tiet 1 volume"
        Write-Host "  [2] Xem Recovery Key (co canh bao)"
        Write-Host "  [3] Xuat Recovery Key ra file Desktop"
        Write-Host "  [4] Suspend / Resume protection"
        Write-Host "  [5] Disable BitLocker (giai ma hoan toan)"
        Write-Host "  [6] Quan ly Key Protector (them/xoa/doi)"
        Write-Host "  [7] Kiem tra lai trang thai"
        Write-Host "  [0] Quay lai"
        $c = Read-Esc "Chon: "
        if ($c -eq $Global:ESC -or $c -eq "0") { return }

        switch ($c) {
            "1" { Show-BitLockerVolumeDetail -Volumes $encryptedVols }
            "2" {
                $v = Select-BitLockerVolume $encryptedVols
                if ($v) { Show-RecoveryKeyWithConfirm -Volume $v | Out-Null; Pause-Return }
            }
            "3" { Export-RecoveryKeysToFile -Volumes $encryptedVols; Pause-Return }
            "4" {
                $v = Select-BitLockerVolume $encryptedVols
                if ($v) { Suspend-BitLockerVolumeWithConfirm -Volume $v; Pause-Return }
            }
            "5" {
                $v = Select-BitLockerVolume $encryptedVols
                if ($v) { Disable-BitLockerVolumeWithProgress -Volume $v; Pause-Return }
            }
            "6" { Show-BitLockerKeyProtectorMenu -Volumes $encryptedVols }
            "7" {
                $volumes = Get-BitLockerVolumesSafe
                $encryptedVols = Get-BitLockerDriveList $volumes
                Clear-Host; Write-Nav; Write-Host "=== 6. BITLOCKER / MA HOA O DIA ===" -ForegroundColor Cyan
                Show-BitLockerStatusTable $volumes
                Write-Host ">> BitLocker: $(if($encryptedVols.Count -gt 0){"CO BAT ($($encryptedVols.Count) volume)"}else{"TAT"})" `
                    -ForegroundColor $(if($encryptedVols.Count -gt 0){'Green'}else{'Yellow'})
            }
        }
    } while ($true)
}

function Show-BitLockerVolumeDetail {
    param($Volumes)
    $v = Select-BitLockerVolume$Volumes
    if (-not $v) { return }

    Clear-Host; Write-Nav
    Write-Host "=== CHI TIET VOLUME $($v.MountPoint) ===" -ForegroundColor Cyan
    Write-Host ("  Mount Point       : {0}" -f $v.MountPoint)
    Write-Host ("  Label             : {0}" -f $v.VolumeLabel)
    Write-Host ("  Volume Status     : {0}" -f $v.VolumeStatus)
    Write-Host ("  Protection Status : {0}" -f $v.ProtectionStatus)
    Write-Host ("  Encryption Method : {0}" -f $v.EncryptionMethod)
    Write-Host ("  Encryption %      : {0}" -f $v.EncryptionPercentage)
    Write-Host ("  Lock Status       : {0}" -f $v.LockStatus)
    Write-Host ("  Auto Unlock       : {0}" -f $v.AutoUnlockEnabled)
    Write-Host ("  Key Protectors    : {0}" -f $v.KeyProtector.Count)
    foreach ($kp in$v.KeyProtector) {
        Write-Host ("    - {0,-20} (ID: {1})" -f $kp.KeyProtectorType, $kp.KeyProtectorId)
    }
    Write-Host ""

    do {
        Write-Host "  [1] Xem Recovery Key cua volume nay"
        Write-Host "  [2] Xuat Recovery Key ra file"
        Write-Host "  [3] Suspend / Resume protection volume nay"
        Write-Host "  [4] Disable BitLocker volume nay (giai ma)"
        Write-Host "  [5] Doi PIN / Password"
        Write-Host "  [6] Xoa 1 Key Protector"
        Write-Host "  [7] Them Recovery Key moi"
        Write-Host "  [0] Quay lai"
        $c = Read-Esc "Chon: "
        if ($c -eq $Global:ESC -or$c -eq "0") { return }

        switch ($c) {
            "1" { Show-RecoveryKeyWithConfirm -Volume $v | Out-Null; Pause-Return }
            "2" { Export-RecoveryKeysToFile -Volumes @($v); Pause-Return }
            "3" { Suspend-BitLockerVolumeWithConfirm -Volume $v; Pause-Return }
            "4" { Disable-BitLockerVolumeWithProgress -Volume $v; Pause-Return }
            "5" { Change-BitLockerPinOrPassword -Volume $v }
            "6" { Remove-BitLockerKeyProtectorInteractive -Volume $v }
            "7" { Add-BitLockerRecoveryKeyInteractive -Volume $v }
        }
    } while ($true)
}

function Change-BitLockerPinOrPassword {
    param($Volume)$mp = "$($Volume.MountPoint)"
    Write-Host ""
    Write-Host "  [1] Doi PIN (TPM + PIN)"
    Write-Host "  [2] Doi Password (TPM + Password)"
    Write-Host "  [0] Huy"
    $c = Read-Esc "Chon: "
    if ($c -eq "1") {
        Write-Host ""
        Write-Host "Nhap PIN moi (4-20 chu so)." -ForegroundColor Yellow
        $pin1 = Read-Esc "PIN moi: "
        if ($pin1 -eq $Global:ESC -or$pin1 -eq "") { Write-Host "Da huy."; Pause-Return; return }
        if ($pin1 -notmatch '^\d{4,20}$') { Write-Host "PIN phai la 4-20 chu so." -ForegroundColor Red; Pause-Return; return }
        $pin2 = Read-Esc "Nhap lai PIN: "
        if ($pin1 -ne$pin2) { Write-Host "PIN khong khop." -ForegroundColor Red; Pause-Return; return }

        try {
            $bde = Get-WmiObject -Namespace "root\CIMV2\Security\MicrosoftVolumeEncryption" `
                -Class Win32_EncryptableVolume -Filter "DriveLetter='$mp'"
            $res = $bde.ChangePIN(0, $pin1, $pin2)
            if ($res.ReturnValue -eq 0) {
                Write-Host "Doi PIN thanh cong." -ForegroundColor Green
                Write-Log "Doi PIN BitLocker $mp"
            } else {
                Write-Host "Loi doi PIN. Ma loi: $($res.ReturnValue)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Loi: $_" -ForegroundColor Red
        }
        Pause-Return
    } elseif ($c -eq "2") {
        Write-Host ""
        Write-Host "Nhap Password moi (8+ ky tu)." -ForegroundColor Yellow
        $pw1 = Read-Esc "Password moi: "
        if ($pw1 -eq $Global:ESC -or $pw1 -eq "") { Write-Host "Da huy."; Pause-Return; return }
        if ($pw1.Length -lt 8) { Write-Host "Password phai >= 8 ky tu." -ForegroundColor Red; Pause-Return; return }
        $pw2 = Read-Esc "Nhap lai Password: "
        if ($pw1 -ne $pw2) { Write-Host "Password khong khop." -ForegroundColor Red; Pause-Return; return }

        try {
            $bde = Get-WmiObject -Namespace "root\CIMV2\Security\MicrosoftVolumeEncryption" `
                -Class Win32_EncryptableVolume -Filter "DriveLetter='$mp'"
            $res =$bde.ChangePassphrase(0, $pw1,$pw2)
            if ($res.ReturnValue -eq 0) {
                Write-Host "Doi Password thanh cong." -ForegroundColor Green
                Write-Log "Doi Password BitLocker $mp"
            } else {
                Write-Host "Loi doi Password. Ma loi: $($res.ReturnValue)" -ForegroundColor Red
            }
        } catch {
            Write-Host "Loi: $_" -ForegroundColor Red
        }
        Pause-Return
    }
}

function Add-BitLockerRecoveryKeyInteractive {
    param($Volume)$mp = "$($Volume.MountPoint)"
    Write-Host ""
    Write-Host "Se tao Recovery Key MOI (48 chu so) cho volume $mp." -ForegroundColor Yellow
    Write-Host "Key cu KHONG bi xoa, ban co the xoa sau bang muc [6]." -ForegroundColor Gray
    $c = Read-Esc "Tiep tuc? [Y/N]: "
    if ($c.ToUpper() -ne "Y") { return }
    try {
        $newKp = Add-BitLockerKeyProtector -MountPoint$mp -RecoveryPasswordProtector -EA Stop
        Write-Host "Da them Recovery Key moi." -ForegroundColor Green
        Write-Host "Key ID: $($newKp.KeyProtectorId)" -ForegroundColor Cyan
        Write-Host "Key   : $($newKp.RecoveryPassword)" -ForegroundColor Green
        Write-Host ""
        Write-Host "Hay ghi lai key nay ngay. Co the xuat ra file bang muc [2]." -ForegroundColor Yellow
        Write-Log "Them Recovery Key cho $mp"
    } catch {
        Write-Host "Loi them key: $_" -ForegroundColor Red
    }
    Pause-Return
}

function Remove-BitLockerKeyProtectorInteractive {
    param($Volume)$mp = "$($Volume.MountPoint)"
    $kps = @($Volume.KeyProtector)
    if ($kps.Count -eq 0) { Write-Host "Khong co Key Protector." -ForegroundColor Yellow; Pause-Return; return }
    if ($kps.Count -eq 1) {
        Write-Host "CANH BAO: Chi con 1 Key Protector. Neu xoa, se khong the mo khoa o!" -ForegroundColor Red
        $c = Read-Esc "Van muon xoa? [Y/N]: "
        if ($c.ToUpper() -ne "Y") { return }
    }

    Write-Host ""
    Write-Host "  Danh sach Key Protectors:" -ForegroundColor Cyan
    $i = 1
    foreach ($kp in$kps) {
        Write-Host ("  [{0}] {1}  -  ID: {2}" -f $i,$kp.KeyProtectorType, $kp.KeyProtectorId)$i++
    }
    Write-Host ""
    $c = Read-Esc "Chon so thu tu de xoa (ESC huy): "
    if ($c -eq $Global:ESC) { return }$n = 0
    if ([int]::TryParse(($c -replace '[^\d]',''), [ref]$n) -and $n -ge 1 -and$n -le $kps.Count) {$target = $kps[$n - 1]
        Write-Host ""
        Write-Host "Se xoa Key Protector: $($target.KeyProtectorType)" -ForegroundColor Yellow
        Write-Host "ID: $($target.KeyProtectorId)" -ForegroundColor Yellow
        $c2 = Read-Esc "Xac nhan xoa? [Y/N]: "
        if ($c2.ToUpper() -ne "Y") { Write-Host "Da huy."; return }
        try {
            Remove-BitLockerKeyProtector -MountPoint $mp -KeyProtectorId$target.KeyProtectorId -EA Stop
            Write-Host "Da xoa Key Protector." -ForegroundColor Green
            Write-Log "Xoa Key Protector $($target.KeyProtectorId) tren$mp"
        } catch {
            Write-Host "Loi xoa: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Lua chon khong hop le." -ForegroundColor Red
    }
    Pause-Return
}

function Show-BitLockerKeyProtectorMenu {
    param($Volumes)
    do {
        Write-Host ""
        Write-Host "  [1] Xem danh sach Key Protectors"
        Write-Host "  [2] Them Recovery Key moi"
        Write-Host "  [3] Xoa Recovery Key cu"
        Write-Host "  [4] Doi PIN (TPM+PIN)"
        Write-Host "  [5] Doi Password (TPM+Password)"
        Write-Host "  [0] Quay lai"
        $c = Read-Esc "Chon: "
        if ($c -eq $Global:ESC -or$c -eq "0") { return }

        switch ($c) {
            "1" {
                $v = Select-BitLockerVolume$Volumes
                if ($v) {
                    Clear-Host
                    Write-Host "=== KEY PROTECTORS CUA $($v.MountPoint) ===" -ForegroundColor Cyan
                    foreach ($kp in$v.KeyProtector) {
                        Write-Host ("  - {0,-20} (ID: {1})" -f $kp.KeyProtectorType, $kp.KeyProtectorId)
                    }
                    Pause-Return
                }
            }
            "2" { $v = Select-BitLockerVolume$Volumes; if ($v) { Add-BitLockerRecoveryKeyInteractive -Volume$v } }
            "3" { $v = Select-BitLockerVolume$Volumes; if ($v) { Remove-BitLockerKeyProtectorInteractive -Volume$v } }
            "4" { $v = Select-BitLockerVolume$Volumes; if ($v) { Change-BitLockerPinOrPassword -Volume$v } }
            "5" { $v = Select-BitLockerVolume$Volumes; if ($v) { Change-BitLockerPinOrPassword -Volume$v } }
        }
    } while ($true)
}

function _Menu-BitLocker {
    Show-BitLockerMenu
}