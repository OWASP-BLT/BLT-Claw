#!/usr/bin/env bash
# =============================================================================
# BLT-Claw: OpenClaw VPS Setup Script
# =============================================================================
# Sets up an OpenClaw AI assistant bot on a fresh VPS, configured to connect
# to your Slack workspace as a helper bot.
#
# Usage:
#   RECOMMENDED — download, review, then run:
#     curl -fsSL https://raw.githubusercontent.com/OWASP-BLT/BLT-Claw/main/setup.sh -o setup.sh
#     less setup.sh   # review before running!
#     sudo bash setup.sh
#   # — or — clone the repo and inspect locally:
#   git clone https://github.com/OWASP-BLT/BLT-Claw.git && cd BLT-Claw && sudo bash setup.sh
#
#   NOTE: Never pipe an unknown script directly to bash without reviewing it first.
#
# Environment variables (all optional — you will be prompted if not set):
#   OPENCLAW_SLACK_BOT_TOKEN   Slack bot token  (xoxb-...)
#   OPENCLAW_SLACK_APP_TOKEN   Slack app-level token (xapp-...)
#   OPENCLAW_MODEL_API_KEY     OpenAI / Anthropic / etc. API key
#   OPENCLAW_MODEL_PROVIDER    Provider name, e.g. "openai" (default: openai)
#   OPENCLAW_MODEL_NAME        Model name, e.g. "gpt-4o"  (default: gpt-4o)
#   OPENCLAW_INSTALL_DIR       Install prefix (default: /opt/openclaw)
#   OPENCLAW_USER              System user to run the daemon (default: openclaw)
#   SKIP_NODE_INSTALL          Set to "1" to skip Node.js installation
#
# Supported OS: Ubuntu 22.04+, Debian 12+, Rocky Linux 9+, AlmaLinux 9+
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Colours & helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }

