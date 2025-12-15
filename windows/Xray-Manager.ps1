# Xray Configuration Manager for Windows
# Usage: Run this script in PowerShell (Administrator) to manage Xray configurations

param(
    [string]$BaseDir = "$($env:SystemDrive)\xray"
)

$Script:XrayLang = "en"

function Initialize-Language {
    try {
        if ($env:XRAY_LANG) {
            $lang = $env:XRAY_LANG.ToLower()
            if ($lang.StartsWith("zh")) {
                $Script:XrayLang = "zh"
                return
            }
        }
        $uiLang = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($uiLang -eq "zh") {
            $Script:XrayLang = "zh"
        }
    } catch {}
}

Initialize-Language

function T {
    param([string]$zh, [string]$en)
    if ($Script:XrayLang -eq "zh") { return $zh } else { return $en }
}

function Write-Info {
    param($msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [INFO ] $msg" -ForegroundColor Cyan
}

function Write-Warn {
    param($msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [WARN ] $msg" -ForegroundColor Yellow
}

function Write-Err {
    param($msg)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$ts] [ERROR] $msg" -ForegroundColor Red
}

$ConfigPath = Join-Path $BaseDir "config.json"
$LinksFile = Join-Path $BaseDir "links.txt"
$TaskName = "XrayServer"

function Show-Menu {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  $(T 'Xray 配置管理' 'Xray Configuration Manager')" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host (T "【配置方案 1-19】" "[Profiles 1-19]") -ForegroundColor Green
    Write-Host "  1)  VLESS Reality + VMess mKCP [$(T '默认，最稳定' 'Default, Most Stable')]"
    Write-Host "  2)  VLESS Reality Only"
    Write-Host "  3)  VMess mKCP Only"
    Write-Host "  4)  VMess TCP"
    Write-Host "  5)  VMess mKCP (Standalone)"
    Write-Host "  6)  VMess QUIC"
    Write-Host "  7)  VMess H2 + TLS"
    Write-Host "  8)  VMess WebSocket + TLS"
    Write-Host "  9)  VMess gRPC + TLS"
    Write-Host "  10) VLESS H2 + TLS"
    Write-Host "  11) VLESS WebSocket + TLS"
    Write-Host "  12) VLESS gRPC + TLS"
    Write-Host "  13) Trojan H2 + TLS"
    Write-Host "  14) Trojan WebSocket + TLS"
    Write-Host "  15) Trojan gRPC + TLS"
    Write-Host "  16) Shadowsocks (AES-256-GCM)"
    Write-Host "  17) VMess TCP Dynamic Port"
    Write-Host "  18) VMess mKCP Dynamic Port"
    Write-Host "  19) VMess QUIC Dynamic Port"
    Write-Host ""
    Write-Host (T "【查看信息 101-102】" "[View Info 101-102]") -ForegroundColor Green
    Write-Host "  101) $(T '查看连接链接' 'View connection URLs')"
    Write-Host "  102) $(T '查看当前配置' 'View current configuration')"
    Write-Host ""
    Write-Host (T "【服务管理 201-203】" "[Service Management 201-203]") -ForegroundColor Green
    Write-Host "  201) $(T '查看服务状态' 'View service status')"
    Write-Host "  202) $(T '重启 Xray 服务' 'Restart Xray service')"
    Write-Host "  203) $(T '更新 Xray 内核' 'Update Xray core')"
    Write-Host ""
    Write-Host (T "【卸载选项 301-302】" "[Uninstall Options 301-302]") -ForegroundColor Green
    Write-Host "  301) $(T '卸载 Xray (保留配置)' 'Uninstall Xray (keep config)')"
    Write-Host "  302) $(T '彻底卸载 Xray' 'Uninstall Xray (remove all)')"
    Write-Host ""
    Write-Host "  0) $(T '退出' 'Exit')"
    Write-Host ""
    Write-Host (T "请选择操作: " "Select an option: ") -NoNewline
}

function Check-Installed {
    if (-not (Test-Path $BaseDir)) {
        Write-Err (T "Xray 未安装。请先运行安装脚本。" "Xray is not installed. Please run the installation script first.")
        exit 1
    }
}

function View-Config {
    if (Test-Path $ConfigPath) {
        Write-Host ""
        Write-Info (T "当前配置文件: $ConfigPath" "Current config file: $ConfigPath")
        Write-Host ""
        Get-Content $ConfigPath | Write-Host
    } else {
        Write-Warn (T "配置文件不存在" "Config file does not exist")
    }
}

function View-Links {
    if (Test-Path $LinksFile) {
        Write-Host ""
        Write-Info (T "连接链接:" "Connection URLs:")
        Write-Host ""
        Get-Content $LinksFile | Write-Host
        Write-Host ""
    } else {
        Write-Warn (T "链接文件不存在" "Links file does not exist")
    }
}

function Restart-XrayService {
    Write-Info (T "重启 Xray 服务..." "Restarting Xray service...")
    try {
        schtasks.exe /End /TN $TaskName /F 2>$null
        Start-Sleep -Seconds 1
        schtasks.exe /Run /TN $TaskName
        Start-Sleep -Seconds 2
        $proc = Get-Process xray -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Info (T "Xray 进程正在运行 (PID: $($proc.Id))" "Xray process is running (PID: $($proc.Id))")
        } else {
            Write-Warn (T "Xray 进程未运行" "Xray process is not running")
        }
    } catch {
        Write-Err (T "重启失败: $($_.Exception.Message)" "Restart failed: $($_.Exception.Message)")
    }
}

