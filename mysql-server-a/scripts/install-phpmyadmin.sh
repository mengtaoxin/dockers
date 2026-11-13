#!/usr/bin/env bash
# Install Apache + PHP and pin phpMyAdmin from the official tarball.
set -euo pipefail

: "${PHPMYADMIN_VERSION:=5.2.3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "${SCRIPT_DIR}/apt-update.sh"
apt-get install -y --no-install-recommends \
  apache2 \
  libapache2-mod-php \
  php-mysql \
  php-mbstring \
  php-zip \
  php-gd \
  php-xml \
  php-curl \
  zip \
  unzip

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

tarball="phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages.tar.gz"
url="https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VERSION}/${tarball}"

curl -fsSL "${url}" -o "${tmp}/${tarball}"
tar -xzf "${tmp}/${tarball}" -C "${tmp}"
rm -rf /var/www/phpmyadmin
mv "${tmp}/phpMyAdmin-${PHPMYADMIN_VERSION}-all-languages" /var/www/phpmyadmin
chown -R www-data:www-data /var/www/phpmyadmin

# Disable the default site; phpMyAdmin vhost is enabled in the Dockerfile.
a2dissite 000-default >/dev/null 2>&1 || true

printf '%s\n' \
  'ServerName localhost' \
  > /etc/apache2/conf-available/servername.conf
a2enconf servername >/dev/null

php -v
apache2 -v
