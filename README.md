# Universal Web Server Setup Script

A comprehensive, interactive bash script for setting up web applications on Ubuntu/Debian servers with Apache2 or Nginx.

## Features

- **Web Server Support**: Apache2 or Nginx (auto-installs if missing)
- **Application Types**: Node.js, Python, PHP, Static files, or reverse proxy
- **SSL/TLS**: Let's Encrypt, self-signed, or existing certificates
- **Process Management**: PM2 for Node.js and Python applications
- **Git Integration**: Clone repositories during setup
- **Helper Scripts**: Auto-generated update, restart, logs, and status scripts

## Requirements

- Ubuntu 20.04/22.04/24.04 or Debian 10/11/12
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

## Interactive Prompts

The script will ask you to configure:

### 1. Web Server
```
Select Web Server:
  1) Apache2
  2) Nginx
```

### 2. Application Type
```
Select Application Type:
  1) Node.js (Next.js, Express, etc.)
  2) Python (FastAPI, Django, Flask)
  3) PHP (Laravel, WordPress, etc.)
  4) Static Files (HTML, CSS, JS)
  5) Reverse Proxy Only (app already running)
```

### 3. Domain Configuration
- Main domain (e.g., `example.com`)
- Include www subdomain (y/n)
- Additional subdomains (e.g., `api, admin`)

### 4. Application Directory
- Default: `/var/www/yourdomain.com`

### 5. Port Configuration
- For Node.js: default 3000
- For Python: default 8000
- Not needed for PHP/static

### 6. Git Repository (Optional)
- Repository URL
- Branch name (default: main)

### 7. SSL/TLS Configuration
```
SSL/TLS Configuration:
  1) Let's Encrypt (recommended for production)
  2) Self-signed certificate (for testing)
  3) No SSL (HTTP only)
  4) Existing certificate (provide paths)
```

### 8. Process Manager (Node.js/Python only)
- Use PM2 for process management
- Custom start command

## What Gets Installed

Depending on your choices:

| Component | Installed When |
|-----------|---------------|
| Apache2 | Selected as web server |
| Nginx | Selected as web server |
| Node.js 20 | App type is Node.js |
| Python 3 + venv | App type is Python |
| PHP + PHP-FPM | App type is PHP |
| PM2 | Process management enabled |
| Certbot | Let's Encrypt SSL selected |

## Generated Configuration

### Apache Virtual Host
- Reverse proxy with WebSocket support
- Security headers (X-Frame-Options, etc.)
- Gzip compression
- Static asset caching

### Nginx Server Block
- Reverse proxy with WebSocket support
- Security headers
- Gzip compression
- Static asset caching

### PM2 Ecosystem
- Auto-restart on crash
- Memory limit restart
- Log file configuration
- Startup script integration

## Helper Scripts

After setup, these scripts are created in your app directory:

| Script | Description |
|--------|-------------|
| `update.sh` | Pull latest code, install dependencies, rebuild, restart |
| `restart.sh` | Restart application and web server |
| `logs.sh` | View application and web server logs |
| `status.sh` | Check service status |

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

### Example 1: Next.js Application

```
Web Server: Nginx
App Type: Node.js
Domain: myapp.com (with www)
Directory: /var/www/myapp.com
Port: 3000
Git: https://github.com/user/myapp.git
SSL: Let's Encrypt
PM2: Yes
```

### Example 2: FastAPI Backend

```
Web Server: Apache2
App Type: Python
Domain: api.myapp.com
Directory: /var/www/api.myapp.com
Port: 8000
Git: https://github.com/user/myapi.git
SSL: Let's Encrypt
PM2: Yes (uvicorn app.main:app --host 127.0.0.1 --port 8000)
```

### Example 3: WordPress Site

```
Web Server: Apache2
App Type: PHP
Domain: blog.example.com (with www)
Directory: /var/www/blog.example.com
Document Root: public
SSL: Let's Encrypt
```

### Example 4: Static Website

```
Web Server: Nginx
App Type: Static
Domain: docs.example.com
Directory: /var/www/docs.example.com
SSL: Let's Encrypt
```

## Post-Setup Tasks

### For Python Applications
Create your `.env` file:
```bash
nano /var/www/yourdomain.com/.env
```

Run database migrations:
```bash
cd /var/www/yourdomain.com
source venv/bin/activate
alembic upgrade head
```

### For Node.js Applications
Configure environment:
```bash
nano /var/www/yourdomain.com/.env.local
```

### For PHP Applications
Set correct permissions:
```bash
chown -R www-data:www-data /var/www/yourdomain.com
chmod -R 755 /var/www/yourdomain.com
chmod -R 775 /var/www/yourdomain.com/storage  # Laravel
```

## Troubleshooting

### Check Web Server Status
```bash
# Apache
sudo systemctl status apache2
sudo apache2ctl configtest

# Nginx
sudo systemctl status nginx
sudo nginx -t
```

### Check Application Status
```bash
pm2 status
pm2 logs your-app-name
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

## Uninstall

To remove a site configuration:

```bash
# Apache
sudo a2dissite yourdomain.com.conf
sudo rm /etc/apache2/sites-available/yourdomain.com.conf
sudo systemctl reload apache2

# Nginx
sudo rm /etc/nginx/sites-enabled/yourdomain.com
sudo rm /etc/nginx/sites-available/yourdomain.com
sudo systemctl reload nginx

# PM2
pm2 delete your-app-name
pm2 save
```

## Security Recommendations

- [ ] Keep system packages updated: `sudo apt update && sudo apt upgrade`
- [ ] Configure firewall: `sudo ufw allow 'Nginx Full'` or `sudo ufw allow 'Apache Full'`
- [ ] Enable fail2ban: `sudo apt install fail2ban`
- [ ] Set up automated backups
- [ ] Use strong database passwords
- [ ] Keep SSL certificates valid (auto-renewed with Let's Encrypt)
- [ ] Review and restrict CORS settings
- [ ] Don't expose .env files publicly

## License

MIT License - Feel free to use and modify.

## Contributing

Contributions welcome! Please submit issues and pull requests.
