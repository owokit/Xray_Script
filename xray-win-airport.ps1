param(
    # Optional: manually specify ports. If not set, random free ports will be used.
    [int]$RealityPort,
    [int]$VmessTcpPort,
    [int]$VmessKcpPort,  # UDP

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
    [string]$RealityShortId
)

#########################
# Basic helper functions
#########################

function Write-Info {
    param($msg)
    Write-Host "[INFO ] $msg" -ForegroundColor Cyan
}

function Write-Warn {
    param($msg)
    Write-Host "[WARN ] $msg" -ForegroundColor Yellow
}

function Write-Err {
    param($msg)
    Write-Host "[ERROR] $msg" -ForegroundColor Red
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
$VmessTcpPort = Ensure-Port -Port $VmessTcpPort -Protocol "TCP"
if ($VmessTcpPort -eq $RealityPort) {
    $VmessTcpPort = Ensure-Port -Port $null -Protocol "TCP"
    Write-Warn "VMess TCP port equals Reality port, changed VMess TCP port to: $VmessTcpPort"
}
$VmessKcpPort = Ensure-Port -Port $VmessKcpPort -Protocol "UDP"
if (($VmessKcpPort -eq $VmessTcpPort) -or ($VmessKcpPort -eq $RealityPort)) {
    $VmessKcpPort = Ensure-Port -Port $null -Protocol "UDP"
    Write-Warn "VMess KCP port conflicts, changed to: $VmessKcpPort"
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

$BaseDir    = "C:\xray"
$CoreBinDir = Join-Path $BaseDir "bin"
$LogDir     = Join-Path $BaseDir "log"
$ConfigPath = Join-Path $BaseDir "config.json"

$TaskName   = "XrayServer"

$CoreRepo     = "XTLS/Xray-core"
$CoreFileName = "Xray-windows-64.zip"
$CoreExeName  = "xray.exe"

$CoreZipPath  = Join-Path $BaseDir $CoreFileName
$CoreExe      = Join-Path $CoreBinDir $CoreExeName

Write-Info "Base directory: $BaseDir"
New-Item -ItemType Directory -Path $BaseDir -Force | Out-Null
New-Item -ItemType Directory -Path $CoreBinDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

#########################
# Download Xray core
#########################

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

$config = @{
    log = @{
        access   = (Join-Path $LogDir "access.log")
        error    = (Join-Path $LogDir "error.log")
        loglevel = "warning"
    }
    inbounds = @(
        # 1) VLESS + Reality (main)
        @{
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
        },
        # 2) VMess TCP (backup)
        @{
            port     = $VmessTcpPort
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
                network = "tcp"
            }
            tag = "in-vmess-tcp"
        },
        # 3) VMess mKCP + wechat-video (backup)
        @{
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
    )
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

try {
    Write-Info "Opening TCP ports: $RealityPort, $VmessTcpPort"
    $fwCmd = Get-Command -Name "New-NetFirewallRule" -ErrorAction SilentlyContinue
    if ($fwCmd) {
        New-NetFirewallRule -DisplayName "Xray_TCP_Reality_$RealityPort" `
            -Direction Inbound -Protocol TCP -LocalPort $RealityPort -Action Allow -ErrorAction SilentlyContinue | Out-Null

        New-NetFirewallRule -DisplayName "Xray_TCP_VMess_$VmessTcpPort" `
            -Direction Inbound -Protocol TCP -LocalPort $VmessTcpPort -Action Allow -ErrorAction SilentlyContinue | Out-Null
    } else {
        & netsh advfirewall firewall add rule name="Xray_TCP_Reality_$RealityPort" dir=in action=allow protocol=TCP localport=$RealityPort | Out-Null
        & netsh advfirewall firewall add rule name="Xray_TCP_VMess_$VmessTcpPort" dir=in action=allow protocol=TCP localport=$VmessTcpPort | Out-Null
    }
}
catch {
    Write-Warn "Failed to create TCP firewall rules. Please open ports $RealityPort and $VmessTcpPort manually if needed."
}

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
    Write-Warn "Failed to create UDP firewall rule. Please open UDP port $VmessKcpPort manually if needed."
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
        schtasks.exe /Delete /TN $TaskName /F | Out-Null 2>&1
    } catch {}

    $taskExe  = "C:\xray\bin\xray.exe"
    $taskArgs = "run -config C:\xray\config.json"

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
        Write-Warn "Failed to create or start scheduled task $TaskName: $($_.Exception.Message)"
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
    Write-Warn "Xray process is not detected after start. Please check C:\xray\log\error.log for details."
}

#########################
# Summary
#########################

$ip = $null

function New-VlessRealityUrl {
    param(
        [string]$Host,
        [int]$Port,
        [string]$Uuid,
        [string]$PublicKey,
        [string]$ShortId,
        [string]$ServerName,
        [string]$Dest
    )

    if (-not $Host) { return $null }

    $name = "xray.owokit.com-VLESS-Reality"
    $query = "encryption=none&flow=xtls-rprx-vision&security=reality&sni=$ServerName&fp=chrome&pbk=$PublicKey&sid=$ShortId&spx=%2F&type=tcp"
    return "vless://$Uuid@$Host:$Port?$query#$name"
}

function New-VmessUrl {
    param(
        [string]$Host,
        [int]$Port,
        [string]$Uuid,
        [string]$Network,
        [string]$HeaderType,
        [string]$Name
    )

    if (-not $Host) { return $null }

    $obj = @{
        v   = "2"
        ps  = $Name
        add = $Host
        port = "$Port"
        id  = $Uuid
        aid = "0"
        scy = "auto"
        net = $Network
        type = $HeaderType
        host = ""
        path = ""
        tls  = ""
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
if (-not $ip) { $ip = "(public IP unknown, please check yourself)" }

Write-Host ""
Write-Host "================= Xray server deployed =================" -ForegroundColor Green
Write-Host "Server public IP: $ip" -ForegroundColor Green

Write-Host ""
Write-Host "[1] VLESS Reality (main node)" -ForegroundColor Green
Write-Host "  Address: $ip"
Write-Host "  Port:    $RealityPort"
Write-Host "  UUID:    $UUID"
Write-Host "  Flow:    xtls-rprx-vision"
Write-Host "  Dest:    $RealityDest"
Write-Host "  SNI:     $RealityServerName"
Write-Host "  shortId: $RealityShortId"
Write-Host "  publicKey:"
Write-Host "    $RealityPublicKey" -ForegroundColor Yellow

$vlessUrl = New-VlessRealityUrl -Host $ip -Port $RealityPort -Uuid $UUID -PublicKey $RealityPublicKey -ShortId $RealityShortId -ServerName $RealityServerName -Dest $RealityDest
if ($vlessUrl) {
    Write-Host "  URL: " -NoNewline -ForegroundColor Cyan
    Write-Host $vlessUrl -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[2] VMess TCP (backup)" -ForegroundColor Green
Write-Host "  Address: $ip"
Write-Host "  Port:    $VmessTcpPort"
Write-Host "  UUID:    $UUID"
Write-Host "  Transport: tcp (no TLS, no WS)"

$vmessTcpUrl = New-VmessUrl -Host $ip -Port $VmessTcpPort -Uuid $UUID -Network "tcp" -HeaderType "none" -Name "xray.owokit.com-VMess-TCP"
if ($vmessTcpUrl) {
    Write-Host "  URL: " -NoNewline -ForegroundColor Cyan
    Write-Host $vmessTcpUrl -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[3] VMess mKCP + wechat-video (backup)" -ForegroundColor Green
Write-Host "  Address:   $ip"
Write-Host "  Port(UDP): $VmessKcpPort"
Write-Host "  UUID:      $UUID"
Write-Host "  Transport: kcp"
Write-Host "  Header:    wechat-video"

$vmessKcpUrl = New-VmessUrl -Host $ip -Port $VmessKcpPort -Uuid $UUID -Network "kcp" -HeaderType "wechat-video" -Name "xray.owokit.com-VMess-mKCP-wechat-video"
if ($vmessKcpUrl) {
    Write-Host "  URL: " -NoNewline -ForegroundColor Cyan
    Write-Host $vmessKcpUrl -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Config file: $ConfigPath" -ForegroundColor Yellow
Write-Host "Log dir:     $LogDir"
Write-Host "Scheduled task: $TaskName (auto start at boot as SYSTEM)" -ForegroundColor Yellow
Write-Host "========================================================"
