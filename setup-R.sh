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

# Create a user-local library if it doesn't exist
USER_LIB="$HOME/R/library"
if [ ! -d "$USER_LIB" ]; then
    echo "[STEP 1.5] Creating user R library at $USER_LIB..."
    mkdir -p "$USER_LIB"
fi

# Set R_LIBS_USER so packages install there
export R_LIBS_USER="$USER_LIB"

echo "[STEP 2] Ensuring required R packages are installed..."
for pkg in "${R_PACKAGES[@]}"; do
    echo " - Checking package: $pkg"
    Rscript -e "if (!requireNamespace('$pkg', quietly = TRUE)) install.packages('$pkg', repos='https://cloud.r-project.org', lib=Sys.getenv('R_LIBS_USER'))"
done

echo "[DONE] All required R packages are installed in $USER_LIB"
