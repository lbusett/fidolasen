#' @title Clip, reproject and warp raster files
#' @description The function applies [gdal_translate] or [gdalwarp]
#'  to clip, reproject and/or warp raster files. The choice of the
#'  algorythm is based on the comparison between input and output
#'  projections ([gdal_translate] if they are equal, [gdalwarp] elsewhere).
#'  If not specified, the output format of each file is the same of the
#'  corresponding source file.
#' @param srcfiles A vector of input file paths (managed by GDAL).
#' @param dstfiles A vector of corresponding output file paths.
#' @param of The output format (use the short format name). Default is
#'  the format of every input filename.
#' @param ref Path of the raster taken as reference: if provided,
#'  parameters regarding the output grid (alignment, resolution and
#'  extent) are taken from this raster. To set differently some of
#'  these values, specify also other values of `mask` and/or `tr`.
#'  `t_srs` parameter value is always ignored when `ref` is provided.
#' @param mask Spatial path or object from which to take the extent
#'  of output files. If it is a polygon, this is used as masking layer;
#'  otherwise, only the bounding box  is considered;. If both `ref`
#'  and `mask` are provided, this parameter will overlay the extent of the
#'  reference raster. In order to take only the grid from `res` and not
#'  to clip on its extent, set `mask=NA`. Notice that the output
#'  projection is never taken from `mask`.
#' @param tr Numeric. (`c(xres,yres)`). set output file resolution
#'  (in target georeferenced units). If bot `ref` and `tr` are provided,
#'  `tr` is rounded in order to match the exact extent.
#' @param t_srs Target spatial reference set (character). The coordinate
#'  systems that can be passed are anything supported by the
#'  OGRSpatialReference.SetFromUserInput() call, which includes EPSG
#'  PCS and GCSes (ie. EPSG:4296), PROJ.4 declarations (as above),
#'  or the name of a .prf file containing well known text.
#' @param r Resampling_method ("near"|"bilinear"|"cubic"|"cubicspline"|
#' "lanczos"|"average"|"mode"|"max"|"min"|"med"|"q1"|"q3").
#' @param dstnodata Set nodata values for output bands (different values
#'  can be supplied for each band). If more than one value is supplied
#'  all values should be quoted to keep them together as a single
#'  operating system argument. New files will be initialized to this
#'  value and if possible the nodata value will be recorded in the output
#'  file. Use a value of NA to ensure that nodata is not defined.
#'  If this argument is not used then nodata values will be copied from
#'  the source datasets. At the moment it is not possible to set different
#'  values for different `srcfiles` (use multiple calls of the functions).
#' @param ... Additional parameters of [gdalwarp] or [gdal_translate]
#'  (different from `s_srs`, `t_srs`, `te`, `tr`, `ts` and `of`).
#' @return NULL
#' @export
#' @importFrom rgdal GDALinfo CRSargs
#' @importFrom gdalUtils gdalwarp gdal_translate
#' @importFrom sp CRS
#' @importFrom sf st_transform st_geometry_type st_write st_cast
#' @importFrom methods as
#' @importFrom reticulate import py_to_r
#' @importFrom magrittr "%>%"
#' @importFrom sprawl cast_vect get_spatype
#' @author Luigi Ranghetti, phD (2017) \email{ranghetti.l@@irea.cnr.it}
#' @note License: GPL 3.0
#' @examples
#' \dontrun{
#' srcfiles <- c("/path/of/a/s2/file.tif",
#'               "/path/of/another/s2/file.tif")
#' crop_poly <- c("/path/of/a/polygon/vector.shp")
#'
#' # Simple clip
#' gdal_warp(srcfiles[1],
#'           test0_clip <- file.path(tempdir(),"test0_clip.tif"),
#'           mask = get_extent(crop_poly))
#'
#' # Clip and mask
#' gdal_warp(srcfiles,
#'           test0_mask <- c(file.path(tempdir(),"test0_mask.tif"),
#'                           tempfile()),
#'           mask = crop_poly)
#'
#' # Warp on a reference raster
#' gdal_warp(srcfiles[1],
#'           test1 <- file.path(tempdir(),"test1.tif"),
#'           ref = test0_mask[1])
#'
#' # Reproject all the input file
#' gdal_warp(srcfiles[1],
#'           test2 <- file.path(tempdir(),"test2.tif"),
#'           t_srs = "+init=epsg:32631")
#'
#' # Reproject and clip on a bounding box
#' gdal_warp(srcfiles[1],
#'           test3a <- file.path(tempdir(),"test3a.tif"),
#'           mask = get_extent(crop_poly),
#'           t_srs = "+init=epsg:32631")
#' # Reproject and clip on polygon (masking outside)
#' gdal_warp(srcfiles[1],
#'           test3b <- file.path(tempdir(),"test3b.tif"),
#'           mask = crop_poly,
#'           t_srs = "+init=epsg:32631")
#' # Workaround to clip on a bounding box without
#' # enlarging it too much (cause of the reprojection)
#' gdal_warp(srcfiles[1],
#'           test3c <- file.path(tempdir(),"test3c.tif"),
#'           mask = st_cast(crop_poly,"LINESTRING"),
#'           t_srs = "+init=epsg:32631")
#'
#' # Use a reference raster with a different projection
#' gdal_warp(srcfiles[1],
#'           test4a <- file.path(tempdir(),"test4a.tif"),
#'           ref = test3b)
#' # Use a reference raster with a different projection
#' # and specify a different bounding box
#' gdal_warp(srcfiles[1],
#'           test4b <- file.path(tempdir(),"test4b.tif"),
#'           mask = test0_clip,
#'           ref = test3b)
#' # Use a reference raster with a different projection and a mask
#' gdal_warp(srcfiles[1],
#'           test4c <- file.path(tempdir(),"test4c.tif"),
#'           mask = crop_poly,
#'           ref = test3b)
#' }

