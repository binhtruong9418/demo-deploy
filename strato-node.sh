#!/bin/bash
# Strato Node Setup Script - One-command node installation
# Usage: curl -sSL https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/strato-node.sh | bash -s -- [client_id] [client_password]
set -e

# Default configuration
DEFAULT_DOWNLOAD_URL="https://github.com/binhtruong9418/merkle-node/releases/latest/download/agent-node-ubuntu-20.04"

# Parse arguments or use environment variables with defaults
CLIENT_ID="${1:-${CLIENT_ID}}"
CLIENT_PASSWORD="${2:-${CLIENT_PASSWORD}}"
DOWNLOAD_URL="${3:-${DOWNLOAD_URL:-$DEFAULT_DOWNLOAD_URL}}"

# Enhanced logging
log() {
    echo -e "\033[32m[$(date '+%H:%M:%S')] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m" >&2
    exit 1
}

# Validate required parameters
[[ -n "$CLIENT_ID" ]] || error "Client ID is required. Usage: bash script.sh [client_id] [client_password]"
[[ -n "$CLIENT_PASSWORD" ]] || error "Client password is required. Usage: bash script.sh [client_id] [client_password]"

log "Installing Strato Node (ID: $CLIENT_ID)"

# Create setup directory
SETUP_DIR="/opt/strato-node"
log "Creating setup directory: $SETUP_DIR"
mkdir -p "$SETUP_DIR"

# Download node binary
log "Downloading strato-agent from: $DOWNLOAD_URL"
cd "$SETUP_DIR" || exit
if ! curl -fsSL -o strato-agent "$DOWNLOAD_URL"; then
    error "Failed to download strato-agent from: $DOWNLOAD_URL"
fi
chmod +x strato-agent

# Create config file
log "Creating configuration file"
cat > config.toml <<EOF
host = "127.0.0.1"
port = 8379
storage_path = "strato_data"
engine = "rwlock"
sync_interval_seconds = 30

[replication]
enabled = true
mqtt_broker = "emqx.decenter.ai"
mqtt_port = 1883
topic_prefix = "strato_kv"
client_id = "$CLIENT_ID"
client_password = "$CLIENT_PASSWORD"
EOF

# Create systemd service
log "Creating systemd service"
sudo tee /etc/systemd/system/strato-node.service > /dev/null <<EOF
[Unit]
Description=Strato Node Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=$SETUP_DIR
ExecStart=$SETUP_DIR/strato-agent --config config.toml
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=strato-node

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
log "Enabling and starting Strato Node service"
sudo systemctl daemon-reload
sudo systemctl enable strato-node.service
sudo systemctl start strato-node.service

# Wait and check service status
sleep 2
if systemctl is-active --quiet strato-node.service; then
    log "Strato Node service started successfully"
    SERVICE_STATUS="running"
else
    log "Warning: Service may have failed to start. Check: journalctl -u strato-node -f"
    SERVICE_STATUS="failed"
fi

# Display installation summary
log "Installation completed!"
echo
echo "Strato Node Details:"
echo "  Client ID: $CLIENT_ID"
echo "  Setup Directory: $SETUP_DIR"
echo "  Service Status: $SERVICE_STATUS"
echo
echo "Service Management Commands:"
echo "  Check status: sudo systemctl status strato-node"
echo "  View logs: sudo journalctl -u strato-node -f"
echo "  Stop service: sudo systemctl stop strato-node"
echo "  Start service: sudo systemctl start strato-node"
echo "  Restart service: sudo systemctl restart strato-node"
