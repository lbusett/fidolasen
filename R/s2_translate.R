#' @title Convert from SAFE format
#' @description The function build a virtual raster from a Sentinel2 SAFE product,
#'  eventually translating it in another spatial format.
#'  For now, only L1C and L2a with long name (< 2016/12/06) are recognised.
#'  Output vrt is at 10m resolution.
#' @param infile Full path of the input SAFE folder (alternatively,
#'  full path of the xml file of the product with metadata).
#' @param outdir (optional) Full name of the output directory where
#'  the files should be created (default: current directory).
#'  `outdir` can bot be an existing or non-existing directory (in the
#'  second case, its parent directory must exists).
#'  If it is a relative path, it is expanded from the directory of `infile`.
#' @param subdirs (optional) Logical: if TRUE, differet output products are
#'  placed in separated `outdir` subdirectories; if FALSE, they are placed in
#'  `outdir` directory; if NA (default), subdirectories are created only if
#'  `prod_type` has length > 1.
#' @param tmpdir (optional) Path where intermediate VRT will be created.
#'  Default is in a hidden subdirectory (called `.vrt`) of the parent
#'  directory of the SAFE folder. Set `tmpdir=tempdir()` if you do not want to
#'  keep the intermediate files after reboot.
#' @param prod_type (optional) Vector of types to be produced as outputs
#'  (see [s2_shortname] for the list of accepted values). Default is
#'  reflectance ("TOA" for level 1C, "BOA" for level 2A).
#' @param res (optional) Spatial resolution (one between '10m', '20m' or '60m');
#'  default is '10m'. Notice that, choosing '10m' or '20m', bands with lower
#'  resolution will be rescaled to `res`. Band 08 is used with `res = '10m'`,
#'  band 08A with `res = '20m'` and `res = '60m'`.
#' @param format (optional) Format of the output file (in a
#'  format recognised by GDAL). Default value is "VRT" (Virtual Raster).
#' @param compress (optional) In the case a GTiff format is
#'  chosen, the compression indicated with this parameter is used.
#' @param vrt_rel_paths (optional) Logical: if TRUE (default), the paths
#'  present in the VRT output file are relative to the VRT position;
#'  if FALSE, they are absolute. This takes effect only with
#'  `format = "VRT"`.
#' @param utmzone (optional) UTM zone of output products (default:
#'  the first one retrieved from input granules). Note that this function
#'  does not perform reprojections: if no granules refer to the specified
#'  UTM zone, no output is created.
#' @return A vector with the names of the created output files.
#' @author Luigi Ranghetti, phD (2017) \email{ranghetti.l@@irea.cnr.it}
#' @note License: GPL 3.0
#' @export
#' @importFrom reticulate import import_builtins py_str py_to_r
#' @examples \dontrun{
#' s2_l1c_example <- file.path(
#'   "/existing/path",
#'   "S2A_MSIL1C_20170603T101031_N0205_R022_T32TQQ_20170603T101026.SAFE")
#' s2_l1c_example <- file.path(
#'   "/existing/path",
#'   "S2A_MSIL2A_20170603T101031_N0205_R022_T32TQQ_20170603T101026.SAFE")
#'
#' # Create a single TOA GeoTIFF in the same directory
#' s2_translate(s2_l1c_example, format="GTiff")
#'
#' # Create a single BOA VRT with a custom name
#' s2_translate(s2_l2a_example, "/new/path/example_sentinel2_sr.vrt",
#'   vrt_rel_paths=TRUE)
#'
#' # Create three products (ENVI) in the same directory at 60m resolution
#' s2_translate(s2_example, format="ENVI", prod_type=c("BOA","TCI","SCL"),
#'   res="60m", subdirs=TRUE)
#'}

