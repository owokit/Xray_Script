param(
    # Optional: manually specify ports. If not set, random free ports will be used.
    [ValidateRange(0,65535)]
    [int]$RealityPort = 0,
    [ValidateRange(0,65535)]
    [int]$VmessKcpPort = 0,  # UDP

    # Optional: main TCP/UDP port for non-Reality profiles (VMess/VLESS/Trojan/Shadowsocks etc.)
    [ValidateRange(0,65535)]
    [int]$MainPort = 0,

    # Optional: UUID. If not set, a random UUID will be generated and shared by all inbounds.
    [string]$UUID,

    # Optional: Xray core version, e.g. v25.9.5. If empty, will use latest.
    [string]$CoreVersion,

    # Optional: proxy for downloading Xray, e.g. http://127.0.0.1:1080 or socks5://127.0.0.1:1080
    [string]$Proxy,

    # Reality settings
    [string]$RealityDest = "cloudflare.com:443",
    [string]$RealityServerName = "cloudflare.com",
    # Reality shortId (hex, length 2~16). If empty, generate 8 hex chars.
    [string]$RealityShortId,

    [string]$Profile = "reality-kcp",

    # Base directory for installation
    [string]$BaseDir = "$( $env:SystemDrive)\xray",

    [switch]$KeepConfig,
    [switch]$ForceRebuildConfig,

    # Add new profile to existing config.json instead of overwriting
    [switch]$Add,

    [switch]$RebuildConfigOnly,
    [switch]$UninstallConfig,
    [switch]$DeleteConfig,

    # Uninstall mode: stop Xray, remove task, firewall rules and files
    [switch]$Uninstall
)

$UpdateCoreOnly = $false

$Script:XrayLang = "en"

function Initialize-Language {
    try {
        if ($env:XRAY_LANG) {
            $lang = $env:XRAY_LANG.ToLower()
            if ($lang.StartsWith("zh")) {
                $Script:XrayLang = "zh"
                return
            } else {
                $Script:XrayLang = "en"
                return
            }
        }
    } catch {
    }

    try {
        $uiLang = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($uiLang -eq "zh") {
            $Script:XrayLang = "zh"
        } else {
            $Script:XrayLang = "en"
        }
    } catch {
        $Script:XrayLang = "en"
    }
}

Initialize-Language

function T {
    param(
        [string]$zh,
        [string]$en
    )
    if ($Script:XrayLang -eq "zh") {
        return $zh
    } else {
        return $en
    }
}

#########################
# Basic helper functions
#########################

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

function Test-SafeBaseDir {
    param([string]$Path)

    if (-not $Path) {
        Write-Err "BaseDir is empty. Please specify a directory such as C:\xray."
        exit 1
    }

    try {
        $full = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        Write-Err ("BaseDir '{0}' is not a valid path: {1}" -f $Path, $_.Exception.Message)
        exit 1
    }

    if ($full -match '^[A-Za-z]:\\$') {
        Write-Err ("Refusing to use drive root '{0}' as BaseDir. Please use a subdirectory such as C:\xray." -f $full)
        exit 1
    }

    $trimmed = $full.TrimEnd('\\')
    $segments = $trimmed -split '\\'
    if ($segments.Length -gt 0) {
        $leaf = $segments[-1]
        $badNames = @("Windows","Program Files","Program Files (x86)","Users")
        foreach ($name in $badNames) {
            if ($leaf.Equals($name, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Err ("Refusing to use potentially critical system directory '{0}' as BaseDir. Please use a dedicated directory such as C:\xray." -f $full)
                exit 1
            }
        }
    }
}

#########################
# Environment checks
#########################

# Must be admin
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Please run this script as Administrator."
    exit 1
}

# Must be 64-bit Windows
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Err "This script only supports 64-bit Windows."
    exit 1
}

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Err "PowerShell 5.0 or later is required. Current version: $($PSVersionTable.PSVersion)"
    exit 1
}

$scriptDir = $null
try {
    if ($MyInvocation.MyCommand.Path) {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    }
} catch {
}
if (-not $scriptDir) {
    try {
        $scriptDir = (Get-Location).Path
    } catch {
        $scriptDir = $null
    }
}

