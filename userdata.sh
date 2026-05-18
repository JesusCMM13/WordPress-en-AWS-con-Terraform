#!/bin/bash
###############################################################
# userdata.sh — Instalación automática de WordPress
# Se ejecuta como root en el primer arranque de la instancia
###############################################################
set -euxo pipefail
exec > /var/log/userdata.log 2>&1

# ─── Variables inyectadas por Terraform ──────────────────────
DB_NAME="${db_name}"
DB_USER="${db_user}"
DB_PASSWORD="${db_password}"
DB_ROOT_PASSWORD="$$(openssl rand -base64 24)"

# ─── Actualizar sistema ──────────────────────────────────────
dnf update -y

# ─── Instalar Apache ─────────────────────────────────────────
dnf install -y httpd
systemctl enable --now httpd

# ─── Instalar PHP + módulos ──────────────────────────────────
dnf install -y \
  php \
  php-mysqlnd \
  php-fpm \
  php-gd \
  php-xml \
  php-mbstring \
  php-curl \
  php-zip \
  php-intl \
  php-opcache

# ─── Configurar PHP-FPM: socket Unix + permisos para Apache ──
# En Amazon Linux 2023, Apache habla con PHP-FPM via socket Unix
sed -i 's|^listen = .*|listen = /run/php-fpm/www.sock|'   /etc/php-fpm.d/www.conf
sed -i 's|^;listen.owner = .*|listen.owner = apache|'     /etc/php-fpm.d/www.conf
sed -i 's|^;listen.group = .*|listen.group = apache|'     /etc/php-fpm.d/www.conf
sed -i 's|^;listen.mode = .*|listen.mode = 0660|'         /etc/php-fpm.d/www.conf

mkdir -p /run/php-fpm
systemctl enable --now php-fpm

# ─── Instalar MariaDB ────────────────────────────────────────
dnf install -y mariadb105-server
systemctl enable --now mariadb

# Securizar MariaDB sin interactividad
mysql -u root <<MYSQL_SCRIPT
  ALTER USER 'root'@'localhost' IDENTIFIED BY '$${DB_ROOT_PASSWORD}';
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

  CREATE DATABASE IF NOT EXISTS $${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  CREATE USER IF NOT EXISTS '$${DB_USER}'@'localhost' IDENTIFIED BY '$${DB_PASSWORD}';
  GRANT ALL PRIVILEGES ON $${DB_NAME}.* TO '$${DB_USER}'@'localhost';
  FLUSH PRIVILEGES;
MYSQL_SCRIPT

# ─── Descargar e instalar WordPress ──────────────────────────
cd /tmp
curl -sLO https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz

cp -r wordpress/* /var/www/html/
chown -R apache:apache /var/www/html/
find /var/www/html/ -type d -exec chmod 755 {} \;
find /var/www/html/ -type f -exec chmod 644 {} \;

# ─── Configurar wp-config.php ────────────────────────────────
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

# Reemplazar credenciales de BD
sed -i "s/database_name_here/$${DB_NAME}/" /var/www/html/wp-config.php
sed -i "s/username_here/$${DB_USER}/"      /var/www/html/wp-config.php
sed -i "s/password_here/$${DB_PASSWORD}/"  /var/www/html/wp-config.php

# Generar claves únicas de seguridad de WordPress
# Las escribimos a un fichero para evitar que bash interprete
# los caracteres especiales que contienen (paréntesis, comillas, etc.)
curl -sS https://api.wordpress.org/secret-key/1.1/salt/ > /tmp/wp-keys.txt

python3 - <<'PYEOF'
with open('/tmp/wp-keys.txt', 'r') as f:
    keys = f.read().strip()

with open('/var/www/html/wp-config.php', 'r') as f:
    content = f.read()

placeholder = (
    "define( 'AUTH_KEY',         'put your unique phrase here' );\n"
    "define( 'SECURE_AUTH_KEY',  'put your unique phrase here' );\n"
    "define( 'LOGGED_IN_KEY',    'put your unique phrase here' );\n"
    "define( 'NONCE_KEY',        'put your unique phrase here' );\n"
    "define( 'AUTH_SALT',        'put your unique phrase here' );\n"
    "define( 'SECURE_AUTH_SALT', 'put your unique phrase here' );\n"
    "define( 'LOGGED_IN_SALT',   'put your unique phrase here' );\n"
    "define( 'NONCE_SALT',       'put your unique phrase here' );"
)

content = content.replace(placeholder, keys)

with open('/var/www/html/wp-config.php', 'w') as f:
    f.write(content)

print("Claves de seguridad de WordPress configuradas correctamente.")
PYEOF

rm -f /tmp/wp-keys.txt

# ─── Configurar Apache para WordPress + PHP-FPM ──────────────
cat > /etc/httpd/conf.d/wordpress.conf <<'APACHE_CONF'
<VirtualHost *:80>
    DocumentRoot /var/www/html
    DirectoryIndex index.php index.html

    # Conectar Apache con PHP-FPM via socket Unix (AL2023)
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    # Seguridad: ocultar archivos sensibles
    <Files wp-config.php>
        Require all denied
    </Files>

    ErrorLog  /var/log/httpd/wordpress-error.log
    CustomLog /var/log/httpd/wordpress-access.log combined
</VirtualHost>
APACHE_CONF

# ─── .htaccess para Permalinks ───────────────────────────────
cat > /var/www/html/.htaccess <<'HTACCESS'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %%{REQUEST_FILENAME} !-f
RewriteCond %%{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESS

chown apache:apache /var/www/html/.htaccess

# ─── Habilitar módulos de Apache necesarios ──────────────────
# mod_rewrite para permalinks de WordPress
# mod_proxy + mod_proxy_fcgi para comunicación con PHP-FPM
cat > /etc/httpd/conf.modules.d/10-wordpress-modules.conf <<'MODULES'
LoadModule proxy_module         modules/mod_proxy.so
LoadModule proxy_fcgi_module    modules/mod_proxy_fcgi.so
MODULES

# ─── Reiniciar servicios en el orden correcto ─────────────────
systemctl restart php-fpm
systemctl restart httpd

# ─── Obtener Token de IMDSv2 y mostrar IP de acceso ──────────
TOKEN=$$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

echo "✅ WordPress instalado correctamente."
echo "Accede en: http://$$(curl -s -H "X-aws-ec2-metadata-token: $$TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)"
