#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Terminal control sequences
HIDE_CURSOR='\033[?25l'
SHOW_CURSOR='\033[?25h'
MOVE_TO_TOP='\033[H'
CLEAR_SCREEN='\033[2J'

LOG_FILE="/provisioning/logs.txt"

# Global variables to track terminal dimensions
PREV_TERMINAL_WIDTH=0
PREV_TERMINAL_HEIGHT=0

# Function to create progress bar
create_progress_bar() {
    local percentage=$1
    local width=$2
    
    # Ensure percentage is valid integer
    if [[ ! "$percentage" =~ ^[0-9]+$ ]]; then
        percentage=0
    fi
    if [ "$percentage" -lt 0 ]; then
        percentage=0
    fi
    if [ "$percentage" -gt 100 ]; then
        percentage=100
    fi
    
    # Calculate filled and empty portions
    local filled=$((percentage * width / 100))
    local empty=$((width - filled))
    
    # Build the progress bar
    local bar=""
    
    # Add opening bracket
    bar+="["
    
    # Add filled portion
    for ((i=0; i<filled; i++)); do
        bar+="_"
    done
    
    # Add empty portion
    for ((i=0; i<empty; i++)); do
        bar+="░"
    done
    
    # Add closing bracket
    bar+="]"
    
    printf "%s" "$bar"
}

# Function to convert scientific notation to integer
scientific_to_int() {
    local value="$1"
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        echo "$value"
    elif [[ "$value" =~ [eE] ]]; then
        echo "$value" | awk '{printf "%.0f", $1}'
    else
        echo "0"
    fi
}

# Function to check if running in container
is_in_container() {
    [ -f "/sys/fs/cgroup/memory/memory.limit_in_bytes" ] || [ -f "/sys/fs/cgroup/memory.max" ]
}

# Function to get container memory limit
get_container_memory_limit() {
    local limit="0"
    
    if [ -f "/sys/fs/cgroup/memory/memory.limit_in_bytes" ]; then
        local raw_limit=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "0")
        limit=$(scientific_to_int "$raw_limit")
        if [ "$limit" -gt 1000000000000000 ]; then
            limit="0"
        fi
    elif [ -f "/sys/fs/cgroup/memory.max" ]; then
        local max_val=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo "max")
        if [ "$max_val" = "max" ]; then
            limit="0"
        else
            limit=$(scientific_to_int "$max_val")
        fi
    fi
    
    echo "$limit"
}

# Function to get container memory usage
get_container_memory_usage() {
    local usage="0"
    
    if [ -f "/sys/fs/cgroup/memory/memory.usage_in_bytes" ]; then
        local raw_usage=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null || echo "0")
        usage=$(scientific_to_int "$raw_usage")
    elif [ -f "/sys/fs/cgroup/memory.current" ]; then
        local raw_usage=$(cat /sys/fs/cgroup/memory.current 2>/dev/null || echo "0")
        usage=$(scientific_to_int "$raw_usage")
    fi
    
    echo "$usage"
}

# Function to get memory stats
get_memory_stats() {
    if is_in_container; then
        local limit=$(get_container_memory_limit)
        local usage=$(get_container_memory_usage)
        
        if [ "$limit" -gt 0 ] && [ "$usage" -gt 0 ]; then
            local percent=$((usage * 100 / limit))
            echo "$usage $limit $percent container"
            return
        fi
    fi
    
    local mem_info=$(free -b | awk 'NR==2{used=$3; total=$2; print used, total, int(used*100/total)}')
    echo "$mem_info host"
}

# Function to convert bytes to GB
bytes_to_gb() {
    local bytes=$1
    if [ "$bytes" -eq 0 ]; then
        echo "0.0"
    else
        echo "$bytes" | awk '{printf "%.1f", $1/1024/1024/1024}'
    fi
}

# Function to get CPU usage
get_cpu_usage() {
    # Use a more reliable method
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    # Remove decimal part and ensure it's an integer
    cpu_usage=${cpu_usage%.*}
    cpu_usage=${cpu_usage:-0}
    
    echo "$cpu_usage"
}

