# Universal Web Server Setup Script v2.0

A comprehensive, production-ready bash script for setting up web applications on Ubuntu/Debian servers with Apache2 or Nginx.

## Features

### Core Features
- **Web Server Support**: Apache2 or Nginx (auto-installs if missing)
- **Application Types**: Node.js, Python, PHP, Static files, or reverse proxy
- **SSL/TLS**: Let's Encrypt (auto-renewal), self-signed, or existing certificates
- **Process Management**: PM2 or Systemd for Node.js and Python applications
- **Git Integration**: Clone repositories during setup

### New in v2.0
- **Database Setup**: Optional MySQL/MariaDB or PostgreSQL installation
- **UFW Firewall**: Automatic firewall configuration
- **Systemd Support**: Alternative to PM2 for process management
- **Improved Logging**: Full installation log at `/var/log/webserver-setup.log`
- **Automatic Backups**: Existing configs backed up before changes
- **Better Error Handling**: Graceful error recovery with detailed messages
- **Input Validation**: Domain, email, and URL validation
- **Configuration Summary**: Review before installation begins

## Requirements

- Ubuntu 20.04/22.04/24.04/25.04 or Debian 10/11/12
- Root or sudo access
- Domain name pointed to your server IP (for SSL)

## Quick Start

```bash
# Download the script
curl -O https://raw.githubusercontent.com/vutia-ent/webserver-setup/main/webserver-setup.sh

# Make executable
chmod +x webserver-setup.sh

# Run with sudo
sudo ./webserver-setup.sh
```

## Interactive Configuration

### 1. Web Server Selection
```
Select Web Server:
  1) Apache2  (feature-rich, .htaccess support)
  2) Nginx    (high performance, modern)
```

### 2. Application Type
```
Select Application Type:
  1) Node.js  (Next.js, Express, NestJS, etc.)
  2) Python   (FastAPI, Django, Flask)
  3) PHP      (Laravel, WordPress, Symfony)
  4) Static   (HTML, CSS, JS, React build)
  5) Proxy    (reverse proxy to existing app)
```

### 3. Domain Configuration
- Main domain with validation (e.g., `example.com`)
- Optional www subdomain
- Additional subdomains (comma-separated)

### 4. Application Settings
- Application directory (default: `/var/www/yourdomain.com`)
- Port configuration (Node.js: 3000, Python: 8000)
- Git repository URL and branch

### 5. Process Manager
```
Process Manager:
  1) PM2       (recommended, easy management)
  2) Systemd   (native, no extra dependencies)
  3) None      (manual process management)
```

### 6. Database Setup (Optional)
```
Database Setup (optional):
  1) MySQL/MariaDB
  2) PostgreSQL
  3) None (skip database setup)
```

### 7. Firewall Configuration
- UFW firewall setup with SSH and web server rules

### 8. SSL/TLS Configuration
```
SSL/TLS Configuration:
  1) Let's Encrypt  (free, auto-renewal, recommended)
  2) Self-signed    (for testing/development)
  3) No SSL         (HTTP only - not recommended)
  4) Existing cert  (provide certificate paths)
```

## What Gets Installed

| Component | Installed When |
|-----------|---------------|
| Apache2 | Selected as web server |
| Nginx | Selected as web server |
| Node.js 20.x | App type is Node.js |
| Python 3 + venv | App type is Python |
| PHP + PHP-FPM | App type is PHP |
| PM2 | PM2 selected as process manager |
| MySQL/MariaDB | Database option selected |
| PostgreSQL | Database option selected |
| UFW | Firewall option enabled |
| Certbot | Let's Encrypt SSL selected |

## Generated Configurations

### Apache2 Features
- Reverse proxy with WebSocket support
- Security headers (X-Content-Type-Options, X-Frame-Options, etc.)
- Gzip compression
- Static asset caching with expires
- HTTPS redirect

### Nginx Features
- Upstream backend with keepalive connections
- WebSocket support via proxy headers
- Security headers
- Gzip compression
- Static asset caching
- HTTP/2 support for SSL

### PM2 Ecosystem
- Cluster mode for Node.js (multi-instance)
- Auto-restart on crash
- Memory limit restart (1GB default)
- Log file configuration with timestamps
- Startup script integration

### Systemd Service
- Auto-restart on failure
- Log integration with journald
- Proper user isolation (www-data)

## Helper Scripts

After setup, these scripts are created in your app directory:

| Script | Description |
|--------|-------------|
| `update.sh` | Pull latest code, install dependencies, rebuild, restart |
| `restart.sh` | Restart application and web server |
| `logs.sh` | View application and web server logs |
| `status.sh` | Check all service statuses |

### Usage Examples

```bash
# Update application
sudo /var/www/example.com/update.sh

# View logs
/var/www/example.com/logs.sh

# Check status
/var/www/example.com/status.sh

# Restart services
sudo /var/www/example.com/restart.sh
```

## Examples

