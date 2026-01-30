#!/usr/bin/env bash

G='\e[32m'
B='\e[34m'
Y='\e[33m'
N='\e[0m'

echo -e "${G}[*] Проверка зависимостей в Arch Linux...${N}"

PKGS=("clang" "curl" "openssl" "ncurses" "nlohmann-json")

for pkg in "${PKGS[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
        echo -e "${G}[+] $pkg уже установлен.${N}"
    else
        echo -e "${Y}[!] $pkg не найден. Установка...${N}"
        sudo pacman -S --noconfirm "$pkg"
    fi
done

echo -e "${G}[OK] all packages installed!${N}"
