#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validate environment variables
if [ -z "$WORKFLOW_GIT_URL" ]; then
    echo -e "${RED}Error: WORKFLOW_GIT_URL environment variable is not set${NC}"
    exit 1
fi

### MODIFIED SECTION - START ###

# Set Conda environment path and activate if needed
EXPECTED_CONDA_ENV_PATH="/venv/main"
# Common base path for Conda installations in Docker images
CONDA_BASE_PATH="/opt/conda" 

# Check if we're already in the correct Conda environment
if [ "$CONDA_PREFIX" != "$EXPECTED_CONDA_ENV_PATH" ]; then
    echo -e "${YELLOW}Not in correct Conda environment, activating $EXPECTED_CONDA_ENV_PATH...${NC}"

    # Check if the Conda environment directory exists
    if [ ! -d "$EXPECTED_CONDA_ENV_PATH" ]; then
        echo -e "${RED}Error: Conda environment not found at $EXPECTED_CONDA_ENV_PATH${NC}"
        exit 1
    fi
    
    # Source the conda.sh script to enable the 'conda' command
    if [ -f "$CONDA_BASE_PATH/etc/profile.d/conda.sh" ]; then
        # shellcheck disable=SC1091
        source "$CONDA_BASE_PATH/etc/profile.d/conda.sh"
    else
        echo -e "${RED}Error: conda.sh not found at $CONDA_BASE_PATH/etc/profile.d/conda.sh. Cannot activate environment.${NC}"
        exit 1
    fi
    
    # Activate Conda environment
    conda activate "$EXPECTED_CONDA_ENV_PATH"
    
    # Verify activation
    if [ "$CONDA_PREFIX" != "$EXPECTED_CONDA_ENV_PATH" ]; then
        echo -e "${RED}Error: Failed to activate Conda environment. CONDA_PREFIX is '$CONDA_PREFIX'${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Conda environment activated: $CONDA_PREFIX${NC}"
else
    echo -e "${GREEN}Already in correct Conda environment: $CONDA_PREFIX${NC}"
fi

### MODIFIED SECTION - END ###


# Global variables
WORKSPACE="/workflow"
PROVISIONING_DIR="/provisioning"
LOG_FILE="$PROVISIONING_DIR/logs.txt"
APP_SCRIPT="$WORKSPACE/init.py"
REQUIREMENTS_FILE="$WORKSPACE/requirements.txt"
INSTALLED_REQUIREMENTS_FILE="$PROVISIONING_DIR/requirements_installed.txt"
APP_PID=""
LAST_COMMIT=""

# Initialize provisioning directory and log file
mkdir -p "$PROVISIONING_DIR"
touch "$LOG_FILE"

# Logging functions that write to both stdout and log file
log() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
    echo -e "${GREEN}${timestamp}${NC} $1"
    echo "${timestamp} $1" >> "$LOG_FILE"
}

error_log() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:"
    echo -e "${RED}${timestamp}${NC} $1"
    echo "${timestamp} $1" >> "$LOG_FILE"
}

warn_log() {
    local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:"
    echo -e "${YELLOW}${timestamp}${NC} $1"
    echo "${timestamp} $1" >> "$LOG_FILE"
}

# Function to clean logs - keep only last 1000 lines
clean_logs() {
    if [ -f "$LOG_FILE" ]; then
        local line_count
        line_count=$(wc -l < "$LOG_FILE")
        if [ "$line_count" -gt 1000 ]; then
            local temp_file
            temp_file=$(mktemp)
            tail -n 1000 "$LOG_FILE" > "$temp_file"
            mv "$temp_file" "$LOG_FILE"
            log "Log file cleaned, kept last 1000 lines (was $line_count lines)"
        fi
    fi
}