s2_translate <- function(infile,
                         outdir=".",
                         subdirs=NA,
                         tmpdir=NA,
                         prod_type=NULL,
                         res="10m",
                         format="VRT",
                         compress="DEFLATE",
                         vrt_rel_paths="TRUE",
                         utmzone="") {

  # import python modules
  py <- import_builtins(convert=FALSE)
  sys <- import("sys",convert=FALSE)
  gdal <- import("osgeo",convert=FALSE)$gdal

  # check res (and use the resolutions >= specified res)
  if (!res %in% c("10m","20m","60m")) {
    print_message(
      type="error",
      "\"res\" value is not recognised (accepted values are '10m', '20m' ",
      "and '60m').")
  }
  if (res == "10m") {
    res <- c("10m","20m","60m")
  } else if (res == "20m") {
    res <- c("20m","60m")
  }

  # check output format
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

  # Check GDAL installation
  check_gdal(abort=TRUE)

  # Retrieve xml required metadata
  infile_meta <- s2_getMetadata(infile, c("xml_main","xml_granules","utm","level","tiles", "jp2list"))
  infile_dir = dirname(infile_meta$xml_main)

  # define output directory
  suppressWarnings(outdir <- expand_path(outdir, parent=dirname(infile_dir), silent=TRUE))
  dir.create(outdir, recursive=FALSE, showWarnings=FALSE)
  # create subdirs
  if (is.na(subdirs)) {
    subdirs <- ifelse(length(prod_type)>1, TRUE, FALSE)
  }
  if (subdirs) {
    sapply(file.path(outdir,prod_type), dir.create, showWarnings=FALSE)
  }

  # check compression value
  if (format=="GTiff") {
    if (!compress %in% c("JPEG","LZW","PACKBITS","DEFLATE","CCITTRLE",
                         "CCITTFAX3","CCITTFAX4","LZMA","NONE")) {
      print_message(type="warning",
                    "'",toupper(compress),"' is not a valid compression value; ",
                    "the default 'DEFLATE' value will be used.")
      compress <- "DEFLATE"
    }
  }

  # retrieve UTM zone
  if (utmzone=="") {
    print_message(
      type="message",
      "Using UTM zone ",sel_utmzone <- infile_meta$utm[1],".")
  } else {
    sel_utmzone <- which(infile_meta$utm== as.integer(utmzone))
    if (length(sel_utmzone)==0) {
      print_message(
        type="warning",
        "Tiles with UTM zone ",utmzone," are not present: zone ",
        sel_utmzone <- infile_meta$utm[1]," will be used.")
    }
  }

  # select default product type if missing
  if (is.null(prod_type)) {
    if (infile_meta$level=="1C") {
      prod_type <- "TOA"
    } else if (infile_meta$level=="2A") {
      prod_type <- "BOA"
    }
  }

  # define output extension
  out_ext <- if (format=="ENVI") {
    "dat"
  } else {
    unlist(strsplit(paste0(py_to_r(sel_driver$GetMetadataItem(gdal$DMD_EXTENSIONS))," ")," "))[1]
  }

  # create a file / set of files for each prod_type
  out_names <- character(0) # names of created files
  for (sel_prod in prod_type) {

    if (sel_prod %in% c("BOA","TOA")) {
      sel_type <- "MSI"
    } else {
      sel_type <- sel_prod
    }

    # define NA flag
    sel_na <- switch(sel_prod,
                     BOA = "65535",
                     TOA = "65535",
                     SCL = "0",
                     TCI = NA,
                     NA)
    # define output subdir
    out_subdir <- ifelse(subdirs, file.path(outdir,sel_prod), outdir)

    # TODO check that required bands are present

    # cycle on granules (with compact names, this runs only once; with old name, one or more)
    for (sel_granule in infile_meta$xml_granules) {

      sel_tile <- s2_getMetadata(dirname(sel_granule), "nameinfo")$id_tile

      # define output basename
      out_prefix <- s2_shortname(sel_granule, prod_type=sel_prod, res=res[1], full.name=FALSE, abort=TRUE)
      # complete output filename
      out_name <- file.path(out_subdir,paste0(out_prefix,".",out_ext))

      # select required bands from the list and order them by resolution
      jp2df_selbands <- infile_meta$jp2list[infile_meta$jp2list$type==sel_type &
                                            infile_meta$jp2list$tile==sel_tile,]
      jp2df_selbands <- jp2df_selbands[with(jp2df_selbands,order(band,res)),]
      # remove lower resolutions and keep only the best resolution for each band
      if (!any(jp2df_selbands$res=="")) {
        jp2df_selbands <- jp2df_selbands[as.integer(substr(jp2df_selbands$res,1,2))>=as.integer(substr(res[1],1,2)),]
      } else {
        # for oldname L1C (which do not have "res" in granule name) remove B08 or B8A basing on the requested "res"
        if (as.integer(substr(res[1],1,2)) < 20) {
          jp2df_selbands <- jp2df_selbands[-grep("B8A.jp2$",jp2df_selbands$layer),]
        } else {
          jp2df_selbands <- jp2df_selbands[-grep("B08.jp2$",jp2df_selbands$layer),]
        }
      }
      jp2df_selbands <- jp2df_selbands[!duplicated(with(jp2df_selbands,paste(band,tile))),]
      # extract vector of paths
      jp2_selbands <- file.path(infile_dir,jp2df_selbands[,"relpath"])

      # create final vrt with all the bands (of select final raster with a single band)
      if (length(jp2_selbands)>1) {
        # define and create tmpdir
        if (is.na(tmpdir)) {
          tmpdir <- file.path(dirname(infile_dir),".vrt")
        }
        dir.create(tmpdir, showWarnings=FALSE)
        final_vrt_name <- ifelse(format=="VRT", out_name, paste0(tmpdir,"/",out_prefix,".vrt"))
        system(
          paste0(
            Sys.which("gdalbuildvrt")," -separate ",
            "-resolution highest ",
            "\"",final_vrt_name,"\" ",
            paste(paste0("\"",jp2_selbands,"\""), collapse=" ")
          ),
          intern = Sys.info()["sysname"] == "Windows"
        )
        if (vrt_rel_paths==TRUE) {
          gdal_abs2rel(out_name)
        }
      } else {
        final_vrt_name <- jp2_selbands
      }

      # create output file (or copy vrt file)
      if (format != "VRT" | length(jp2_selbands)==1) {
        system(
          paste0(
            Sys.which("gdal_translate")," -of ",format," ",
            if (format=="GTiff") {paste0("-co COMPRESS=",toupper(compress)," ")},
            if (!is.na(sel_na)) {paste0("-a_nodata ",sel_na," ")},
            "\"",final_vrt_name,"\" ",
            "\"",out_name,"\""
          ), intern = Sys.info()["sysname"] == "Windows"
        )
        if (format == "VRT" & vrt_rel_paths==TRUE) {
          gdal_abs2rel(out_name)
        }
      }

      out_names <- c(out_names, out_name)

    } # end of sel_granule cycle

  } # end of prod_type cycle

  print_message(type="message",
                length(out_names)," output files were correctly created.")
  return(out_names)

}