function View-Status {
    Write-Info (T "Xray 服务状态:" "Xray service status:")
    $proc = Get-Process xray -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host (T "  Xray 进程正在运行 (PID: $($proc.Id))" "  Xray process is running (PID: $($proc.Id))") -ForegroundColor Green
    } else {
        Write-Host (T "  Xray 进程未运行" "  Xray process is not running") -ForegroundColor Yellow
    }
    
    try {
        $task = schtasks.exe /Query /TN $TaskName /FO CSV 2>$null | ConvertFrom-Csv
        if ($task) {
            Write-Host (T "  计划任务: $TaskName 已配置" "  Scheduled task: $TaskName is configured") -ForegroundColor Green
        }
    } catch {}
}

function Update-Core {
    Write-Info (T "更新 Xray 内核..." "Updating Xray core...")
    $scriptUrl = "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1"
    try {
        $script = Invoke-WebRequest -Uri $scriptUrl -UseBasicParsing
        Invoke-Expression "$($script.Content) -KeepConfig"
    } catch {
        Write-Err (T "下载脚本失败: $($_.Exception.Message)" "Failed to download script: $($_.Exception.Message)")
    }
}

function Uninstall-KeepConfig {
    $scriptUrl = "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1"
    try {
        $script = Invoke-WebRequest -Uri $scriptUrl -UseBasicParsing
        Invoke-Expression "$($script.Content) -UninstallConfig"
    } catch {
        Write-Err (T "下载脚本失败: $($_.Exception.Message)" "Failed to download script: $($_.Exception.Message)")
    }
}

function Uninstall-All {
    $scriptUrl = "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1"
    try {
        $script = Invoke-WebRequest -Uri $scriptUrl -UseBasicParsing
        Invoke-Expression "$($script.Content) -Uninstall"
    } catch {
        Write-Err (T "下载脚本失败: $($_.Exception.Message)" "Failed to download script: $($_.Exception.Message)")
    }
}

function Add-ProfileDirect {
    param([string]$ProfileName)
    
    Write-Info (T "选择方案: $ProfileName" "Selected profile: $ProfileName")
    
    $scriptUrl = "https://github.com/owokit/Xray_Script/raw/main/xray-win-airport.ps1"
    try {
        $script = Invoke-WebRequest -Uri $scriptUrl -UseBasicParsing
        Invoke-Expression "$($script.Content) -Profile $ProfileName -Add"
    } catch {
        Write-Err (T "下载脚本失败: $($_.Exception.Message)" "Failed to download script: $($_.Exception.Message)")
    }
}

# Main loop
Check-Installed

while ($true) {
    Show-Menu
    $choice = Read-Host
    
    switch ($choice) {
        # Profiles 1-19
        "1"  { Add-ProfileDirect "reality-kcp" }
        "2"  { Add-ProfileDirect "reality-only" }
        "3"  { Add-ProfileDirect "kcp-only" }
        "4"  { Add-ProfileDirect "vmess-tcp" }
        "5"  { Add-ProfileDirect "vmess-mkcp" }
        "6"  { Add-ProfileDirect "vmess-quic" }
        "7"  { Add-ProfileDirect "vmess-h2-tls" }
        "8"  { Add-ProfileDirect "vmess-ws-tls" }
        "9"  { Add-ProfileDirect "vmess-grpc-tls" }
        "10" { Add-ProfileDirect "vless-h2-tls" }
        "11" { Add-ProfileDirect "vless-ws-tls" }
        "12" { Add-ProfileDirect "vless-grpc-tls" }
        "13" { Add-ProfileDirect "trojan-h2-tls" }
        "14" { Add-ProfileDirect "trojan-ws-tls" }
        "15" { Add-ProfileDirect "trojan-grpc-tls" }
        "16" { Add-ProfileDirect "shadowsocks" }
        "17" { Add-ProfileDirect "vmess-tcp-dynamic" }
        "18" { Add-ProfileDirect "vmess-mkcp-dynamic" }
        "19" { Add-ProfileDirect "vmess-quic-dynamic" }
        # View Info 101-102
        "101" { View-Links }
        "102" { View-Config }
        # Service Management 201-203
        "201" { View-Status }
        "202" { Restart-XrayService }
        "203" { Update-Core }
        # Uninstall Options 301-302
        "301" { Uninstall-KeepConfig; break }
        "302" { Uninstall-All; break }
        # Exit
        "0" { Write-Host (T "再见!" "Goodbye!"); break }
        default { Write-Warn (T "无效选项" "Invalid option") }
    }
}
