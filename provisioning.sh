#!/bin/bash

# Append the code to /root/onstart.sh
cat >> /root/onstart.sh << 'EOF'
touch ~/.no_auto_tmux;
mkdir -p /provisioning
cd /provisioning
[ ! -f provisioning.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-provisioning/refs/heads/main/provisioning.sh && chmod +x provisioning.sh

[ ! -f monitoring.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-provisioning/refs/heads/main/monitoring.sh && chmod +x monitoring.sh

while true; do ./provisioning.sh; sleep 1; done &
EOF

touch ~/.no_auto_tmux;
mkdir -p /provisioning
cd /provisioning
[ ! -f provisioning.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-provisioning/refs/heads/main/provisioning.sh && chmod +x provisioning.sh

[ ! -f monitoring.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-provisioning/refs/heads/main/monitoring.sh && chmod +x monitoring.sh

while true; do ./provisioning.sh; sleep 1; done &
