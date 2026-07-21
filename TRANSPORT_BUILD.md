# Транспортировка исходников SCN и сборка на другой машине

Пакет создаётся скриптом `pack-transport.ps1` → `transport/scn-sources-*.zip`.

## Что внутри пакета

- `scn/` — Flutter-приложение + Win7 shim / runner
- `build.ps1` — автономная сборка (сама скачает Flutter **3.24.5**)
- `server/scn-relay/` — relay (нужен только для WAN)
- `_loadtest/rd_frames_*.py` — LAN smoke для frames RD
- `memory-bank/` — текущий контекст (Win7 RD frames)
- `TRANSPORT_BUILD.md` — эта инструкция

**Не входит** (и не нужно копировать вручную): `flutter-sdk/`, `releases/`, `scn/build/`, `.git/`, тестовые DLL.

## Требования на машине сборки (Windows 10/11 x64)

1. **Visual Studio 2022** Build Tools или Community  
   Workload: *Desktop development with C++* (MSVC, Windows 10/11 SDK)
2. **Python 3** в PATH (`python` / `pip`) — для Win7 PE-patch (`pefile` поставится сам)
3. Интернет на первой сборке (скачивание Flutter ~1 GB + pub packages)
4. Disk: ~5–8 GB свободно

Сборку делайте на **Win10/11**. На Win7 только **запускайте** готовый `releases\windows\` (Profile + shims).

## Сборка

```powershell
# 1. Распаковать zip, например в C:\PROJECTS\scn
cd C:\PROJECTS\scn

# 2. Сборка Windows Profile (Win7-совместимая)
.\build.ps1

# Результат:
#   releases\windows\scn.exe
#   releases\windows\*.dll  (+ data\)
```

Повторная чистая сборка:

```powershell
.\build.ps1 -Clean
```

Номер билда в `pubspec.yaml` увеличивается автоматически (`1.0.0+N`).

## Тест frames RD на этой же Win10 (без реальной Win7)

Сборка **без UAC** (иначе smoke не стартует из скрипта):

```powershell
$env:SCN_SMOKE_NO_UAC = '1'
# нужно пересобрать runner (сброс CMake cache):
Remove-Item scn\build\windows\x64\CMakeCache.txt -ErrorAction SilentlyContinue
.\build.ps1

python _loadtest\rd_frames_lan_smoke.py --exe releases\windows\scn.exe --instance 1 --frames 3
python _loadtest\rd_frames_viewer_smoke.py
```

Env для ручного прогона:

| Переменная | Назначение |
|---|---|
| `SCN_RD_FRAMES=1` | хост шлёт JPEG frames вместо WebRTC |
| `SCN_RD_TEST_HOST=1` | авто-включить RD + пароль |
| `SCN_RD_TEST_PASSWORD` | пароль (по умолчанию `test1234`) |
| `SCN_RD_TEST_CONNECT=127.0.0.1:53327` | viewer auto-connect |
| `SCN_WIN7=1` | полный Win7 runtime-режим (на реальной Win7 выставляется runner’ом) |

Production для Win7 снова **с UAC**:

```powershell
Remove-Item Env:SCN_SMOKE_NO_UAC -ErrorAction SilentlyContinue
Remove-Item scn\build\windows\x64\CMakeCache.txt -ErrorAction SilentlyContinue
.\build.ps1
```

Скопируйте всю папку `releases\windows\` на Win7 и запускайте `scn.exe` (нужны права админа).

## Тест Win10 viewer → Win7 host (WAN)

1. На Win7: свежий `releases\windows\`, Settings → Allow remote desktop, пароль/relay  
2. На Win10: Connect к хосту (LAN IP или WAN code)  
3. Ожидается `transport=frames` (JPEG), мышь/клавиатура через signaling

## Если сборка падает

- Закройте все `scn.exe` / разблокируйте файлы в `releases\windows`
- Запустите терминал **от администратора** при копировании в `releases\` (UAC exe)
- `pip install pefile`
- Проверьте: `flutter-sdk\bin\flutter doctor` после первого `.\build.ps1`

## Перепаковать исходники снова

На машине-доноре:

```powershell
.\pack-transport.ps1
# → transport\scn-sources-YYYYMMDD-HHMM.zip
```
