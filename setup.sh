#!/bin/bash
# VM Setup Script - Sets up SSH key authentication with sudo access
# Usage: export NEW_USER=your-username && sudo curl -sSL https://your-server.com/setup.sh | sudo bash
set -e

# Configuration with environment variables
GITHUB_USERNAME="${GITHUB_USERNAME:-binhtruong9418}"  # Can be overridden with env var
NEW_USER="${NEW_USER:-strato_user-2}"                  # Can be overridden with env var
WEBHOOK_URL="${WEBHOOK_URL:-https://be-local.ducbinh203.tech/api/webhook/strato/validate-setup}"    # Can be overridden with env var

# Logging function with timestamp
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message"
}

log "Starting VM setup"
log "GitHub Username: $GITHUB_USERNAME"
log "New User: $NEW_USER"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    log "ERROR: This script must be run as root"
    log "Please run: export NEW_USER=your-username && sudo curl -sSL https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/setup.sh | sudo bash"
    exit 1
fi

# Validate required environment variables
if [ -z "$NEW_USER" ]; then
    log "ERROR: NEW_USER environment variable is required"
    log "Please run: export NEW_USER=your-username && sudo curl -sSL ..."
    exit 1
fi

if [ -z "$GITHUB_USERNAME" ]; then
    log "ERROR: GITHUB_USERNAME environment variable is required"
    log "Please run: export GITHUB_USERNAME=your-github-username && sudo curl -sSL ..."
    exit 1
fi

# Update system
log "Updating system packages"
apt-get update -y

# Install required packages
log "Installing required packages"
apt-get install -y curl wget sudo openssh-server jq

# Create user if doesn't exist
if ! id "$NEW_USER" &>/dev/null; then
    log "Creating user: $NEW_USER"
    useradd -m -s /bin/bash "$NEW_USER"
    
    # Add user to sudo group
    usermod -aG sudo "$NEW_USER"
    
    # Allow passwordless sudo
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
    chmod 440 "/etc/sudoers.d/$NEW_USER"
    log "User $NEW_USER created with sudo privileges"
else
    log "User $NEW_USER already exists"
fi

# Create .ssh directory
USER_HOME="/home/$NEW_USER"
SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

log "Setting up SSH keys"

# Create .ssh directory
sudo -u "$NEW_USER" mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# Fetch public key from GitHub
log "Fetching public key from GitHub for user: $GITHUB_USERNAME"
GITHUB_KEYS_URL="https://github.com/$GITHUB_USERNAME.keys"

if curl -sSL "$GITHUB_KEYS_URL" -o "$AUTHORIZED_KEYS"; then
    log "Successfully downloaded public key from GitHub"
else
    log "ERROR: Failed to download public key from GitHub"
    log "Please check that your GitHub username is correct: $GITHUB_USERNAME"
    log "Please check that you have public keys added to your GitHub account"
    log "Please check that your GitHub profile allows public key access"
    exit 1
fi

# Set proper permissions
chown "$NEW_USER:$NEW_USER" "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"
chown "$NEW_USER:$NEW_USER" "$SSH_DIR"
log "SSH key permissions set correctly"

# Ensure SSH service is running
SSH_SERVICE=""
if systemctl list-unit-files | grep -q "^ssh.service"; then
    SSH_SERVICE="ssh"
elif systemctl list-unit-files | grep -q "^sshd.service"; then
    SSH_SERVICE="sshd"
elif systemctl list-unit-files | grep -q "^openssh.service"; then
    SSH_SERVICE="openssh"
fi

if [ -n "$SSH_SERVICE" ]; then
    log "Starting SSH service: $SSH_SERVICE"
    systemctl start "$SSH_SERVICE"
    systemctl enable "$SSH_SERVICE"
    log "SSH service started and enabled"
else
    log "WARNING: Could not determine SSH service name"
    log "Please start SSH service manually using: systemctl start ssh"
fi

# Get VM information
VM_IP=$(hostname -I | awk '{print $1}')
VM_HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Send webhook notification
if [ -n "$WEBHOOK_URL" ]; then
    log "Sending webhook notification"
    
    # Prepare JSON payload
    WEBHOOK_PAYLOAD=$(jq -n \
        --arg username "$NEW_USER" \
        --arg ip "$VM_IP" \
        --arg hostname "$VM_HOSTNAME" \
        --arg timestamp "$TIMESTAMP" \
        --arg status "success" \
        '{
            username: $username,
            ip: $ip,
            hostname: $hostname,
            timestamp: $timestamp,
            status: $status,
        }')
    
    # Send webhook
    if curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$WEBHOOK_PAYLOAD" \
        --max-time 30 \
        --silent; then
        log "Webhook notification sent successfully"
    else
        log "WARNING: Failed to send webhook notification"
        log "Webhook URL: $WEBHOOK_URL"
    fi
else
    log "Webhook URL not configured, skipping notification"
fi

# Display connection info
log "Setup completed successfully"
log "User: $NEW_USER"
log "IP: $VM_IP"
log "SSH key authentication configured from GitHub: $GITHUB_USERNAME"
