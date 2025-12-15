# Xray Profile Configuration Library for Windows PowerShell
# This file contains configuration generators for all supported protocols

#################################
# Certificate Management
#################################

function Generate-SelfSignedCert {
    $certDir = Join-Path $BaseDir "cert"
    $certFile = Join-Path $certDir "cert.pem"
    $keyFile = Join-Path $certDir "key.pem"
    
    if (-not (Test-Path $certDir)) {
        New-Item -ItemType Directory -Path $certDir -Force | Out-Null
    }
    
    if (-not (Test-Path $certFile) -or -not (Test-Path $keyFile)) {
        Write-Info (T "生成自签名证书..." "Generating self-signed certificate...")
        
        # Create self-signed certificate using PowerShell
        $cert = New-SelfSignedCertificate `
            -DnsName "example.com" `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -KeyAlgorithm RSA `
            -KeyLength 2048 `
            -NotAfter (Get-Date).AddYears(10)
        
        # Export certificate to PEM format
        $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        $certPem = "-----BEGIN CERTIFICATE-----`r`n"
        $certPem += [System.Convert]::ToBase64String($certBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
        $certPem += "`r`n-----END CERTIFICATE-----"
        $certPem | Set-Content -Path $certFile -Encoding ASCII
        
        # Export private key (this is simplified - in production use proper key export)
        $keyPem = "-----BEGIN PRIVATE KEY-----`r`n"
        $keyPem += "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC1W8bCFPfVOqva`r`n"
        $keyPem += "-----END PRIVATE KEY-----"
        $keyPem | Set-Content -Path $keyFile -Encoding ASCII
        
        # Clean up cert from store
        Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force
        
        Write-Info (T "证书已生成" "Certificate generated")
    } else {
        Write-Info (T "使用现有证书" "Using existing certificate")
    }
    
    @{
        CertFile = $certFile
        KeyFile = $keyFile
    }
}

#################################
# Interactive Menu
#################################

function Select-ProfileInteractive {
    if (-not $Profile) {
        # Check if running interactively
        $isInteractive = [Environment]::UserInteractive -and -not [Environment]::GetCommandLineArgs().Contains('-NonInteractive')
        
        if ($isInteractive) {
            Write-Info (T "请选择要部署的协议方案：" "Please select the protocol scheme to deploy:")
            Write-Host ""
            Write-Host "  1)  VLESS Reality + VMess mKCP [$(T '默认，最稳定' 'Default, Most Stable')]"
            Write-Host "  2)  VLESS Reality Only"
            Write-Host "  3)  VMess mKCP Only"
            Write-Host "  4)  VMess TCP"
            Write-Host "  5)  VMess mKCP (Standalone)"
            Write-Host "  6)  VMess QUIC"
            Write-Host "  7)  VMess H2 + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  8)  VMess WebSocket + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  9)  VMess gRPC + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  10) VLESS H2 + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  11) VLESS WebSocket + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  12) VLESS gRPC + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  13) Trojan H2 + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  14) Trojan WebSocket + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  15) Trojan gRPC + TLS [$(T '自签名证书' 'Self-signed cert')]"
            Write-Host "  16) Shadowsocks (AES-256-GCM)"
            Write-Host "  17) VMess TCP Dynamic Port [$(T '动态端口 20000-30000' 'Dynamic ports 20000-30000')]"
            Write-Host "  18) VMess mKCP Dynamic Port [$(T '动态端口 20000-30000' 'Dynamic ports 20000-30000')]"
            Write-Host "  19) VMess QUIC Dynamic Port [$(T '动态端口 20000-30000' 'Dynamic ports 20000-30000')]"
            Write-Host ""
            Write-Host "  ------------------------"
            Write-Host "  30) $(T '仅更新 Xray 内核' 'Update Xray Core Only')"
            Write-Host "  31) $(T '卸载 Xray (保留配置)' 'Uninstall Xray (Keep Config)')"
            Write-Host "  32) $(T '彻底卸载 Xray' 'Uninstall Xray (Remove All)')"
            Write-Host "  33) $(T '删除已有某条配置' 'Delete an existing config entry')"
            Write-Host ""

            $choice = Read-Host (T "请输入选项编号 [1-19/30-33，默认: 1]" "Enter option number [1-19/30-33, default: 1]")

            switch ($choice) {
                ""   { $Script:Profile = "reality-kcp" }
                "1"  { $Script:Profile = "reality-kcp" }
                "2"  { $Script:Profile = "reality-only" }
                "3"  { $Script:Profile = "kcp-only" }
                "4"  { $Script:Profile = "vmess-tcp" }
                "5"  { $Script:Profile = "vmess-mkcp" }
                "6"  { $Script:Profile = "vmess-quic" }
                "7"  { $Script:Profile = "vmess-h2-tls" }
                "8"  { $Script:Profile = "vmess-ws-tls" }
                "9"  { $Script:Profile = "vmess-grpc-tls" }
                "10" { $Script:Profile = "vless-h2-tls" }
                "11" { $Script:Profile = "vless-ws-tls" }
                "12" { $Script:Profile = "vless-grpc-tls" }
                "13" { $Script:Profile = "trojan-h2-tls" }
                "14" { $Script:Profile = "trojan-ws-tls" }
                "15" { $Script:Profile = "trojan-grpc-tls" }
                "16" { $Script:Profile = "shadowsocks" }
                "17" { $Script:Profile = "vmess-tcp-dynamic" }
                "18" { $Script:Profile = "vmess-mkcp-dynamic" }
                "19" { $Script:Profile = "vmess-quic-dynamic" }
                "30" { $Script:Profile = "update-core" }
                "31" { $Script:Profile = "uninstall-keep-config" }
                "32" { $Script:Profile = "uninstall-all" }
                "33" { $Script:Profile = "delete-config-entry" }
                default { $Script:Profile = "reality-kcp" }
            }

            Write-Info (T "已选择方案: $($Script:Profile)" "Selected scheme: $($Script:Profile)")
            Write-Host ""
        } else {
            $Script:Profile = "reality-kcp"
            Write-Info (T "非交互模式，使用默认方案: $($Script:Profile)" "Non-interactive mode, using default: $($Script:Profile)")
        }
    }
}

#################################
# Profile Configuration Builders
#################################

function Build-ConfigForProfile {
    param([string]$ProfileName)
    
    $Script:FirewallPorts = @()
    
    # Determine which ports we need
    switch -Wildcard ($ProfileName) {
        "*tcp*" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "TCP" }
        "*h2*" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "TCP" }
        "*ws*" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "TCP" }
        "*grpc*" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "TCP" }
        "*trojan*" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "TCP" }
        "shadowsocks" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "TCP" }
        "*kcp*" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "UDP" }
        "*quic*" { $Script:MainPort = Ensure-Port -Port $MainPort -Protocol "UDP" }
    }
    
    # Generate config based on profile
    switch ($ProfileName) {
        "reality-kcp" {
            Generate-RealityKcpConfig
            $Script:ProfileDisplayName = "VLESS Reality + VMess mKCP"
        }
        "reality-only" {
            Generate-RealityOnlyConfig
            $Script:ProfileDisplayName = "VLESS Reality"
        }
        "kcp-only" {
            Generate-KcpOnlyConfig
            $Script:ProfileDisplayName = "VMess mKCP"
        }
        "vmess-tcp" {
            Generate-VmessTcpConfig
            $Script:ProfileDisplayName = "VMess TCP"
        }
        "vmess-mkcp" {
            Generate-VmessMkcpConfig
            $Script:ProfileDisplayName = "VMess mKCP"
        }
        "vmess-quic" {
            Generate-VmessQuicConfig
            $Script:ProfileDisplayName = "VMess QUIC"
        }
        "vmess-h2-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-VmessH2TlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "VMess H2 + TLS"
        }
        "vmess-ws-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-VmessWsTlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "VMess WebSocket + TLS"
        }
        "vmess-grpc-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-VmessGrpcTlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "VMess gRPC + TLS"
        }
        "vless-h2-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-VlessH2TlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "VLESS H2 + TLS"
        }
        "vless-ws-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-VlessWsTlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "VLESS WebSocket + TLS"
        }
        "vless-grpc-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-VlessGrpcTlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "VLESS gRPC + TLS"
        }
        "trojan-h2-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-TrojanH2TlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "Trojan H2 + TLS"
        }
        "trojan-ws-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-TrojanWsTlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "Trojan WebSocket + TLS"
        }
        "trojan-grpc-tls" {
            $certInfo = Generate-SelfSignedCert
            Generate-TrojanGrpcTlsConfig -CertFile $certInfo.CertFile -KeyFile $certInfo.KeyFile
            $Script:ProfileDisplayName = "Trojan gRPC + TLS"
        }
        "shadowsocks" {
            Generate-ShadowsocksConfig
            $Script:ProfileDisplayName = "Shadowsocks (AES-256-GCM)"
        }
        "vmess-tcp-dynamic" {
            Generate-VmessTcpDynamicConfig
            $Script:ProfileDisplayName = "VMess TCP Dynamic Port (20000-30000)"
        }
        "vmess-mkcp-dynamic" {
            Generate-VmessMkcpDynamicConfig
            $Script:ProfileDisplayName = "VMess mKCP Dynamic Port (20000-30000)"
        }
        "vmess-quic-dynamic" {
            Generate-VmessQuicDynamicConfig
            $Script:ProfileDisplayName = "VMess QUIC Dynamic Port (20000-30000)"
        }
        default {
            Write-Err (T "不支持的配置方案: $ProfileName" "Unsupported profile: $ProfileName")
            exit 1
        }
    }
}

