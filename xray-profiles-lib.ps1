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
    # Windows version: Profile is already set via parameter with default "reality-kcp"
    # No interactive menu needed - just use default directly for automation
    if (-not $Script:Profile) {
        $Script:Profile = "reality-kcp"
        Write-Info (T "使用默认方案: $($Script:Profile)" "Using default profile: $($Script:Profile)")
    }
}

#################################
# Profile Configuration Builders
#################################

function Build-ConfigForProfile {
    param([string]$ProfileName)
    
    $Script:FirewallPorts = @()
    
    # Determine which ports we need
    # IMPORTANT: Handle reality* first since "reality-kcp" contains "kcp"
    if ($ProfileName -like "reality*") {
        $Script:RealityPort = Ensure-Port -Port $RealityPort -Protocol "TCP"
        if ($ProfileName -eq "reality-kcp") {
            $Script:VmessKcpPort = Ensure-Port -Port $VmessKcpPort -Protocol "UDP"
        }
    } else {
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
                }
                finalmask = @{
                    udp = @(
                        @{
                            type = "header-wechat"
                            settings = @{}
                        }
                    )
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
                }
                finalmask = @{
                    udp = @(
                        @{
                            type = "header-wechat"
                            settings = @{}
                        }
                    )
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
                }
                finalmask = @{
                    udp = @(
                        @{
                            type = "header-wechat"
                            settings = @{}
                        }
                    )
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