# Function to clone repository with minimal data
clone_repo() {
    log "Cloning repository from $WORKFLOW_GIT_URL..."
    
    if [ -d "$WORKSPACE" ]; then
        rm -rf "$WORKSPACE"
    fi
    
    # Clone with minimal history and data
    git clone \
        --depth 1 \
        --single-branch \
        --no-tags \
        "$WORKFLOW_GIT_URL" "$WORKSPACE" >> "$LOG_FILE" 2>&1
    
    cd "$WORKSPACE"
    LAST_COMMIT=$(git rev-parse HEAD)
    log "Repository cloned successfully. Commit: ${LAST_COMMIT:0:8}"
}

# Function to get new requirements that need to be installed
get_new_requirements() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        return 0
    fi
    
    # Create empty installed requirements file if it doesn't exist
    if [ ! -f "$INSTALLED_REQUIREMENTS_FILE" ]; then
        touch "$INSTALLED_REQUIREMENTS_FILE"
    fi
    
    # Compare requirements files and get new ones
    # Remove comments and empty lines, then compare
    comm -23 \
        <(grep -v '^#' "$REQUIREMENTS_FILE" | grep -v '^$' | sort) \
        <(grep -v '^#' "$INSTALLED_REQUIREMENTS_FILE" | grep -v '^$' | sort)
}

# Function to install new requirements
install_requirements() {
    if [ ! -f "$REQUIREMENTS_FILE" ]; then
        warn_log "No requirements.txt found, skipping requirements installation"
        return 0
    fi
    
    local new_requirements
    new_requirements=$(get_new_requirements)
    
    if [ -n "$new_requirements" ]; then
        log "Installing new requirements:"
        echo "$new_requirements" | while read -r req; do
            echo "  - $req"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')]   - $req" >> "$LOG_FILE"
        done
        
        # Create temporary file with new requirements
        local temp_req_file
        temp_req_file=$(mktemp)
        echo "$new_requirements" > "$temp_req_file"
        
        # ### MODIFIED ### Use 'pip' directly from the activated Conda environment
        if pip install -r "$temp_req_file" >> "$LOG_FILE" 2>&1; then
            # Update installed requirements file only if installation succeeds
            cp "$REQUIREMENTS_FILE" "$INSTALLED_REQUIREMENTS_FILE"
            log "Requirements installation completed successfully"
        else
            error_log "Requirements installation failed"
            rm -f "$temp_req_file"
            return 1
        fi
        
        rm -f "$temp_req_file"
    else
        log "No new requirements to install"
    fi
}

# Function to start the application
start_app() {
    if [ ! -f "$APP_SCRIPT" ]; then
        error_log "$APP_SCRIPT not found"
        return 1
    fi
    
    log "Starting web-server.py..."
    cd "$WORKSPACE"
    
    # Log separator for python application output
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Python Application Output ===" >> "$LOG_FILE"
    
    # ### MODIFIED ### Use 'python' directly from the activated Conda environment
    python "$APP_SCRIPT" >> "$LOG_FILE" 2>&1 &
    APP_PID=$!
    
    # Give it a moment to start and check if it's still running
    sleep 2
    if kill -0 "$APP_PID" 2>/dev/null; then
        log "Application started successfully with PID: $APP_PID"
        return 0
    else
        error_log "Application failed to start"
        APP_PID=""
        return 1
    fi
}

# Function to stop the application gracefully
stop_app() {
    if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
        log "Stopping application (PID: $APP_PID)..."
        
        # Try graceful shutdown first
        kill -TERM "$APP_PID" 2>/dev/null || true
        
        # Wait up to 10 seconds for graceful shutdown
        local count=0
        while [ $count -lt 10 ] && kill -0 "$APP_PID" 2>/dev/null; do
            sleep 1
            count=$((count + 1))
        done
        
        # Force kill if still running
        if kill -0 "$APP_PID" 2>/dev/null; then
            warn_log "Forcefully killing application"
            kill -KILL "$APP_PID" 2>/dev/null || true
        fi
        
        wait "$APP_PID" 2>/dev/null || true
        APP_PID=""
        
        # Log separator when application stops
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] === Python Application Stopped ===" >> "$LOG_FILE"
        log "Application stopped"
    fi
}