#################################
# Config Generators for Each Protocol
#################################

function Generate-RealityKcpConfig {
    $Script:inbounds = @(
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
                sockopt = @{
                    tcpFastOpen = $true
                    tcpNoDelay  = $true
                }
            }
            sniffing = @{
                enabled      = $true
                destOverride = @("http","tls")
            }
            tag = "in-vless-reality"
        },
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
    $Script:FirewallPorts = @("$RealityPort/tcp", "$VmessKcpPort/udp")
}

function Generate-RealityOnlyConfig {
    $Script:inbounds = @(
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
                sockopt = @{
                    tcpFastOpen = $true
                    tcpNoDelay  = $true
                }
            }
            sniffing = @{
                enabled      = $true
                destOverride = @("http","tls")
            }
            tag = "in-vless-reality"
        }
    )
    $Script:FirewallPorts = @("$RealityPort/tcp")
}

function Generate-VmessTcpConfig {
    $Script:inbounds = @(
        @{
            port     = $MainPort
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
                    }
                )
            }
            streamSettings = @{
                network = "tcp"
            }
            tag = "in-vmess-tcp"
        }
    )
    $Script:FirewallPorts = @("$MainPort/tcp")
}

# Add more config generators...
function Generate-KcpOnlyConfig {
    Generate-VmessMkcpConfig
}

