# ============================================================
#  SOFTWARE.PS1 - Module 5: Phan mem
#  Duoc dot-source boi ToolkitCore.ps1 khi nguoi dung chon muc 5
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

function _Menu-Software {
    Show-Menu -Title "5. SOFTWARE / PHAN MEM" -NavEntry "5" -Options ([ordered]@{

        # ===== NHOM A: DUYET WEB & LIEN LAC =====
        "__HEADER__A" = @{ Label = "A. Duyet web & Lien lac" }
        "1"  = @{ Label = "Google Chrome";           Action = { Open-Site "Google Chrome" "https://www.google.com/chrome/" } }
        "2"  = @{ Label = "Coc Coc";                 Action = { Open-Site "Coc Coc" "https://coccoc.com/download" } }
        "3"  = @{ Label = "Zalo PC";                 Action = { Open-Site "Zalo PC" "https://zalo.me/pc" } }
        "4"  = @{ Label = "Zoom";                    Action = { Open-Site "Zoom" "https://zoom.us/download" } }
        "5"  = @{ Label = "Telegram";                Action = { Open-Site "Telegram" "https://telegram.org/dl/desktop/win" } }
        "6"  = @{ Label = "WeChat PC";               Action = { Open-Site "WeChat" "https://www.wechat.com/en/" } }
        "7"  = @{ Label = "KakaoTalk PC";            Action = { Open-Site "KakaoTalk" "https://www.kakaocorp.com/page/service/all?lang=ENG" } }

        # ===== NHOM B: VAN PHONG - OFFICE =====
        "__SEP__B"    = @{ Label = "" }
        "__HEADER__B" = @{ Label = "B. Van phong - Office" }
        "8"  = @{ Label = "Office 365";              Action = { Open-Site "Office 365" "https://www.microsoft.com/en-us/microsoft-365/try" } }
        "9"  = @{ Label = "WPS Office";              Action = { Open-Site "WPS Office" "https://www.wps.com/download/" } }
        "10" = @{ Label = "LibreOffice";             Action = { Open-Site "LibreOffice" "https://www.libreoffice.org/download/download/" } }
        "11" = @{ Label = "Foxit PDF Reader";        Action = { Open-Site "Foxit PDF Reader" "https://www.foxit.com/pdf-reader/" } }
        "12" = @{ Label = "PDFgear (Edit PDF)";      Action = { Open-Site "PDFgear" "https://pdfgear.com/pdfgear-for-windows/" } }
        "13" = @{ Label = "Unikey";                  Action = { Open-Site "Unikey" "https://www.unikey.org/download.html" } }
        "14" = @{ Label = "Cai dat font chu Viet Nam (1398)"; Action = { Run-FontViet } }
        "15" = @{ Label = "EVKey";   Action = { Open-Site "EVKey" "https://evkeyvn.com" } }

        # ===== NHOM C: DA PHUONG TIEN =====
        "__SEP__C"    = @{ Label = "" }
        "__HEADER__C" = @{ Label = "C. Da phuong tien" }
        "16" = @{ Label = "VLC Player";              Action = { Open-Site "VLC" "https://www.videolan.org/vlc/download-windows.html" } }
        "17" = @{ Label = "CapCut";                  Action = { Open-Site "CapCut" "https://www.capcut.com/tools/pc-video-editor" } }
        "18" = @{ Label = "OBS Studio";              Action = { Open-Site "OBS Studio" "https://obsproject.com/download" } }
        "19" = @{ Label = "ImageGlass";              Action = { Open-Site "ImageGlass" "https://imageglass.org/" } }
        "20" = @{ Label = "Fliqlo Screensaver";      Action = { Open-Site "Fliqlo Screensaver" "https://fliqlo.com/screensaver/" } }
        "21" = @{ Label = "Bing Wallpaper";          Action = { Open-Site "Bing Wallpaper" "https://www.microsoft.com/en-us/bing/bing-wallpaper" } }

        # ===== NHOM D: TIEN ICH HE THONG =====
        "__SEP__D"    = @{ Label = "" }
        "__HEADER__D" = @{ Label = "D. Tien ich he thong" }
        "22" = @{ Label = "WinRAR";                  Action = { Open-Site "WinRAR" "https://www.rarlab.com/download.htm" } }
        "23" = @{ Label = "AnyDesk";                 Action = { Open-Site "AnyDesk" "https://anydesk.com/en/downloads/windows" } }
        "24" = @{ Label = "UltraViewer";             Action = { Open-Site "UltraViewer" "https://www.ultraviewer.net/en/download.html" } }
        "25" = @{ Label = "Crystal Disk Info";       Action = { Open-Site "Crystal Disk Info" "https://crystalmark.info/en/download/" } }
        "26" = @{ Label = "MiniTool Partition Wizard"; Action = { Open-Site "MiniTool Partition Wizard" "https://www.partitionwizard.com/free-partition-manager.html" } }
        "27" = @{ Label = "Recoverit";               Action = { Open-Site "Recoverit" "https://recoverit.wondershare.com/" } }
        "28" = @{ Label = "Double Driver";           Action = { Open-Site "Double Driver" "https://download.com.vn/double-driver-25157" } }
        "29" = @{ Label = "Go phan mem (HiBit)"; Action = { Open-Site "HiBit Uninstaller" "https://www.hibitsoft.ir/Uninstaller.html" } }
        "30" = @{ Label = "Don file rac BleachBit";  Action = { Open-Site "BleachBit" "https://www.bleachbit.org/download" } }

        # ===== NHOM E: PHAN MEM KHAC =====
        "__SEP__E"    = @{ Label = "" }
        "__HEADER__E" = @{ Label = "E. Phan mem khac" }
        "99" = @{ Label = "Office AIO / AutoCAD / WinToHDD"; Action = { Menu-OtherSoftware } }
    })
}

# ============================================================
# MAIN MENU
# ============================================================