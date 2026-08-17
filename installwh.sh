#!/bin/bash
cd "$(dirname "$0")" || exit 1
if [ "$EUID" -ne 0 ]; then exec sudo "$0" "$@"; fi

# Выбор языка (цифра без Enter; фолбэк — английский)
echo "Выберите язык / Choose language:"
echo "  [1] Русский"
echo "  [2] English"
read -rsn1 lang_choice
case "$lang_choice" in
    1) LANG_UI=ru ;;
    *) LANG_UI=en ;;
esac
echo "$LANG_UI" > /root/.wh_lang
# L "русский" "english" — вывод строки на выбранном языке
L(){ if [ "$LANG_UI" = ru ]; then echo "$1"; else echo "$2"; fi; }

SCRIPT_DIR="$(pwd)"
# домашняя папка реального пользователя (не /root под sudo)
if [ -n "${SUDO_USER:-}" ]; then USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6); else USER_HOME="$HOME"; fi
[ -z "$USER_HOME" ] && USER_HOME="$HOME"
# исходники ВСЕГДА в ~/wifi-tools/src, куда бы ни распаковали архив
DEST_DIR="$USER_HOME/wifi-tools"
DATA_DIR="$USER_HOME/wifi-unlock"
WH_FILE="$SCRIPT_DIR/wh"
SRC_DIR="$DEST_DIR/src"
mkdir -p "$DEST_DIR"
# папка пользовательских данных (сети, логи, handshake) — создаём если нет, содержимое не трогаем
mkdir -p "$DATA_DIR"
[ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER":"$(id -gn "$SUDO_USER" 2>/dev/null)" "$DATA_DIR" 2>/dev/null
# кладём свежий wh рядом с исходниками (самодостаточная папка)
[ -f "$WH_FILE" ] && [ "$SCRIPT_DIR" != "$DEST_DIR" ] && cp -f "$WH_FILE" "$DEST_DIR/wh"

echo "$(L "=== Установка Wi-Fi Manager из $SCRIPT_DIR ===" "=== Installing Wi-Fi Manager from $SCRIPT_DIR ===")"

# 1. Ставим wh в систему + симлинки
install -m 755 "$WH_FILE" /usr/local/bin/wh
for n in цр installwh uninstallwh wifistart wifistop; do
    ln -sf /usr/local/bin/wh "/usr/local/bin/$n"
done
echo "$(L "  wh установлен, симлинки созданы" "  wh installed, symlinks created")"

# 2. Определяем дистрибутив и пакетный менеджер (ALT проверяем ПЕРВЫМ)
if [ -f /etc/altlinux-release ] || grep -qi "ALT" /etc/os-release 2>/dev/null; then
    PM_KIND="alt";    DISTRO="ALT Linux";     PM_NAME="apt-get (RPM)"
elif command -v dnf >/dev/null 2>&1; then
    PM_KIND="dnf";    DISTRO="Fedora/RHEL";   PM_NAME="dnf"
elif command -v apt-get >/dev/null 2>&1; then
    PM_KIND="apt";    DISTRO="Debian/Ubuntu"; PM_NAME="apt-get"
elif command -v pacman >/dev/null 2>&1; then
    PM_KIND="pacman"; DISTRO="Arch";          PM_NAME="pacman"
else
    PM_KIND="none";   DISTRO="Unknown";       PM_NAME="—"
fi
echo "$(L "  Обнаружен дистрибутив: $DISTRO" "  Detected distribution: $DISTRO")"
echo "$(L "  Пакетный менеджер: $PM_NAME" "  Package manager: $PM_NAME")"

# 3. Зависимости (имена пакетов свои для каждого дистрибутива)
echo "$(L "=== Установка зависимостей ===" "=== Installing dependencies ===")"
# при английском языке заставляем пакетный менеджер говорить по-английски
[ "$LANG_UI" = en ] && PMLC="LC_ALL=C" || PMLC=""
case $PM_KIND in
    alt)
        env $PMLC apt-get update >/dev/null 2>&1
        env $PMLC apt-get install -y git make gcc gcc-c++ pkg-config libtool_2.4 autoconf automake \
            libnl-devel libpcap-devel libpcre2-devel libsqlite3-devel libssl-devel zlib-devel \
            libcurl-devel usbutils pciutils || true ;;
    apt)
        env $PMLC apt-get update -y >/dev/null 2>&1
        env $PMLC apt-get install -y git make gcc g++ pkg-config libtool autoconf automake \
            libnl-3-dev libnl-genl-3-dev libpcap-dev libpcre2-dev libsqlite3-dev libssl-dev zlib1g-dev \
            libcurl4-openssl-dev usbutils pciutils || true ;;
    dnf)
        env $PMLC dnf install -y git make gcc gcc-c++ pkgconfig libtool autoconf automake \
            libnl3-devel libpcap-devel pcre2-devel sqlite-devel openssl-devel zlib-devel \
            libcurl-devel usbutils pciutils || true ;;
    pacman)
        env $PMLC pacman -S --noconfirm git make gcc pkgconf libtool autoconf automake \
            libnl libpcap pcre2 sqlite openssl zlib \
            curl usbutils pciutils || true ;;
    none)
        echo "$(L "  ! Дистрибутив не определён — установи зависимости вручную:" "  ! Distribution not detected — install dependencies manually:")"
        echo "    git make gcc gcc-c++ pkg-config libtool autoconf automake libnl-devel libpcap-devel libpcre2-devel libsqlite3-devel libssl-devel zlib-devel"
        echo "$(L "  Продолжаю сборку (вдруг всё уже установлено)..." "  Continuing build (in case everything is already installed)...")" ;;
