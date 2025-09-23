#!/bin/bash
# VM Setup Script - Sets up SSH key authentication with sudo access
# Usage: curl -sSL https://your-server.com/setup.sh | bash
set -e
# Configuration
GITHUB_USERNAME="binhtruong9418"  # Replace with your GitHub username
NEW_USER="depin"                  # User to create with sudo access
WEBHOOK_URL="https://be-local.ducbinh203.tech/api/webhook/user-vps/events"    # Replace with your webhook URL (e.g., https://your-api.com/webhook)
NODE_VERSION="20"                 # Node.js version to install

echo "🚀 Starting VM setup..."
# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ This script must be run as root"
    echo "Please run: sudo curl -sSL https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/setup.sh | sudo bash"
    exit 1
fi
# Update system
echo "📦 Updating system packages..."
apt-get update -y
# Install required packages
echo "🔧 Installing required packages..."
apt-get install -y curl wget sudo openssh-server jq
# Create user if doesn't exist
if ! id "$NEW_USER" &>/dev/null; then
    echo "👤 Creating user: $NEW_USER"
    useradd -m -s /bin/bash "$NEW_USER"
    
    # Add user to sudo group
    usermod -aG sudo "$NEW_USER"
    
    # Allow passwordless sudo
    echo "$NEW_USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$NEW_USER"
    chmod 440 "/etc/sudoers.d/$NEW_USER"
fi
# Create .ssh directory
USER_HOME="/home/$NEW_USER"
SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
echo "🔑 Setting up SSH keys..."
# Create .ssh directory
sudo -u "$NEW_USER" mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
# Fetch public key from GitHub
echo "📥 Fetching public key from GitHub..."
GITHUB_KEYS_URL="https://github.com/$GITHUB_USERNAME.keys"
if curl -sSL "$GITHUB_KEYS_URL" -o "$AUTHORIZED_KEYS"; then
    echo "✅ Successfully downloaded public key from GitHub"
else
    echo "❌ Failed to download public key from GitHub"
    echo "Please check that:"
    echo "  1. Your GitHub username is correct: $GITHUB_USERNAME"
    echo "  2. You have public keys added to your GitHub account"
    echo "  3. Your GitHub profile allows public key access"
    exit 1
fi
# Set proper permissions
chown "$NEW_USER:$NEW_USER" "$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS"
chown "$NEW_USER:$NEW_USER" "$SSH_DIR"
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
    echo "🔄 Ensuring SSH service is running ($SSH_SERVICE)..."
    systemctl start "$SSH_SERVICE"
    systemctl enable "$SSH_SERVICE"
    echo "✅ SSH service started and enabled"
else
    echo "⚠️  Could not determine SSH service name. Please start SSH manually:"
    echo "   Common commands to try:"
    echo "   - systemctl start ssh"
    echo "   - systemctl start sshd" 
    echo "   - service ssh start"
fi

# Get VM information
VM_IP=$(hostname -I | awk '{print $1}')
VM_HOSTNAME=$(hostname)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Send webhook notification
if [ -n "$WEBHOOK_URL" ]; then
    echo "📡 Sending webhook notification..."
    
    # Prepare JSON payload
    WEBHOOK_PAYLOAD=$(jq -n \
        --arg username "$NEW_USER" \
        --arg ip "$VM_IP" \
        --arg hostname "$VM_HOSTNAME" \
        --arg github_username "$GITHUB_USERNAME" \
        --arg timestamp "$TIMESTAMP" \
        --arg status "success" \
        '{
            username: $username,
            ip: $ip,
            hostname: $hostname,
            github_username: $github_username,
            timestamp: $timestamp,
            status: $status,
            ssh_command: ("ssh " + $username + "@" + $ip)
        }')
    
    # Send webhook
    if curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$WEBHOOK_PAYLOAD" \
        --max-time 30 \
        --retry 3; then
        echo "✅ Webhook notification sent successfully"
    else
        echo "⚠️  Failed to send webhook notification (continuing anyway...)"
        echo "   Webhook URL: $WEBHOOK_URL"
        echo "   Payload: $WEBHOOK_PAYLOAD"
    fi
else
    echo "⚠️  Webhook URL not configured, skipping notification"
fi

# Display connection info
echo ""
echo "🎉 Setup complete!"
echo ""
echo "Connection details:"
echo "  User: $NEW_USER"
echo "  IP: $VM_IP"
echo "  SSH command: ssh $NEW_USER@$VM_IP"
echo ""
echo "The user '$NEW_USER' has been created with:"
echo "  ✅ SSH key authentication (from GitHub: $GITHUB_USERNAME)"
echo "  ✅ Sudo privileges (passwordless)"
echo "  ✅ SSH access configured"
echo ""