# Function to check if app is running
is_app_running() {
    [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null
}

# Function to check for git updates
check_git_updates() {
    cd "$WORKSPACE"
    
    # Fetch latest changes and log output
    if ! git fetch origin --quiet >> "$LOG_FILE" 2>&1; then
        warn_log "Failed to fetch from remote repository"
        return 1
    fi
    
    local current_commit
    current_commit=$(git rev-parse HEAD)
    
    local remote_commit
    remote_commit=$(git rev-parse origin/$(git rev-parse --abbrev-ref HEAD))
    
    if [ "$current_commit" != "$remote_commit" ]; then
        log "Updates detected: ${current_commit:0:8} -> ${remote_commit:0:8}"
        return 0  # Updates available
    else
        return 1  # No updates
    fi
}

# Function to update repository
update_repo() {
    cd "$WORKSPACE"
    log "Pulling latest changes..."
    
    if git pull origin --quiet >> "$LOG_FILE" 2>&1; then
        LAST_COMMIT=$(git rev-parse HEAD)
        log "Repository updated successfully. New commit: ${LAST_COMMIT:0:8}"
        return 0
    else
        error_log "Failed to pull updates"
        return 1
    fi
}

# Cleanup function
cleanup() {
    log "Received shutdown signal, cleaning up..."
    stop_app
    log "Cleanup completed, exiting"
    exit 0
}

# Set up signal handlers for graceful shutdown
trap cleanup SIGTERM SIGINT SIGQUIT

# Function to restart application
restart_app() {
    log "Restarting application..."
    stop_app
    if start_app; then
        log "Application restarted successfully"
    else
        error_log "Failed to restart application"
        return 1
    fi
}

# Main execution function
main() {
    # ### MODIFIED ### Updated log message for clarity
    log "Starting deployment script..."
    log "Repository: $WORKFLOW_GIT_URL"
    log "Conda environment: $EXPECTED_CONDA_ENV_PATH"
    log "Workspace: $WORKSPACE"
    log "Provisioning directory: $PROVISIONING_DIR"
    log "Log file: $LOG_FILE"
    log "Installed requirements file: $INSTALLED_REQUIREMENTS_FILE"
    
    # Initial setup
    if ! clone_repo; then
        error_log "Failed to clone repository"
        exit 1
    fi
    
    if ! install_requirements; then
        error_log "Failed to install initial requirements"
        exit 1
    fi
    
    if ! start_app; then
        error_log "Failed to start initial application"
        exit 1
    fi
    
    log "Initial setup completed, starting monitoring loop..."
    
    # Main monitoring loop
    local check_counter=0
    local log_clean_counter=0
    while true; do
        # Check if app is still running, restart if crashed
        if ! is_app_running; then
            warn_log "Application crashed, restarting..."
            if ! start_app; then
                error_log "Failed to restart crashed application, will retry in 5 seconds"
                sleep 5
                continue
            fi
        fi
        
        # Check for git updates every second
        if check_git_updates; then
            log "Git updates found, updating application..."
            
            stop_app
            
            if update_repo && install_requirements && start_app; then
                log "Application updated and restarted successfully"
            else
                error_log "Failed to update application, will retry in 5 seconds"
                sleep 5
                continue
            fi
        fi
        
        # Clean logs every 60 seconds
        log_clean_counter=$((log_clean_counter + 1))
        if [ $((log_clean_counter % 60)) -eq 0 ]; then
            clean_logs
            log_clean_counter=0
        fi
        
        # Log status every 60 seconds
        check_counter=$((check_counter + 1))
        if [ $((check_counter % 60)) -eq 0 ]; then
            log "Application running normally (PID: $APP_PID, Commit: ${LAST_COMMIT:0:8})"
        fi
        
        sleep 1
    done
}

# Ensure we're not already running in workspace
if [ "$PWD" = "$WORKSPACE" ]; then
    cd /
fi

# Run main function
main "$@"
