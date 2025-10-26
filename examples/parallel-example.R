library(terra)
library(ncdf4)
library(parallel)

URL <- "https://www.ngdc.noaa.gov/thredds/fileServer/regional/central_oregon_13_navd88_2015.nc"
NCFILE <- "central_oregon_13_navd88_2015.nc"

download_file <- function(url, local_path) {
  if (!file.exists(local_path)) {
    cat("[INFO] Downloading file from", url, "\n")
    download.file(url, destfile = local_path, mode = "wb", quiet = FALSE)
    cat("[INFO] File saved to", local_path, "\n")
  } else {
    cat("[INFO] File already exists:", local_path, "\n")
  }
}

print_tif_info <- function(filepath) {
  r <- rast(filepath)
  e <- ext(r)
  cat("[INFO] File:", filepath, "\n")
  cat("  Width:", ncol(r), "\n")
  cat("  Height:", nrow(r), "\n")
  cat("  CRS:", crs(r), "\n")
  cat(sprintf("  Extent: xmin=%.6f xmax=%.6f ymin=%.6f ymax=%.6f\n", e[1], e[2], e[3], e[4]))
  vals <- values(r, mat = FALSE)
  vals <- vals[!is.na(vals)]
  if (length(vals) > 0) {
    cat("  Min:", min(vals), "\n")
    cat("  Max:", max(vals), "\n")
    cat("  Mean:", mean(vals), "\n")
  } else {
    cat("  Min/Max/Mean: No valid data\n")
  }
  cat("\n")
}

compute_chunk <- function(elev_chunk, xres, yres) {
  dzdx <- (cbind(elev_chunk[, -1], elev_chunk[, ncol(elev_chunk)]) -
           cbind(elev_chunk[, 1], elev_chunk[, -ncol(elev_chunk)])) / (2 * xres)

  dzdy <- (rbind(elev_chunk[-1, ], elev_chunk[nrow(elev_chunk), ]) -
           rbind(elev_chunk[1, ], elev_chunk[-nrow(elev_chunk), ])) / (2 * yres)

  slope_rad <- atan(sqrt(dzdx^2 + dzdy^2))
  slope_deg <- slope_rad * 180 / pi

  aspect_rad <- atan2(dzdy, -dzdx)
  aspect_deg <- aspect_rad * 180 / pi
  aspect_deg[aspect_deg < 0] <- 90 - aspect_deg[aspect_deg < 0]
  aspect_deg[aspect_deg >= 0] <- 360 - aspect_deg[aspect_deg >= 0] + 90
  aspect_deg[dzdx == 0 & dzdy == 0] <- -1

  list(slope = slope_deg, aspect = aspect_deg)
}

process_block <- function(task, elev, xres, yres) {
  i0 <- task[1]; i1 <- task[2]; j0 <- task[3]; j1 <- task[4]
  sub <- elev[(i0-1):(i1+1), (j0-1):(j1+1)]
  chunk <- compute_chunk(sub, xres, yres)
  slope_block <- chunk$slope[2:(nrow(chunk$slope)-1), 2:(ncol(chunk$slope)-1)]
  aspect_block <- chunk$aspect[2:(nrow(chunk$aspect)-1), 2:(ncol(chunk$aspect)-1)]
  list(slope = slope_block, aspect = aspect_block, range = c(i0, i1, j0, j1))
}

