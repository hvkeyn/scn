# SCN Relay — Yandex RU deploy

Изолированная установка: только `/opt/scn-relay` + порт **53319**.
Не трогает nginx/apache и сайты на 80/443/8080.

## Требования на VM
- Node.js 18+
- SSH с правом создать `/opt/scn-relay` и systemd unit
- Security Group / firewall: TCP **53319** inbound

## Установка
```bash
# с машины администратора:
scp -r server/scn-relay root@YANDEX_IP:/tmp/scn-relay-src
ssh root@YANDEX_IP 'bash /tmp/scn-relay-src/deploy/install-ru.sh'
```

Проверка:
```bash
curl -s http://127.0.0.1:53319/api/v1/health
curl -s http://YANDEX_IP:53319/api/v1/health
```

Ожидается `"id":"ru","region":"ru"`.

## Важно
Клиенты SCN уже содержат оба endpoint (`ru` + `de`). Host регистрируется на всех живых; viewer выбирает ближайший, где хост online.
