#!/bin/bash
set -euo pipefail

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_progress() {
    echo -e "${CYAN}[PROGRESS]${NC} $1"
}

# Restart order: ch2 → ch3 → ch1
HOSTS=("ch2" "ch3" "ch1" "rh4" "rh2" "rh3" "rh1")

SUCCESSFUL_HOSTS=0
FAILED_HOSTS=0

# Function to abort on error
abort() {
    local msg="$1"
    print_error "$msg"
    echo ""
    echo -e "${CYAN}=====================================================================${NC}"
    echo -e "${CYAN}                              SUMMARY${NC}"
    echo -e "${CYAN}=====================================================================${NC}"
    print_error "Script aborted due to error on host: ${YELLOW}$HOST${NC}"
    print_info  "Successful hosts before abort: $SUCCESSFUL_HOSTS / ${#HOSTS[@]}"
    echo ""
    exit 1
}

print_info "Starting HAProxy restart on hosts: ${HOSTS[*]}"
echo ""

for i in "${!HOSTS[@]}"; do
    HOST="${HOSTS[i]}"
    HOST_NUM=$((i + 1))

    echo -e "${CYAN}=====================================================================${NC}"
    print_progress "[$HOST_NUM/${#HOSTS[@]}] Restarting HAProxy on: ${YELLOW}$HOST${NC}"
    echo -e "${CYAN}=====================================================================${NC}"

    # Check SSH connection
    print_info "Checking connection to $HOST..."
    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$HOST" "true" 2>/dev/null; then
        ((FAILED_HOSTS++))
        abort "No SSH connection to $HOST – aborting script!"
    fi
    print_success "Connection to $HOST OK"

    # Restart HAProxy
    print_info "Restarting HAProxy on $HOST..."
    RESTART_OUTPUT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 "$HOST" \
        "systemctl restart haproxy 2>&1; echo EXIT_CODE:\$?" 2>/dev/null)
    RESTART_EXIT=$(echo "$RESTART_OUTPUT" | grep -oP '(?<=EXIT_CODE:)\d+')

    if [ "$RESTART_EXIT" = "0" ]; then
        print_success "HAProxy restarted successfully on $HOST"
    else
        echo "$RESTART_OUTPUT" | grep -v 'EXIT_CODE:' | while read -r line; do
            print_error "  > $line"
        done
        (( FAILED_HOSTS++ )) || true
        abort "HAProxy restart failed on $HOST (exit code: $RESTART_EXIT) – aborting script!"
    fi

    # Verify HAProxy status after restart
    print_info "Checking HAProxy status on $HOST..."
    STATUS_OUTPUT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$HOST" \
        "systemctl is-active haproxy" 2>/dev/null)

    if [ "$STATUS_OUTPUT" = "active" ]; then
        print_success "HAProxy is running correctly on $HOST (status: active)"
        (( SUCCESSFUL_HOSTS++ )) || true
    else
        (( FAILED_HOSTS++ )) || true
        abort "HAProxy on $HOST has status: '$STATUS_OUTPUT' (expected: active) – aborting script!"
    fi

    echo ""
done

# Summary
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${CYAN}                              SUMMARY${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ $SUCCESSFUL_HOSTS -eq ${#HOSTS[@]} ]; then
    print_success "HAProxy restarted successfully on all hosts!"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_success "Successful hosts: $SUCCESSFUL_HOSTS"
elif [ $SUCCESSFUL_HOSTS -gt 0 ]; then
    print_warning "Restart completed with errors"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_success "Successful hosts: $SUCCESSFUL_HOSTS"
    print_error "Failed hosts: $FAILED_HOSTS"
else
    print_error "Failed to restart HAProxy on any host!"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_error "Failed hosts: $FAILED_HOSTS"
    exit 1
fi

echo ""
print_info "Script finished."
