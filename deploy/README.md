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
