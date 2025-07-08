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

# Set Conda environment path and activate if needed
EXPECTED_CONDA_ENV_PATH="/venv/main"
CONDA_BASE_PATH="/opt/conda" 

# Check if we're already in the correct Conda environment
if [ "$CONDA_PREFIX" != "$EXPECTED_CONDA_ENV_PATH" ]; then
    echo "Not in correct Conda environment, activating $EXPECTED_CONDA_ENV_PATH..."

    if [ ! -d "$EXPECTED_CONDA_ENV_PATH" ]; then
        echo "Error: Conda environment not found at $EXPECTED_CONDA_ENV_PATH"
        exit 1
    fi
    
    if [ -f "$CONDA_BASE_PATH/etc/profile.d/conda.sh" ]; then
        # shellcheck disable=SC1091
        source "$CONDA_BASE_PATH/etc/profile.d/conda.sh"
    else
        echo "Error: conda.sh not found at $CONDA_BASE_PATH/etc/profile.d/conda.sh. Cannot activate environment."
        exit 1
    fi
    
    conda activate "$EXPECTED_CONDA_ENV_PATH"
    
    if [ "$CONDA_PREFIX" != "$EXPECTED_CONDA_ENV_PATH" ]; then
        echo "Error: Failed to activate Conda environment. CONDA_PREFIX is '$CONDA_PREFIX'"
        exit 1
    fi
    
    echo "Conda environment activated: $CONDA_PREFIX"
else
    echo "Already in correct Conda environment: $CONDA_PREFIX"
fi

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
disown
