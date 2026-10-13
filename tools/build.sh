#!/bin/bash
# Собирает два установщика (нужны makensis, curl и 7z: apt install nsis curl p7zip-full):
#   installer/GomLike-Setup.exe          скачивает mpv во время установки
#   installer/GomLike-Setup-Offline.exe  mpv внутри, интернет не нужен
# mpv для второго скачивается один раз в installer/mpv; --update-mpv скачивает свежий
set -e
cd "$(dirname "$0")/../installer"
rm -rf payload && mkdir payload
trap 'rm -rf payload mpv.new' EXIT
cp -r ../player/portable_config ../player/README.txt ../LICENSE payload/

makensis -V2 GomLike.nsi
echo "Готово: installer/GomLike-Setup.exe"

if [ "$1" = "--update-mpv" ] || [ ! -f mpv/mpv.exe ]; then
    echo "Скачиваю mpv..."
    url=$(curl -fsSL https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest |
        grep -o '"browser_download_url": *"[^"]*/mpv-x86_64-[0-9]\{8\}-git-[0-9a-f]*\.7z"' |
        head -n1 | sed 's/.*"\(https[^"]*\)"$/\1/')
    [ -n "$url" ] || { echo "Архив mpv не найден в релизе"; exit 1; }
    rm -rf mpv.new && mkdir -p mpv.new/x
    curl -fL -o mpv.new/mpv.7z "$url"
    7z x -y -ompv.new/x mpv.new/mpv.7z >/dev/null
    src=$(dirname "$(find mpv.new/x -name mpv.exe | head -n1)")
    mkdir mpv.new/out
    # только сам плеер, как в getmpv.ps1: без обновлялки и скриптов установки mpv
    for f in "$src"/*; do
        case "$(basename "$f")" in
            portable_config|installer|updater.bat|updater.ps1|mpv-register.bat|mpv-unregister.bat) ;;
            *) cp -r "$f" mpv.new/out/; basename "$f" >> mpv.new/out/gomlike-files.txt ;;
        esac
    done
    # откуда взята эта сборка mpv (mpv под GPLv2+, см. licenses/mpv)
    tag=$(echo "$url" | sed 's|.*/download/\([^/]*\)/.*|\1|')
    commit=$(echo "$url" | sed 's|.*-git-\([0-9a-f]*\)\.7z$|\1|')
    printf '%s\r\n' "mpv build: $(basename "$url")" \
        "Build release: https://github.com/shinchiro/mpv-winbuild-cmake/releases/tag/$tag" \
        "Build scripts: https://github.com/shinchiro/mpv-winbuild-cmake" \
        "mpv source: https://github.com/mpv-player/mpv/tree/$commit" > mpv.new/out/mpv-source.txt
    rm -rf mpv && mv mpv.new/out mpv
fi

makensis -V2 -DOFFLINE GomLike.nsi
echo "Готово: installer/GomLike-Setup-Offline.exe"
