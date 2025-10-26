#!/usr/bin/env bash
set -euo pipefail

# Check if uv is installed
if ! command -v uv >/dev/null 2>&1; then
    echo "[INFO] uv not found. Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.cargo/bin:$PATH"
fi

# If uv still isn't available, fall back to Python venv + pip
if command -v uv >/dev/null 2>&1; then
    echo "[STEP] Creating virtual environment with uv..."
    uv venv .venv
    source .venv/bin/activate
    echo "[STEP] Installing Python packages with uv..."
    uv pip install \
        numpy \
        rasterio \
        xarray \
        dask \
        netCDF4
else
    echo "[WARN] uv installation failed. Falling back to python3 -m venv."
    python3 -m venv .venv
    source .venv/bin/activate
    python3 -m pip install --upgrade pip
    pip install \
        numpy \
        rasterio \
        xarray \
        dask \
        netCDF4
fi

echo "[DONE] All required packages have been installed successfully."
echo "To activate the virtual environment later, run:"
echo "  source .venv/bin/activate"