esac


# 4. Создаём src если нет
mkdir -p "$SRC_DIR"

# 5. URL исходников
declare -A URL=(
    [aircrack-ng]="https://github.com/aircrack-ng/aircrack-ng.git"
    [pixiewps]="https://github.com/wiire-a/pixiewps.git"
    [reaver]="https://github.com/t6x/reaver-wps-fork-t6x.git"
    [bully]="https://github.com/aanarchyy/bully.git"
    [hcxdumptool]="https://github.com/ZerBea/hcxdumptool.git"
    [hcxtools]="https://github.com/ZerBea/hcxtools.git"
)

# 6. Удаляем старый хлам из корня папки
for old in aircrack-ng pixiewps reaver reaver-wps-fork-t6x bully hcxdumptool hcxtools; do
    [ -d "$DEST_DIR/$old" ] && rm -rf "$DEST_DIR/$old" && echo "$(L "  удалено наследие: $old" "  removed legacy: $old")"
done

# 7. Клонируем/обновляем все проекты в src/
# hcxdumptool закреплён на 6.2.9 — последняя версия, совместимая с ath9k_htc (7.x ломает arm)
declare -A PIN=( [hcxdumptool]="6.2.9" )
for n in aircrack-ng pixiewps reaver bully hcxdumptool hcxtools; do
    echo "=== $n ==="
    rm -rf "$SRC_DIR/$n"
    if [ -n "${PIN[$n]:-}" ]; then
        git clone --depth 1 --branch "${PIN[$n]}" "${URL[$n]}" "$SRC_DIR/$n" 2>&1
    else
        git clone "${URL[$n]}" "$SRC_DIR/$n" 2>&1
    fi
    if [ -d "$SRC_DIR/$n/.git" ]; then
        echo "$(L "  склонировано OK" "  cloned OK")"
    else
        echo "$(L "  ОШИБКА клонирования $n (нет сети?)" "  CLONE ERROR $n (no network?)")"
        continue
    fi
done

# 8. Собираем
echo "$(L "=== Сборка ===" "=== Building ===")"
for n in aircrack-ng pixiewps reaver bully hcxdumptool hcxtools; do
    [ ! -d "$SRC_DIR/$n" ] && continue
    echo "$(L "--- собираю $n ---" "--- building $n ---")"
    case $n in
        aircrack-ng) cd "$SRC_DIR/$n" && ./autogen.sh --with-experimental && make -j$(nproc) && make install && ldconfig ;;
        pixiewps) cd "$SRC_DIR/$n" && make && make install ;;
        reaver) cd "$SRC_DIR/$n/src" && ./configure && make -j$(nproc) && make install ;;
        bully) cd "$SRC_DIR/$n/src" && make && install -m 755 bully /usr/local/bin/bully ;;
        hcxdumptool) cd "$SRC_DIR/$n" && make -j$(nproc) && make install ;;
        hcxtools) cd "$SRC_DIR/$n" && make -j$(nproc) && make install ;;
    esac
done

# 9. Обновляем даты
find "$SRC_DIR" -exec touch -m {} +