gdal_warp <- function(srcfiles,
                      dstfiles,
                      of = NULL,
                      ref = NULL,
                      mask = NULL,
                      tr = NULL,
                      t_srs = NULL,
                      r = NULL,
                      dstnodata = NULL,
                      ...) {

  # import python modules
  gdal <- import("osgeo",convert=FALSE)$gdal

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

  # if "ref" is specified, read ref parameters
  if (!is.null(ref)) {
    ref_metadata <- suppressWarnings(GDALinfo(ref))
    ref_res <- ref_metadata[c("res.x","res.y")]
    ref_ll <- ref_metadata[c("ll.x","ll.y")]
    ref_size <- ref_metadata[c("columns","rows")]
    ref_bbox <- matrix(
      c(ref_ll, ref_ll + ref_size * ref_res),
      ncol=2)
    dimnames(ref_bbox) <- list(c("x","y"),c("min","max"))
    t_srs <- attr(ref_metadata, "projection") %>%
      CRS() %>% CRSargs()
    # round "tr" to ref grid
    if (is.null(tr)) {
      tr <- ref_res
    } else {
      tr <- ref_size*ref_res/round((ref_size*ref_res)/tr)
    }
  }

  # if "mask" is specified, take "mask" and "te" from it
  if (!is.null(mask)) {
    mask_type <- get_spatype(mask)
    # if it is a vector, set "te" to the bounding box (in t_srs)
    if (mask_type %in% c("sfobject","spobject","vectfile")) {
      mask <- cast_vect(mask,"sfobject")
      if (length(grep("POLYGON",st_geometry_type(mask))>1)) {
        st_write(st_cast(mask, "MULTIPOLYGON"),
                 mask_file <- paste0(tempfile(),".shp"))
      } # if not, mask_polygon is not created
    } else if (mask_type == "rastfile") {
      mask <- get_extent(mask)
    }
    if (is(mask, "sprawlext")) {
      mask <- as(mask, "sfc_POLYGON")
    }
    # create mask_bbox if t_srs is specified;
    # otherwise, create each time within srcfile cycle
    if (!is.null(t_srs)) {
      mask_bbox <- st_transform(mask, t_srs) %>%
        get_extent() %>%
        as("matrix")
    }
  }

  # cycle on each srcfile
  for (i in seq_along(srcfiles)) {
    srcfile <- srcfiles[i]
    dstfile <- dstfiles[i]

    # read infile parameters
    sel_metadata <- suppressWarnings(GDALinfo(srcfile))
    sel_res <- sel_metadata[c("res.x","res.y")]
    sel_ll <- sel_metadata[c("ll.x","ll.y")]
    sel_size <- sel_metadata[c("columns","rows")]
    sel_s_srs <- attr(sel_metadata, "projection") %>%
      CRS() %>% CRSargs()
    sel_bbox <- matrix(
      c(sel_ll, sel_ll + sel_size * sel_res),
      ncol=2)
    dimnames(sel_bbox) <- list(c("x","y"),c("min","max"))
    sel_extent <- get_extent(sel_bbox, sel_s_srs)
    sel_of <- ifelse (is.null(of), attr(sel_metadata, "driver"), of)

    # set default parameter values (if not specified)
    sel_t_srs <- ifelse(is.null(t_srs), sel_s_srs, t_srs)
    sel_tr <- if (is.null(tr)) {sel_res} else {tr}
    # default method: near if the target resolution is lower than an half of the source,
    # mode elsewhere
    sel_r <- if (is.null(r)) {
      ifelse(all(2*tr < sel_res), "near", "mode")
    } else {
      r
    }

    # get reprojected extent
    # (if already set it was referring to mask; in this case, to srcfile)
    suppressMessages(
      sel_src_bbox <- as(reproj_extent(sel_extent, sel_t_srs), "matrix")
    )

    # set the correct bounding box for srcfile
    if (is.null(ref)) {
      if (is.null(mask)) {
        # ref NULL & mask NULL: use bbox of srcfile, reprojected
        sel_te <- sel_src_bbox
      } else if (class(mask)=="logical" && is.na(mask)) { # check if mask==NA
        # ref NULL & mask NA: the same (use bbox of srcfile, reprojected)
        sel_te <- sel_src_bbox
      } else {
        # ref NULL & mask provided: use bbox of mask, reprojected and aligned to src grid
        sel_mask_bbox <- if (exists("mask_bbox")) {
          mask_bbox
        } else {
          st_transform(mask, sel_t_srs) %>%
            get_extent() %>%
            as("matrix")
        }
        sel_te <- (sel_mask_bbox - sel_ll) / sel_tr
        sel_te <- cbind(floor(sel_te[,1]), ceiling(sel_te[,2]))
        dimnames(sel_te) <- list(c("x","y"),c("min","max"))
        sel_te <- sel_te * sel_tr + sel_ll
      }
    } else {
      if (is.null(mask)) {
        # ref provided & mask NULL: use bbox of ref
        sel_te <- ref_bbox
      } else if (class(mask)=="logical" && is.na(mask)) {
        # ref provided & mask NA: use bbox of srcfile (reprojected and aligned to ref grid)
        sel_te <- (sel_src_bbox - ref_ll) / sel_tr
        sel_te <- cbind(floor(sel_te[,1]), ceiling(sel_te[,2]))
        dimnames(sel_te) <- list(c("x","y"),c("min","max"))
        sel_te <- sel_te * sel_tr + ref_ll
      } else {
        # ref provided & mask provided: use bbox of mask (reprojected and aligned to ref grid)
        sel_mask_bbox <- if (exists("mask_bbox")) {
          mask_bbox
        } else {
          st_transform(mask, sel_t_srs) %>%
            get_extent() %>%
            as("matrix")
        }
        sel_te <- (sel_mask_bbox - ref_ll) / sel_tr
        sel_te <- cbind(floor(sel_te[,1]), ceiling(sel_te[,2]))
        dimnames(sel_te) <- list(c("x","y"),c("min","max"))
        sel_te <- sel_te * sel_tr + ref_ll
      }
    }

    # finally, apply gdal_warp or gdal_translate
    if (compareCRS(CRS(sel_t_srs), CRS(sel_s_srs)) & !exists("mask_file")) {
      gdal_translate(src_dataset = srcfile, dst_dataset = dstfile,
               projwin = sel_te[c(1,4,3,2)],
               tr = sel_tr,
               of = sel_of,
               r = sel_r,
               a_nodata = dstnodata,
               ...)
    } else {
      gdalwarp_expr <- paste0(
        "gdalwarp(srcfile = srcfile, dstfile = dstfile, ",
        "s_srs = sel_s_srs, t_srs = sel_t_srs, ",
        "te = c(sel_te), ",
        if (exists("mask_file")) {
          "cutline = mask_file, "
        },
        "tr = sel_tr, ",
        "of = sel_of, ",
        "r = sel_r, ",
        if (!is.null(dstnodata)) {
          if (is.na(dstnodata)) {
            "dstnodata = NULL, "
          } else {
            "dstnodata = dstnodata, "
          }
        },
        "...)")
      eval(parse(text=gdalwarp_expr))
    }

  }

}
