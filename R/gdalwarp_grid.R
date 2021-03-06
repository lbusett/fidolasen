#' @title Warp basing on the grid of another file
#' @description The function apply [gdalwarp] to build rasters with the
#'  same projection, resolution and grid alignment of another raster.
#'  If not specified, the output format of each file is the same of the
#'  corresponding source file.
#' @param srcfiles A vector of input file paths (managed by GDAL).
#' @param dstfiles A vector of input file paths.
#' @param ref Path of the raster taken as reference.
#' @param of The output format (use the short format name). Default is
#'  the format of every input filename.
#' @param ... Additional parameters of [gdalwarp] (different from `s_srs`,
#'  `t_srs`, `te`, `tr`, `ts` and `of`).
#' @return NULL
#' @importFrom rgdal GDALinfo
#' @importFrom gdalUtils gdalwarp
#' @importFrom methods as
#' @importFrom reticulate import py_to_r
#' @author Luigi Ranghetti, phD (2017) \email{ranghetti.l@@irea.cnr.it}
#' @note License: GPL 3.0
#' @examples
#' \dontrun{
#' ex_sel <- c("/path/of/existing/input/file.tif",
#'             "/path/of/existing/input/anotherfile.jp2")
#' ex_ref <- "/path/of/the/reference/file.jp2"
#' ex_out <- c("/path/of/the/output/file.tif",
#'             "/path/of/the/output/anotherfile.jp2")
#'
#' gdalwarp_grid(ex_sel, ex_out, ex_ref, dstnodata=0, overwrite=TRUE)
#' }

gdalwarp_grid <- function(srcfiles,
                          dstfiles,
                          ref,
                          of = NULL,
                          ...) {

  # import python modules
  gdal <- import("osgeo",convert=FALSE)$gdal

  # read ref parameters
  ref_metadata <- suppressWarnings(GDALinfo(ref))
  ref_res <- ref_metadata[c("res.x","res.y")]
  ref_min <- ref_metadata[c("ll.x","ll.y")]
  ref_proj <- attr(ref_metadata, "projection")

  # check consistency between inputs and outputs
  if (length(srcfiles) != length(dstfiles)) {
    print_message(type="error", "\"srcfiles\" and \"dstfiles\" must be of the same length.")
  }

  # check output format
  if (!is.null(of)) {
    sel_driver <- gdal$GetDriverByName(of)
    if (is.null(py_to_r(sel_driver))) {
      print_message(
        type="error",
        "Format \"",of,"\" is not recognised; ",
        "please use one of the formats supported by your GDAL installation.\n\n",
        "To list them, use the following command:\n",
        "gdalUtils::gdalinfo(formats=TRUE)\n\n",
        "To search for a specific format, use:\n",
        "gdalinfo(formats=TRUE)[grep(\"yourformat\", gdalinfo(formats=TRUE))]")
    }
  }

  # cycle on each infiles
  for (i in seq_along(srcfiles)) {
    srcfile <- srcfiles[i]
    dstfile <- dstfiles[i]

    # read infile parameters
    sel_metadata <- suppressWarnings(GDALinfo(srcfile))
    sel_res <- sel_metadata[c("res.x","res.y")]
    sel_proj <- attr(sel_metadata, "projection")
    sel_bbox <- matrix(
      c(sel_metadata[c("ll.x","ll.y")],
        sel_metadata[c("ll.x","ll.y")] + sel_metadata[c("rows","columns")] * sel_res),
      ncol=2)
    dimnames(sel_bbox) <- list(c("x","y"),c("min","max"))
    sel_extent <- get_extent(sel_bbox, sel_proj)
    of <- ifelse (is.null(of), attr(sel_metadata, "driver"), of)

    # get reprojected extent
    out_extent <- reproj_extent(sel_extent, ref_proj)

    # allineate out_extent to ref grid
    out_bbox_mod <- round((as(out_extent, "matrix") - ref_min) / ref_res) * ref_res + ref_min
    # out_extent_mod <- get_extent(out_bbox_mod, ref_proj)

    # warp
    # (using gdalwarp() instead of calling gdalwarp from system() is a bit slower,
    # but it easily allows to pass additional parameters)
    gdalwarp(srcfile = srcfile, dstfile = dstfile,
             s_srs = sel_proj, t_srs = ref_proj,
             te = c(out_bbox_mod),
             tr = ref_res,
             of = of,
             ...)

  }

}