function Import-XrayModuleIfPresent {
    param(
        [string]$RelativePath
    )

    $candidates = @()

    if ($scriptDir) {
        $candidates += (Join-Path $scriptDir $RelativePath)
    }
    if ($BaseDir) {
        $candidates += (Join-Path $BaseDir $RelativePath)
    }

    foreach ($path in $candidates) {
        if (Test-Path $path) {
            . $path
            return
        }
    }
}

Import-XrayModuleIfPresent -RelativePath "windows\Xray-Ports.ps1"
Import-XrayModuleIfPresent -RelativePath "windows\Xray-Uninstall.ps1"

$modes = @()
if ($Uninstall)        { $modes += "-Uninstall" }
if ($UninstallConfig)  { $modes += "-UninstallConfig" }
if ($DeleteConfig)     { $modes += "-DeleteConfig" }
if ($RebuildConfigOnly){ $modes += "-RebuildConfigOnly" }

if ($modes.Count -gt 1) {
    Write-Err "Multiple modes specified. Please choose only one of: -Uninstall, -UninstallConfig, -DeleteConfig, -RebuildConfigOnly."
    exit 1
}

if ($Uninstall) {
    if (Get-Command -Name Invoke-XrayUninstallAll -ErrorAction SilentlyContinue) {
        Invoke-XrayUninstallAll
        exit 0
    }

    Test-SafeBaseDir -Path $BaseDir
    Write-Info "Uninstall mode detected. Stopping Xray and cleaning up..."

    $TaskName = "XrayServer"

    try {
        $schtasksCmd = Get-Command -Name "schtasks.exe" -ErrorAction SilentlyContinue
        if ($schtasksCmd) {
            try {
                schtasks.exe /End /TN $TaskName /F > $null 2>&1
            } catch {}
            try {
                schtasks.exe /Delete /TN $TaskName /F > $null 2>&1
            } catch {}
            Write-Info "Scheduled task ${TaskName} removed (if it existed)."
        }
    }
    catch {
        Write-Warn "Failed to remove scheduled task ${TaskName}: $($_.Exception.Message)"
    }

    try {
        $xrayProc = Get-Process xray -ErrorAction SilentlyContinue
        if ($xrayProc) {
            $xrayProc | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Info "Stopped running xray processes."
        }
    }
    catch {
        Write-Warn "Failed to stop xray process: $($_.Exception.Message)"
    }

    try {
        $fwCmd = Get-Command -Name "Get-NetFirewallRule" -ErrorAction SilentlyContinue
        if ($fwCmd) {
            $patterns = @("Xray_TCP_Reality_*","Xray_TCP_VMess_*","Xray_UDP_VMessKCP_*")
            foreach ($pattern in $patterns) {
                Get-NetFirewallRule -DisplayName $pattern -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            }
            Write-Info "Firewall rules for Xray removed (if they existed)."
        } else {
            Write-Warn "Get-NetFirewallRule is not available. Please remove Xray_* firewall rules manually if needed."
        }
    }
    catch {
        Write-Warn "Failed to remove firewall rules: $($_.Exception.Message)"
    }

    try {
        if (Test-Path $BaseDir) {
            Remove-Item -Path $BaseDir -Recurse -Force
            Write-Info "Removed directory: $BaseDir"
        } else {
            Write-Info "Base directory not found: $BaseDir"
        }
    }
    catch {
        Write-Warn "Failed to remove base directory ${BaseDir}: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Xray has been uninstalled." -ForegroundColor Green
    exit 0
}

if ($UninstallConfig) {
    if (Get-Command -Name Invoke-XrayUninstallConfig -ErrorAction SilentlyContinue) {
        Invoke-XrayUninstallConfig
        exit 0
    }

    Test-SafeBaseDir -Path $BaseDir
    Write-Info "Uninstall-config mode detected. Stopping Xray and removing configuration files..."

    $TaskName = "XrayServer"

    try {
        $schtasksCmd = Get-Command -Name "schtasks.exe" -ErrorAction SilentlyContinue
        if ($schtasksCmd) {
            try {
                schtasks.exe /End /TN $TaskName /F > $null 2>&1
            } catch {}
            try {
                schtasks.exe /Delete /TN $TaskName /F > $null 2>&1
            } catch {}
            Write-Info "Scheduled task ${TaskName} removed (if it existed)."
        }
    }
    catch {
        Write-Warn "Failed to remove scheduled task ${TaskName}: $($_.Exception.Message)"
    }

    try {
        $xrayProc = Get-Process xray -ErrorAction SilentlyContinue
        if ($xrayProc) {
            $xrayProc | Stop-Process -Force -ErrorAction SilentlyContinue
            Write-Info "Stopped running xray processes."
        }
    }
    catch {
        Write-Warn "Failed to stop xray process: $($_.Exception.Message)"
    }

    try {
        $fwCmd = Get-Command -Name "Get-NetFirewallRule" -ErrorAction SilentlyContinue
        if ($fwCmd) {
            $patterns = @("Xray_TCP_Reality_*","Xray_TCP_VMess_*","Xray_UDP_VMessKCP_*")
            foreach ($pattern in $patterns) {
                Get-NetFirewallRule -DisplayName $pattern -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
            }
            Write-Info "Firewall rules for Xray removed (if they existed)."
        } else {
            Write-Warn "Get-NetFirewallRule is not available. Please remove Xray_* firewall rules manually if needed."
        }
    }
    catch {
        Write-Warn "Failed to remove firewall rules: $($_.Exception.Message)"
    }

    $ConfigPath = Join-Path $BaseDir "config.json"
    $LinksFile  = Join-Path $BaseDir "links.txt"

    try {
        if (Test-Path $ConfigPath) {
            Remove-Item -Path $ConfigPath -Force
        }
        if (Test-Path $LinksFile) {
            Remove-Item -Path $LinksFile -Force
        }
        Write-Info "Removed configuration files under $BaseDir (config.json, links.txt)."
    }
    catch {
        Write-Warn "Failed to remove configuration files under ${BaseDir}: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Xray configuration has been uninstalled on Windows. Core binaries and logs were kept." -ForegroundColor Green
    exit 0
}

if ($DeleteConfig) {
    if (Get-Command -Name Invoke-XrayDeleteConfig -ErrorAction SilentlyContinue) {
        Invoke-XrayDeleteConfig
        exit 0
    }

    Test-SafeBaseDir -Path $BaseDir
    Write-Info "Delete-config mode detected. Deleting configuration files only..."

    $ConfigPath = Join-Path $BaseDir "config.json"
    $LinksFile  = Join-Path $BaseDir "links.txt"

    try {
        if (Test-Path $ConfigPath) {
            Remove-Item -Path $ConfigPath -Force
        }
        if (Test-Path $LinksFile) {
            Remove-Item -Path $LinksFile -Force
        }
        Write-Info "Deleted configuration files (if they existed): $ConfigPath, $LinksFile"
    }
    catch {
        Write-Warn "Failed to delete configuration files under ${BaseDir}: $($_.Exception.Message)"
    }

    exit 0
}

if (-not (Get-Command -Name "Invoke-WebRequest" -ErrorAction SilentlyContinue)) {
    Write-Err "Invoke-WebRequest is not available in this PowerShell environment."
    exit 1
}

if (-not (Get-Command -Name "Invoke-RestMethod" -ErrorAction SilentlyContinue)) {
    Write-Warn "Invoke-RestMethod is not available. Public IP detection will be skipped."
}

#########################
# Port helpers
#########################

# Common ports to avoid when generating random ports
$BanPorts = @(22, 80, 81, 82, 83, 88, 110, 143, 443, 3306, 6379, 8080, 8081, 1080, 1081, 3389, 53, 25, 587, 465)

function Test-PortFree {
    param(
        [int]$Port,
        [ValidateSet("TCP","UDP")]
        [string]$Protocol
    )

    if ($Protocol -eq "TCP") {
        $cmd = Get-Command -Name "Get-NetTCPConnection" -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                $tcp = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
                return -not $tcp
            }
            catch {
            }
        }
        try {
            $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
            $listener.Start()
            $listener.Stop()
            return $true
        }
        catch {
            return $false
        }
    } else {
        $cmd = Get-Command -Name "Get-NetUDPEndpoint" -ErrorAction SilentlyContinue
        if ($cmd) {
            try {
                $udp = Get-NetUDPEndpoint -LocalPort $Port -ErrorAction SilentlyContinue
                return -not $udp
            }
            catch {
            }
        }
        try {
            $udpClient = New-Object System.Net.Sockets.UdpClient($Port)
            $udpClient.Close()
            return $true
        }
        catch {
            return $false
        }
    }
}

