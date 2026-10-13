#!/bin/bash
# Собирает installer/GomLike-Setup.exe (нужен makensis: apt install nsis)
set -e
cd "$(dirname "$0")/../installer"
rm -rf payload && mkdir payload
cp -r ../player/portable_config ../player/README.txt payload/
makensis -V2 GomLike.nsi
rm -rf payload
echo "Готово: installer/GomLike-Setup.exe"
