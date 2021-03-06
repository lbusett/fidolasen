#' @title Apply cloud masks
#' @description Apply a cloud mask to a Sentinel-2 product. Since
#'  [raster] functions are used to perform computations, output files
#'  are physical rasters (no output VRT is allowed).
#' @param infiles A vector of input filenames. Input files are paths
#'  of products already converted from SAFE format to a
#'  format managed by GDAL (use [s2_translate] to do it);
#'  their names must be in the fidolasen-S2 naming convention
#'  ([s2_shortname]).
#' @param maskfiles A vector of filenames from which to take the
#'  information about cloud coverage (for now, only SCL products
#'  have been implemented). It is not necessary that `maskfiles`
#'  elements strictly match `infiles` ones. Input files are paths
#'  of products already converted from SAFE format to a
#'  format managed by GDAL (use [s2_translate] to do it);
#'  their names must be in the fidolasen-S2 naming convention
#'  ([s2_shortname]).
#' @param mask_type Character vector which determines the type of
#'  mask to be applied. Accepted values are:
#'  - "cloud_high_proba": mask pixels checked as "No data" or
#'      "Cloud (high probability)" in the SCL product;
#'  - "cloud_medium_proba": mask pixels checked as "No data" or
#'      "Cloud (high or medium probability)" in the SCL product;
#'  - "cloud_low_proba": mask pixels checked as "No data" or
#'      "Cloud (any probability)" in the SCL product;
#'  - "cloud_and_shadow": mask pixels checked as "No data",
#'      "Cloud (any probability)" or "Cloud shadow" in the SCL product;
#'  - "cloud_shadow_cirrus": mask pixels checked as "No data",
#'      "Cloud (any probability)", "Cloud shadow" or "Thin cirrus"
#'      in the SCL product;
#'  - "opaque_clouds" (still to be implemented).
#' @param outdir (optional) Full name of the output directory where
#'  the files should be created (default: "current directory"masked"
#'  subdir of current directory).
#'  `outdir` can bot be an existing or non-existing directory (in the
#'  second case, its parent directory must exists).
#'  If it is a relative path, it is expanded from the common parent
#'  directory of `infiles`.
#' @param format (optional) Format of the output file (in a
#'  format recognised by GDAL). Default is the same format of input images
#'  (or "GTiff" in case of VRT input images).
#' @param subdirs (optional) Logical: if TRUE, different indices are
#'  placed in separated `outfile` subdirectories; if FALSE, they are placed in
#'  `outfile` directory; if NA (default), subdirectories are created only if
#'  more than a single spectral index is required.
#' @param compress (optional) In the case a GTiff format is
#'  present, the compression indicated with this parameter is used.
#' @return A vector with the names of the created products.
#' @export
#' @importFrom rgdal GDALinfo
#' @importFrom reticulate import
#' @importFrom raster stack brick values mask NAvalue dataType
#' @importFrom magrittr "%>%"
#' @author Luigi Ranghetti, phD (2017) \email{ranghetti.l@@irea.cnr.it}
#' @note License: GPL 3.0

