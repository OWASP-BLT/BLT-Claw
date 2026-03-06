# BLT-Claw

> Set up an [OpenClaw](https://github.com/openclaw/openclaw) AI assistant bot on your own VPS,
> connected to the OWASP BLT Slack workspace as a helper.

[![OWASP BLT](https://img.shields.io/badge/OWASP-BLT-E10101?style=for-the-badge)](https://blt.owasp.org)
[![OpenClaw](https://img.shields.io/badge/Powered%20by-OpenClaw-E10101?style=for-the-badge)](https://github.com/openclaw/openclaw)

**[🌐 Homepage](https://owasp-blt.github.io/BLT-Claw/) · [📖 OpenClaw Docs](https://docs.openclaw.ai) · [🤖 OpenClaw Repo](https://github.com/openclaw/openclaw)**

---

## Overview

BLT-Claw provides a turnkey setup for running OpenClaw — a personal, self-hosted AI assistant — as a
production-grade systemd daemon on a Linux VPS, preconfigured for the OWASP BLT Slack workspace.

What's included:

| File | Purpose |
|---|---|
| [`setup.sh`](setup.sh) | One-command interactive installer for Ubuntu/Debian/Rocky |
| [`ansible/setup.yml`](ansible/setup.yml) | Ansible playbook for automated / repeatable deploys |
| [`ansible/roles/openclaw/`](ansible/roles/openclaw/) | Ansible role (Node.js, user, config, systemd) |
| [`ansible/inventory.yml`](ansible/inventory.yml) | Example inventory — edit with your VPS IP |
| [`ansible/group_vars/all/vars.yml`](ansible/group_vars/all/vars.yml) | All tunable defaults |
| [`docs/index.html`](docs/index.html) | GitHub Pages homepage |

---

## Quick Start (setup.sh)

### Prerequisites

- A fresh VPS running Ubuntu 22.04+, Debian 12+, or Rocky/AlmaLinux 9+
- Root or `sudo` access
- A [Slack app](https://api.slack.com/apps) with **Socket Mode** enabled (see below)
- An AI model API key (e.g. OpenAI `sk-…`)

### Create a Slack App

1. Go to <https://api.slack.com/apps> → **Create New App** → *From scratch*
2. Enable **Socket Mode** (under *Settings → Socket Mode*) and note your **App-Level Token** (`xapp-…`)
3. Under *Features → OAuth & Permissions → Bot Token Scopes*, add:
   - `app_mentions:read`, `channels:history`, `chat:write`, `im:history`, `im:read`, `im:write`
4. Install the app to your workspace and note your **Bot Token** (`xoxb-…`)

### Run the installer

```bash
# RECOMMENDED — download, review, then run
curl -fsSL https://raw.githubusercontent.com/OWASP-BLT/BLT-Claw/main/setup.sh -o setup.sh
less setup.sh   # review before running!
sudo bash setup.sh

# Alternative — clone and run
git clone https://github.com/OWASP-BLT/BLT-Claw.git
cd BLT-Claw
sudo bash setup.sh
```

The script will prompt for your tokens if they are not already set as environment variables.
To pre-set them:

```bash
export OPENCLAW_SLACK_BOT_TOKEN="xoxb-your-bot-token"
export OPENCLAW_SLACK_APP_TOKEN="xapp-your-app-token"
export OPENCLAW_MODEL_API_KEY="sk-your-openai-key"
export OPENCLAW_MODEL_PROVIDER="openai"   # default
export OPENCLAW_MODEL_NAME="gpt-4o"       # default

sudo -E bash setup.sh
```

---

## Ansible Deployment

For infrastructure-as-code or multi-server deployments:

```bash
# 1. Install Ansible + the community.general collection
pip install ansible
ansible-galaxy collection install community.general

# 2. Edit ansible/inventory.yml with your VPS IP

# 3. Run the playbook
ansible-playbook -i ansible/inventory.yml ansible/setup.yml \
  --extra-vars "openclaw_slack_bot_token=xoxb-... \
                openclaw_slack_app_token=xapp-... \
                openclaw_model_api_key=sk-..."
```

For production, store secrets in an [ansible-vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
encrypted file instead of passing them on the command line.

---

## Operations

| Task | Command |
|---|---|
| Check service status | `systemctl status openclaw` |
| Follow live logs | `journalctl -u openclaw -f` |
| Restart the gateway | `systemctl restart openclaw` |
| Run health check | `openclaw doctor` |
| Approve DM pairing code | `openclaw pairing approve slack <CODE>` |
| Update OpenClaw | `npm install -g openclaw@latest && systemctl restart openclaw` |
| View config | `cat /opt/openclaw/home/.openclaw/config.json` |
| Send a test message | `openclaw agent --message "ping"` |

---

## Configuration

The config file is written to `/opt/openclaw/home/.openclaw/config.json` (mode `0600`,
owned by the `openclaw` system user). Edit it and restart the service.

```json
{
  "gateway": {
    "port": 18789,
    "host": "127.0.0.1"
  },
  "models": [
    {
      "provider": "openai",
      "name": "gpt-4o",
      "apiKey": "sk-…"
    }
  ],
  "channels": {
    "slack": {
      "enabled": true,
      "botToken": "xoxb-…",
      "appToken": "xapp-…",
      "dmPolicy": "pairing",
      "allowFrom": []
    }
  }
}
```

### DM pairing policy

| `dmPolicy` | Behaviour |
|---|---|
| `"pairing"` *(default)* | Unknown senders get a code; run `openclaw pairing approve slack <CODE>` to allow |
| `"open"` | Any Slack user can DM the bot (also add `"*"` to `allowFrom`) |

---

## Security

- The daemon runs as a dedicated `openclaw` system user with no login shell
- systemd hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`
- Config file permissions: `0600` (only readable by the `openclaw` user)
- DM pairing is enabled by default — unknown senders cannot interact without explicit approval
- Run `openclaw doctor` to surface any risky configuration


