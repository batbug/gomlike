# GomLike

Личный видеоплеер для Windows без рекламы и обновлений: [mpv](https://mpv.io) + своя панель управления в классическом стиле (тёмная, оранжевый акцент), горячие клавиши как в GOM, плейлист из папки по клику колесиком.

## Структура

- `player/portable_config/` — всё, что лежит рядом с `mpv.exe`:
  - `mpv.conf` — настройки плеера
  - `input.conf` — горячие клавиши (дублированы для русской раскладки)
  - `scripts/classicbar.lua` — панель управления, плейлист, клик/двойной клик, окно выбора файла Windows
  - `script-opts/classicbar.conf` — цвета, высота панели, автоскрытие
  - `scripts/uosc/`, `fonts/` — [uosc](https://github.com/tomasklaen/uosc) (сторонний проект, используется только для меню по правому клику; лицензия — в его репозитории)
- `player/README.txt` — инструкция для пользователя (кладётся в папку установки)
- `installer/` — установщик на NSIS:
  - `GomLike.nsi` — установка в выбранную папку для текущего пользователя, ярлыки, ассоциации файлов, удаление
  - `getmpv.ps1` — скачивает свежую сборку mpv ([shinchiro/mpv-winbuild-cmake](https://github.com/shinchiro/mpv-winbuild-cmake)): во время установки или при сборке офлайн-версии
- `tools/build.ps1` (Windows), `tools/build.sh` (Linux) — сборка установщиков
- `tools/vtscan.ps1` — проверка собранных установщиков на VirusTotal

## Сборка

Собираются два установщика:

- `installer/GomLike-Setup.exe` (2 МБ) — скачивает mpv во время установки;
- `installer/GomLike-Setup-Offline.exe` (около 38 МБ) — mpv уже внутри, интернет не нужен. mpv для него скачивается при первой сборке в `installer/mpv` и дальше берётся оттуда; свежий — с ключом `-UpdateMpv` (`--update-mpv` в build.sh).

Windows:

```
winget install NSIS.NSIS
powershell -ExecutionPolicy Bypass -File tools\build.ps1
```

Linux:

```
sudo apt install nsis curl p7zip-full
tools/build.sh
```

Для проверки установщика без скачивания mpv: `tools\build.ps1 -Test` (или `makensis -DTEST installer/GomLike.nsi` после подготовки `installer/payload`, см. build.sh) — соберёт `test-setup.exe` с заглушкой вместо mpv.

## Проверка на VirusTotal

Нужен API-ключ VirusTotal (https://www.virustotal.com/gui/my-apikey) в переменной `VT_API_KEY`:

```
setx VT_API_KEY "<ключ>"
powershell -ExecutionPolicy Bypass -File tools\vtscan.ps1
```

Без параметров проверяет оба собранных установщика, занимает несколько минут. Неподписанные установщики NSIS обычно ловят несколько эвристических срабатываний («Malicious», «Unsafe», «PossibleThreat»), это ожидаемо.