# Function to create aligned metric line
create_metric_line() {
    local label="$1"
    local percent="$2"
    local usage_info="$3"
    local bar_width="$4"
    
    # Ensure percent is an integer
    percent=${percent%.*}
    percent=${percent:-0}
    
    # Pad label to consistent width
    local padded_label=$(printf "%-6s" "$label:")
    
    # Pad percentage to consistent width
    local padded_percent=$(printf "%3s%%" "$percent")
    
    # Pad usage info to consistent width
    local padded_usage=""
    if [ -n "$usage_info" ]; then
        padded_usage=$(printf " %-19s" "$usage_info")
    else
        padded_usage=$(printf " %-19s" "")
    fi
    
    # Create the line
    printf "${GREEN}%s${NC} %s%s %s" "$padded_label" "$padded_percent" "$padded_usage" "$(create_progress_bar "$percent" "$bar_width")"
}

# Function to check if terminal was resized
terminal_resized() {
    local current_width=$(tput cols)
    local current_height=$(tput lines)
    
    if [ "$current_width" -ne "$PREV_TERMINAL_WIDTH" ] || [ "$current_height" -ne "$PREV_TERMINAL_HEIGHT" ]; then
        PREV_TERMINAL_WIDTH=$current_width
        PREV_TERMINAL_HEIGHT=$current_height
        return 0  # True - terminal was resized
    fi
    
    return 1  # False - no resize
}