function Get-RandomPort {
    param(
        [ValidateSet("TCP","UDP")]
        [string]$Protocol
    )

    while ($true) {
        $p = Get-Random -Minimum 10000 -Maximum 60000
        if ($BanPorts -contains $p) { continue }
        if (Test-PortFree -Port $p -Protocol $Protocol) {
            return $p
        }
    }
}

function Ensure-Port {
    param(
        [int]$Port,
        [ValidateSet("TCP","UDP")]
        [string]$Protocol
    )

    if (-not $Port) {
        $Port = Get-RandomPort -Protocol $Protocol
        Write-Info "No $Protocol port specified, using random free port: $Port"
    } else {
        if (-not (Test-PortFree -Port $Port -Protocol $Protocol)) {
            $old = $Port
            $Port = Get-RandomPort -Protocol $Protocol
            Write-Warn "Port $old ($Protocol) is in use, changed to: $Port"
        }
    }
    return $Port
}

#########################
# UUID and shortId
#########################

if (-not $UUID) {
    $UUID = [guid]::NewGuid().ToString()
    Write-Info "No UUID specified, generated: $UUID"
}

# Assign ports and avoid collisions
$RealityPort  = Ensure-Port -Port $RealityPort  -Protocol "TCP"
$VmessKcpPort = Ensure-Port -Port $VmessKcpPort -Protocol "UDP"
if ($VmessKcpPort -eq $RealityPort) {
    $VmessKcpPort = Ensure-Port -Port $null -Protocol "UDP"
    Write-Warn "VMess KCP port conflicts with Reality port, changed to: $VmessKcpPort"
}

