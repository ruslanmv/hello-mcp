#!/bin/bash

# A simple script to install Python 3.11 on Ubuntu 22.04.
# This script should be run with sudo or by a user with sudo privileges.

# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- 🐍 Updating package lists and installing prerequisites ---"
sudo apt update
sudo apt install software-properties-common -y

echo "--- Adding the deadsnakes PPA for newer Python versions ---"
sudo add-apt-repository ppa:deadsnakes/ppa -y

echo "--- Updating package lists again to include the new PPA ---"
sudo apt update

echo "--- Installing Python 3.11 and its virtual environment module ---"
sudo apt install python3.11 python3.11-venv -y

echo "--- Verifying the installation ---"
python3.11 --version

echo "--- ✅ Python 3.11 installation is complete! ---"