# 9b. Словари паролей — качаем при установке, если их ещё нет
CRACKED_BASE="$DATA_DIR/cracked.txt"
CRACKED_URL="https://wpa-sec.stanev.org/dict/cracked.txt.gz"
ROCKYOU_BASE="$DATA_DIR/rockyou.txt"
ROCKYOU_URL="https://raw.githubusercontent.com/teamstealthsec/wordlists/master/rockyou.txt.gz"
is_gzip(){ [ -s "$1" ] && [ "$(head -c2 "$1" 2>/dev/null | od -An -tx1 | tr -d ' ')" = "1f8b" ] && gzip -t "$1" 2>/dev/null; }
# автопоиск любого рабочего прокси (НИЧЕГО не захардкожено)
find_proxy(){
    local envp="${https_proxy:-${http_proxy:-${HTTPS_PROXY:-${HTTP_PROXY:-}}}}"
    [ -n "$envp" ] && { printf '%s' "$envp"; return 0; }
    local host p
    for host in 127.0.0.1 localhost; do
        for p in 7890 7897 1080 8080 8118 10809 20171 2080; do
            if timeout 1 bash -c "exec 3<>/dev/tcp/$host/$p" 2>/dev/null; then
                printf 'http://%s:%s' "$host" "$p"; return 0
            fi
        done
    done
    return 1
}
# fetch_gz <url> <dest_без_gz> <название> <для_чего_RU> <для_чего_EN>
fetch_gz(){
    local url="$1" dest="$2" title="$3" why_ru="$4" why_en="$5" gz="$2.gz"
    if [ -s "$dest" ]; then
        echo "$(L "  $title уже есть — пропускаю" "  $title already present — skipping")"; return 0
    fi
    echo "$(L "=== Скачиваю $title ===" "=== Downloading $title ===")"
    rm -f "$gz"
    # этап 1 — быстрая проба напрямую: 1 попытка, короткий таймаут (не виснуть)
    echo "$(L "  Пробую напрямую (быстро)..." "  Trying directly (quick)...")"
    wget --tries=1 --timeout=8 --show-progress -q -O "$gz" "$url"
    # этап 2 — не вышло за 8с → сразу прокси (не долбим повторно напрямую)
    if ! is_gzip "$gz"; then
        rm -f "$gz"
        local px; px=$(find_proxy)
        if [ -n "$px" ]; then
            echo "$(L "  Напрямую не вышло — качаю через прокси: $px" "  Direct failed — downloading via proxy: $px")"
            https_proxy="$px" http_proxy="$px" wget --tries=3 --timeout=30 --continue --show-progress -q -O "$gz" "$url"
        else
            echo "$(L "  Прокси не найден." "  No proxy found.")"
        fi
    fi
    if is_gzip "$gz"; then
        gunzip -f "$gz" 2>/dev/null
        [ -n "${SUDO_USER:-}" ] && chown "$SUDO_USER":"$(id -gn "$SUDO_USER" 2>/dev/null)" "$dest" 2>/dev/null
        echo "$(L "  Готово: $dest" "  Ready: $dest")"
    else
        rm -f "$gz"
        # подробная двуязычная инструкция: что, где, под каким названием, зачем
        echo ""
        echo "$(L "  ┌─ ВНИМАНИЕ: не удалось скачать $title (троттлинг/блок/нет сети)" "  ┌─ NOTICE: failed to download $title (throttling/block/no network)")"
        echo "$(L "  │  Без этого файла $why_ru" "  │  Without this file $why_en")"
        echo "$(L "  │  Скачай вручную отсюда:" "  │  Download it manually from:")"
        echo "  │    $url"
        echo "$(L "  │  Распакуй и положи СЮДА (без .gz на конце):" "  │  Unpack and place it HERE (without .gz):")"
        echo "  │    $dest"
        echo "$(L "  │  Или одной командой:" "  │  Or with one command:")"
        echo "  │    wget -O '$gz' '$url' && gunzip '$gz'"
        echo "$(L "  └─ После этого перезапусти проверку в меню." "  └─ After that, re-run the check in the menu.")"
    fi
}
fetch_gz "$CRACKED_URL" "$CRACKED_BASE" "cracked.txt" \
    "НЕ будет работать 'Этап 1' в пункте меню 'Диагностика WPA/WPA2 → Работа с хэшем → Локальная проверка (cracked + rockyou)' — быстрая проверка хэша по базе уже засвеченных паролей." \
    "'Stage 1' won't work in menu 'WPA/WPA2 Diagnostics → Work with hash → Local check (cracked + rockyou)' — quick hash check against already-exposed passwords."
fetch_gz "$ROCKYOU_URL" "$ROCKYOU_BASE" "rockyou.txt" \
    "НЕ будет работать 'Этап 2' в том же пункте 'Локальная проверка (cracked + rockyou)' — перебор хэша по большому словарю rockyou (~14 млн паролей). Останется только онлайн-проверка на wpa-sec." \
    "'Stage 2' won't work in the same 'Local check (cracked + rockyou)' item — brute-forcing the hash against the big rockyou wordlist (~14M passwords). Only the wpa-sec online check will remain."

# 10. Возвращаем владельца папки пользователю (клонировали под root)
if [ -n "${SUDO_USER:-}" ]; then
    chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$DEST_DIR" 2>/dev/null
fi

echo
if [ "$LANG_UI" = en ]; then
    echo "=== DONE ==="
    echo "Sources: $SRC_DIR (6 projects)"
    echo
    echo "  wh                — launch Wi-Fi Manager"
    echo "  wifistart         — enable monitor mode"
    echo "  wifistop          — disable monitor mode"
    echo "  sudo installwh    — update (rebuild everything)"
    echo "  sudo uninstallwh  — remove completely"
else
    echo "=== ГОТОВО ==="
    echo "Исходники: $SRC_DIR (6 проектов)"
    echo
    echo "  wh                — запустить Wi-Fi Manager"
    echo "  wifistart         — поднять монитор"
    echo "  wifistop          — выключить монитор"
    echo "  sudo installwh    — обновить (пересобрать всё)"
    echo "  sudo uninstallwh  — полностью удалить"
fi
