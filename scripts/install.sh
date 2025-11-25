#!/usr/bin/env bash
set -Eeuo pipefail

# Beep It Installation Script for Raspberry Pi
# This script sets up the Beep It application to run on startup

# ============================================================
# GitHub Personal Access Token (read-only) for auto-updates
# This token is shared across all Pis for fetching releases
# Generate at: https://github.com/settings/tokens
# Required scope: repo (read-only access to private repos)
# Edit this variable with your actual token before deploying
# ============================================================
GH_TOKEN_RO="{{GH_TOKEN_RO}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="/opt/beep_it"
SYSTEMD_DIR="/etc/systemd/system"
DEFAULT_DIR="/etc/default"

log() { printf "[install] %s\n" "$*"; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

# Check for Python 3
log "Checking for Python 3..."
if ! command -v python3 &> /dev/null; then
    error "Python 3 is not installed. Install it with: sudo apt-get install python3 python3-pip python3-venv"
fi

# Verify Python version (minimum 3.7 for tkinter support)
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [[ "$PYTHON_MAJOR" -lt 3 ]] || { [[ "$PYTHON_MAJOR" -eq 3 ]] && [[ "$PYTHON_MINOR" -lt 7 ]]; }; then
    error "Python 3.7 or higher is required (found $PYTHON_VERSION). Update Python with: sudo apt-get update && sudo apt-get install python3"
fi

log "Found Python $PYTHON_VERSION"

# Check for pip3
if ! command -v pip3 &> /dev/null; then
    error "pip3 is not installed. Install it with: sudo apt-get install python3-pip"
fi

# Install system dependencies
log "Installing system dependencies..."
apt-get update -qq || error "Failed to update apt package list"
apt-get install -y \
    python3-tk \
    python3-psycopg2 \
    python3-pygame || error "Failed to install system dependencies"

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null && [[ "${FORCE_INSTALL:-}" != "1" ]]; then
    error "This script is designed for Raspberry Pi. Set FORCE_INSTALL=1 to override."
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

log "Installing Beep It application..."

# Create installation directory
log "Creating installation directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

# Install application
log "Installing application files..."
install -m 0755 "$REPO_ROOT/scan_gui.py" "$INSTALL_DIR/scan_gui.py"

# Copy sounds directory
log "Installing sound files..."
mkdir -p "$INSTALL_DIR/sounds"
cp -r "$REPO_ROOT/sounds/"* "$INSTALL_DIR/sounds/" || error "Failed to copy sound files"

# Create initial VERSION file
if [[ -f "$REPO_ROOT/updates/VERSION" ]]; then
    install -m 0644 "$REPO_ROOT/updates/VERSION" "$INSTALL_DIR/VERSION"
else
    echo "0.0.0" > "$INSTALL_DIR/VERSION"
fi

# Note: Python dependencies are now installed via apt (python3-psycopg2)
# No pip installation needed

# Install systemd service for the application
log "Installing systemd service: beep-it.service"
install -m 0644 "$REPO_ROOT/contrib/systemd/beep-it.service" "$SYSTEMD_DIR/beep-it.service"

# Install update script and systemd units
log "Installing auto-update mechanism..."
install -m 0755 "$REPO_ROOT/scripts/beep-it-update" "/usr/local/sbin/beep-it-update"
install -m 0644 "$REPO_ROOT/contrib/systemd/beep-it-update.service" "$SYSTEMD_DIR/beep-it-update.service"
install -m 0644 "$REPO_ROOT/contrib/systemd/beep-it-update.timer" "$SYSTEMD_DIR/beep-it-update.timer"

# Configure environment for updater
log "Configuring GitHub token for auto-updates..."
cat > "$DEFAULT_DIR/beep-it-update" <<EOF
# GitHub Personal Access Token (read-only) for fetching private releases
# This token is shared across all Pis
GH_TOKEN_RO=${GH_TOKEN_RO}
EOF
chmod 600 "$DEFAULT_DIR/beep-it-update"

if [[ "$GH_TOKEN_RO" == "{{GH_TOKEN_RO}}" ]]; then
    log "WARNING: GitHub token is still set to placeholder!"
    log "Edit the GH_TOKEN_RO variable at the top of this script and re-run."
    log "Auto-updates will not work until the token is configured."
    SKIP_UPDATE_START=true
else
    log "GitHub token configured successfully!"
    SKIP_UPDATE_START=false
fi

# Reload systemd
log "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start the application service
log "Enabling beep-it.service to start on boot..."
systemctl enable beep-it.service

log "Starting beep-it.service..."
systemctl start beep-it.service

# Enable and optionally start the update timer
log "Enabling beep-it-update.timer..."
systemctl enable beep-it-update.timer

if [[ "${SKIP_UPDATE_START:-false}" == "false" ]]; then
    log "Starting beep-it-update.timer..."
    systemctl start beep-it-update.timer
fi

log ""
log "=============================================="
log "Installation complete!"
log "=============================================="
log ""
log "The Beep It application is now running!"
log ""
if [[ "${SKIP_UPDATE_START:-false}" == "true" ]]; then
    log "Note: Auto-updates are not configured yet."
    log "Edit GH_TOKEN_RO at the top of this script and re-run to enable auto-updates."
fi
log ""
log "Useful commands:"
log "  - Check app status:    sudo systemctl status beep-it.service"
log "  - View app logs:       sudo journalctl -u beep-it.service -f"
log "  - Restart app:         sudo systemctl restart beep-it.service"
log "  - Check update timer:  sudo systemctl list-timers beep-it-update.timer"
log "  - Manual update:       sudo systemctl start beep-it-update.service"
log ""
