#!/bin/bash

# Get script directory to work with relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Determine which certificate to check
CERT_PATH="${1:-$SCRIPT_DIR/cert/haproxy.pem}"

# Print help/usage if requested
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Script to verify SSL certificate details."
    echo ""
    echo "Usage: $0 [path_to_pem_file]"
    echo ""
    echo "Example:"
    echo "  $0                      # Checks the default cert/haproxy.pem file"
    echo "  $0 cert/fullchain.pem   # Checks a different certificate file"
    exit 0
fi

# Check if certificate file exists
if [ ! -f "$CERT_PATH" ]; then
    echo -e "${RED}[ERROR]${NC} Certificate file does not exist: $CERT_PATH"
    exit 1
fi

# Check if file is readable
if [ ! -r "$CERT_PATH" ]; then
    echo -e "${RED}[ERROR]${NC} No read permission for file: $CERT_PATH"
    echo -e "${YELLOW}[TIP]${NC} Try running the script with root privileges: ${GREEN}sudo $0${NC}"
    exit 1
fi

# Print header
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${BLUE}             SSL CERTIFICATE DETAILS${NC}"
echo -e "${CYAN}=====================================================================${NC}"
echo -e "${BLUE}File location:${NC}  $CERT_PATH"
echo ""

# Extract information using openssl
SUBJECT_CN=$(openssl x509 -noout -subject -in "$CERT_PATH" 2>/dev/null | sed -e 's/^subject=//' -e 's/^.*CN[[:space:]]*=[[:space:]]*//' -e 's/,.*//' | xargs)
ISSUER=$(openssl x509 -noout -issuer -in "$CERT_PATH" 2>/dev/null | sed 's/^issuer=//' | sed 's/^ *//')
SERIAL=$(openssl x509 -noout -serial -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)

START_DATE=$(openssl x509 -noout -startdate -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
END_DATE=$(openssl x509 -noout -enddate -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)

# Calculate days remaining
expiry_timestamp=$(date -d "$END_DATE" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$END_DATE" +%s 2>/dev/null)
current_timestamp=$(date +%s)

if [ -n "$expiry_timestamp" ]; then
    days_left=$(( (expiry_timestamp - current_timestamp) / 86400 ))
else
    days_left="Unknown"
fi

# Subject Alternative Names (SANs)
SANS_LINE=$(openssl x509 -noout -ext subjectAltName -in "$CERT_PATH" 2>/dev/null | grep -v "Subject Alternative Name" | xargs)

# Display Basic Info
echo -e "${CYAN}[BASIC INFORMATION]${NC}"
echo -e "  ${BLUE}Common Name (CN):${NC}      ${GREEN}$SUBJECT_CN${NC}"
echo -e "  ${BLUE}Issuer:${NC}                $ISSUER"
echo -e "  ${BLUE}Serial Number:${NC}         $SERIAL"
echo -e "  ${BLUE}SHA256 Fingerprint:${NC}    $FINGERPRINT"
echo ""

# Display Validity Info
echo -e "${CYAN}[VALIDITY PERIOD]${NC}"
echo -e "  ${BLUE}Not Before:${NC}            $START_DATE"
echo -e "  ${BLUE}Not After:${NC}             $END_DATE"

if [ "$days_left" != "Unknown" ]; then
    if [ "$days_left" -lt 0 ]; then
        days_ago=$(( -days_left ))
        echo -e "  ${BLUE}Days remaining:${NC}        ${RED}EXPIRED (${days_ago} days ago)${NC}"
    elif [ "$days_left" -lt 30 ]; then
        echo -e "  ${BLUE}Days remaining:${NC}        ${YELLOW}$days_left (Expiring soon!)${NC}"
    else
        echo -e "  ${BLUE}Days remaining:${NC}        ${GREEN}$days_left (Valid)${NC}"
    fi
else
    echo -e "  ${BLUE}Days remaining:${NC}        ${YELLOW}Unknown validity status${NC}"
fi
echo ""

# Display SANs
echo -e "${CYAN}[SUBJECT ALTERNATIVE NAMES (SAN)]${NC}"
if [ -n "$SANS_LINE" ]; then
    # Format and indent each SAN
    echo "$SANS_LINE" | tr ',' '\n' | sed 's/^[[:space:]]*DNS://' | sed 's/^[[:space:]]*//' | while read -r san; do
        echo -e "  - $san"
    done
else
    echo -e "  - ${YELLOW}No Subject Alternative Names (SAN)${NC}"
fi

echo -e "${CYAN}=====================================================================${NC}"
