#' Decode Base64 Data URL to Raw Bytes
#'
#' @param data_url Character string containing a base64 image data URL (e.g. "data:image/jpeg;base64,...").
#' @return Raw byte vector.
#' @export
decode_base64_image <- function(data_url) {
  if (is.null(data_url) || !nzchar(data_url)) return(raw(0))
  b64 <- sub("^data:image/[a-zA-Z0-9+.-]+;base64,", "", data_url)
  base64enc::base64decode(b64)
}

#' Convert Camera Snapshot or Raw Image Bytes to EBImage Array
#'
#' Converts raw image bytes, a base64 data URL, or a camera snapshot object directly
#' into an \code{EBImage::Image} object for immediate computer vision, filtering, or quantitative analysis.
#'
#' @param x Raw byte vector, base64 character string, or snapshot list returned by \code{usbCameraServer}.
#' @return An \code{EBImage::Image} object.
#' @export
#' @examples
#' \dontrun{
#' img <- as_ebimage(snapshot()$raw_bytes)
#' EBImage::display(img)
#' }
as_ebimage <- function(x) {
  if (!requireNamespace("EBImage", quietly = TRUE)) {
    stop("Package 'EBImage' must be installed to use 'as_ebimage()'.")
  }
  raw_bytes <- if (is.list(x) && !is.null(x$raw_bytes)) {
    x$raw_bytes
  } else if (is.character(x)) {
    decode_base64_image(x)
  } else if (is.raw(x)) {
    x
  } else {
    stop("Input must be a raw vector, a base64 string, or a snapshot list object.")
  }

  if (length(raw_bytes) == 0) return(NULL)

  tf <- tempfile(fileext = ".jpg")
  on.exit(unlink(tf), add = TRUE)
  writeBin(raw_bytes, tf)
  EBImage::readImage(tf)
}

#' Save Camera Snapshot to File
#'
#' Writes a snapshot's raw bytes directly to a file on disk.
#'
#' @param snapshot Snapshot object or raw byte vector.
#' @param file_path Destination file path.
#' @return Normalized absolute path of the written file.
#' @export
save_camera_image <- function(snapshot, file_path) {
  raw_bytes <- if (is.list(snapshot) && !is.null(snapshot$raw_bytes)) {
    snapshot$raw_bytes
  } else if (is.raw(snapshot)) {
    snapshot
  } else if (is.character(snapshot)) {
    decode_base64_image(snapshot)
  } else {
    stop("Input must be a raw vector, a base64 string, or a snapshot list.")
  }

  dir.create(dirname(file_path), showWarnings = FALSE, recursive = TRUE)
  writeBin(raw_bytes, file_path)
  invisible(normalizePath(file_path, mustWork = FALSE))
}
