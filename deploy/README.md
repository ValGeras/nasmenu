# Подключение домена к серверу Ubuntu

Скрипт `setup-domain.sh` настраивает Nginx и выпускает бесплатный SSL-сертификат
(Let's Encrypt) для домена `maximtalalayev.ru`.

## Перед запуском

1. Убедитесь, что A-запись домена указывает на IP вашего сервера:
   ```bash
   dig +short maximtalalayev.ru
   ```
2. Скопируйте скрипт на сервер и подключитесь по SSH.

## Запуск

Если приложение работает на локальном порту (Node.js, Express и т.п.),
по умолчанию скрипт настроит проксирование на `http://127.0.0.1:3000`:

```bash
sudo DOMAIN=maximtalalayev.ru EMAIL=you@example.com ./setup-domain.sh
```

Чтобы указать другой порт приложения:

```bash
sudo DOMAIN=maximtalalayev.ru PROXY_PASS=http://127.0.0.1:8080 ./setup-domain.sh
```

Если нужно отдавать статические файлы напрямую (без приложения на порту):

```bash
sudo DOMAIN=maximtalalayev.ru MODE=static WEBROOT=/var/www/maximtalalayev.ru ./setup-domain.sh
```

## Что делает скрипт

- Устанавливает Nginx и Certbot.
- Создаёт конфиг сайта в `/etc/nginx/sites-available/` для домена и его `www`-версии.
- Открывает порты 80/443 в UFW (если он активен).
- Выпускает SSL-сертификат Let's Encrypt и настраивает автоматический редирект на HTTPS.
- Проверяет автопродление сертификата (`certbot renew --dry-run`).

## Автодеплой из GitHub

При каждом push в ветку `main` GitHub Actions (`.github/workflows/deploy.yml`)
подключается по SSH к серверу и запускает `deploy/deploy.sh`, который обновляет
код (`git pull`), ставит PHP-зависимости через composer (если есть
`composer.json`) и перезапускает PHP-FPM и Nginx.

### Первоначальная настройка (один раз)

1. На сервере (от root) запустите:
   ```bash
   sudo DEPLOY_PATH=/var/www/maximtalalayev.ru ./deploy/setup-deploy-user.sh
   ```
   Скрипт создаст отдельного пользователя `deploy`, склонирует репозиторий в
   `DEPLOY_PATH` и разрешит пользователю `deploy` без пароля перезапускать
   только `php-fpm` и `nginx` (больше никаких sudo-прав).

2. На своём компьютере сгенерируйте SSH-ключ для деплоя и добавьте его на сервер:
   ```bash
   ssh-keygen -t ed25519 -f deploy_key -N "" -C "github-actions-deploy"
   cat deploy_key.pub | ssh root@<IP_СЕРВЕРА> "cat >> /home/deploy/.ssh/authorized_keys"
   ```

3. В GitHub-репозитории: **Settings → Secrets and variables → Actions** —
   добавьте секреты:
   | Секрет | Значение |
   |---|---|
   | `DEPLOY_HOST` | IP-адрес или домен сервера |
   | `DEPLOY_USER` | `deploy` |
   | `DEPLOY_SSH_KEY` | содержимое приватного ключа `deploy_key` |
   | `DEPLOY_PATH` | `/var/www/maximtalalayev.ru` |

4. Удалите `deploy_key`/`deploy_key.pub` с локального компьютера — он больше не нужен.

После этого каждый push в `main` будет автоматически выкладываться на сервер.
Проверить статус деплоя можно во вкладке **Actions** репозитория на GitHub.