### Example 1: Next.js with PM2

```
Web Server: Nginx
App Type: Node.js
Domain: myapp.com (with www)
Port: 3000
Git: https://github.com/user/myapp.git
Process Manager: PM2
Database: None
Firewall: Yes
SSL: Let's Encrypt
```

### Example 2: FastAPI with Systemd

```
Web Server: Apache2
App Type: Python
Domain: api.myapp.com
Port: 8000
Git: https://github.com/user/myapi.git
Process Manager: Systemd
Database: PostgreSQL
Firewall: Yes
SSL: Let's Encrypt
```

### Example 3: Laravel with MySQL

```
Web Server: Nginx
App Type: PHP
Domain: blog.example.com
Document Root: public
Database: MySQL
Firewall: Yes
SSL: Let's Encrypt
```

### Example 4: Static Website

```
Web Server: Nginx
App Type: Static
Domain: docs.example.com
Firewall: Yes
SSL: Let's Encrypt
```

## Post-Setup Tasks

### For Python Applications
```bash
# Create .env file
nano /var/www/yourdomain.com/.env

# Run database migrations
cd /var/www/yourdomain.com
source venv/bin/activate
alembic upgrade head
```

### For Node.js Applications
```bash
# Configure environment
nano /var/www/yourdomain.com/.env.local
```

### For PHP Applications
```bash
# Set correct permissions (Laravel)
chown -R www-data:www-data /var/www/yourdomain.com
chmod -R 755 /var/www/yourdomain.com
chmod -R 775 /var/www/yourdomain.com/storage
```

### For MySQL/MariaDB
```bash
# Secure the installation
sudo mysql_secure_installation
```

## Troubleshooting

### Check Installation Log
```bash
cat /var/log/webserver-setup.log
```

### Web Server Status
```bash
# Apache
sudo systemctl status apache2
sudo apache2ctl configtest

# Nginx
sudo systemctl status nginx
sudo nginx -t
```

### Application Status
```bash
# PM2
pm2 status
pm2 logs your-app-name

# Systemd
systemctl status your-app-name
journalctl -u your-app-name -f
```

### View Error Logs
```bash
# Apache
sudo tail -f /var/log/apache2/yourdomain.com_error.log

# Nginx
sudo tail -f /var/log/nginx/yourdomain.com_error.log
```

### SSL Certificate Issues
```bash
# Check certificate status
sudo certbot certificates

# Renew certificates
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal
```

### Port Already in Use
```bash
# Find what's using the port
sudo lsof -i :3000
sudo netstat -tlnp | grep 3000

# Kill the process
sudo kill -9 <PID>
```

### Firewall Status
```bash
sudo ufw status verbose
```

## Uninstall

To remove a site configuration:

```bash
# Apache
sudo a2dissite yourdomain.com.conf
sudo rm /etc/apache2/sites-available/yourdomain.com.conf
sudo rm /etc/apache2/sites-available/yourdomain.com-ssl.conf
sudo systemctl reload apache2

# Nginx
sudo rm /etc/nginx/sites-enabled/yourdomain.com
sudo rm /etc/nginx/sites-available/yourdomain.com
sudo systemctl reload nginx

# PM2
pm2 delete your-app-name
pm2 save

# Systemd
sudo systemctl stop your-app-name
sudo systemctl disable your-app-name
sudo rm /etc/systemd/system/your-app-name.service
sudo systemctl daemon-reload
```

## Backups

The script automatically backs up existing configurations to:
```
/var/backups/webserver-setup/YYYYMMDD_HHMMSS/
```

## Security Features

### Automatic Security Headers
- X-Content-Type-Options: nosniff
- X-Frame-Options: SAMEORIGIN
- X-XSS-Protection: 1; mode=block
- Referrer-Policy: strict-origin-when-cross-origin
- Strict-Transport-Security (HSTS) for SSL

### Firewall Rules
- Default deny incoming
- Allow SSH (port 22)
- Allow HTTP (port 80)
- Allow HTTPS (port 443)

### Additional Recommendations
- [ ] Keep system packages updated: `sudo apt update && sudo apt upgrade`
- [ ] Enable fail2ban: `sudo apt install fail2ban`
- [ ] Set up automated backups
- [ ] Use strong database passwords
- [ ] Review and restrict CORS settings
- [ ] Don't expose .env files publicly

## Changelog

### v2.0.0
- Added Systemd as alternative to PM2
- Added database installation (MySQL/PostgreSQL)
- Added UFW firewall configuration
- Added comprehensive logging
- Added automatic backups
- Improved error handling
- Added input validation
- Added configuration summary before install
- Fixed package installation reliability
- Fixed PM2 Python configuration
- Improved SSL setup for existing certificates

### v1.0.0
- Initial release

## License

MIT License - Feel free to use and modify.

## Contributing

Contributions welcome! Please submit issues and pull requests at:
https://github.com/vutia-ent/webserver-setup
