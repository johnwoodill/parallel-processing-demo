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

# If Linux, install system dependencies for terra and ncdf4
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "[STEP 1.5] Installing system dependencies for terra and ncdf4..."
    sudo apt-get update
    sudo apt-get install -y \
        gdal-bin \
        libgdal-dev \
        libproj-dev \
        libgeos-dev \
        libudunits2-dev \
        libnetcdf-dev \
        netcdf-bin
fi

# Create a user-local library if it doesn't exist
USER_LIB="$HOME/R/library"
if [ ! -d "$USER_LIB" ]; then
    echo "[STEP 2] Creating user R library at $USER_LIB..."
    mkdir -p "$USER_LIB"
fi

# Persist R_LIBS_USER to ~/.Renviron so Rscript always finds it
if ! grep -q "R_LIBS_USER" "$HOME/.Renviron" 2>/dev/null; then
    echo "[STEP 2.5] Adding R_LIBS_USER to ~/.Renviron..."
    echo "R_LIBS_USER=$USER_LIB" >> "$HOME/.Renviron"
fi

# Set it for this shell session too
export R_LIBS_USER="$USER_LIB"

echo "[STEP 3] Ensuring required R packages are installed..."
for pkg in "${R_PACKAGES[@]}"; do
    echo " - Checking package: $pkg"
    Rscript -e "if (!requireNamespace('$pkg', quietly = TRUE)) { \
        install.packages('$pkg', repos='https://cloud.r-project.org', lib=Sys.getenv('R_LIBS_USER')) \
    } else { \
        cat('[INFO] $pkg already installed\n') \
    }"
done

echo "[STEP 4] Verifying installation..."
for pkg in "${R_PACKAGES[@]}"; do
    if Rscript -e "library($pkg)" >/dev/null 2>&1; then
        echo " - $pkg loaded successfully."
    else
        echo "[ERROR] Failed to load $pkg after installation."
        echo "[HINT] Check .libPaths() in Rscript to verify R_LIBS_USER is set."
        exit 1
    fi
done

echo "[DONE] All required R packages are installed and verified in $USER_LIB"
