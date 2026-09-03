#!/usr/bin/env bash
#
# Подключение домена к серверу Ubuntu: Nginx + бесплатный SSL от Let's Encrypt.
#
# Что делает скрипт:
#   1. Устанавливает Nginx и Certbot.
#   2. Создаёт конфиг сайта в Nginx для домена (и его www-версии).
#   3. Открывает нужные порты в файрволе (UFW), если он используется.
#   4. Выпускает и настраивает SSL-сертификат через Certbot (с автопродлением).
#
# Перед запуском:
#   - У домена должна быть A-запись (и AAAA, если используете IPv6),
#     указывающая на IP этого сервера. Проверить: dig +short $DOMAIN
#   - Скрипт запускается с правами root (через sudo).
#
# Использование:
#   sudo DOMAIN=maximtalalayev.ru EMAIL=you@example.com ./setup-domain.sh
#   (либо просто отредактируйте переменные ниже и запустите: sudo ./setup-domain.sh)

set -euo pipefail

# ---------------------------------------------------------------------------
# Настройки
# ---------------------------------------------------------------------------

# Домен, который подключаем.
DOMAIN="${DOMAIN:-maximtalalayev.ru}"
# Email для уведомлений Let's Encrypt (истечение сертификата и т.п.).
EMAIL="${EMAIL:-admin@${DOMAIN}}"

# Режим работы сайта:
#   "proxy"  — Nginx проксирует запросы на локальное приложение (Node.js и т.п.)
#   "static" — Nginx отдаёт статические файлы напрямую из каталога
MODE="${MODE:-proxy}"

# Для режима "proxy": адрес и порт, на котором работает приложение.
PROXY_PASS="${PROXY_PASS:-http://127.0.0.1:3000}"

# Для режима "static": каталог со статическими файлами сайта.
WEBROOT="${WEBROOT:-/var/www/${DOMAIN}}"

# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт с правами root: sudo $0" >&2
  exit 1
fi

echo "==> Домен: ${DOMAIN} (и www.${DOMAIN})"
echo "==> Режим: ${MODE}"

echo "==> Обновляем список пакетов и устанавливаем Nginx + Certbot..."
apt-get update -y
apt-get install -y nginx certbot python3-certbot-nginx

SITE_AVAILABLE="/etc/nginx/sites-available/${DOMAIN}"
SITE_ENABLED="/etc/nginx/sites-enabled/${DOMAIN}"

if [[ "${MODE}" == "static" ]]; then
  echo "==> Создаём каталог для статики: ${WEBROOT}"
  mkdir -p "${WEBROOT}"
  chown -R www-data:www-data "${WEBROOT}"

  if [[ ! -f "${WEBROOT}/index.html" ]]; then
    cat > "${WEBROOT}/index.html" <<HTML
<!doctype html>
<html lang="ru">
<head><meta charset="utf-8"><title>${DOMAIN}</title></head>
<body><h1>${DOMAIN} работает</h1></body>
</html>
HTML
  fi

  cat > "${SITE_AVAILABLE}" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    root ${WEBROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINX
else
  cat > "${SITE_AVAILABLE}" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};

    location / {
        proxy_pass ${PROXY_PASS};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINX
fi

echo "==> Включаем конфиг сайта в Nginx..."
ln -sf "${SITE_AVAILABLE}" "${SITE_ENABLED}"
# Отключаем дефолтный конфиг, если он ещё активен, чтобы не мешал.
rm -f /etc/nginx/sites-enabled/default

echo "==> Проверяем конфигурацию Nginx..."
nginx -t
systemctl reload nginx

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  echo "==> Открываем порты 80/443 в UFW..."
  ufw allow 'Nginx Full'
fi

echo "==> Проверяем, что домен указывает на этот сервер..."
SERVER_IP="$(curl -s https://api.ipify.org || true)"
DOMAIN_IP="$(dig +short "${DOMAIN}" A | tail -n1 || true)"
if [[ -n "${SERVER_IP}" && -n "${DOMAIN_IP}" && "${SERVER_IP}" != "${DOMAIN_IP}" ]]; then
  echo "ВНИМАНИЕ: A-запись домена (${DOMAIN_IP}) не совпадает с IP сервера (${SERVER_IP})."
  echo "Обновите DNS-запись у регистратора домена и подождите её распространения,"
  echo "прежде чем выпускать SSL-сертификат."
fi

echo "==> Выпускаем SSL-сертификат Let's Encrypt..."
certbot --nginx \
  -d "${DOMAIN}" -d "www.${DOMAIN}" \
  --non-interactive --agree-tos -m "${EMAIL}" \
  --redirect

echo "==> Проверяем автопродление сертификата..."
certbot renew --dry-run

echo ""
echo "Готово! Сайт доступен по адресу: https://${DOMAIN}"
