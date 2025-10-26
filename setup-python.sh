#!/usr/bin/env bash
set -e

# Create and activate a virtual environment (optional but recommended)
uv venv .venv
source .venv/bin/activate

# Install required packages
uv pip install \
    numpy \
    rasterio \
    xarray \
    dask \
    netCDF4

echo "All required packages have been installed successfully."
echo "Activate the virtual environment with:"
echo "  source .venv/bin/activate"
