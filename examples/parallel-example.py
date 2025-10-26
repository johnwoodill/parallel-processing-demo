import os
import sys
import numpy as np
import rasterio
from rasterio.transform import from_origin
import xarray as xr
from multiprocessing import Pool, cpu_count
from functools import partial
import urllib.request
from time import time

URL = "https://www.ngdc.noaa.gov/thredds/fileServer/regional/central_oregon_13_navd88_2015.nc"
NCFILE = "central_oregon_13_navd88_2015.nc"

def print_tif_info(filepath):
    with rasterio.open(filepath) as src:
        print(f"[INFO] File: {filepath}")
        print(f"  Width: {src.width}")
        print(f"  Height: {src.height}")
        print(f"  Count (bands): {src.count}")
        print(f"  CRS: {src.crs}")
        print(f"  Dtype: {src.dtypes[0]}")
        print(f"  Transform:\n{src.transform}")
        print(f"  Bounds: {src.bounds}")
        data = src.read(1)
        mask = np.isfinite(data)
        if np.any(mask):
            valid = data[mask]
            print(f"  Min: {valid.min()}")
            print(f"  Max: {valid.max()}")
            print(f"  Mean: {valid.mean()}")
        else:
            print("  Min/Max/Mean: No valid data")
        print(f"  Nodata: {src.nodata}")

def download_file(url, local_path):
    if not os.path.exists(local_path):
        print(f"[INFO] Downloading file from {url}")
        urllib.request.urlretrieve(url, local_path)
        print(f"[INFO] File saved to {local_path}")
    else:
        print(f"[INFO] File already exists: {local_path}")

def compute_chunk(elev_chunk, xres, yres):
    dzdx = (np.roll(elev_chunk, -1, axis=1) - np.roll(elev_chunk, +1, axis=1)) / (2 * xres)
    dzdy = (np.roll(elev_chunk, -1, axis=0) - np.roll(elev_chunk, +1, axis=0)) / (2 * yres)
    slope_rad = np.arctan(np.sqrt(dzdx**2 + dzdy**2))
    slope_deg = np.degrees(slope_rad)
    aspect_rad = np.arctan2(dzdy, -dzdx)
    aspect_deg = np.degrees(aspect_rad)
    aspect_deg = np.where(aspect_deg < 0, 90.0 - aspect_deg, 360.0 - aspect_deg + 90.0)
    aspect_deg = np.where((dzdx == 0) & (dzdy == 0), -1.0, aspect_deg)
    return slope_deg, aspect_deg

def process_block(elev, i0, i1, j0, j1, xres, yres):
    sub = elev[i0-1:i1+1, j0-1:j1+1]
    slope_block, aspect_block = compute_chunk(sub, xres, yres)
    return slope_block[1:-1, 1:-1], aspect_block[1:-1, 1:-1], (i0, i1, j0, j1)

# Wrapper so imap gets a single tuple argument
def process_block_wrapper(args, elev, xres, yres):
    i0, i1, j0, j1 = args
    return process_block(elev, i0, i1, j0, j1, xres, yres)

def main():
    start_time = time()
    print("[STEP 1] Downloading or verifying dataset...")
    download_file(URL, NCFILE)

    print("[STEP 2] Opening NetCDF dataset...")
    ds = xr.open_dataset(NCFILE)
    elev = ds['Band1'].values

    # Resolution calculation
    lon_res_deg = float(ds['lon'].diff('lon').mean().values)
    lat_res_deg = float(ds['lat'].diff('lat').mean().values)
    meters_per_deg_lat = 111320
    meters_per_deg_lon = 111320 * np.cos(np.deg2rad(ds['lat'].mean().values))
    xres = lon_res_deg * meters_per_deg_lon
    yres = lat_res_deg * meters_per_deg_lat

    print(f"[INFO] Elevation grid shape: {elev.shape}")
    print(f"[INFO] Resolution (approx): x={xres:.2f} m, y={yres:.2f} m")

    print("[STEP 3] Generating processing tasks...")
    block_rows, block_cols = 500, 500
    tasks = []
    for i0 in range(1, elev.shape[0], block_rows):
        i1 = min(i0 + block_rows, elev.shape[0]-1)
        for j0 in range(1, elev.shape[1], block_cols):
            j1 = min(j0 + block_cols, elev.shape[1]-1)
            tasks.append((i0, i1, j0, j1))
    print(f"[INFO] Total tasks: {len(tasks)}")

    # DEBUG: only process a subset for testing
    tasks = tasks[:10]
    print(f"[DEBUG] Limiting processing to {len(tasks)} tasks")


    print(f"[STEP 4] Computing slope and aspect in parallel on {cpu_count()} cores...")
    total_tasks = len(tasks)
    processed = 0
    results = []

    with Pool(processes=cpu_count()) as pool:
        for result in pool.imap(partial(process_block_wrapper, elev=elev, xres=xres, yres=yres), tasks):
            results.append(result)
            processed += 1
            if processed % 50 == 0 or processed == total_tasks:
                pct = (processed / total_tasks) * 100
                print(f"[PROGRESS] {processed}/{total_tasks} blocks ({pct:.1f}%) complete")
                sys.stdout.flush()

    print("[INFO] All chunks processed.")

    print("[STEP 5] Merging results...")
    slope = np.full(elev.shape, np.nan, dtype=np.float32)
    aspect = np.full(elev.shape, np.nan, dtype=np.float32)
    for idx, (slope_block, aspect_block, (i0, i1, j0, j1)) in enumerate(results, 1):
        slope[i0:i1, j0:j1] = slope_block
        aspect[i0:i1, j0:j1] = aspect_block
        if idx % 50 == 0 or idx == len(results):
            print(f"[INFO] Merged {idx}/{len(results)} blocks")

    print("[STEP 6] Calculating elevation stats...")
    quantiles = np.nanpercentile(elev, [10, 25, 50, 75, 90])
    print(f"[INFO] Elevation quantiles (m): {quantiles}")
    low5 = np.sum(elev < 5)
    low10 = np.sum(elev < 10)
    print(f"[INFO] Cells <5 m: {low5}, <10 m: {low10}")

    print("[STEP 7] Writing GeoTIFF outputs...")
    transform = from_origin(ds['lon'].min().values, ds['lat'].max().values, lon_res_deg, lat_res_deg)
    profile = {
        'driver': 'GTiff',
        'dtype': rasterio.float32,
        'nodata': -9999,
        'width': elev.shape[1],
        'height': elev.shape[0],
        'count': 1,
        'crs': 'EPSG:4326',
        'transform': transform
    }

    outputs = [
        ('slope.tif', slope),
        ('aspect.tif', aspect),
        ('elevation.tif', elev.astype(np.float32))
    ]
    for filename, array in outputs:
        with rasterio.open(filename, 'w', **profile) as dst:
            dst.write(array, 1)
        print(f"[INFO] Wrote {filename}")

    total_time = time() - start_time
    print(f"[DONE] All processing complete in {total_time:.2f} seconds.")

    print_tif_info("slope.tif")
    print_tif_info("aspect.tif")
    print_tif_info("elevation.tif")


if __name__ == '__main__':
    main()
