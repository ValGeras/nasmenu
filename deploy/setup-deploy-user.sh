#!/usr/bin/env bash
#
# Разовая настройка автодеплоя на сервере Ubuntu:
#   1. Создаёт отдельного системного пользователя (deploy) для деплоя.
#   2. Клонирует репозиторий в каталог сайта.
#   3. Разрешает пользователю deploy без пароля перезапускать PHP-FPM/Nginx
#      (и больше ничего — sudo ограничен только этими двумя командами).
#   4. Готовит ~/.ssh/authorized_keys, куда нужно добавить публичный ключ,
#      которым GitHub Actions будет заходить на сервер.
#
# Запускать один раз на сервере, с правами root:
#   sudo ./setup-deploy-user.sh

set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_PATH="${DEPLOY_PATH:-/var/www/maximtalalayev.ru}"
REPO_URL="${REPO_URL:-https://github.com/ValGeras/nasmenu.git}"
BRANCH="${BRANCH:-main}"

if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт с правами root: sudo $0" >&2
  exit 1
fi

echo "==> Создаём пользователя ${DEPLOY_USER} (если его ещё нет)..."
if ! id "${DEPLOY_USER}" &>/dev/null; then
  adduser --disabled-password --gecos "" "${DEPLOY_USER}"
  usermod -aG www-data "${DEPLOY_USER}"
fi

echo "==> Клонируем репозиторий в ${DEPLOY_PATH}..."
mkdir -p "$(dirname "${DEPLOY_PATH}")"
if [[ ! -d "${DEPLOY_PATH}/.git" ]]; then
  sudo -u "${DEPLOY_USER}" git clone --branch "${BRANCH}" "${REPO_URL}" "${DEPLOY_PATH}"
else
  echo "    Каталог уже содержит git-репозиторий, пропускаем клонирование."
fi

chown -R "${DEPLOY_USER}:www-data" "${DEPLOY_PATH}"
chmod -R 750 "${DEPLOY_PATH}"
chmod +x "${DEPLOY_PATH}/deploy/deploy.sh" 2>/dev/null || true

echo "==> Настраиваем ограниченный sudo для перезапуска сервисов..."
PHP_FPM_SERVICE="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null \
  | awk '{print $1}' | grep -m1 '^php.*-fpm\.service$' || echo "php-fpm.service")"

cat > "/etc/sudoers.d/${DEPLOY_USER}-deploy" <<EOF
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl reload ${PHP_FPM_SERVICE}
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl reload nginx
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/chown -R ${DEPLOY_USER}\:www-data ${DEPLOY_PATH}
EOF
chmod 440 "/etc/sudoers.d/${DEPLOY_USER}-deploy"
visudo -c -f "/etc/sudoers.d/${DEPLOY_USER}-deploy"

echo "==> Готовим SSH-доступ для GitHub Actions..."
DEPLOY_HOME="$(getent passwd "${DEPLOY_USER}" | cut -d: -f6)"
mkdir -p "${DEPLOY_HOME}/.ssh"
touch "${DEPLOY_HOME}/.ssh/authorized_keys"
chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "${DEPLOY_HOME}/.ssh"
chmod 700 "${DEPLOY_HOME}/.ssh"
chmod 600 "${DEPLOY_HOME}/.ssh/authorized_keys"

cat <<MSG

Готово.

Дальше на своём компьютере:
  1. Сгенерируйте ключ для деплоя:
       ssh-keygen -t ed25519 -f deploy_key -N "" -C "github-actions-deploy"
  2. Добавьте публичный ключ на сервер:
       cat deploy_key.pub | ssh root@<IP_СЕРВЕРА> \\
         "cat >> ${DEPLOY_HOME}/.ssh/authorized_keys"
  3. В настройках GitHub-репозитория (Settings → Secrets and variables → Actions)
     добавьте секреты:
       DEPLOY_HOST = <IP или домен сервера>
       DEPLOY_USER = ${DEPLOY_USER}
       DEPLOY_SSH_KEY = <содержимое приватного ключа deploy_key>
       DEPLOY_PATH = ${DEPLOY_PATH}
  4. Удалите deploy_key/deploy_key.pub с локального компьютера после добавления секрета.

После этого любой push в ветку "${BRANCH}" будет автоматически деплоиться на сервер.
MSG
