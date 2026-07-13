# Let's Encrypt SSL Certificate Management

Automated SSL certificate renewal pipeline using Let's Encrypt with Cloudflare DNS challenge,
distributed to HAProxy hosts via Jenkins.

## 📁 Repository Structure

```
certbot/
├── 01-letsencrypt-renewal.sh   # Certbot renewal via Cloudflare DNS challenge
├── 02-copy-cert.sh             # SCP haproxy.pem to all target HAProxy hosts
├── 03-restart-haproxy.sh       # Restart & verify HAProxy on all hosts
├── convert-to-pfx.sh           # Convert haproxy.pem to PFX (PKCS#12) format
├── setup-letsencrypt.sh        # One-time setup: installs packages, cron job
├── cloudflare.ini              # Cloudflare API credentials (not committed)
├── domains.conf                # List of domains for the certificate
├── Jenkinsfile                 # Jenkins declarative pipeline definition
├── jenkins-certbot-pipeline.md # Jenkins pipeline setup guide & troubleshooting log
└── README.md                   # This file
```

> **Note:** Generated certificate files are stored in a `cert/` subdirectory
> (created automatically by `01-letsencrypt-renewal.sh`):
> `cert.pem`, `chain.pem`, `fullchain.pem`, `privkey.pem`, `haproxy.pem`

---

## 🚀 Jenkins Pipeline (Primary Workflow)

The repository is designed to run as a **Jenkins declarative pipeline** defined in [Jenkinsfile](./Jenkinsfile).

### Pipeline Stages

```
Jenkins Agent (label: 0.240)
│
├─ Stage 01: sudo -H bash 01-letsencrypt-renewal.sh --force
│            └─ Certbot (Cloudflare DNS) ──► /var/jenkins/_workdir/cert/haproxy.pem
│
├─ Stage 02: sudo -H bash 02-copy-cert.sh
│            └─ SCP haproxy.pem ──► ch2, ch3, ch1, rh4, rh2, rh3, rh1
│                                   /etc/haproxy/certs/haproxy.pem
│
└─ Stage 03: sudo -H bash 03-restart-haproxy.sh
             └─ SSH: systemctl restart haproxy
                     systemctl is-active haproxy  (must return "active")
```

### Pipeline Design

| Setting | Value | Reason |
|---|---|---|
| `agent` | `label '0.240'` | Must run on the specific agent with SSH access to all HAProxy hosts |
| `sudo -H bash` | every stage | Scripts require root; `-H` ensures SSH uses `/root/.ssh/` |
| `set -e` | every `sh` block | Pipeline aborts immediately on any non-zero exit code |
| `timestamps()` | enabled | Adds timestamps to every log line |

See [jenkins-certbot-pipeline.md](./jenkins-certbot-pipeline.md) for full setup guide, sudoers configuration, and troubleshooting history.

---

## 📋 Script Descriptions

### 🔧 setup-letsencrypt.sh

One-time setup script. Run this once to prepare the environment.

**What it does:**
- Installs `certbot`, `python3-certbot-dns-cloudflare`, `openssl`, `cron` via `apt-get`
- Creates the `cert/` output directory
- Sets permissions: `cloudflare.ini` → 600, `domains.conf` → 644
- Adds a weekly cron job (every Sunday at 2:00 AM) for automatic renewal

**Usage:**
```bash
sudo /var/jenkins/_workdir/setup-letsencrypt.sh
```

> **After running setup**, edit `cloudflare.ini` and `domains.conf`, then update
> `PRIMARY_DOMAIN` and `EMAIL` variables in `01-letsencrypt-renewal.sh`.

---

### 🔄 01-letsencrypt-renewal.sh

Main certificate renewal script using the Cloudflare DNS challenge.

