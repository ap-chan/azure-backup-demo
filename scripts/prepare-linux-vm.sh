#!/bin/bash

# Setup logging
LOG_FILE="/tmp/prepare-linux-vm.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting Linux VM configuration..."

# Detect OS version
. /etc/os-release
log "Detected OS: $NAME $VERSION"

# Install prerequisites
log "Installing prerequisites..."
sudo apt-get update
sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg

# Install Azure CLI using the recommended method for Ubuntu 24.04
log "Installing Azure CLI..."
# Option 1: One-line install (recommended by Microsoft)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

log "Azure CLI installation completed."

# Create test files and folders
log "Creating test files..."
sudo mkdir -p /var/sample-files

sudo bash -c 'cat <<EOF > /var/sample-files/samplefile1.txt
This is sample file 1
EOF'

sudo bash -c 'cat <<EOF > /var/sample-files/samplefile2.txt
This is sample file 2
EOF'

sudo bash -c 'cat <<EOF > /var/sample-files/samplefile3.txt
This is sample file 3
EOF'

sudo chmod -R 644 /var/sample-files
sudo chmod 755 /var/sample-files

log "Test files created successfully."
log "Script completed."