# Function to get system stats
get_stats() {
    # Check for terminal resize
    local need_clear=false
    if terminal_resized; then
        need_clear=true
    fi
    
    # Get terminal dimensions (already updated by terminal_resized function)
    local terminal_width=$PREV_TERMINAL_WIDTH
    local terminal_height=$PREV_TERMINAL_HEIGHT
    
    # Get CPU usage
    local cpu_percent=$(get_cpu_usage)
    
    # Get memory stats
    local mem_stats=$(get_memory_stats)
    local mem_used=$(echo $mem_stats | cut -d' ' -f1)
    local mem_total=$(echo $mem_stats | cut -d' ' -f2)
    local mem_percent=$(echo $mem_stats | cut -d' ' -f3)
    local mem_source=$(echo $mem_stats | cut -d' ' -f4)
    
    # Get disk stats
    local disk_stats=$(df -B1 / 2>/dev/null | awk 'NR==2{used=$3; total=$2; print used, total, int(used*100/total)}')
    local disk_used=$(echo $disk_stats | cut -d' ' -f1)
    local disk_total=$(echo $disk_stats | cut -d' ' -f2)
    local disk_percent=$(echo $disk_stats | cut -d' ' -f3)
    
    # Ensure valid values
    mem_used=${mem_used:-0}
    mem_total=${mem_total:-0}
    mem_percent=${mem_percent:-0}
    disk_used=${disk_used:-0}
    disk_total=${disk_total:-0}
    disk_percent=${disk_percent:-0}
    
    # Convert to GB
    local mem_used_gb=$(bytes_to_gb "$mem_used")
    local mem_total_gb=$(bytes_to_gb "$mem_total")
    local disk_used_gb=$(bytes_to_gb "$disk_used")
    local disk_total_gb=$(bytes_to_gb "$disk_total")
    
    # Format usage strings
    local mem_usage_str="${mem_used_gb}/${mem_total_gb} GB"
    local disk_usage_str="${disk_used_gb}/${disk_total_gb} GB"
    
    # Calculate progress bar width
    local bar_width=$((terminal_width - 35))
    if [ "$bar_width" -lt 20 ]; then bar_width=20; fi
    
    # GPU info
    local gpu_lines=""
    local lines_used=6
    local has_gpu=false
    
    if command -v nvidia-smi >/dev/null 2>&1; then
        local gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
        
        if [ -n "$gpu_info" ] && [ "$gpu_info" != "No devices were found" ]; then
            local total_gpu_load=0
            local total_vram_used=0
            local total_vram_total=0
            local gpu_count=0
            
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    local gpu_util=$(echo "$line" | cut -d',' -f1 | tr -d ' ')
                    local gpu_mem_used=$(echo "$line" | cut -d',' -f2 | tr -d ' ')
                    local gpu_mem_total=$(echo "$line" | cut -d',' -f3 | tr -d ' ')
                    
                    if [[ "$gpu_util" =~ ^[0-9]+$ ]] && [[ "$gpu_mem_used" =~ ^[0-9]+$ ]] && [[ "$gpu_mem_total" =~ ^[0-9]+$ ]]; then
                        total_gpu_load=$((total_gpu_load + gpu_util))
                        total_vram_used=$((total_vram_used + gpu_mem_used))
                        total_vram_total=$((total_vram_total + gpu_mem_total))
                        gpu_count=$((gpu_count + 1))
                    fi
                fi
            done <<< "$gpu_info"
            
            if [ "$gpu_count" -gt 0 ]; then
                local gpu_percent=$((total_gpu_load / gpu_count))
                local vram_percent=0
                if [ "$total_vram_total" -gt 0 ]; then
                    vram_percent=$((total_vram_used * 100 / total_vram_total))
                fi
                
                local vram_usage_str="${total_vram_used}/${total_vram_total} MB"
                gpu_lines="$(create_metric_line "GPU" "$gpu_percent" "" "$bar_width")\n"
                gpu_lines+="$(create_metric_line "VRAM" "$vram_percent" "$vram_usage_str" "$bar_width")\n"
                has_gpu=true
                ((lines_used++))
            fi
        fi
    fi
    
    if [ "$has_gpu" = false ]; then
        gpu_lines="${GREEN}GPU:  ${NC} No GPU detected\n"
    fi
    
    # Environment indicator
    local env_str=""
    if [ "$mem_source" = "container" ]; then
        env_str=" (Docker Container)"
    fi
    
    # Calculate log lines
    local log_lines=$((terminal_height - lines_used - 1))
    if [ "$log_lines" -lt 1 ]; then log_lines=1; fi
    
    # Get logs
    local log_content=""
    if [ -f "$LOG_FILE" ]; then
        while IFS= read -r line; do
            if [[ $line == *"ERROR"* ]]; then
                log_content+="${RED}$line${NC}\n"
            elif [[ $line == *"WARNING"* ]]; then
                log_content+="${YELLOW}$line${NC}\n"
            else
                log_content+="$line\n"
            fi
        done < <(tail -n "$log_lines" "$LOG_FILE" 2>/dev/null)
        log_content="${log_content%\\n}"
    else
        log_content="${RED}Log file not found: $LOG_FILE${NC}"
    fi
    
    # Build complete output buffer with aligned metrics
    local output=""
    output+="${CYAN}=== SYSTEM MONITORING${env_str} ===${NC}\n"
    output+="$(create_metric_line "CPU" "$cpu_percent" "" "$bar_width")\n"
    output+="$(create_metric_line "RAM" "$mem_percent" "$mem_usage_str" "$bar_width")\n"
    output+="$(create_metric_line "DISK" "$disk_percent" "$disk_usage_str" "$bar_width")\n"
    output+="${gpu_lines}"
    output+="${CYAN}=== LOGS ===${NC}\n"
    output+="${log_content}"
    
    # Choose display method based on whether terminal was resized
    if [ "$need_clear" = true ]; then
        # Full clear and redraw on resize
        printf "${HIDE_CURSOR}${CLEAR_SCREEN}${MOVE_TO_TOP}%b${SHOW_CURSOR}" "$output"
    else
        # Normal overwrite for performance
        printf "${HIDE_CURSOR}${MOVE_TO_TOP}%b${SHOW_CURSOR}" "$output"
    fi
}

# Function for initial screen setup
setup_screen() {
    # Initialize terminal dimensions
    PREV_TERMINAL_WIDTH=$(tput cols)
    PREV_TERMINAL_HEIGHT=$(tput lines)
    
    printf "${CLEAR_SCREEN}${MOVE_TO_TOP}"
}

# Trap to handle exit gracefully
cleanup() {
    printf "${SHOW_CURSOR}${CLEAR_SCREEN}${MOVE_TO_TOP}"
    echo "Monitoring stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo -e "${YELLOW}Warning: Log file $LOG_FILE does not exist yet.${NC}"
    echo "Starting monitoring anyway..."
    sleep 2
fi

# Setup
echo -e "${GREEN}Starting system monitoring... Press Ctrl+C to exit${NC}"
sleep 1
setup_screen

# Main monitoring loop
while true; do
    get_stats
    sleep 0.5
done