$Profile = $Profile.ToLowerInvariant()
$enableRealityInbound = $false
$enableVmessKcpInbound = $false

switch ($Profile) {
    "reality-kcp" {
        $enableRealityInbound = $true
        $enableVmessKcpInbound = $true
    }
    "reality-only" {
        $enableRealityInbound = $true
    }
    "kcp-only" {
        $enableVmessKcpInbound = $true
    }
    default {
        Write-Err (T ("无效的 Profile: {0}，支持: reality-kcp, reality-only, kcp-only." -f $Profile) ("Invalid profile: {0}. Supported values: reality-kcp, reality-only, kcp-only." -f $Profile))
        exit 1
    }
}

# Reality shortId
if (-not $RealityShortId) {
    $bytes = New-Object 'System.Byte[]' 4
    (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
    $RealityShortId = -join ($bytes | ForEach-Object { $_.ToString("x2") })
    Write-Info "No Reality shortId specified, generated: $RealityShortId"
}

#########################
# Directories and paths
#########################

$CoreBinDir = Join-Path $BaseDir "bin"
$LogDir     = Join-Path $BaseDir "log"
$ConfigPath = Join-Path $BaseDir "config.json"

$TaskName   = "XrayServer"

$CoreRepo     = "XTLS/Xray-core"
$CoreFileName = "Xray-windows-64.zip"
$CoreExeName  = "xray.exe"

$CoreZipPath  = Join-Path $BaseDir $CoreFileName
$CoreExe      = Join-Path $CoreBinDir $CoreExeName

Test-SafeBaseDir -Path $BaseDir

if ($RebuildConfigOnly) {
    if ($KeepConfig -or $ForceRebuildConfig) {
        Write-Err "-KeepConfig and -ForceRebuildConfig cannot be used together with -RebuildConfigOnly."
        exit 1
    }
    if (-not (Test-Path $ConfigPath)) {
        Write-Err "Config file not found at $ConfigPath. Please run this script without -RebuildConfigOnly first to perform initial installation."
        exit 1
    }
} else {
    if (Test-Path $ConfigPath) {
        if ($KeepConfig -and $ForceRebuildConfig) {
            Write-Err "Both -KeepConfig and -ForceRebuildConfig were specified. Please choose only one."
            exit 1
        } elseif ($KeepConfig) {
            $UpdateCoreOnly = $true
            Write-Info "Existing config detected at $ConfigPath. -KeepConfig is set: will only update Xray core and keep existing config, firewall rules and scheduled task."
        } elseif ($ForceRebuildConfig) {
            Write-Warn "Existing config at $ConfigPath will be overwritten because -ForceRebuildConfig is set."
        } else {
            Write-Err "Config file already exists at $ConfigPath. Use -KeepConfig to reuse it or -ForceRebuildConfig to overwrite it."
            exit 1
        }
    } else {
        if ($KeepConfig) {
            Write-Warn "-KeepConfig was specified but no existing config was found at $ConfigPath. A fresh config will be created."
        }
    }
}

Write-Info "Base directory: $BaseDir"
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $CoreBinDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

#########################
# Download Xray core
#########################

if (-not $RebuildConfigOnly) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    }
    catch {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }

    if ($CoreVersion) {
        $CoreVersionNorm = "v" + $CoreVersion.TrimStart("v")
        $coreUrl = "https://github.com/$CoreRepo/releases/download/$CoreVersionNorm/$CoreFileName"
        Write-Info "Using Xray version: $CoreVersionNorm"
    } else {
        $coreUrl = "https://github.com/$CoreRepo/releases/latest/download/$CoreFileName"
        Write-Info "Using latest Xray from $CoreRepo"
    }

    Write-Info "Downloading Xray from: $coreUrl"

    try {
        $invokeParams = @{
            Uri     = $coreUrl
            OutFile = $CoreZipPath
            UseBasicParsing = $true
        }
        if ($Proxy) {
            Write-Info "Using proxy for download: $Proxy"
            $invokeParams["Proxy"] = $Proxy
        }
        Invoke-WebRequest @invokeParams
    }
    catch {
        Write-Err "Failed to download Xray core: $($_.Exception.Message)"
        exit 1
    }

    Write-Info "Extracting Xray to $CoreBinDir"

    try {
        if (Test-Path $CoreBinDir) {
            Get-ChildItem $CoreBinDir | Remove-Item -Force -Recurse
        }
        $expandArchiveCmd = Get-Command -Name "Expand-Archive" -ErrorAction SilentlyContinue
        if ($expandArchiveCmd) {
            Expand-Archive -Path $CoreZipPath -DestinationPath $CoreBinDir -Force
        } else {
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            [System.IO.Compression.ZipFile]::ExtractToDirectory($CoreZipPath, $CoreBinDir)
        }
    }
    catch {
        Write-Err "Failed to extract Xray: $($_.Exception.Message)"
        exit 1
    }

    if (-not (Test-Path $CoreExe)) {
        Write-Err "xray.exe not found after extraction."
        exit 1
    }

    if ($UpdateCoreOnly) {
        Write-Info "Core update-only mode: existing config at $ConfigPath was kept. Firewall rules and scheduled task were not modified."
        Write-Info "To apply the new core, please restart the existing scheduled task or service. For example, reboot the system or run: schtasks.exe /Run /TN $TaskName"
        exit 0
    }
} else {
    if (-not (Test-Path $CoreExe)) {
        Write-Err "xray.exe not found: $CoreExe. Please run this script without -RebuildConfigOnly first to install Xray core."
        exit 1
    }
}