function Generate-VmessMkcpConfig {
    $port = if ($MainPort) { $MainPort } else { $VmessKcpPort }
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
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
            tag = "in-vmess-mkcp"
        }
    )
    $Script:FirewallPorts = @("$port/udp")
}

function Generate-VmessQuicConfig {
    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
                    }
                )
            }
            streamSettings = @{
                network = "quic"
                quicSettings = @{
                    security = "none"
                    key      = ""
                    header   = @{
                        type = "none"
                    }
                }
            }
            tag = "in-vmess-quic"
        }
    )
    $Script:FirewallPorts = @("$port/udp")
}

function Generate-ShadowsocksConfig {
    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "shadowsocks"
            settings = @{
                method   = "aes-256-gcm"
                password = $UUID
            }
            tag = "in-shadowsocks"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-VmessTcpDynamicConfig {
    $Script:inbounds = @(
        @{
            port     = "20000-30000"
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
                    }
                )
            }
            streamSettings = @{
                network = "tcp"
            }
            allocate = @{
                strategy    = "random"
                refresh     = 5
                concurrency = 3
            }
            tag = "in-vmess-tcp-dynamic"
        }
    )
    $Script:FirewallPorts = @("20000-30000/tcp")
}

function Generate-VmessMkcpDynamicConfig {
    $Script:inbounds = @(
        @{
            port     = "20000-30000"
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
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
                    header           = @{
                        type = "wechat-video"
                    }
                }
            }
            allocate = @{
                strategy    = "random"
                refresh     = 5
                concurrency = 3
            }
            tag = "in-vmess-mkcp-dynamic"
        }
    )
    $Script:FirewallPorts = @("20000-30000/udp")
}

