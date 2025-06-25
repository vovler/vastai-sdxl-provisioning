#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

LOG_FILE="/provisioning/logs.txt"

# Function to get system stats
get_stats() {
    local lines_used=0
    
    # Clear screen and move cursor to top
    clear
    
    echo -e "${CYAN}=== SYSTEM MONITORING ===${NC}"
    ((lines_used++))
    
    # CPU Usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "${GREEN}CPU:${NC} ${cpu_usage}% | ${GREEN}Load:${NC} $(cat /proc/loadavg | cut -d' ' -f1-3)"
    ((lines_used++))
    
    # Memory Usage
    local mem_info=$(free -h | awk 'NR==2{printf "Used: %s/%s (%.1f%%)", $3, $2, $3*100/$2}')
    echo -e "${GREEN}RAM:${NC} $mem_info"
    ((lines_used++))
    
    # Disk Usage
    local disk_info=$(df -h / | awk 'NR==2{printf "Used: %s/%s (%s)", $3, $2, $5}')
    echo -e "${GREEN}Disk:${NC} $disk_info"
    ((lines_used++))
    
    # GPU Usage (if nvidia-smi is available)
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits | head -1)
        if [ -n "$gpu_info" ]; then
            local gpu_util=$(echo $gpu_info | cut -d',' -f1 | tr -d ' ')
            local gpu_mem_used=$(echo $gpu_info | cut -d',' -f2 | tr -d ' ')
            local gpu_mem_total=$(echo $gpu_info | cut -d',' -f3 | tr -d ' ')
            echo -e "${GREEN}GPU:${NC} ${gpu_util}% | ${GREEN}VRAM:${NC} ${gpu_mem_used}MB/${gpu_mem_total}MB"
            ((lines_used++))
        fi
    else
        echo -e "${YELLOW}GPU:${NC} nvidia-smi not available"
        ((lines_used++))
    fi
    
    echo -e "${CYAN}=== LOGS (${LOG_FILE}) ===${NC}"
    ((lines_used++))
    
    # Calculate remaining lines for logs
    local terminal_height=$(tput lines)
    local log_lines=$((terminal_height - lines_used - 1))
    
    # Show logs
    if [ -f "$LOG_FILE" ]; then
        tail -n $log_lines "$LOG_FILE" | while IFS= read -r line; do
            # Color code log lines
            if [[ $line == *"ERROR"* ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ $line == *"WARNING"* ]]; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "$line"
            fi
        done
    else
        echo -e "${RED}Log file not found: $LOG_FILE${NC}"
    fi
}

# Trap to handle exit gracefully
cleanup() {
    clear
    echo "Monitoring stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo -e "${YELLOW}Warning: Log file $LOG_FILE does not exist yet.${NC}"
    echo "Starting monitoring anyway..."
    sleep 2
fi

# Main monitoring loop
echo -e "${GREEN}Starting system monitoring... Press Ctrl+C to exit${NC}"
sleep 1

while true; do
    get_stats
    sleep 1
done
