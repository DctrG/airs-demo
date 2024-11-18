#!/bin/bash

INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
echo "Running on instance: $INSTANCE_NAME"

# Set up logging
exec 1> >(tee -a /var/log/startup-script.log) 2>&1
echo "[$(date)] Starting startup script..."

# Exit on any error
set -ex

Install prerequisites
echo "[$(date)] Installing prerequisites..."
apt-get update
apt-get install -y python3-pip python3-venv git

# Create and activate virtual environment
echo "[$(date)] Setting up virtual environment..."
python3 -m venv /root/venv
source /root/venv/bin/activate

# Set up environment variables
echo "[$(date)] Setting up environment variables..."
echo "export SSL_CERT_FILE=/etc/ssl/certs/root_ca.pem" >> /root/.bashrc
echo "export REQUESTS_CA_BUNDLE=/etc/ssl/certs/root_ca.pem" >> /root/.bashrc
echo "export GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/etc/ssl/certs/root_ca.pem" >> /root/.bashrc


source /root/.bashrc

# Stop service if exists
echo "[$(date)] Handling bank-app service..."
if systemctl list-unit-files | grep -q bank-app.service; then
    systemctl stop bank-app.service
fi

# Setup application
echo "[$(date)] Setting up application..."
cd /home/paloalto || mkdir -p /home/paloalto && cd /home/paloalto
[ -d "apps" ] && rm -rf apps

echo "[$(date)] Cloning repository..."
git clone https://github.com/DctrG/apps.git
cd apps

echo "[$(date)] Installing requirements..."
pip install --trusted-host pypi.org --trusted-host files.pythonhosted.org -r requirements.txt

echo "[$(date)] Copying files..."
if [ -f "bank-app.sh" ]; then
    cp bank-app.sh /usr/bin/
    chmod +x /usr/bin/bank-app.sh
else
    echo "Error: bank-app.sh not found"
    exit 1
fi

if [[ "$INSTANCE_NAME" != *"unprotected"* ]]; then
    echo "Configuring protected instance..."
    mv bank-app-protected.py bank-app.py
fi

# Create service file with environment variables
echo "[$(date)] Creating service file..."
cat > /etc/systemd/system/bank-app.service << 'EOL'
[Unit]
Description=Bank App Service
After=network.target

[Service]
# Environment=SSL_CERT_FILE=/etc/ssl/certs/root_ca.pem
# Environment=REQUESTS_CA_BUNDLE=/etc/ssl/certs/root_ca.pem
# Environment=GRPC_DEFAULT_SSL_ROOTS_FILE_PATH=/etc/ssl/certs/root_ca.pem
ExecStart=/usr/bin/bank-app.sh
Restart=always
User=root
WorkingDirectory=/home/paloalto/apps

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd and start service
echo "[$(date)] Starting service..."
systemctl daemon-reload
systemctl enable bank-app.service
systemctl start bank-app.service
systemctl status bank-app.service

echo "[$(date)] Startup script completed"
