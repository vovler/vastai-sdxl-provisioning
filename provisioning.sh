#!/bin/bash

# System setup: update, upgrade, and install packages
apt-get update -y && apt-get upgrade -y
apt-get install -y aria2 libjemalloc-dev libjemalloc2

# Append aliases, functions, and environment variables to .bashrc
# This ensures they are available in every new shell session.
if ! grep -q "# --- Custom vast.ai configuration ---" ~/.bashrc; then
    cat <<'EOF' >> ~/.bashrc

# --- Custom vast.ai configuration ---

# Custom Aliases
alias vram='watch -n 0.1 nvidia-smi'
alias download='aria2c -x 16 -s 16 -k 10M'

# Custom pip function for optimized installation
pip() {
    if [[ "$1" == "install" ]]; then
        echo "Using custom pip install with TMPDIR=/dev/shm/"
        TMPDIR=/dev/shm/ command pip install --no-cache-dir "${@:2}" && rm -rf /dev/shm/*
    else
        command pip "$@"
    fi
}

# Environment variables for performance
export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2:$LD_PRELOAD
export PYTORCH_CUDA_ALLOC_CONF='expandable_segments:True'
export CUDA_DEVICE_ORDER=PCI_BUS_ID

# --- End of Custom vast.ai configuration ---

EOF
fi

# Source .bashrc to set up the environment, including conda activation.
# This is done to ensure that the following commands run in the correct environment.
echo "Sourcing ~/.bashrc to set up environment..."
source ~/.bashrc

pip install --upgrade pip

# Append the code to /root/onstart.sh
#cat >> /root/onstart.sh << 'EOF'
#cd /provisioning
#nohup bash -c 'while true; do ./startup.sh; sleep 1; done' > /dev/null 2>&1 &
#disown
#EOF

# Execute the provisioning setup immediately
touch ~/.no_auto_tmux;
mkdir -p /provisioning
cd /provisioning
#[ ! -f startup.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-sdxl-provisioning/refs/heads/main/startup.sh && chmod +x startup.sh

[ ! -f monitoring.sh ] && curl -O https://raw.githubusercontent.com/vovler/vastai-sdxl-provisioning/refs/heads/main/monitoring.sh && chmod +x monitoring.sh

# Create symlink to monitoring.sh so it can be called as 'monitor' from anywhere
[ -f /provisioning/monitoring.sh ] && ln -sf /provisioning/monitoring.sh /usr/local/bin/monitor

# Run startup.sh in a while loop in background, then exit
#nohup bash -c 'while true; do ./startup.sh; sleep 1; done' > /dev/null 2>&1 &
#disown