banner() {
cat <<'EOF'
 ____  _   _____         _____ _
| __ )| |_|_   _|       / ____| |
|  _ \| |   | |  ____  | |    | | __ ___      __
| |_) | |   | | |____| | |    | |/ _` \ \ /\ / /
|____/|_|   |_|         \____|_|\__,_|__/\_/  

  OpenClaw VPS Setup  —  OWASP BLT-Claw
EOF
echo ""
}

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-0}"
    else
        error "Cannot detect OS — /etc/os-release not found."
    fi
    info "Detected OS: ${OS_ID} ${OS_VERSION}"
}

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
install_prerequisites() {
    info "Installing system prerequisites…"

    case "${OS_ID}" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq curl git unzip jq lsof
            ;;
        rhel|centos|rocky|almalinux|fedora)
            dnf install -y curl git unzip jq lsof
            ;;
        *)
            warn "Unknown OS '${OS_ID}'. Attempting to continue without package installs."
            ;;
    esac

    success "Prerequisites installed."
}

# ---------------------------------------------------------------------------
# Node.js ≥22  (via NodeSource)
# ---------------------------------------------------------------------------
NODE_REQUIRED=22

install_nodejs() {
    if [[ "${SKIP_NODE_INSTALL:-0}" == "1" ]]; then
        info "Skipping Node.js install (SKIP_NODE_INSTALL=1)."
        return
    fi

    if command -v node &>/dev/null; then
        NODE_VER=$(node --version | sed 's/v//' | cut -d. -f1)
        if (( NODE_VER >= NODE_REQUIRED )); then
            success "Node.js $(node --version) already installed — skipping."
            return
        fi
        warn "Node.js $(node --version) is < v${NODE_REQUIRED}. Upgrading…"
    fi

    info "Installing Node.js v${NODE_REQUIRED} via NodeSource…"

    case "${OS_ID}" in
        ubuntu|debian)
            curl -fsSL "https://deb.nodesource.com/setup_${NODE_REQUIRED}.x" | bash -
            apt-get install -y -qq nodejs
            ;;
        rhel|centos|rocky|almalinux|fedora)
            curl -fsSL "https://rpm.nodesource.com/setup_${NODE_REQUIRED}.x" | bash -
            dnf install -y nodejs
            ;;
        *)
            error "Unsupported OS for automatic Node.js install. Install Node ≥${NODE_REQUIRED} manually."
            ;;
    esac

    success "Node.js $(node --version) installed."
}

# ---------------------------------------------------------------------------
# Dedicated system user
# ---------------------------------------------------------------------------
OPENCLAW_USER="${OPENCLAW_USER:-openclaw}"
OPENCLAW_INSTALL_DIR="${OPENCLAW_INSTALL_DIR:-/opt/openclaw}"
OPENCLAW_HOME="${OPENCLAW_INSTALL_DIR}/home"
OPENCLAW_CONFIG_DIR="${OPENCLAW_HOME}/.openclaw"

create_system_user() {
    if id "${OPENCLAW_USER}" &>/dev/null; then
        info "System user '${OPENCLAW_USER}' already exists — skipping."
    else
        info "Creating system user '${OPENCLAW_USER}'…"
        useradd --system \
                --home-dir "${OPENCLAW_HOME}" \
                --create-home \
                --shell /usr/sbin/nologin \
                --comment "OpenClaw daemon" \
                "${OPENCLAW_USER}"
        success "User '${OPENCLAW_USER}' created."
    fi

    mkdir -p "${OPENCLAW_CONFIG_DIR}"
    chown -R "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_INSTALL_DIR}"
}

# ---------------------------------------------------------------------------
# OpenClaw installation
# ---------------------------------------------------------------------------
install_openclaw() {
    info "Installing openclaw@latest globally…"
    npm install -g openclaw@latest --prefer-dedupe
    success "OpenClaw $(openclaw --version 2>/dev/null || echo 'installed') ready."
}

# ---------------------------------------------------------------------------
# Credentials prompt
# ---------------------------------------------------------------------------
prompt_if_empty() {
    local var_name="$1"
    local prompt_text="$2"
    local secret="${3:-false}"

    if [[ -z "${!var_name:-}" ]]; then
        if [[ "${secret}" == "true" ]]; then
            read -rsp "${BOLD}${prompt_text}${RESET}: " "${var_name}"
            echo ""
        else
            read -rp  "${BOLD}${prompt_text}${RESET}: " "${var_name}"
        fi
        export "${var_name?}"
    fi
}

collect_credentials() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD} Configuration${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo "  Slack bot token   → Slack app dashboard > OAuth & Permissions (xoxb-…)"
    echo "  Slack app token   → Slack app dashboard > Basic Information > App-Level Tokens (xapp-…)"
    echo "  API key           → Your AI provider dashboard (e.g. platform.openai.com)"
    echo ""

    OPENCLAW_MODEL_PROVIDER="${OPENCLAW_MODEL_PROVIDER:-openai}"
    OPENCLAW_MODEL_NAME="${OPENCLAW_MODEL_NAME:-gpt-4o}"

    prompt_if_empty OPENCLAW_SLACK_BOT_TOKEN "Slack Bot Token (xoxb-…)" true
    prompt_if_empty OPENCLAW_SLACK_APP_TOKEN "Slack App Token (xapp-…)" true
    prompt_if_empty OPENCLAW_MODEL_API_KEY   "AI Model API Key" true

    read -rp "${BOLD}Model provider [${OPENCLAW_MODEL_PROVIDER}]${RESET}: " _provider
    OPENCLAW_MODEL_PROVIDER="${_provider:-${OPENCLAW_MODEL_PROVIDER}}"

    read -rp "${BOLD}Model name [${OPENCLAW_MODEL_NAME}]${RESET}: " _model
    OPENCLAW_MODEL_NAME="${_model:-${OPENCLAW_MODEL_NAME}}"
}

# ---------------------------------------------------------------------------
# Write openclaw config
# ---------------------------------------------------------------------------
write_config() {
    info "Writing OpenClaw configuration to ${OPENCLAW_CONFIG_DIR}/config.json…"

    mkdir -p "${OPENCLAW_CONFIG_DIR}"

    cat > "${OPENCLAW_CONFIG_DIR}/config.json" <<JSONEOF
{
  "gateway": {
    "port": 18789,
    "host": "127.0.0.1"
  },
  "models": [
    {
      "provider": "${OPENCLAW_MODEL_PROVIDER}",
      "name": "${OPENCLAW_MODEL_NAME}",
      "apiKey": "${OPENCLAW_MODEL_API_KEY}"
    }
  ],
  "channels": {
    "slack": {
      "enabled": true,
      "botToken": "${OPENCLAW_SLACK_BOT_TOKEN}",
      "appToken": "${OPENCLAW_SLACK_APP_TOKEN}",
      "dmPolicy": "pairing",
      "allowFrom": []
    }
  }
}
JSONEOF

    chmod 600 "${OPENCLAW_CONFIG_DIR}/config.json"
    chown "${OPENCLAW_USER}:${OPENCLAW_USER}" "${OPENCLAW_CONFIG_DIR}/config.json"
    success "Config written."
}

# ---------------------------------------------------------------------------
# systemd service
# ---------------------------------------------------------------------------
OPENCLAW_SERVICE="openclaw"

write_systemd_service() {
    info "Creating systemd service '${OPENCLAW_SERVICE}'…"

    OPENCLAW_BIN="$(command -v openclaw)"

    cat > "/etc/systemd/system/${OPENCLAW_SERVICE}.service" <<SVCEOF
[Unit]
Description=OpenClaw AI Gateway
Documentation=https://docs.openclaw.ai
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${OPENCLAW_USER}
Group=${OPENCLAW_USER}
WorkingDirectory=${OPENCLAW_HOME}
Environment="HOME=${OPENCLAW_HOME}"
ExecStart=${OPENCLAW_BIN} gateway --port 18789
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${OPENCLAW_SERVICE}

# Hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${OPENCLAW_INSTALL_DIR}

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    systemctl enable "${OPENCLAW_SERVICE}"
    success "systemd service '${OPENCLAW_SERVICE}' enabled."
}

# ---------------------------------------------------------------------------
# Start & verify
# ---------------------------------------------------------------------------
start_service() {
    info "Starting OpenClaw gateway…"
    systemctl restart "${OPENCLAW_SERVICE}"

    # Wait up to 15 seconds for the gateway to be ready
    local attempts=0
    while (( attempts < 15 )); do
        if curl -sf "http://127.0.0.1:18789/health" &>/dev/null; then
            success "OpenClaw gateway is up on port 18789."
            return
        fi
        sleep 1
        (( attempts++ ))
    done

    warn "Gateway did not respond on /health within 15s. Check: journalctl -u ${OPENCLAW_SERVICE}"
}

# ---------------------------------------------------------------------------
# Print summary
# ---------------------------------------------------------------------------
print_summary() {
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${BOLD}${GREEN} Setup complete!${RESET}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    echo -e "  Service:     ${CYAN}systemctl status ${OPENCLAW_SERVICE}${RESET}"
    echo -e "  Logs:        ${CYAN}journalctl -u ${OPENCLAW_SERVICE} -f${RESET}"
    echo -e "  Config:      ${CYAN}${OPENCLAW_CONFIG_DIR}/config.json${RESET}"
    echo -e "  Gateway:     ${CYAN}http://127.0.0.1:18789${RESET}"
    echo ""
    echo -e "  Approve a DM pairing code:"
    echo -e "    ${CYAN}openclaw pairing approve slack <CODE>${RESET}"
    echo ""
    echo -e "  Run health check:"
    echo -e "    ${CYAN}openclaw doctor${RESET}"
    echo ""
    echo -e "  Docs:        ${CYAN}https://docs.openclaw.ai${RESET}"
    echo -e "  Project:     ${CYAN}https://github.com/OWASP-BLT/BLT-Claw${RESET}"
    echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    banner

    # Must run as root
    if [[ $EUID -ne 0 ]]; then
        error "Please run this script as root (or with sudo)."
    fi

    detect_os
    install_prerequisites
    install_nodejs
    create_system_user
    install_openclaw
    collect_credentials
    write_config
    write_systemd_service
    start_service
    print_summary
}

main "$@"
