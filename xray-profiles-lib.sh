#!/usr/bin/env bash

# Xray Profile Configuration Library
# This file contains configuration generators for all supported protocols

#################################
# Certificate Management
#################################

generate_self_signed_cert() {
  local cert_dir="${BASE_DIR}/cert"
  local cert_file="${cert_dir}/cert.pem"
  local key_file="${cert_dir}/key.pem"
  local mode="${TLS_CERT_MODE:-self-signed}"

  mkdir -p "$cert_dir"

  # In custom / letsencrypt modes, we expect cert.pem/key.pem to already exist
  if [[ "$mode" == "custom" || "$mode" == "letsencrypt" ]]; then
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
      log_error "$(t "已选择使用自有/CA 证书模式，但未在 ${cert_dir} 中找到 cert.pem/key.pem" "Custom/CA certificate mode selected, but cert.pem/key.pem not found in ${cert_dir}")"
      exit 1
    fi
    if [[ "$mode" == "letsencrypt" ]]; then
      log_info "$(t "使用 Let’s Encrypt 颁发的证书" "Using Let\'s Encrypt certificate")"
    else
      log_info "$(t "使用自定义 CA 证书" "Using existing CA certificate")"
    fi
  else
    # Default: generate a self-signed certificate
    if [[ ! -f "$cert_file" || ! -f "$key_file" ]]; then
      log_info "$(t "生成自签名证书..." "Generating self-signed certificate...")"
      local cn="${TLS_DOMAIN:-example.com}"
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$key_file" -out "$cert_file" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${cn}" \
        2>/dev/null || {
          log_error "$(t "生成证书失败" "Failed to generate certificate")"
          exit 1
        }
      chmod 600 "$key_file" "$cert_file"
      log_info "$(t "证书已生成" "Certificate generated")"
    else
      log_info "$(t "使用现有证书" "Using existing certificate")"
    fi
  fi

  CERT_FILE="$cert_file"
  KEY_FILE="$key_file"
}

#################################
# Interactive Menu
#################################

select_profile_interactive() {
  local input_file="/dev/stdin"
  local interactive_mode="false"

  if [[ -t 0 ]]; then
    interactive_mode="true"
  elif [[ -e /dev/tty ]]; then
    interactive_mode="true"
    input_file="/dev/tty"
  fi

  if [[ -z "$PROFILE" && "$interactive_mode" == "true" ]]; then
    log_info "$(t "请选择要部署的协议方案：" "Please select the protocol scheme to deploy:")"
    echo ""
    echo "  1)  VLESS Reality + VMess mKCP [$(t "默认，最稳定" "Default, Most Stable")]"
    echo "  2)  VLESS Reality Only"
    echo "  3)  VMess mKCP Only"
    echo "  4)  VMess TCP"
    echo "  5)  VMess mKCP (Standalone)"
    echo "  6)  VMess QUIC"
    echo "  7)  VMess H2 + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  8)  VMess WebSocket + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  9)  VMess gRPC + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  10) VLESS H2 + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  11) VLESS WebSocket + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  12) VLESS gRPC + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  13) Trojan H2 + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  14) Trojan WebSocket + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  15) Trojan gRPC + TLS [$(t "自签名证书" "Self-signed cert")]"
    echo "  16) Shadowsocks (AES-256-GCM)"
    echo "  17) VMess TCP Dynamic Port [$(t "动态端口 20000-30000" "Dynamic ports 20000-30000")]"
    echo "  18) VMess mKCP Dynamic Port [$(t "动态端口 20000-30000" "Dynamic ports 20000-30000")]"
    echo "  19) VMess QUIC Dynamic Port [$(t "动态端口 20000-30000" "Dynamic ports 20000-30000")]"
    echo ""
    echo "  ------------------------"
    echo "  30) $(t "仅更新 Xray 内核" "Update Xray Core Only")"
    echo "  31) $(t "卸载 Xray (保留配置)" "Uninstall Xray (Keep Config)")"
    echo "  32) $(t "彻底卸载 Xray" "Uninstall Xray (Remove All)")"
    echo "  33) $(t "删除已有某条配置" "Delete an existing config entry")"
    echo ""
    printf "$(t "请输入选项编号 [1-19/30-33，默认: 1]: " "Enter option number [1-19/30-33, default: 1]: ")"
    read -r choice < "$input_file"
    
    case "${choice:-1}" in
      1)  PROFILE="reality-kcp" ;;
      2)  PROFILE="reality-only" ;;
      3)  PROFILE="kcp-only" ;;
      4)  PROFILE="vmess-tcp" ;;
      5)  PROFILE="vmess-mkcp" ;;
      6)  PROFILE="vmess-quic" ;;
      7)  PROFILE="vmess-h2-tls" ;;
      8)  PROFILE="vmess-ws-tls" ;;
      9)  PROFILE="vmess-grpc-tls" ;;
      10) PROFILE="vless-h2-tls" ;;
      11) PROFILE="vless-ws-tls" ;;
      12) PROFILE="vless-grpc-tls" ;;
      13) PROFILE="trojan-h2-tls" ;;
      14) PROFILE="trojan-ws-tls" ;;
      15) PROFILE="trojan-grpc-tls" ;;
      16) PROFILE="shadowsocks" ;;
      17) PROFILE="vmess-tcp-dynamic" ;;
      18) PROFILE="vmess-mkcp-dynamic" ;;
      19) PROFILE="vmess-quic-dynamic" ;;
      30) PROFILE="update-core" ;;
      31) PROFILE="uninstall-keep-config" ;;
      32) PROFILE="uninstall-all" ;;
      33) PROFILE="delete-config-entry" ;;
      *)  PROFILE="reality-kcp" ;;
    esac
    
    log_info "$(t "已选择方案: $PROFILE" "Selected scheme: $PROFILE")"
    echo ""
  elif [[ -z "$PROFILE" ]]; then
    PROFILE="reality-kcp"
    log_info "$(t "非交互模式，使用默认方案: $PROFILE" "Non-interactive mode, using default: $PROFILE")"
  fi
}

