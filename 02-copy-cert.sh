#!/bin/bash

# Get script directory to work with relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="/var/jenkins/_workdir/cert"

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

# List of hosts - order as defined in the array
HOSTS=("ch2" "ch3" "ch1" "rh4" "rh2" "rh3" "rh1")

# Check if certificate directory exists
if [ ! -d "$CERT_DIR" ]; then
    print_error "Certificate directory $CERT_DIR does not exist!"
    exit 1
fi

# Check if haproxy.pem file exists
if [ ! -f "$CERT_DIR/haproxy.pem" ]; then
    print_error "File $CERT_DIR/haproxy.pem not found!"
    exit 1
fi

print_info "Starting certificate copy to ${#HOSTS[@]} hosts..."
print_info "Source file: $CERT_DIR/haproxy.pem"
echo ""

SUCCESSFUL_HOSTS=0
FAILED_HOSTS=0

for i in "${!HOSTS[@]}"; do
    HOST="${HOSTS[i]}"
    HOST_NUM=$((i + 1))
    
    echo -e "${CYAN}=====================================================================${NC}"
    print_progress "[$HOST_NUM/${#HOSTS[@]}] Processing host: ${YELLOW}$HOST${NC}"
    echo -e "${CYAN}=====================================================================${NC}"

    # Create directories on target machine
    print_info "Creating directories /etc/haproxy/certs/ and /etc/haproxy/backup/ on $HOST..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$HOST" \
        "mkdir -p /etc/haproxy/certs/ /etc/haproxy/backup/" 2>/dev/null; then
        print_success "Directories created / already exist"
    else
        print_error "Cannot create directories on $HOST"
        ((FAILED_HOSTS++))
        echo ""
        continue
    fi

    # Backup existing certificates before overwriting
    print_info "Creating backup of existing certificates on $HOST..."
    BACKUP_TS=$(date +%Y%m%d_%H%M%S)
    BACKUP_CMD=""
    BACKUP_CMD+="shopt -s nullglob; "
    BACKUP_CMD+="files=(/etc/haproxy/certs/*); "
    BACKUP_CMD+="if [ \${#files[@]} -gt 0 ]; then "
    BACKUP_CMD+="  cp -a /etc/haproxy/certs/. /etc/haproxy/backup/cert_${BACKUP_TS}/; "
    BACKUP_CMD+="  echo BACKED_UP; "
    BACKUP_CMD+="else "
    BACKUP_CMD+="  echo EMPTY; "
    BACKUP_CMD+="fi"
    BACKUP_RESULT=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$HOST" "bash -c '$BACKUP_CMD'" 2>/dev/null)
    if [ "$BACKUP_RESULT" = "BACKED_UP" ]; then
        print_success "Backup saved to /etc/haproxy/backup/cert_${BACKUP_TS}/ on $HOST"
    elif [ "$BACKUP_RESULT" = "EMPTY" ]; then
        print_warning "No existing certificates to back up on $HOST – skipping"
    else
        print_error "Failed to create backup on $HOST"
        ((FAILED_HOSTS++))
        echo ""
        continue
    fi

    # Copy haproxy.pem to /etc/haproxy/certs/
    print_info "Copying haproxy.pem to $HOST at /etc/haproxy/certs/ ..."
    if scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$CERT_DIR/haproxy.pem" "$HOST":/etc/haproxy/certs/haproxy.pem 2>/dev/null; then
        print_success "haproxy.pem copied successfully to $HOST"
        ((SUCCESSFUL_HOSTS++))

        # Verify copied file
        print_info "Verifying copied file..."
        if ssh -o StrictHostKeyChecking=no "$HOST" "[ -f /etc/haproxy/certs/haproxy.pem ]" 2>/dev/null; then
            print_success "Verification successful – haproxy.pem exists on $HOST"
        else
            print_warning "Verification failed – please check the file manually"
        fi
    else
        print_error "Failed to copy certificates to $HOST"
        ((FAILED_HOSTS++))
    fi

    echo ""
done

# Summary
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${CYAN}                               SUMMARY${NC}"
echo -e "${CYAN}=====================================================================${NC}"

if [ $SUCCESSFUL_HOSTS -eq ${#HOSTS[@]} ]; then
    print_success "All certificates copied successfully!"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_success "Successful hosts: $SUCCESSFUL_HOSTS"
elif [ $SUCCESSFUL_HOSTS -gt 0 ]; then
    print_warning "Copy completed with errors"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_success "Successful hosts: $SUCCESSFUL_HOSTS"
    print_error "Failed hosts: $FAILED_HOSTS"
else
    print_error "Failed to copy certificates to any host!"
    print_info "Hosts processed: ${#HOSTS[@]}"
    print_error "Failed hosts: $FAILED_HOSTS"
    exit 1
fi

echo ""
print_info "Script finished."