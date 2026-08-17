#!/bin/bash
# Wi-Fi Manager — one-command installer
#   curl -sL https://raw.githubusercontent.com/Shah-man/Wi-Fi-Manager/main/install.sh | bash

set -e

REPO="https://github.com/Shah-man/Wi-Fi-Manager.git"
DEST="$HOME/Wi-Fi-Manager"

C_CYAN='\033[0;36m'; C_GRN='\033[0;32m'; C_YEL='\033[1;33m'; C_NC='\033[0m'

banner() {
cat <<'BANNER'
 __      __ _   ___  _   __  __
 \ \    / /(_) | __|(_) |  \/  | __ _  _ _   __ _  __ _  ___  _ _
  \ \/\/ / | | | _|  | | | |\/| |/ _` || ' \ / _` |/ _` |/ -_)| '_|
   \_/\_/  |_| |_|   |_| |_|  |_|\__,_||_||_|\__,_|\__, |\___||_|
                                                   |___/
       Wi-Fi network testing bench  .  EN / RU  .  GPLv3
BANNER
}

echo -e "${C_CYAN}"; banner; echo -e "${C_NC}"
echo -e "${C_YEL}One-command installer${C_NC}\n"

# 1. git is required
if ! command -v git >/dev/null 2>&1; then
    echo "Installing git..."
    if command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get install -y git
    elif command -v dnf >/dev/null 2>&1; then sudo dnf install -y git
    elif command -v pacman >/dev/null 2>&1; then sudo pacman -Sy --noconfirm git
    else echo "Please install git manually and retry."; exit 1; fi
fi

# 2. clone (or update if already present)
if [ -d "$DEST/.git" ]; then
    echo "Wi-Fi Manager already present - updating..."
    git -C "$DEST" pull --ff-only || true
else
    echo "Downloading Wi-Fi Manager..."
    git clone --depth 1 "$REPO" "$DEST"
fi

# 3. make scripts executable
chmod +x "$DEST/wh" "$DEST/installwh.sh" "$DEST/install.sh" 2>/dev/null || true

# 4. run the tools installer (it will ask for sudo and let you pick a language)
echo -e "\n${C_GRN}Launching the tools installer...${C_NC}"
cd "$DEST"
sudo ./installwh.sh

echo -e "\n${C_GRN}Done!${C_NC}"
echo "  wh          - launch Wi-Fi Manager"
echo "  wifistart   - enable monitor mode"
echo "  wifistop    - disable monitor mode"