#########################
# Generate Reality keys
#########################

Write-Info "Generating Reality X25519 key pair (xray x25519)..."
try {
    $x25519Output = & $CoreExe x25519 2>&1
}
catch {
    Write-Err "Failed to run 'xray x25519': $($_.Exception.Message)"
    exit 1
}

# 1) Try old-style output:
#    Private key: xxx
#    Public key:  yyy
$privMatch = [regex]::Match($x25519Output, 'Private key:\s*([0-9A-Za-z_\-]+)')
$pubMatch  = [regex]::Match($x25519Output, 'Public key:\s*([0-9A-Za-z_\-]+)')

# 2) If not matched, try new-style output:
#    PrivateKey: xxx
#    Password:   yyy  (Password is actually the public key)
if (-not $privMatch.Success -or -not $pubMatch.Success) {
    $privMatch = [regex]::Match($x25519Output, 'PrivateKey:\s*([0-9A-Za-z_\-]+)')
    $pubMatch  = [regex]::Match($x25519Output, 'Password:\s*([0-9A-Za-z_\-]+)')
}

if (-not $privMatch.Success -or -not $pubMatch.Success) {
    Write-Err "Could not parse Reality keys from 'xray x25519' output."
    Write-Host $x25519Output
    exit 1
}

$RealityPrivateKey = $privMatch.Groups[1].Value
$RealityPublicKey  = $pubMatch.Groups[1].Value

