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

#' Create SVG Vector Overlay for Camera Viewfinder
#'
#' Generates an SVG overlay container with matching aspect ratio (`preserveAspectRatio = "xMidYMid meet"`)
#' that automatically locks SVG coordinates 1-to-1 with native camera sensor pixels.
#'
#' @param width Native camera pixel width (default: 1280).
#' @param height Native camera pixel height (default: 960).
#' @param ... Child SVG elements (tags$line, tags$rect, tags$circle, tags$text, tags$path).
#' @param style Optional CSS styling string.
#' @return Shiny/htmltools tag object.
#' @export
cameraOverlaySVG <- function(width = 1280, height = 960, ..., style = NULL) {
  htmltools::tags$svg(
    viewBox = sprintf("0 0 %d %d", as.integer(width), as.integer(height)),
    preserveAspectRatio = "xMidYMid meet",
    class = "usb-camera-svg-overlay",
    style = paste("position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 15;", style %||% ""),
    ...
  )
}
