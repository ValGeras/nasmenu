#!/usr/bin/env bash
#
# Выполняется НА СЕРВЕРЕ при каждом деплое (запускается GitHub Actions по SSH).
# Подтягивает последний код из ветки, ставит зависимости (если нужно)
# и перезапускает PHP-FPM/Nginx, чтобы подхватить изменения.

set -euo pipefail

DEPLOY_PATH="${DEPLOY_PATH:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BRANCH="${BRANCH:-main}"

cd "${DEPLOY_PATH}"

echo "==> Обновляем код (${BRANCH}) в ${DEPLOY_PATH}..."
git fetch origin "${BRANCH}"
git reset --hard "origin/${BRANCH}"

if [[ -f composer.json ]] && command -v composer >/dev/null 2>&1; then
  echo "==> Устанавливаем PHP-зависимости (composer)..."
  composer install --no-dev --optimize-autoloader --no-interaction
fi

echo "==> Восстанавливаем права доступа..."
sudo -n chown -R "$(id -un):www-data" "${DEPLOY_PATH}"

echo "==> Перезапускаем PHP-FPM и Nginx..."
PHP_FPM_SERVICE="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null \
  | awk '{print $1}' | grep -m1 '^php.*-fpm\.service$' || true)"
if [[ -n "${PHP_FPM_SERVICE}" ]]; then
  sudo -n systemctl reload "${PHP_FPM_SERVICE}"
fi
sudo -n systemctl reload nginx

echo "==> Деплой завершён: $(git rev-parse --short HEAD)"