Write-Info "Reality keys generated."

#########################
# Build config.json
#########################

Write-Info "Building config: $ConfigPath"

$inbounds = @()

if ($enableRealityInbound) {
    # 1) VLESS + Reality (main)
    $inbounds += @{
        port     = $RealityPort
        listen   = "0.0.0.0"
        protocol = "vless"
        settings = @{
            clients = @(
                @{
                    id   = $UUID
                    flow = "xtls-rprx-vision"
                }
            )
            decryption = "none"
        }
        streamSettings = @{
            network  = "tcp"
            security = "reality"
            realitySettings = @{
                show        = $false
                dest        = $RealityDest
                xver        = 0
                serverNames = @($RealityServerName)
                privateKey  = $RealityPrivateKey
                shortIds    = @($RealityShortId)
            }
        }
        sniffing = @{
            enabled      = $true
            destOverride = @("http","tls")
        }
        tag = "in-vless-reality"
    }
}

if ($enableVmessKcpInbound) {
    # 2) VMess mKCP + wechat-video (fallback)
    $inbounds += @{
        port     = $VmessKcpPort
        listen   = "0.0.0.0"
        protocol = "vmess"
        settings = @{
            clients = @(
                @{
                    id      = $UUID
                    alterId = 0
                    level   = 0
                }
            )
        }
        streamSettings = @{
            network = "kcp"
            kcpSettings = @{
                mtu              = 1350
                tti              = 20
                uplinkCapacity   = 5
                downlinkCapacity = 20
                congestion       = $false
                readBufferSize   = 2
                writeBufferSize  = 2
                header = @{
                    type = "wechat-video"
                }
            }
        }
        tag = "in-vmess-kcp-wechatvideo"
    }
}

$config = @{
    log = @{
        access   = (Join-Path $LogDir "access.log")
        error    = (Join-Path $LogDir "error.log")
        loglevel = "warning"
    }
    inbounds = $inbounds
    outbounds = @(
        @{
            protocol = "freedom"
            settings = @{}
            tag      = "direct"
        },
        @{
            protocol = "blackhole"
            settings = @{}
            tag      = "blocked"
        }
    )
    routing = @{
        domainStrategy = "AsIs"
        rules          = @()
    }
}

# Write config as UTF-8 without BOM (important for Xray)
$cfgJson = $config | ConvertTo-Json -Depth 10
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ConfigPath, $cfgJson, $utf8NoBom)

#########################
# Firewall rules
#########################

if ($enableRealityInbound) {
    try {
        Write-Info "Opening TCP port: $RealityPort"
        $fwCmd = Get-Command -Name "New-NetFirewallRule" -ErrorAction SilentlyContinue
        if ($fwCmd) {
            New-NetFirewallRule -DisplayName "Xray_TCP_Reality_$RealityPort" `
                -Direction Inbound -Protocol TCP -LocalPort $RealityPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
        } else {
            & netsh advfirewall firewall add rule name="Xray_TCP_Reality_$RealityPort" dir=in action=allow protocol=TCP localport=$RealityPort | Out-Null
        }
    }
    catch {
        Write-Warn "Failed to create TCP firewall rule for port ${RealityPort}: $($_.Exception.Message). Please open this port manually if needed."
    }
}

if ($enableVmessKcpInbound) {
    try {
        Write-Info "Opening UDP port: $VmessKcpPort"
        $fwCmd = Get-Command -Name "New-NetFirewallRule" -ErrorAction SilentlyContinue
        if ($fwCmd) {
            New-NetFirewallRule -DisplayName "Xray_UDP_VMessKCP_$VmessKcpPort" `
                -Direction Inbound -Protocol UDP -LocalPort $VmessKcpPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
        } else {
            & netsh advfirewall firewall add rule name="Xray_UDP_VMessKCP_$VmessKcpPort" dir=in action=allow protocol=UDP localport=$VmessKcpPort | Out-Null
        }
    }
    catch {
        Write-Warn "Failed to create UDP firewall rule for port ${VmessKcpPort}: $($_.Exception.Message). Please open this port manually if needed."
    }
}

