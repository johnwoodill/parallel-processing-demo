# Parallel Processing Demo

Hands-on example projects for running geospatial raster processing workloads in parallel using either Python (`multiprocessing`) or R (`parallel`). Each example downloads a NOAA coastal elevation NetCDF file, chunks the grid, distributes slope/aspect calculations across all available CPU cores, and writes GeoTIFF outputs (`slope.tif`, `aspect.tif`, `elevation.tif`) for inspection.

## Repository Layout
- `setup-ec2-github.sh` – bootstraps an EC2 instance with your local GitHub SSH key so you can clone/push from the remote host.
- `setup-python.sh` / `setup-R.sh` – install language-specific dependencies (Python uses [uv](https://docs.astral.sh/uv/) when available; R installs into `~/R/library`).
- `examples/parallel-example.py` / `examples/parallel-example.R` – end-to-end processing pipelines that chunk, parallelize, and merge raster computations, then summarize and export results.
- `examples/*.tif`, `examples/*.nc` – working directory for the downloaded NetCDF and generated GeoTIFFs.

## 1. Provision EC2 Access (optional but recommended)
If you plan to run the examples on a cloud instance, first push your local GitHub key up to the target machine:

```bash
cd parallel-processing-demo
./setup-ec2-github.sh "ssh -i demo-test.pem ubuntu@ec2-00-000-000-000.compute-1.amazonaws.com"
```

The script expects a private key file (after `-i`) and a reachable host. It:
1. Fixes permissions on the specified PEM file.
2. Copies your local GitHub key from `~/.ssh/github` to the remote.
3. Adds the key to the remote SSH config and agent so `git clone git@github.com:...` works immediately.

Skip this step if you are working locally.

## 2. Set Up the Python Environment
The Python demo requires Python 3.9+ and standard build tools. Run:

```bash
./setup-python.sh
source .venv/bin/activate
python examples/parallel-example.py
```

What happens:
- `setup-python.sh` installs [uv](https://docs.astral.sh/uv/) if missing, creates `.venv`, and installs `numpy`, `rasterio`, `xarray`, `dask`, and `netCDF4` (falls back to `python -m venv` + `pip` if needed).
- `parallel-example.py` downloads `central_oregon_13_navd88_2015.nc` on first run, builds ~500×500 cell tasks, fans them out across `multiprocessing.Pool`, merges the results, prints summary stats, and writes GeoTIFFs next to the script.

Tip: Adjust `block_rows`, `block_cols`, or remove the `[DEBUG]` task limiter in the script to scale up/down the workload.

## 3. Set Up the R Environment
Requirements: R 4.x, and (on Linux) GDAL/NetCDF development headers for the `terra` and `ncdf4` packages.

```bash
./setup-R.sh
Rscript examples/parallel-example.R
```

The setup script installs R (via `apt` or Homebrew) if needed, ensures geospatial system dependencies exist on Linux, configures a user library at `~/R/library`, and installs `terra`, `ncdf4`, and `parallel`. The example script mirrors the Python flow using `parLapply` over the generated blocks and produces the same GeoTIFF outputs plus console stats.

## Working With the Outputs
Both examples generate:
- `examples/central_oregon_13_navd88_2015.nc` – cached source dataset.
- `examples/elevation.tif`, `examples/slope.tif`, `examples/aspect.tif` – GeoTIFF rasters in EPSG:4326 with `-9999` nodata.

Use `rio info examples/slope.tif` or open the files in QGIS to verify the results.

## Troubleshooting
- **uv install issues** – ensure `curl` is available and that `~/.local/bin` is on your `PATH`. You can manually install `uv` or edit `setup-python.sh` to skip it.
- **R package compilation failures on Linux** – confirm GDAL/NetCDF dev packages are present (`sudo apt-get install gdal-bin libgdal-dev libproj-dev libgeos-dev libudunits2-dev libnetcdf-dev netcdf-bin`).
- **Slow download** – the NOAA file is ~1.3 GB. Keep it cached in `examples/` to avoid repeated transfers.
- **Memory pressure** – decrease the block size or limit the number of tasks/cores if running on small instances.

With these scripts and examples you can quickly benchmark and compare parallel raster-processing strategies between Python and R.
