#!/usr/bin/env bash
set -euo pipefail

echo "--- 🐍 Ensuring prerequisites ---"
sudo apt update
sudo apt install -y software-properties-common

# Add deadsnakes only if not already present
if ! grep -h "^deb .*/deadsnakes/ppa" /etc/apt/sources.list /etc/apt/sources.list.d/* > /dev/null 2>&1; then
  echo "--- ➕ Adding deadsnakes PPA ---"
  sudo add-apt-repository -y ppa:deadsnakes/ppa
  sudo apt update
else
  echo "--- 👉 deadsnakes PPA already added ---"
fi

# If python3.11 is already installed, remove it (and its venv bits)
if dpkg -l | grep -qw python3.11; then
  echo "--- 🗑 Removing existing Python 3.11 and venv package ---"
  sudo apt remove --purge -y python3.11 python3.11-venv
  sudo apt autoremove -y
else
  echo "--- 👉 Python 3.11 not currently installed ---"
fi

echo "--- 📦 Installing Python 3.11 and venv support ---"
sudo apt install -y python3.11 python3.11-venv

echo "--- 🔍 Verifying installation ---"
python3.11 --version
python3.11 -m venv --help >/dev/null

echo "--- ✅ Python 3.11 (and venv) is ready to go! ---"