#########################
# Scheduled task (auto start)
#########################

Write-Info "Configuring scheduled task: $TaskName"

try {
    $schtasksCmd = Get-Command -Name "schtasks.exe" -ErrorAction Stop
}
catch {
    $schtasksCmd = $null
    Write-Warn "schtasks.exe not found. Skipping scheduled task creation. Xray will be started directly in the current session."
}

if ($schtasksCmd) {
    try {
        schtasks.exe /Delete /TN $TaskName /F > $null 2>&1
    } catch {}

    $taskExe  = $CoreExe
    $taskArgs = "run -config `"$ConfigPath`""

    $createArgs = @(
        '/Create',
        '/TN', $TaskName,
        '/TR', "`"$taskExe`" $taskArgs",
        '/SC', 'ONSTART',
        '/RU', 'SYSTEM'
    )

    try {
        schtasks.exe @createArgs | Out-Null
        Write-Info "Scheduled task $TaskName created (run at system startup as SYSTEM)."
        schtasks.exe /Run /TN $TaskName | Out-Null
        Start-Sleep -Seconds 2
    }
    catch {
        Write-Warn "Failed to create or start scheduled task ${TaskName}: $($_.Exception.Message)"
    }
}

if (-not $schtasksCmd) {
    try {
        Start-Process -FilePath $CoreExe -ArgumentList "run -config `"$ConfigPath`"" -WindowStyle Hidden
        Start-Sleep -Seconds 2
        Write-Warn "Xray was started directly without a scheduled task. It will stop when the process is terminated or the system reboots."
    }
    catch {
        Write-Err "Failed to start xray.exe directly: $($_.Exception.Message)"
    }
}

$xrayProc = Get-Process xray -ErrorAction SilentlyContinue
if ($xrayProc) {
    Write-Info "Xray process is running (PID: $($xrayProc.Id))."
} else {
    Write-Warn "Xray process is not detected after start. Please check $LogDir\error.log for details."
}

#########################
# Summary
#########################

$ip = $null

function New-VlessRealityUrl {
    param(
        [string]$Address,
        [int]$Port,
        [string]$Uuid,
        [string]$PublicKey,
        [string]$ShortId,
        [string]$ServerName,
        [string]$Dest
    )

    if (-not $Address) { return $null }

    $name = "xray.owokit.com-VLESS-Reality"
    $query = "encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ServerName&fp=chrome&pbk=$PublicKey&sid=$ShortId&spx=%2F&type=tcp"
    return "vless://${Uuid}@${Address}:${Port}?${query}#${name}"
}

function New-VmessUrl {
    param(
        [string]$Address,
        [int]$Port,
        [string]$Uuid,
        [string]$Network,
        [string]$HeaderType,
        [string]$Name
    )

    if (-not $Address) { return $null }

    $obj = @{
        v    = "2"
        ps   = $Name
        add  = $Address
        port = "$Port"
        id   = $Uuid
        aid  = "0"
        scy  = "auto"
        net  = $Network
        type = $HeaderType
        host = ""
        path = ""
        tls  = ""
        sni  = ""
        alpn = ""
        fp   = ""
    }

    try {
        $json = $obj | ConvertTo-Json -Depth 5 -Compress
    }
    catch {
        $json = $obj | ConvertTo-Json -Depth 5
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $b64 = [System.Convert]::ToBase64String($bytes)
    return "vmess://$b64"
}

try {
    $ip = (Invoke-RestMethod -Uri "https://api.ipify.org?format=json" -ErrorAction Stop).ip
}
catch {
    $ip = $null
}
if (-not $ip) { $ip = T "（公网 IP 未知，请自行检查）" "(public IP unknown, please check yourself)" }

Write-Host ""
Write-Host (T "================= Xray 服务器部署完成 =================" "================= Xray server deployed =================") -ForegroundColor Cyan
Write-Host (T ("服务器公网 IP: {0}" -f $ip) ("Server public IP: {0}" -f $ip)) -ForegroundColor Cyan

$vlessUrl = $null
$vmessKcpUrl = $null

if ($enableRealityInbound) {
    Write-Host ""
    Write-Host (T "[1] VLESS Reality（主节点）" "[1] VLESS Reality (main node)") -ForegroundColor Green
    Write-Host ("  {0,-11} {1}" -f (T "地址:" "Address:"), $ip) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f (T "端口:" "Port:"), $RealityPort) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f "UUID:", $UUID) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f (T "流控:" "Flow:"), "xtls-rprx-vision") -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f (T "目标站:" "Dest:"), $RealityDest) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f "SNI:", $RealityServerName) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f "shortId:", $RealityShortId) -ForegroundColor Gray
    Write-Host ("  {0,-11}" -f (T "公钥:" "publicKey:")) -ForegroundColor Gray
    Write-Host "    $RealityPublicKey" -ForegroundColor Magenta

    $vlessUrl = New-VlessRealityUrl -Address $ip -Port $RealityPort -Uuid $UUID -PublicKey $RealityPublicKey -ShortId $RealityShortId -ServerName $RealityServerName -Dest $RealityDest
    if ($vlessUrl) {
        Write-Host (T "  订阅链接: " "  URL: ") -NoNewline -ForegroundColor Cyan
        Write-Host $vlessUrl -ForegroundColor Yellow
    }
}

if ($enableVmessKcpInbound) {
    Write-Host ""
    Write-Host (T "[2] VMess mKCP + wechat-video（备用，仅在 TCP/Reality 不可用时尝试；注意部分运营商/网络可能限制 UDP）" "[2] VMess mKCP + wechat-video (backup, only try when TCP/Reality is not available; UDP may be limited by ISP/QoS)") -ForegroundColor Green
    Write-Host ("  {0,-11} {1}" -f (T "地址:" "Address:"), $ip) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f (T "端口(UDP):" "Port(UDP):"), $VmessKcpPort) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f "UUID:", $UUID) -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f (T "传输:" "Transport:"), "kcp") -ForegroundColor Gray
    Write-Host ("  {0,-11} {1}" -f (T "伪装头:" "Header:"), "wechat-video") -ForegroundColor Gray

    $vmessKcpUrl = New-VmessUrl -Address $ip -Port $VmessKcpPort -Uuid $UUID -Network "kcp" -HeaderType "wechat-video" -Name "xray.owokit.com-VMess-mKCP-wechat-video"
    if ($vmessKcpUrl) {
        Write-Host (T "  订阅链接: " "  URL: ") -NoNewline -ForegroundColor Cyan
        Write-Host $vmessKcpUrl -ForegroundColor Yellow
    }
}

$linksFile = Join-Path $BaseDir "links.txt"
try {
    $links = @()
    if ($vlessUrl)    { $links += $vlessUrl }
    if ($vmessKcpUrl) { $links += $vmessKcpUrl }
    if ($links.Count -gt 0) {
        $links | Set-Content -Path $linksFile -Encoding UTF8
        Write-Host (T "所有链接已保存到: $linksFile" "All URLs have been saved to: $linksFile") -ForegroundColor Green
    }
}
catch {
    Write-Warn (T "保存链接到文件失败: $($_.Exception.Message)" "Failed to save URLs to file: $($_.Exception.Message)")
}

Write-Host ""
Write-Host (T "提示：复制订阅链接时请确保一整行完整复制，不要包含换行符。" "Tip: When copying the URLs in plain text, make sure there are no line breaks and that the full link stays on a single line.") -ForegroundColor Red
Write-Host ""
Write-Host (T "配置文件: $ConfigPath" "Config file: $ConfigPath") -ForegroundColor Gray
Write-Host (T "日志目录: $LogDir" "Log dir:     $LogDir") -ForegroundColor Gray
Write-Host (T "计划任务: $TaskName（开机自动以 SYSTEM 运行）" "Scheduled task: $TaskName (auto start at boot as SYSTEM)") -ForegroundColor Gray
Write-Host (T "========================================================" "========================================================") -ForegroundColor Cyan
