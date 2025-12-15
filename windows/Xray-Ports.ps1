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