s2_mask <- function(infiles,
                    maskfiles,
                    mask_type="cloud_medium_proba",
                    outdir="./masked",
                    format=NA,
                    subdirs=NA,
                    compress="DEFLATE") {

  . <- NULL

  # import python modules
  gdal <- import("osgeo",convert=FALSE)$gdal

  # Check that files exist
  if (!any(sapply(infiles, file.exists))) {
    print_message(
      type="error",
      "The input files do not exists locally; please check file names and paths.")
  } else if (!all(sapply(infiles, file.exists))) {
    print_message(
      type="error",
      "Some of the input files (\"",
      paste(infiles[!sapply(infiles, file.exists)], collapse="\", \""),
      "\") do not exists locally; please check file names and paths.")
  }

  # check output format
  if (!is.na(format)) {
    gdal <- import("osgeo",convert=FALSE)$gdal
    sel_driver <- gdal$GetDriverByName(format)
    if (is.null(py_to_r(sel_driver))) {
      print_message(
        type="error",
        "Format \"",format,"\" is not recognised; ",
        "please use one of the formats supported by your GDAL installation.\n\n",
        "To list them, use the following command:\n",
        "gdalUtils::gdalinfo(formats=TRUE)\n\n",
        "To search for a specific format, use:\n",
        "gdalinfo(formats=TRUE)[grep(\"yourformat\", gdalinfo(formats=TRUE))]")
    }
  }

  # Get files metadata
  infiles_meta <- data.table(fs2nc_getElements(infiles, format="data.frame"))
  maskfiles_meta <- data.table(fs2nc_getElements(maskfiles, format="data.frame"))
  # suppressWarnings(
  #   infiles_meta_gdal <- sapply(infiles, function(x) {attributes(GDALinfo(x))[c("df")]})
  # )

  # create subdirs (if requested)
  prod_types <- unique(infiles_meta$prod_type)
  if (is.na(subdirs)) {
    subdirs <- ifelse(length(prod_types)>1, TRUE, FALSE)
  }
  if (subdirs) {
    sapply(file.path(outdir,prod_types), dir.create, showWarnings=FALSE)
  }

  # define required bands and formula to compute masks
  # accepted mask_type values: cloud_high_proba, cloud_medium_proba, cloud_low_proba, cloud_and_shadow, cloud_shadow_cirrus, opaque_clouds
  # structure of req_masks: list, names are prod_types, content are values of the files to set as 0, otherwise 1
  if (mask_type == "cloud_high_proba") {
    req_masks <- list("SCL"=c(0,9))
  } else if (mask_type == "cloud_medium_proba") {
    req_masks <- list("SCL"=c(0,8:9))
  } else if (mask_type == "cloud_low_proba") {
    req_masks <- list("SCL"=c(0,7:9))
  } else if (mask_type == "cloud_and_shadow") {
    req_masks <- list("SCL"=c(0,3,7:9))
  } else if (mask_type == "cloud_shadow_cirrus") {
    req_masks <- list("SCL"=c(0,3,7:10))
  } else if (mask_type == "opaque_clouds") {
    print_message(type="error", "Mask type 'opaque_clouds' has not been yet implemented.")
  }

  # cycle on each file
  outfiles <- character(0)
  for (i in seq_along(infiles)) {
    sel_infile <- infiles[i]
    sel_infile_meta <- c(infiles_meta[i,])
    sel_format <- suppressWarnings(ifelse(
      !is.na(format), format, attr(GDALinfo(sel_infile), "driver")
    )) %>% ifelse(.!="VRT",.,"GTiff")
    sel_out_ext <- ifelse(
      sel_format=="ENVI", "dat",
      unlist(strsplit(paste0(py_to_r(sel_driver$GetMetadataItem(gdal$DMD_EXTENSIONS))," ")," "))[1])

    # check that infile has the correct maskfile
    sel_maskfiles <- sapply(names(req_masks), function(m) {
      maskfiles[which(maskfiles_meta$prod_type==m &
                        maskfiles_meta$type==sel_infile_meta$type &
                        maskfiles_meta$mission==sel_infile_meta$mission &
                        maskfiles_meta$level==sel_infile_meta$level &
                        maskfiles_meta$sensing_date==sel_infile_meta$sensing_date &
                        maskfiles_meta$id_orbit==sel_infile_meta$id_orbit &
                        maskfiles_meta$res==sel_infile_meta$res)][1]
    })

    # define subdir
    out_subdir <- ifelse(subdirs, file.path(outdir,infiles_meta[i,"prod_type"]), outdir)

    # define out name (a vrt for all except the last mask)
    sel_outfile <- file.path(
      out_subdir,
      gsub(paste0("\\.",infiles_meta[i,"file_ext"],"$"),
           paste0(".",sel_out_ext),
           basename(sel_infile)))

    # create global mask
    inmask <- raster::stack(sel_maskfiles)
    outmask <- inmask[[1]]
    raster::values(outmask) <- sapply(
      seq_along(inmask@layers),
      function(i) {
        !raster::values(inmask)[,i] %in% req_masks[[i]]
      }) %>% apply(1, sum)

    inraster <- raster::brick(sel_infile)
    raster::mask(inraster,
                 outmask,
                 filename = sel_outfile,
                 maskvalue = 0,
                 updatevalue = NAvalue(inraster),
                 updateNA = TRUE,
                 datatype = dataType(inraster),
                 format = sel_format,
                 options = ifelse(sel_format=="GTiff",
                                  c(paste0("COMPRESS=",compress)),
                                  ""),
                 overwrite = TRUE)

    # fix for envi extension (writeRaster use .envi)
    if (sel_format=="ENVI" &
        file.exists(gsub(paste0("\\.",sel_out_ext,"$"),".envi",sel_outfile))) {
      file.rename(gsub(paste0("\\.",sel_out_ext,"$"),".envi",sel_outfile),
                  sel_outfile)
      file.rename(paste0(gsub(paste0("\\.",sel_out_ext,"$"),".envi",sel_outfile),".aux.xml"),
                  paste0(sel_outfile,".aux.xml"))
    }

    outfiles <- c(outfiles, sel_outfile)

  } # end on infiles cycle

  return(outfiles)

}