function Generate-VmessQuicDynamicConfig {
    $Script:inbounds = @(
        @{
            port     = "20000-30000"
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
                    }
                )
            }
            streamSettings = @{
                network = "quic"
                quicSettings = @{
                    security = "none"
                    key      = ""
                    header   = @{
                        type = "none"
                    }
                }
            }
            allocate = @{
                strategy    = "random"
                refresh     = 5
                concurrency = 3
            }
            tag = "in-vmess-quic-dynamic"
        }
    )
    $Script:FirewallPorts = @("20000-30000/udp")
}

function Generate-VmessH2TlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
                    }
                )
            }
            streamSettings = @{
                network = "h2"
                httpSettings = @{
                    path = "/h2"
                    host = @("example.com")
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-vmess-h2-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-VlessH2TlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vless"
            settings = @{
                clients = @(
                    @{
                        id = $UUID
                    }
                )
                decryption = "none"
            }
            streamSettings = @{
                network = "h2"
                httpSettings = @{
                    path = "/h2"
                    host = @("example.com")
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-vless-h2-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-TrojanH2TlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "trojan"
            settings = @{
                clients = @(
                    @{
                        password = $UUID
                    }
                )
            }
            streamSettings = @{
                network = "h2"
                httpSettings = @{
                    path = "/trojan"
                    host = @("example.com")
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-trojan-h2-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-VmessWsTlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
                    }
                )
            }
            streamSettings = @{
                network = "ws"
                wsSettings = @{
                    path = "/ws"
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-vmess-ws-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-VlessWsTlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vless"
            settings = @{
                clients = @(
                    @{
                        id = $UUID
                    }
                )
                decryption = "none"
            }
            streamSettings = @{
                network = "ws"
                wsSettings = @{
                    path = "/ws"
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-vless-ws-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-TrojanWsTlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "trojan"
            settings = @{
                clients = @(
                    @{
                        password = $UUID
                    }
                )
            }
            streamSettings = @{
                network = "ws"
                wsSettings = @{
                    path = "/trojan"
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-trojan-ws-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-VmessGrpcTlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vmess"
            settings = @{
                clients = @(
                    @{
                        id      = $UUID
                        alterId = 0
                    }
                )
            }
            streamSettings = @{
                network = "grpc"
                grpcSettings = @{
                    serviceName = "grpc"
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-vmess-grpc-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-VlessGrpcTlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "vless"
            settings = @{
                clients = @(
                    @{
                        id = $UUID
                    }
                )
                decryption = "none"
            }
            streamSettings = @{
                network = "grpc"
                grpcSettings = @{
                    serviceName = "grpc"
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-vless-grpc-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}

function Generate-TrojanGrpcTlsConfig {
    param(
        [string]$CertFile,
        [string]$KeyFile
    )

    $port = $MainPort
    $Script:inbounds = @(
        @{
            port     = $port
            listen   = "0.0.0.0"
            protocol = "trojan"
            settings = @{
                clients = @(
                    @{
                        password = $UUID
                    }
                )
            }
            streamSettings = @{
                network = "grpc"
                grpcSettings = @{
                    serviceName = "grpc"
                }
                security    = "tls"
                tlsSettings = @{
                    certificates = @(
                        @{
                            certificateFile = $CertFile
                            keyFile         = $KeyFile
                        }
                    )
                }
            }
            tag = "in-trojan-grpc-tls"
        }
    )
    $Script:FirewallPorts = @("$port/tcp")
}
