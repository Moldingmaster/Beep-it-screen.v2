#!/usr/bin/env bash
set -Eeuo pipefail

# Beep It v2 Installation Script for Raspberry Pi
# This script sets up the Beep It application with audio fixes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_DIR="/home/pi/Beep-it-screen.v2"
SYSTEMD_DIR="/etc/systemd/system"

log() { printf "[install] %s\n" "$*"; }
error() { printf "[ERROR] %s\n" "$*" >&2; exit 1; }

# Check for Python 3
log "Checking for Python 3..."
if ! command -v python3 &> /dev/null; then
    error "Python 3 is not installed. Install it with: sudo apt-get install python3"
fi

# Verify Python version (minimum 3.7 for tkinter support)
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [[ "$PYTHON_MAJOR" -lt 3 ]] || { [[ "$PYTHON_MAJOR" -eq 3 ]] && [[ "$PYTHON_MINOR" -lt 7 ]]; }; then
    error "Python 3.7 or higher is required (found $PYTHON_VERSION). Update Python with: sudo apt-get update && sudo apt-get install python3"
fi

log "Found Python $PYTHON_VERSION"

# Install system dependencies
log "Installing system dependencies..."
apt-get update -qq || error "Failed to update apt package list"
apt-get install -y \
    python3-tk \
    python3-psycopg2 \
    ffmpeg \
    mpg123 \
    alsa-utils || error "Failed to install system dependencies"

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null && [[ "${FORCE_INSTALL:-}" != "1" ]]; then
    error "This script is designed for Raspberry Pi. Set FORCE_INSTALL=1 to override."
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (use sudo)"
fi

log "Installing Beep It v2 application..."

# Convert sound files to WAV format
log "Converting sound files to WAV format..."
cd "$REPO_ROOT"
bash scripts/convert-sounds-to-wav.sh || error "Failed to convert sound files"

# Configure ALSA audio for HDMI (touchscreen speakers)
# Note: Using plughw for automatic format conversion (required for HDMI audio)
log "Configuring ALSA audio for HDMI output..."
cat > /etc/asound.conf <<EOF
pcm.!default {
    type plug
    slave.pcm "hw:1,0"
}

ctl.!default {
    type hw
    card 1
}
EOF
log "ALSA configured to use plughw:1,0 (HDMI with format conversion)"

log "Testing audio configuration..."
if command -v aplay &> /dev/null; then
    log "Audio configured. Test with: aplay $INSTALL_DIR/sounds/positive.wav"
else
    error "aplay not found after installation"
fi

# Create systemd service
log "Creating systemd service: beep-it.service"
cat > "$SYSTEMD_DIR/beep-it.service" <<EOF
[Unit]
Description=Beep It Job Scanner Application
After=network.target sound.target

[Service]
Type=simple
User=pi
Group=audio
WorkingDirectory=$INSTALL_DIR
Environment="DISPLAY=:0"
Environment="XAUTHORITY=/home/pi/.Xauthority"
ExecStart=/usr/bin/python3 $INSTALL_DIR/scan_gui.py
Restart=always
RestartSec=10

[Install]
WantedBy=graphical.target
EOF

# Setup database
log "Database setup..."
log "Run these commands to setup the database:"
log "  psql -h 10.69.1.52 -U postgres -d postgres -f $INSTALL_DIR/migrations/001_create_pi_devices.sql"
log "  psql -h 10.69.1.52 -U postgres -d postgres -f $INSTALL_DIR/migrations/002_add_hostname_to_scan_log.sql"
log "  Password: RxpJcA7FZRiUCPXhLX8T"
log ""
log "Then register this Pi:"
log "  psql -h 10.69.1.52 -U postgres -d postgres -c \"INSERT INTO pi_devices (hostname, location, is_active) VALUES ('\$(hostname)', '\$(hostname)', true) ON CONFLICT (hostname) DO UPDATE SET is_active = true;\""
log ""

# Reload systemd
log "Reloading systemd daemon..."
systemctl daemon-reload

# Enable and start the application service
log "Enabling beep-it.service to start on boot..."
systemctl enable beep-it.service

log "Starting beep-it.service..."
systemctl start beep-it.service

log ""
log "=============================================="
log "Installation complete!"
log "=============================================="
log ""
log "The Beep It application is now running!"
log ""
log "Next steps:"
log "1. Run the database migration commands shown above"
log "2. Register this Pi in the database"
log "3. Test the application by scanning a barcode"
log ""
log "Useful commands:"
log "  - Check app status:    sudo systemctl status beep-it.service"
log "  - View app logs:       sudo journalctl -u beep-it.service -f"
log "  - Restart app:         sudo systemctl restart beep-it.service"
log "  - Stop app:            sudo systemctl stop beep-it.service"
log ""
