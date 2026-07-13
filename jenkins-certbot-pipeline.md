# Jenkins Pipeline — Let's Encrypt Certificate Renewal for HAProxy

## Overview

This document describes the setup of a Jenkins declarative pipeline that automates:
1. SSL certificate renewal via Certbot (Cloudflare DNS challenge)
2. Distributing the new certificate to all HAProxy hosts
3. Restarting HAProxy on each host and verifying its status

---

## Repository Structure

```
/var/jenkins/_workdir/
├── 01-letsencrypt-renewal.sh   # Certbot renewal via Cloudflare DNS
├── 02-copy-cert.sh             # SCP haproxy.pem to all target hosts
├── 03-restart-haproxy.sh       # Restart & verify HAProxy on all hosts
├── Jenkinsfile                 # Pipeline definition
├── cert/                       # Output directory for generated certificates
│   └── haproxy.pem             # Combined cert+key file for HAProxy
├── cloudflare.ini              # Cloudflare API token (credentials)
└── domains.conf                # List of domains for the certificate
```

---

## Scripts

### `01-letsencrypt-renewal.sh`
- Uses Certbot with `--dns-cloudflare` plugin
- Reads domains from `domains.conf`
- Accepts `--force` / `-f` flag to force renewal regardless of expiry
- Copies generated certs to `./cert/` directory, creates `haproxy.pem` (fullchain + privkey)
- Requires **root** privileges

### `02-copy-cert.sh`
- Reads `haproxy.pem` from `/var/jenkins/_workdir/cert/`
- Connects via SSH/SCP to hosts: `ch2 ch3 ch1 rh4 rh2 rh3 rh1`
- Creates backup of existing certs on each host before overwriting
- Exits with code `1` if **all** hosts fail; partial failures produce a warning
- Requires SSH access with keys from `/root/.ssh/`

### `03-restart-haproxy.sh`
- Connects via SSH to each host in order: `ch2 ch3 ch1 rh4 rh2 rh3 rh1`
- Runs `systemctl restart haproxy` and verifies `systemctl is-active haproxy`
- Uses internal `abort()` function — **stops immediately** on first failed host
- Has `set -euo pipefail` — any unexpected error terminates the script

---

## Jenkinsfile

```groovy
pipeline {
    agent { label '0.240' }

    options {
        timestamps()
    }

    stages {

        stage('01 - Let\'s Encrypt Certificate Renewal') {
            steps {
                sh '''
                    set -e
                    sudo -H bash /var/jenkins/_workdir/01-letsencrypt-renewal.sh --force
                '''
            }
        }

        stage('02 - Copy Certificate to Hosts') {
            steps {
                sh '''
                    set -e
                    sudo -H bash /var/jenkins/_workdir/02-copy-cert.sh
                '''
            }
        }

        stage('03 - Restart HAProxy') {
            steps {
                sh '''
                    set -e
                    sudo -H bash /var/jenkins/_workdir/03-restart-haproxy.sh
                '''
            }
        }

    }

    post {
        success {
            echo 'All stages completed successfully. Certificate renewed and HAProxy restarted.'
        }
        failure {
            echo 'Pipeline failed. Check the logs above.'
        }
    }
}
```

### Pipeline Design Decisions

| Setting | Value | Reason |
|---|---|---|
| `agent` | `label '0.240'` | Run only on the specific agent that has SSH access to all hosts |
| `sudo -H bash` | on every step | Scripts require root; `-H` sets `HOME=/root` so SSH uses `/root/.ssh/` |
| `set -e` | in every `sh` block | Pipeline aborts immediately on any non-zero exit code |
| `ansiColor` | **removed** | Plugin not installed on this Jenkins instance |
| `timestamps()` | enabled | Adds timestamps to every log line |

---

## Changes Made During Setup

### Step 1 — Created `Jenkinsfile`
Initial version with `agent any`, three stages, ANSI color support.

### Step 2 — Changed agent label
```diff
-    agent any
+    agent { label '0.240' }
```

### Step 3 — Removed `ansiColor` option
Jenkins compilation error: `ansiColor` is not a valid option without the AnsiColor plugin.
```diff
     options {
-        // stop pipeline on error
         timestamps()
-        ansiColor('xterm')
     }
```

### Step 4 — Added `sudo -H bash`
Scripts failed with `ERROR: This script must be run as root`.
Changed every `bash` call to `sudo -H bash`.

### Step 5 — Fixed sudoers configuration
`sudo` still asked for a password because the sudoers rule matched the script path directly,
not the actual command (`/bin/bash`). See [sudoers-and-sudo-H.md](./sudoers-and-sudo-H.md) for details.

### Step 6 — Updated `CERT_DIR` in `02-copy-cert.sh`
```diff
-CERT_DIR="/root/certbot/cert"
+CERT_DIR="/var/jenkins/_workdir/cert"
```
Certificate is generated into the Jenkins workdir, not `/root/certbot/cert`.

---

## Prerequisites Checklist

- [ ] SSH keys and `/root/.ssh/config` configured for all target hosts
- [ ] `/var/jenkins/_workdir/cloudflare.ini` present with a valid Cloudflare API token
- [ ] `/var/jenkins/_workdir/domains.conf` present with the list of domains
- [ ] Certbot installed: `apt install certbot python3-certbot-dns-cloudflare`
- [ ] Jenkins agent runs as user `jenkins`
- [ ] `/etc/sudoers.d/jenkins-certbot` configured (see [sudoers-and-sudo-H.md](./sudoers-and-sudo-H.md))

---

## Flow Diagram

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
