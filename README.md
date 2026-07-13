# Let's Encrypt SSL Certificate Management

This repository contains scripts for automated SSL certificate management using Let's Encrypt with Cloudflare DNS challenge.

## 🚀 Features

All scripts work **independently of the current directory** and use **relative paths** to the script location. You can run them from anywhere on the system.

## 📁 Project Structure

```
certbot/
├── cert/                    # Certificate files directory
│   ├── cert.pem            # End entity certificate
│   ├── chain.pem           # Intermediate CA certificate
│   ├── fullchain.pem       # Full certificate chain
│   ├── privkey.pem         # Private key
│   ├── haproxy.pem         # Combined cert+key for HAProxy
│   └── haproxy.pfx         # PFX format for Windows/IIS
├── cloudflare.ini          # Cloudflare API credentials
├── domains.conf            # List of domains to include
├── setup-letsencrypt.sh    # Initial setup script
├── letsencrypt-renewal.sh  # Main renewal script
├── copy-cert.sh            # Distribute certificates to servers
├── update-cert.sh          # Update certificates on remote hosts
├── check-cert.sh           # Analyze certificate properties
├── convert-to-pfx.sh       # Convert to PFX format
└── README.md               # This file
```

## 📋 Script Descriptions

### 🔧 setup-letsencrypt.sh
Initial setup script that installs required packages and configures the environment.

**Features:**
- Installs certbot and required packages
- Creates certificate directory
- Sets proper permissions
- Configures automatic renewal cron job

**Usage:**
```bash
# Run from any directory
sudo /path/to/certbot/setup-letsencrypt.sh
```

### 🔄 letsencrypt-renewal.sh
Main certificate renewal script with Cloudflare DNS challenge.

**Features:**
- Automatic certificate renewal based on expiry date
- Force renewal option
- Cloudflare DNS challenge
- Certificate chain creation
- Directory cleanup

**Usage:**
```bash
# Normal renewal (only if needed)
/path/to/certbot/letsencrypt-renewal.sh

# Force renewal regardless of expiry
/path/to/certbot/letsencrypt-renewal.sh --force

# Show help
/path/to/certbot/letsencrypt-renewal.sh --help
```

### 📦 copy-cert.sh
Distributes certificates to multiple remote servers.

**Features:**
- Colored output with progress tracking
- Verification of copied files
- Detailed statistics and error reporting
- SSH connection testing

**Usage:**
```bash
# Copy certificates to all configured hosts
/path/to/certbot/copy-cert.sh
```

### 🔄 update-cert.sh
Updates certificates on remote hosts with host-specific commands.

**Features:**
- Different commands for different host types
- Docker Swarm, OCI HAProxy, Azure HAProxy support
- Verification of updates
- Comprehensive error handling

**Usage:**
```bash
# Update certificates on all configured hosts
/path/to/certbot/update-cert.sh
```

### 🔍 check-cert.sh
Comprehensive certificate analysis tool.

**Features:**
- Certificate identity information
- Validity period analysis
- Subject Alternative Names (SAN)
- Key information and algorithms
- Certificate extensions
- Chain verification
- Remote certificate checking
- Colored output with warnings

**Usage:**
```bash
# Check default certificate
/path/to/certbot/check-cert.sh

# Check specific file
/path/to/certbot/check-cert.sh -f /path/to/cert.pem

# Check all certificates
/path/to/certbot/check-cert.sh -a

# Check remote certificate
/path/to/certbot/check-cert.sh -r domain.com:443

# Verbose mode
/path/to/certbot/check-cert.sh --verbose
```

### 🔐 convert-to-pfx.sh
Converts certificates to PFX format for Windows/IIS.

**Features:**
- Converts HAProxy PEM to PFX format
- Customizable password
- File verification
- Secure permissions

**Usage:**
```bash
# Convert with default settings
/path/to/certbot/convert-to-pfx.sh

# Convert with custom password
/path/to/certbot/convert-to-pfx.sh -p mypassword

# Convert with custom output file
/path/to/certbot/convert-to-pfx.sh -o /path/to/output.pfx -p mypassword
```

## ⚙️ Configuration

### cloudflare.ini
Configure your Cloudflare API credentials:
```ini
dns_cloudflare_api_token = your_cloudflare_api_token_here
```

### domains.conf
List all domains to include in the certificate:
```
domain.com
*.domain.com
subdomain.domain.com
```

## 🔧 Installation & Setup

1. **Clone or download** the certbot directory to your server
2. **Edit configuration files:**
   - `cloudflare.ini` - Add your Cloudflare API token
   - `domains.conf` - Add your domains
3. **Run setup script:**
   ```bash
   sudo /path/to/certbot/setup-letsencrypt.sh
   ```
4. **Test certificate generation:**
   ```bash
   /path/to/certbot/letsencrypt-renewal.sh --force
   ```

## 🚀 Workflow Example

```bash
# 1. Generate/renew certificates
/path/to/certbot/letsencrypt-renewal.sh --force

# 2. Copy certificates to remote hosts
/path/to/certbot/copy-cert.sh

# 3. Update certificates on remote hosts
/path/to/certbot/update-cert.sh

# 4. Verify certificate properties
/path/to/certbot/check-cert.sh

# 5. Convert to PFX if needed
/path/to/certbot/convert-to-pfx.sh
```

## 📅 Automatic Renewal

The setup script creates a cron job that runs every Sunday at 2 AM:
```
0 2 * * 0 /path/to/certbot/letsencrypt-renewal.sh >> /var/log/letsencrypt-renewal.log 2>&1
```

## 🔍 Monitoring & Logs

- **Renewal logs:** `/var/log/letsencrypt-renewal.log`
- **Certbot logs:** `/var/log/letsencrypt/letsencrypt.log`
- **Script outputs:** Colored console output with timestamps

## 🎯 Key Features

✅ **Portable** - All scripts work from any directory  
✅ **Relative paths** - No hardcoded absolute paths  
✅ **Colored output** - Easy to read console output  
✅ **Error handling** - Comprehensive error checking  
✅ **Progress tracking** - Real-time progress information  
✅ **Verification** - Built-in verification steps  
✅ **Flexible** - Configurable parameters and options  
✅ **Secure** - Proper file permissions and secure defaults

## 🔧 Host Configuration

### copy-cert.sh & update-cert.sh
These scripts are configured for the following hosts:
- `az-haproxy-1`, `az-haproxy-2` (Azure HAProxy servers)
- `oci-haproxy-1`, `oci-haproxy-2` (OCI HAProxy servers)  
- `dmaster1`, `dmaster2`, `dmaster3` (Docker Swarm masters)
- `dworker1`, `dworker2`, `dworker3` (Docker Swarm workers)

Edit the `HOSTS` array in these scripts to match your infrastructure.

## 🚨 Important Notes

- All scripts must be run as root or with appropriate sudo privileges
- Ensure SSH key authentication is set up for remote hosts
- The `cert/` directory will be created automatically
- Certificate files are automatically set to 600 permissions for security
- The setup script will install required packages automatically