#' @import htmltools
#' @import shiny
.onLoad <- function(libname, pkgname) {
  shiny::addResourcePath(
    prefix = "usbcamera",
    directoryPath = system.file("www", package = "USBCamera")
  )
}

#' USBCamera HTML Dependencies
#' @return An htmltools HTML dependency object
#' @export
usb_camera_dependency <- function() {
  htmltools::htmlDependency(
    name = "usbcamera",
    version = utils::packageVersion("USBCamera"),
    package = "USBCamera",
    src = "www",
    script = "usb_camera.js",
    stylesheet = "usb_camera.css"
  )
}
