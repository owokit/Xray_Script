function Invoke-XrayUninstallAll {
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
}

function Invoke-XrayUninstallConfig {
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
}

function Invoke-XrayDeleteConfig {
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
}