**What it does:**
- Checks existing certificate validity (default threshold: 30 days before expiry)
- Skips renewal if the certificate is still valid (unless `--force` is used)
- Runs `certbot certonly --dns-cloudflare` with all domains from `domains.conf`
- Cleans old Let's Encrypt directories before forced renewal
- Copies resulting PEM files to `./cert/` and creates `haproxy.pem` (fullchain + privkey)
- Sets 600 permissions on all copied certificate files

**Usage:**
```bash
# Check expiry and renew only if needed
sudo /var/jenkins/_workdir/01-letsencrypt-renewal.sh

# Force renewal regardless of expiry date
sudo /var/jenkins/_workdir/01-letsencrypt-renewal.sh --force
sudo /var/jenkins/_workdir/01-letsencrypt-renewal.sh -f

# Show help
sudo /var/jenkins/_workdir/01-letsencrypt-renewal.sh --help
```

**Variables to configure** (at the top of the script):

| Variable | Description |
|---|---|
| `EMAIL` | ACME registration email |
| `PRIMARY_DOMAIN` | Primary domain (used for Let's Encrypt directory names) |
| `RENEWAL_THRESHOLD` | Days before expiry to trigger renewal (default: 30) |

---

### 📦 02-copy-cert.sh

Distributes `haproxy.pem` to all HAProxy hosts via SCP.

**What it does:**
- Reads `haproxy.pem` from `/var/jenkins/_workdir/cert/`
- Iterates over hosts: `ch2 ch3 ch1 rh4 rh2 rh3 rh1`
- Creates `/etc/haproxy/certs/` and `/etc/haproxy/backup/` on each host
- Backs up existing certificates before overwriting
- Copies `haproxy.pem` to `/etc/haproxy/certs/haproxy.pem` on each host
- Verifies the file exists after copy
- Reports per-host success/failure with a final summary
- Exits with code `1` only if **all** hosts fail; partial failures produce a warning

**Usage:**
```bash
sudo /var/jenkins/_workdir/02-copy-cert.sh
```

**Target hosts** (edit `HOSTS` array in the script to match your infrastructure):
```bash
HOSTS=("ch2" "ch3" "ch1" "rh4" "rh2" "rh3" "rh1")
```

---

### 🔄 03-restart-haproxy.sh

Restarts HAProxy on all hosts and verifies it is running after restart.

**What it does:**
- Iterates over hosts: `ch2 ch3 ch1 rh4 rh2 rh3 rh1`
- Tests SSH connectivity before attempting restart
- Runs `systemctl restart haproxy` via SSH
- Verifies the service is `active` with `systemctl is-active haproxy`
- **Aborts immediately** on the first failed host (no partial-failure mode)
- Uses `set -euo pipefail` for strict error handling

**Usage:**
```bash
sudo /var/jenkins/_workdir/03-restart-haproxy.sh
```

> ⚠️ This script uses an `abort()` function that terminates on the first failure.
> Ensure all hosts are reachable before running.

---

### 🔐 convert-to-pfx.sh

Converts `haproxy.pem` to PFX (PKCS#12) format for use with Windows/IIS.

**What it does:**
- Reads `cert/haproxy.pem` (fullchain + private key)
- Validates that the file contains both certificates and a private key (RSA and EC key types supported)
- Backs up an existing `haproxy.pfx` if present
- Converts using `openssl pkcs12 -export`
- Verifies the resulting PFX structure and prints certificate subject/validity dates
- Sets 600 permissions on the output file

**Usage:**
```bash
# Convert with a password (required)
/var/jenkins/_workdir/convert-to-pfx.sh -p mypassword

# Convert with custom input/output paths
/var/jenkins/_workdir/convert-to-pfx.sh -p mypassword -i /path/to/haproxy.pem -o /path/to/output.pfx

# Set a custom PFX friendly name
/var/jenkins/_workdir/convert-to-pfx.sh -p mypassword -n my-certificate

# Show help
/var/jenkins/_workdir/convert-to-pfx.sh --help
```

> ⚠️ The `-p` / `--password` flag is **required** — no default password is set.
> Store the PFX password in a secrets manager, not in plain text.

---

## ⚙️ Configuration Files

### cloudflare.ini

Cloudflare API credentials used by certbot. Two authentication methods are supported:

```ini
# Option 1: Global API Key (legacy)
dns_cloudflare_email = YOUR_EMAIL@example.com
dns_cloudflare_api_key = YOUR_GLOBAL_API_KEY_HERE

# Option 2: API Token (recommended)
# dns_cloudflare_api_token = YOUR_API_TOKEN_HERE
```

> ⚠️ This file **must** have restricted permissions: `chmod 600 cloudflare.ini`
> It must **never** be committed with real credentials.

### domains.conf

List of domains to include in the certificate (one per line, wildcards supported):

```
example.com
*.example.com
*.sub1.example.com
*.sub2.example.com
```

---

## 🔧 Initial Setup

1. **Clone the repository** to the Jenkins work directory:
   ```bash
   git clone <repo-url> /var/jenkins/_workdir
   ```

2. **Edit configuration files:**
   - `cloudflare.ini` — add your Cloudflare API credentials
   - `domains.conf` — add your domains
   - `01-letsencrypt-renewal.sh` — set `EMAIL` and `PRIMARY_DOMAIN`

3. **Run the setup script:**
   ```bash
   sudo /var/jenkins/_workdir/setup-letsencrypt.sh
   ```

4. **Configure sudoers** so the `jenkins` user can run scripts as root without a password.
   See [jenkins-certbot-pipeline.md](./jenkins-certbot-pipeline.md) for details.

5. **Configure SSH keys** so root has passwordless access to all target hosts:
   ```
   # /root/.ssh/config should have entries for: ch1, ch2, ch3, rh1, rh2, rh3, rh4
   ```

6. **Test certificate generation:**
   ```bash
   sudo /var/jenkins/_workdir/01-letsencrypt-renewal.sh --force
   ```

---

## 📅 Automatic Renewal (Cron)

The setup script creates a cron job for weekly renewal:
```
0 2 * * 0 /var/jenkins/_workdir/01-letsencrypt-renewal.sh >> /var/log/letsencrypt-renewal.log 2>&1
```

---

## 🔍 Monitoring & Logs

| Source | Location |
|---|---|
| Renewal script log | `/var/log/letsencrypt-renewal.log` |
| Certbot logs | `/var/log/letsencrypt/letsencrypt.log` |
| Certificate backups on hosts | `/etc/haproxy/backup/cert_<timestamp>/` |
| Jenkins pipeline output | Jenkins UI → Build → Console Output |

---

## 🎯 Key Features

✅ **Jenkins-native** — full pipeline automation via Jenkinsfile
✅ **Portable scripts** — all scripts resolve paths relative to their own location
✅ **Safe renewals** — certificate validity check prevents unnecessary renewals
✅ **Backup before overwrite** — existing certs are backed up on each host
✅ **Fail-fast restart** — HAProxy restart aborts on first failure to prevent partial states
✅ **Colored output** — clear, color-coded console output for all scripts
✅ **PFX export** — optional conversion to Windows-compatible PKCS#12 format

---

## 🚨 Prerequisites Checklist

- [ ] Jenkins agent with label `0.240` is running
- [ ] SSH keys configured under `/root/.ssh/` for all target hosts (`ch1`–`ch3`, `rh1`–`rh4`)
- [ ] `/var/jenkins/_workdir/cloudflare.ini` present with a valid Cloudflare API token
- [ ] `/var/jenkins/_workdir/domains.conf` present with the list of domains
- [ ] Certbot installed: `apt install certbot python3-certbot-dns-cloudflare`
- [ ] `/etc/sudoers.d/jenkins-certbot` configured for passwordless sudo
- [ ] HAProxy installed and running on all target hosts
