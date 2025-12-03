# Universal Web Server Setup Script v3.0

A comprehensive, production-ready bash script for setting up web applications on Ubuntu/Debian servers with Apache2 or Nginx. Now with full frontend framework support!

## Features

### Core Features
- **Web Server Support**: Apache2 or Nginx (auto-installs if missing)
- **SSL/TLS**: Let's Encrypt (auto-renewal), self-signed, or existing certificates
- **Process Management**: PM2 or Systemd for SSR applications
- **Git Integration**: Clone repositories during setup
- **Database Setup**: Optional MySQL/MariaDB or PostgreSQL installation
- **UFW Firewall**: Automatic firewall configuration

### Backend Support
- **Node.js**: Express, NestJS, Fastify, and more
- **Python**: FastAPI, Django, Flask
- **PHP**: Laravel, WordPress, Symfony

### Frontend Support (NEW in v3.0)
- **Next.js**: SSR, Static Export, and Standalone modes
- **Nuxt.js**: SSR, Static Generation, and SPA modes
- **React**: Vite and Create React App
- **Vue.js**: Vite and Vue CLI
- **Angular**: Angular CLI
- **Svelte/SvelteKit**: SSR, Static, and SPA modes

### Frontend-Specific Features
- **Package Manager Selection**: npm, pnpm, yarn, or bun
- **Node.js Version Selection**: 18, 20, or 22 LTS
- **Build-time Environment Variables**: Configure during setup
- **Optimized Caching**: Immutable hashes for assets, proper SPA routing
- **API URL Configuration**: Automatic environment setup for backend connections

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
  ── Backend ──
  1) Node.js  (Express, NestJS, Fastify, etc.)
  2) Python   (FastAPI, Django, Flask)
  3) PHP      (Laravel, WordPress, Symfony)
  ── Frontend ──
  4) Next.js  (React SSR/SSG framework)
  5) Nuxt.js  (Vue SSR/SSG framework)
  6) React    (SPA - Vite, CRA)
  7) Vue.js   (SPA - Vite, Vue CLI)
  8) Angular  (SPA - Angular CLI)
  9) Svelte   (SPA/SSR - SvelteKit)
  ── Other ──
  10) Static  (pre-built HTML, CSS, JS)
  11) Proxy   (reverse proxy to existing app)
```

### 3. Frontend Configuration (for frontend frameworks)

#### Deployment Mode
```
# Next.js
Next.js Deployment Mode:
  1) SSR        (Server-Side Rendering - needs Node.js server)
  2) Static     (Static Export - output: 'export' in next.config.js)
  3) Standalone (Self-contained server - output: 'standalone')

# Nuxt.js
Nuxt.js Deployment Mode:
  1) SSR        (Server-Side Rendering - universal mode)
  2) Static     (Static Generation - nuxt generate)
  3) SPA        (Single Page Application - ssr: false)

# Svelte
Svelte Deployment Mode:
  1) SvelteKit SSR    (Server-Side Rendering)
  2) SvelteKit Static (adapter-static)
  3) Svelte SPA       (Vite only, no SvelteKit)
```

#### Node.js Version
```
Node.js Version:
  1) Node.js 20 LTS (recommended)
  2) Node.js 22 LTS (latest LTS)
  3) Node.js 18 LTS (older LTS)
```

#### Package Manager
```
Package Manager:
  1) npm   (default)
  2) pnpm  (fast, efficient)
  3) yarn  (classic)
  4) bun   (fastest, all-in-one)
```

#### Environment Variables
- Configure build-time environment variables during setup
- Automatic API URL configuration for frontend-backend connections

### 4. Domain Configuration
- Main domain with validation (e.g., `example.com`)
- Optional www subdomain
- Additional subdomains (comma-separated)

### 5. Application Settings
- Application directory (default: `/var/www/yourdomain.com`)
- Port configuration (SSR apps: 3000)
- Git repository URL and branch

### 6. Process Manager (for SSR apps)
```
Process Manager:
  1) PM2       (recommended, easy management)
  2) Systemd   (native, no extra dependencies)
  3) None      (manual process management)
```

### 7. Database Setup (Optional)
```
Database Setup (optional):
  1) MySQL/MariaDB
  2) PostgreSQL
  3) None (skip database setup)
