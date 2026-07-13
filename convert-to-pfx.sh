#!/bin/bash

# Get script directory to work with relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Functions for colored output
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

# Configuration
CERT_DIR="$SCRIPT_DIR/cert"
INPUT_FILE="$CERT_DIR/haproxy.pem"
OUTPUT_FILE="$CERT_DIR/haproxy.pfx"
# No default password -- must be supplied via -p / --password
DEFAULT_PASSWORD=""
# Friendly name embedded in the PFX; override with -n / --name if needed
PFX_NAME="haproxy-certificate"

# Display help
show_help() {
    echo "Convert haproxy.pem to PFX (PKCS#12) format"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -p, --password PASSWORD    Password for the PFX file (required)"
    echo "  -o, --output FILE          Output file path (default: $OUTPUT_FILE)"
    echo "  -i, --input FILE           Input file path  (default: $INPUT_FILE)"
    echo "  -n, --name NAME            Friendly name embedded in PFX (default: $PFX_NAME)"
    echo "  -h, --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -p mypassword"
    echo "  $0 -p mypassword -o /tmp/cert.pfx"
    echo "  $0 -p mypassword -i /path/to/haproxy.pem -o /path/to/output.pfx"
}

# Parse arguments
PASSWORD="$DEFAULT_PASSWORD"

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -i|--input)
            INPUT_FILE="$2"
            shift 2
            ;;
        -n|--name)
            PFX_NAME="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main conversion function
convert_to_pfx() {
    echo -e "${CYAN}=====================================================================${NC}"
    echo -e "${CYAN}                 CERTIFICATE CONVERSION TO PFX FORMAT${NC}"
    echo -e "${CYAN}=====================================================================${NC}"

    print_info "Conversion date : $(date '+%Y-%m-%d %H:%M:%S')"
    print_info "Input file      : $INPUT_FILE"
    print_info "Output file     : $OUTPUT_FILE"
    print_info "Friendly name   : $PFX_NAME"
    echo ""

    # Validate password
    if [ -z "$PASSWORD" ]; then
        print_error "A password is required. Use -p <password> to specify one."
        show_help
        exit 1
    fi

    # Check input file exists
    if [ ! -f "$INPUT_FILE" ]; then
        print_error "Input file not found: $INPUT_FILE"
        exit 1
    fi

    print_success "Input file found"

    # Validate input file structure
    print_info "Validating input file structure..."

    local cert_count
    cert_count=$(grep -c "BEGIN CERTIFICATE" "$INPUT_FILE" 2>/dev/null || echo 0)
    local key_count
    key_count=$(grep -c "BEGIN.*PRIVATE KEY" "$INPUT_FILE" 2>/dev/null || echo 0)

    print_info "Certificates found : $cert_count"
    print_info "Private keys found : $key_count"

    if [ "$cert_count" -eq 0 ]; then
        print_error "No certificates found in the input file!"
        exit 1
    fi

    if [ "$key_count" -eq 0 ]; then
        print_error "No private key found in the input file!"
        print_warning "haproxy.pem must contain: certificate + chain + private key"
        exit 1
    fi

    print_success "Input file structure is valid"

    # Check OpenSSL availability
    if ! command -v openssl &> /dev/null; then
        print_error "OpenSSL is not installed!"
        print_info "Attempting to install OpenSSL..."
        if ! apt-get update && apt-get install -y openssl; then
            print_error "Failed to install OpenSSL"
            exit 1
        fi
        print_success "OpenSSL installed successfully"
    fi

    # Print OpenSSL version
    local openssl_version
    openssl_version=$(openssl version 2>/dev/null)
    print_info "OpenSSL version: $openssl_version"

    # Back up existing output file if present
    if [ -f "$OUTPUT_FILE" ]; then
        local backup_file="${OUTPUT_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        print_warning "Output file already exists -- creating backup: $(basename "$backup_file")"
        cp "$OUTPUT_FILE" "$backup_file"
        print_success "Backup created"
    fi

    # Perform the conversion
    print_progress "Starting conversion to PFX format..."

    if openssl pkcs12 -export \
        -in "$INPUT_FILE" \
        -out "$OUTPUT_FILE" \
        -passout "pass:$PASSWORD" \
        -name "$PFX_NAME" 2>/dev/null; then

        print_success "Conversion completed successfully!"

        # Verify the generated file
        print_info "Verifying the generated PFX file..."

        if [ -f "$OUTPUT_FILE" ]; then
            local file_size
            file_size=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)
            print_success "PFX file created: $(basename "$OUTPUT_FILE") (${file_size} bytes)"

            # Verify PFX structure
            if openssl pkcs12 -in "$OUTPUT_FILE" -passin "pass:$PASSWORD" -nokeys -noout 2>/dev/null; then
                print_success "PFX structure verification passed"

                # Display certificate information
                print_info "Certificate details:"
                local cert_info
                cert_info=$(openssl pkcs12 -in "$OUTPUT_FILE" -passin "pass:$PASSWORD" -nokeys 2>/dev/null \
                    | openssl x509 -subject -dates -noout 2>/dev/null)
                if [ -n "$cert_info" ]; then
                    echo -e "${YELLOW}$cert_info${NC}"
                fi
            else
                print_warning "Could not verify PFX structure (possible wrong password)"
            fi
        else
            print_error "PFX file was not created!"
            return 1
        fi

    else
        print_error "Conversion failed!"
        print_warning "Ensure the input file contains a valid certificate and private key"
        return 1
    fi
}

# Display summary
show_summary() {
    echo ""
    echo -e "${CYAN}=====================================================================${NC}"
    echo -e "${CYAN}                              SUMMARY${NC}"
    echo -e "${CYAN}=====================================================================${NC}"

    print_info "PFX file    : $OUTPUT_FILE"
    print_info "Created at  : $(date '+%Y-%m-%d %H:%M:%S')"

    if [ -f "$OUTPUT_FILE" ]; then
        local file_size
        file_size=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null)
        print_success "File size   : $file_size bytes"
        print_info "Permissions : $(stat -c%a "$OUTPUT_FILE" 2>/dev/null)"

        # Set secure permissions
        chmod 600 "$OUTPUT_FILE"
        print_success "Secure permissions applied (600)"
    fi

    echo ""
    print_info "The PFX file can now be used in applications that require PKCS#12 format."
    print_warning "Keep the PFX password in a secure location (e.g., a secrets manager)."

    echo ""
    print_info "Usage examples:"
    echo -e "${YELLOW}  # Import into Windows Certificate Store:${NC}"
    echo -e "${YELLOW}  certlm.msc -> Import certificate -> Select the PFX file${NC}"
    echo ""
    echo -e "${YELLOW}  # Verify PFX contents:${NC}"
    echo -e "${YELLOW}  openssl pkcs12 -in $(basename "$OUTPUT_FILE") -info -noout${NC}"
}

# Check permissions
if [ "$EUID" -ne 0 ] && [ ! -r "$INPUT_FILE" ]; then
    print_warning "Root access may be required to read certificate files"
fi

# Run conversion
if convert_to_pfx; then
    show_summary
    print_success "All done!"
else
    print_error "Conversion failed!"
    exit 1
fi
