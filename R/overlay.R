#' Create Reticle Crosshair Overlay for Camera Viewfinder
#'
#' Generates an HTML overlay container with horizontal/vertical alignment guides
#' and an optional center circle for focusing and specimen centering.
#'
#' @param circle_radius Radius of center reticle circle in pixels (default: 80).
#' @param color CSS color string (default: "rgba(239, 68, 68, 0.75)").
#' @return Shiny/htmltools tag object.
#' @export
cameraOverlayCrosshair <- function(circle_radius = 80, color = "rgba(239, 68, 68, 0.75)") {
  htmltools::div(
    class = "usb-camera-reticle",
    htmltools::div(
      class = "usb-camera-reticle-crosshair",
      htmltools::div(class = "usb-camera-reticle-line-h", style = sprintf("background: %s;", color)),
      htmltools::div(class = "usb-camera-reticle-line-v", style = sprintf("background: %s;", color)),
      htmltools::div(
        class = "usb-camera-reticle-circle",
        style = sprintf("width: %dpx; height: %dpx; border-color: %s;", circle_radius * 2, circle_radius * 2, color)
      )
    )
  )
}