main <- function() {
  start_time <- Sys.time()
  cat("[STEP 1] Downloading or verifying dataset...\n")
  download_file(URL, NCFILE)

  cat("[STEP 2] Opening NetCDF dataset...\n")
  nc <- nc_open(NCFILE)
  elev <- ncvar_get(nc, "Band1")
  lon <- ncvar_get(nc, "lon")
  lat <- ncvar_get(nc, "lat")
  nc_close(nc)

  lon_res_deg <- mean(diff(lon))
  lat_res_deg <- mean(diff(lat))
  meters_per_deg_lat <- 111320
  meters_per_deg_lon <- 111320 * cos(mean(lat) * pi / 180)
  xres <- lon_res_deg * meters_per_deg_lon
  yres <- lat_res_deg * meters_per_deg_lat

  # Export needed vars to global environment for cluster
  assign("elev", elev, envir = .GlobalEnv)
  assign("xres", xres, envir = .GlobalEnv)
  assign("yres", yres, envir = .GlobalEnv)

  cat("[INFO] Elevation grid shape:", dim(elev)[1], "x", dim(elev)[2], "\n")
  cat(sprintf("[INFO] Resolution (approx): x=%.2f m, y=%.2f m\n", xres, yres))

  cat("[STEP 3] Generating processing tasks...\n")
  block_rows <- 500
  block_cols <- 500
  tasks <- list()
  for (i0 in seq(2, nrow(elev)-1, by = block_rows)) {
    i1 <- min(i0 + block_rows - 1, nrow(elev)-1)
    for (j0 in seq(2, ncol(elev)-1, by = block_cols)) {
      j1 <- min(j0 + block_cols - 1, ncol(elev)-1)
      tasks[[length(tasks)+1]] <- c(i0, i1, j0, j1)
    }
  }
  cat("[INFO] Total tasks:", length(tasks), "\n")

  tasks <- tasks[1:min(10, length(tasks))]
  cat("[DEBUG] Limiting processing to", length(tasks), "tasks\n")

  cat("[STEP 4] Computing slope and aspect in parallel...\n")
  cl <- makeCluster(detectCores())
  clusterExport(cl, c("elev", "xres", "yres", "compute_chunk", "process_block"))
  results <- parLapply(cl, tasks, process_block, elev = elev, xres = xres, yres = yres)
  stopCluster(cl)
  cat("[INFO] All chunks processed.\n")

  cat("[STEP 5] Merging results...\n")
  slope <- matrix(NA, nrow = nrow(elev), ncol = ncol(elev))
  aspect <- matrix(NA, nrow = nrow(elev), ncol = ncol(elev))
  for (res in results) {
    i0 <- res$range[1]; i1 <- res$range[2]; j0 <- res$range[3]; j1 <- res$range[4]
    slope[i0:i1, j0:j1] <- res$slope
    aspect[i0:i1, j0:j1] <- res$aspect
  }

  cat("[STEP 6] Calculating elevation stats...\n")
  elev_vals <- as.vector(elev)
  elev_vals <- elev_vals[!is.na(elev_vals)]
  quantiles <- quantile(elev_vals, probs = c(0.1, 0.25, 0.5, 0.75, 0.9))
  cat("[INFO] Elevation quantiles (m):", quantiles, "\n")
  cat("[INFO] Cells <5 m:", sum(elev_vals < 5), "\n")
  cat("[INFO] Cells <10 m:", sum(elev_vals < 10), "\n")

  cat("[STEP 7] Writing GeoTIFF outputs...\n")
  r_slope <- rast(slope, extent = c(min(lon), max(lon), min(lat), max(lat)), crs = "EPSG:4326")
  r_aspect <- rast(aspect, extent = c(min(lon), max(lon), min(lat), max(lat)), crs = "EPSG:4326")
  r_elev <- rast(elev, extent = c(min(lon), max(lon), min(lat), max(lat)), crs = "EPSG:4326")

  writeRaster(r_slope, "slope.tif", overwrite = TRUE, NAflag = -9999)
  writeRaster(r_aspect, "aspect.tif", overwrite = TRUE, NAflag = -9999)
  writeRaster(r_elev, "elevation.tif", overwrite = TRUE, NAflag = -9999)
  cat("[INFO] GeoTIFF files written.\n")

  total_time <- difftime(Sys.time(), start_time, units = "secs")
  cat(sprintf("[DONE] All processing complete in %.2f seconds.\n", as.numeric(total_time)))

  print_tif_info("slope.tif")
  print_tif_info("aspect.tif")
  print_tif_info("elevation.tif")
}

main()
