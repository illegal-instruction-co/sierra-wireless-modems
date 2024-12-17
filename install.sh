#!/bin/bash

PACKAGES=(
    php
    libqmi-glib5
    libqmi-proxy
    libqmi-utils
    wget
    minicom
    curl
    gcc
    make
    unzip
)

set -e
set -u
set -o pipefail
exec > >(tee -i /var/log/script.log) 2>&1

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root."
    exit 1
fi

if ! ping -c 1 8.8.8.8 &>/dev/null; then
    echo "No internet connection."
    exit 1
fi

sudo DEBIAN_FRONTEND=noninteractive add-apt-repository universe -y
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

for PACKAGE in "${PACKAGES[@]}"; do
    if ! dpkg -l | grep -q $PACKAGE; then
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$PACKAGE"
    else
        echo "$PACKAGE already installed."
    fi
done

sudo DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

echo "Installation completed successfully."
