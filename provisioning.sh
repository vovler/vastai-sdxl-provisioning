#!/bin/bash

# Append the code to /root/onstart.sh
cat >> /root/onstart.sh << 'EOF'
cd /provisioning
nohup bash -c 'while true; do ./startup.sh; sleep 1; done' > /dev/null 2>&1 &
disown
EOF

# Execute the provisioning setup immediately
touch ~/.no_auto_tmux;
mkdir -p /provisioning
cd /provisioning
[ ! -f startup.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-sdxl-provisioning/refs/heads/main/startup.sh && chmod +x startup.sh

[ ! -f monitoring.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-sdxl-provisioning/refs/heads/main/monitoring.sh && chmod +x monitoring.sh

# Create symlink to monitoring.sh so it can be called as 'monitor' from anywhere
[ -f /provisioning/monitoring.sh ] && ln -sf /provisioning/monitoring.sh /usr/local/bin/monitor

# Run startup.sh in a while loop in background, then exit
nohup bash -c 'while true; do ./startup.sh; sleep 1; done' > /dev/null 2>&1 &
disown