#################################
# Profile Configuration Builders
#################################

# Build inbounds configuration based on profile
build_config_for_profile() {
  local profile="$1"
  local main_port tcp_port udp_port
  
  # Determine which ports we need
  case "$profile" in
    *tcp*|*h2*|*ws*|*grpc*|*trojan*|shadowsocks)
      tcp_port="$(ensure_port "${MAIN_PORT:-0}" tcp)"
      MAIN_PORT="$tcp_port"
      ;;
    *kcp*|*quic*)
      udp_port="$(ensure_port "${MAIN_PORT:-0}" udp)"
      MAIN_PORT="$udp_port"
      ;;
    reality*)
      tcp_port="$(ensure_port "${REALITY_PORT:-0}" tcp)"
      REALITY_PORT="$tcp_port"
      if [[ "$profile" == "reality-kcp" ]]; then
        udp_port="$(ensure_port "${VMESS_KCP_PORT:-0}" udp)"
        VMESS_KCP_PORT="$udp_port"
      fi
      ;;
  esac
  
  # Generate config based on profile
  case "$profile" in
    reality-kcp)
      generate_reality_kcp_config
      ;;
    reality-only)
      generate_reality_only_config
      ;;
    kcp-only)
      generate_kcp_only_config
      ;;
    vmess-tcp)
      generate_vmess_tcp_config "$tcp_port"
      ;;
    vmess-mkcp)
      generate_vmess_mkcp_config "$udp_port"
      ;;
    vmess-quic)
      generate_vmess_quic_config "$udp_port"
      ;;
    vmess-h2-tls)
      generate_self_signed_cert
      generate_vmess_h2_tls_config "$tcp_port"
      ;;
    vmess-ws-tls)
      generate_self_signed_cert
      generate_vmess_ws_tls_config "$tcp_port"
      ;;
    vmess-grpc-tls)
      generate_self_signed_cert
      generate_vmess_grpc_tls_config "$tcp_port"
      ;;
    vless-h2-tls)
      generate_self_signed_cert
      generate_vless_h2_tls_config "$tcp_port"
      ;;
    vless-ws-tls)
      generate_self_signed_cert
      generate_vless_ws_tls_config "$tcp_port"
      ;;
    vless-grpc-tls)
      generate_self_signed_cert
      generate_vless_grpc_tls_config "$tcp_port"
      ;;
    trojan-h2-tls)
      generate_self_signed_cert
      generate_trojan_h2_tls_config "$tcp_port"
      ;;
    trojan-ws-tls)
      generate_self_signed_cert
      generate_trojan_ws_tls_config "$tcp_port"
      ;;
    trojan-grpc-tls)
      generate_self_signed_cert
      generate_trojan_grpc_tls_config "$tcp_port"
      ;;
    shadowsocks)
      generate_shadowsocks_config "$tcp_port"
      ;;
    vmess-tcp-dynamic)
      generate_vmess_tcp_dynamic_config
      ;;
    vmess-mkcp-dynamic)
      generate_vmess_mkcp_dynamic_config
      ;;
    vmess-quic-dynamic)
      generate_vmess_quic_dynamic_config
      ;;
    *)
      log_error "$(t "不支持的配置方案: $profile" "Unsupported profile: $profile")"
      exit 1
      ;;
  esac
}

#################################
# Config Generators for Each Protocol
#################################

generate_reality_kcp_config() {
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${REALITY_PORT},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": ["${REALITY_SERVER_NAME}"],
          "privateKey": "${reality_priv}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "in-vless-reality-${UUID}"
    },
    {
      "port": ${VMESS_KCP_PORT},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "level": 0
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 20,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "wechat-video"
          }
        }
      },
      "tag": "in-vmess-kcp-wechatvideo"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${REALITY_PORT}/tcp ${VMESS_KCP_PORT}/udp"
  PROFILE_DISPLAY_NAME="VLESS Reality + VMess mKCP"
}