```

### 8. Firewall & SSL Configuration

## What Gets Installed

| Component | Installed When |
|-----------|---------------|
| Apache2 | Selected as web server |
| Nginx | Selected as web server |
| Node.js 18/20/22.x | Any frontend framework or Node.js backend |
| pnpm | Selected as package manager |
| yarn | Selected as package manager |
| bun | Selected as package manager |
| Python 3 + venv | App type is Python |
| PHP + PHP-FPM | App type is PHP |
| PM2 | PM2 selected as process manager |
| MySQL/MariaDB | Database option selected |
| PostgreSQL | Database option selected |
| UFW | Firewall option enabled |
| Certbot | Let's Encrypt SSL selected |

## Generated Configurations

### Frontend SPA (React, Vue, Angular, Static)
- SPA routing (index.html fallback)
- Immutable caching for hashed assets (1 year)
- No-cache for HTML files
- Compressed responses (gzip/brotli)
- Security headers

### Frontend SSR (Next.js, Nuxt.js, SvelteKit)
- Reverse proxy to Node.js server
- WebSocket support for HMR
- PM2 cluster mode
- Auto-restart on crash

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

### PM2 Ecosystem for Frontend SSR
```javascript
// Next.js Standalone mode
module.exports = {
  apps: [{
    name: 'myapp.com',
    cwd: '/var/www/myapp.com/.next/standalone',
    script: 'server.js',
    instances: 'max',
    exec_mode: 'cluster',
    // ...
  }]
};

// Nuxt.js SSR
module.exports = {
  apps: [{
    name: 'myapp.com',
    cwd: '/var/www/myapp.com',
    script: '.output/server/index.mjs',
    instances: 'max',
    exec_mode: 'cluster',
    // ...
  }]
};
```

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

### Example 1: Next.js SSR with PM2

```
Web Server: Nginx
App Type: Next.js
Mode: SSR
Node.js: 20 LTS
Package Manager: pnpm
Domain: myapp.com (with www)
Port: 3000
Git: https://github.com/user/myapp.git
Process Manager: PM2
Firewall: Yes
SSL: Let's Encrypt
```

### Example 2: React SPA (Vite) - Static Deployment

```
Web Server: Nginx
App Type: React
Build Tool: Vite
Node.js: 20 LTS
Package Manager: npm
Domain: app.example.com
Git: https://github.com/user/react-app.git
Firewall: Yes
SSL: Let's Encrypt
```

### Example 3: Nuxt.js Static Generation

```
Web Server: Nginx
App Type: Nuxt.js
Mode: Static
Node.js: 20 LTS
Package Manager: yarn
Domain: blog.example.com
Git: https://github.com/user/nuxt-blog.git
Firewall: Yes
SSL: Let's Encrypt
```

### Example 4: Vue.js SPA with Backend API

```
Web Server: Apache2
App Type: Vue.js
Build Tool: Vite
Node.js: 20 LTS
Package Manager: npm
Domain: dashboard.example.com
API URL: https://api.example.com
Git: https://github.com/user/vue-dashboard.git
Firewall: Yes
SSL: Let's Encrypt
```

### Example 5: Angular Application

```
Web Server: Nginx
App Type: Angular
Project Name: my-angular-app
Node.js: 20 LTS
Package Manager: npm
Domain: admin.example.com
Git: https://github.com/user/angular-admin.git
Firewall: Yes
SSL: Let's Encrypt
```

### Example 6: FastAPI Backend

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

## Post-Setup Tasks

### For Frontend Applications
```bash
# Rebuild and redeploy
cd /var/www/yourdomain.com
pnpm run build  # or npm/yarn/bun

# Restart (for SSR apps)
pm2 restart your-app-name
```

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

### v3.0.0
- **Frontend Framework Support**: Added support for Next.js, Nuxt.js, React, Vue.js, Angular, and Svelte
- **Deployment Modes**: SSR, Static Export, and SPA modes for applicable frameworks
- **Package Manager Selection**: Choose between npm, pnpm, yarn, or bun
- **Node.js Version Selection**: 18, 20, or 22 LTS
- **Build-time Environment Variables**: Configure during setup
- **Optimized Caching**: Immutable caching for hashed assets, no-cache for HTML
- **SPA Routing**: Proper fallback routing for single-page applications
- **PM2 Configs**: Framework-specific PM2 configurations for SSR apps
- **API URL Configuration**: Automatic environment setup for frontend-backend connections

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
