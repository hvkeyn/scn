# WAN P2P Foundation

## Что изменилось

SCN больше не рассматривает прямой `IP:port` как основной интернет-механизм. Базовый WAN-путь теперь строится так:

1. Оба пира встречаются через signaling backend.
2. Клиенты обмениваются `SDP/ICE`.
3. WebRTC пытается поднять `direct` путь.
4. Если NAT слишком жесткий, используется `TURN relay`.

## Embedded signaling в приложении

Теперь signaling backend поднимается автоматически внутри `scn.exe` вместе с остальными сервисами.
Это возвращает модель "единое приложение в клиент-серверном режиме": хост может сам создавать WAN invite без отдельного ручного запуска backend.

По умолчанию embedded signaling слушает локальный адрес `127.0.0.1:8787` и при занятости порта берет следующий свободный.
Экран `Internet P2P` показывает:

- локальный embedded signaling URL
- advertised URL, который попадет в invite
- live-этапы `signaling -> offer/answer -> ICE -> data channel -> connected`

## Отдельный signaling backend

Отдельный запуск все еще поддерживается для выделенного server-mode:

```bash
dart run bin/signaling_server.dart
```

Такой вариант нужен, если вы хотите держать signaling на отдельной машине или на публичном сервере.

## Переменные окружения

- `SCN_SIGNAL_PORT` - порт signaling backend, по умолчанию `8787`
- `SCN_STUN_URLS` - CSV-список STUN URL
- `SCN_TURN_URLS` - CSV-список TURN URL
- `SCN_TURN_USERNAME` - имя пользователя TURN
- `SCN_TURN_CREDENTIAL` - пароль / credential TURN

Пример:

```powershell
$env:SCN_SIGNAL_PORT="8787"
$env:SCN_STUN_URLS="stun:stun.l.google.com:19302,stun:stun.cloudflare.com:3478"
$env:SCN_TURN_URLS="turn:turn.example.com:3478?transport=udp,turn:turn.example.com:3478?transport=tcp"
$env:SCN_TURN_USERNAME="scn"
$env:SCN_TURN_CREDENTIAL="secret"
dart run bin/signaling_server.dart
```

## Что видит пользователь

Экран `Internet P2P` теперь показывает:

- NAT-диагностику
- режим `direct / relay / legacy direct`
- live-состояния signaling / ICE / DataChannel
- invite token вместо обещания, что любой NAT будет пробит напрямую

## Рекомендации по роутеру

- Проброс портов больше не считается обязательным условием.
- Для обычной работы важнее доступность signaling server и TURN.
- Если используется embedded signaling внутри приложения, для internet-доступа к нему нужен публичный адрес или проброс соответствующего порта.
- Port forwarding может немного помочь `legacy direct`, но не решает `CGNAT` и symmetric NAT.

## Ограничения текущего foundation-этапа

- Control-plane уже переведен на `signaling + WebRTC`.
- Планировщик транспорта уже считает `DataChannel` целевым WAN data-plane.
- Старый `HTTP`-путь пока остается совместимым режимом для LAN/legacy direct и требует дальнейшей миграции для полноценных internet file transfers.