generate_reality_only_config() {
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${REALITY_PORT},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": ["${REALITY_SERVER_NAME}"],
          "privateKey": "${reality_priv}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "tag": "in-vless-reality-${UUID}"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${REALITY_PORT}/tcp"
  PROFILE_DISPLAY_NAME="VLESS Reality"
}

generate_vmess_tcp_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0,
            "level": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      },
      "tag": "in-vmess-tcp"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="VMess TCP"
}

generate_vmess_ws_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ws"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-vmess-ws-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="VMess WebSocket + TLS"
}

generate_vless_ws_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/ws"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-vless-ws-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="VLESS WebSocket + TLS"
}

generate_trojan_ws_tls_config() {
  local port="$1"
  # Trojan uses password, we'll use UUID as password
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "${UUID}"
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/trojan"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-trojan-ws-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="Trojan WebSocket + TLS"
}

generate_shadowsocks_config() {
  local port="$1"
  # Use UUID as password for Shadowsocks
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-256-gcm",
        "password": "${UUID}"
      },
      "tag": "in-shadowsocks"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="Shadowsocks (AES-256-GCM)"
}

generate_vmess_tcp_dynamic_config() {
  # Dynamic port configuration
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": "20000-30000",
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      },
      "allocate": {
        "strategy": "random",
        "refresh": 5,
        "concurrency": 3
      },
      "tag": "in-vmess-tcp-dynamic"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="20000-30000/tcp"
  PROFILE_DISPLAY_NAME="VMess TCP Dynamic Port (20000-30000)"
}

# H2 + TLS Configs
generate_vmess_h2_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "h2",
        "httpSettings": {
          "path": "/h2",
          "host": ["example.com"]
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-vmess-h2-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="VMess H2 + TLS"
}

generate_vless_h2_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "h2",
        "httpSettings": {
          "path": "/h2",
          "host": ["example.com"]
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-vless-h2-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="VLESS H2 + TLS"
}

generate_trojan_h2_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "${UUID}"
          }
        ]
      },
      "streamSettings": {
        "network": "h2",
        "httpSettings": {
          "path": "/trojan",
          "host": ["example.com"]
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-trojan-h2-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="Trojan H2 + TLS"
}

# gRPC + TLS Configs
generate_vmess_grpc_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "grpc"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-vmess-grpc-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="VMess gRPC + TLS"
}

generate_vless_grpc_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "grpc"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-vless-grpc-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="VLESS gRPC + TLS"
}

generate_trojan_grpc_tls_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "${UUID}"
          }
        ]
      },
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {
          "serviceName": "grpc"
        },
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "${CERT_FILE}",
              "keyFile": "${KEY_FILE}"
            }
          ]
        }
      },
      "tag": "in-trojan-grpc-tls"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/tcp"
  PROFILE_DISPLAY_NAME="Trojan gRPC + TLS"
}

# Dynamic Port Configs
generate_vmess_mkcp_dynamic_config() {
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": "20000-30000",
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 20,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "wechat-video"
          }
        }
      },
      "allocate": {
        "strategy": "random",
        "refresh": 5,
        "concurrency": 3
      },
      "tag": "in-vmess-mkcp-dynamic"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="20000-30000/udp"
  PROFILE_DISPLAY_NAME="VMess mKCP Dynamic Port (20000-30000)"
}

generate_vmess_quic_dynamic_config() {
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": "20000-30000",
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "quic",
        "quicSettings": {
          "security": "none",
          "key": "",
          "header": {
            "type": "none"
          }
        }
      },
      "allocate": {
        "strategy": "random",
        "refresh": 5,
        "concurrency": 3
      },
      "tag": "in-vmess-quic-dynamic"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="20000-30000/udp"
  PROFILE_DISPLAY_NAME="VMess QUIC Dynamic Port (20000-30000)"
}
generate_kcp_only_config() {
  generate_vmess_mkcp_config "${VMESS_KCP_PORT}"
}

generate_vmess_mkcp_config() {
  local port="${1:-$MAIN_PORT}"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "kcp",
        "kcpSettings": {
          "mtu": 1350,
          "tti": 20,
          "uplinkCapacity": 5,
          "downlinkCapacity": 20,
          "congestion": false,
          "readBufferSize": 2,
          "writeBufferSize": 2,
          "header": {
            "type": "wechat-video"
          }
        }
      },
      "tag": "in-vmess-mkcp"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/udp"
  PROFILE_DISPLAY_NAME="VMess mKCP"
}

generate_vmess_quic_config() {
  local port="$1"
  cat >"$CONFIG_PATH" <<EOF
{
  "log": {
    "access": "${LOG_DIR}/access.log",
    "error": "${LOG_DIR}/error.log",
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": ${port},
      "listen": "0.0.0.0",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "quic",
        "quicSettings": {
          "security": "none",
          "key": "",
          "header": {
            "type": "none"
          }
        }
      },
      "tag": "in-vmess-quic"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF
  FIREWALL_PORTS="${port}/udp"
  PROFILE_DISPLAY_NAME="VMess QUIC"
}

# Export functions for main script
export -f generate_self_signed_cert
export -f select_profile_interactive
export -f build_config_for_profile
