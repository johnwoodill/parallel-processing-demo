#!/usr/bin/env bash
set -euo pipefail

# Required R packages
R_PACKAGES=("terra" "ncdf4" "parallel")

echo "[STEP 1] Checking if R is installed..."
if ! command -v R >/dev/null 2>&1; then
    echo "[INFO] R not found. Installing R..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update
        sudo apt-get install -y r-base
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        if ! command -v brew >/dev/null 2>&1; then
            echo "[ERROR] Homebrew not found. Please install Homebrew first: https://brew.sh"
            exit 1
        fi
        brew install r
    else
        echo "[ERROR] Unsupported OS: $OSTYPE"
        exit 1
    fi
else
    echo "[INFO] R is already installed."
fi

echo "[STEP 2] Ensuring required R packages are installed..."
for pkg in "${R_PACKAGES[@]}"; do
    echo " - Checking package: $pkg"
    Rscript -e "if (!requireNamespace('$pkg', quietly = TRUE)) install.packages('$pkg', repos='https://cloud.r-project.org')"
done
