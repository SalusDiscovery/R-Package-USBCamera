#' USB Camera Viewfinder UI Module
#'
#' Embeds a high-reliability WebRTC camera viewfinder with real-time CSS transformations,
#' status badge, flash feedback, and overlay slots.
#'
#' @param id Shiny module namespace ID.
#' @param width Viewport CSS width (e.g. "100%", "640px").
#' @param height Viewport CSS height (e.g. "480px", "600px").
#' @param show_status Whether to display the live connection status badge in the corner.
#' @param reticle Whether to initialize with the built-in crosshair overlay visible.
#' @param overlay Optional custom HTML/SVG overlay tag object placed over the live video.
#' @return Shiny UI tag list.
#' @export
usbCameraUI <- function(id, width = "100%", height = "480px", show_status = TRUE, reticle = FALSE, overlay = NULL) {
  ns <- shiny::NS(id)

  htmltools::tagList(
    usb_camera_dependency(),
    htmltools::div(
      id = ns("container"),
      class = "usb-camera-container",
      style = sprintf("width: %s; height: %s;", width, height),
      tags$video(
        id = ns("video"),
        class = "usb-camera-video",
        autoplay = NA,
        playsinline = NA,
        muted = NA
      ),
      if (show_status) {
        htmltools::div(
          id = ns("badge"),
          class = "usb-camera-status-badge",
          htmltools::span(id = ns("status-dot"), class = "usb-camera-status-dot"),
          htmltools::span(id = ns("status-text"), "Initializing...")
        )
      },
      htmltools::div(
        id = ns("reticle"),
        class = "usb-camera-reticle",
        style = if (!reticle) "display: none;" else NULL,
        cameraOverlayCrosshair()
      ),
      if (!is.null(overlay)) {
        htmltools::div(
          id = ns("custom-overlay"),
          class = "usb-camera-overlay-layer",
          overlay
        )
      },
      htmltools::div(id = ns("flash"), class = "usb-camera-flash-overlay"),
      tags$script(HTML(sprintf(
        "$(document).on('shiny:connected', function() { window.initUSBCamera('%s', {}); });",
        ns(NULL)
      )))
    )
  )
}

#' USB Camera Controls Panel UI Helper
#'
#' Creates a modular toolbar with rotation buttons (0/90/180/270), flip toggles,
#' reticle crosshair toggle, 1:1 pixel zoom toggle, and a snapshot button.
#'
#' @param id Shiny module namespace ID.
#' @return Shiny UI tag list.
#' @export
usbCameraControlsUI <- function(id) {
  ns <- shiny::NS(id)
  htmltools::div(
    class = "usb-camera-controls-panel",
    shiny::actionButton(ns("btn_capture"), "Take Snapshot", icon = shiny::icon("camera"), class = "btn-primary btn-sm"),
    shiny::radioButtons(
      ns("rot_select"), label = NULL,
      choices = c("0\u00b0" = "0", "90\u00b0" = "90", "180\u00b0" = "180", "270\u00b0" = "270"),
      selected = "0", inline = TRUE
    ),
    shiny::checkboxInput(ns("flip_h"), "Flip H", value = FALSE, width = "auto"),
    shiny::checkboxInput(ns("flip_v"), "Flip V", value = FALSE, width = "auto"),
    shiny::checkboxInput(ns("show_reticle"), "Reticle", value = FALSE, width = "auto"),
    shiny::checkboxInput(ns("zoom_center"), "1:1 Zoom", value = FALSE, width = "auto")
  )
}

#' USB Camera Server Module
#'
#' Manages camera connection state, device listing, orientation calibration,
#' frame capture, and conversion to EBImage objects.
#'
#' @param id Shiny module namespace ID.
#' @param filter Regex or string pattern used to auto-select a specific camera by label
#'   (e.g., "dino|microscope", "Logitech", or "Cypress").
#' @param preferred_resolution Integer vector of length 2 specifying preferred width and height (default: c(1280, 960)).
#' @param auto_connect Logical, whether to auto-connect to the matching camera immediately on session start.
#' @return A list of reactives and methods:
#'   \describe{
#'     \item{status}{Reactive list with fields: \code{working} (logical), \code{message} (character), \code{activeDevice} (character).}
#'     \item{devices}{Reactive data frame of discovered cameras (\code{deviceId}, \code{label}).}
#'     \item{snapshot}{Reactive list representing the latest captured frame, containing \code{raw_bytes}, \code{data_url}, \code{width}, \code{height}, \code{time_str}, and helper methods \code{as_ebimage()} and \code{save(path)}.}
#'     \item{capture(format = "jpeg", quality = 0.95)}{Function triggering an immediate capture.}
#'     \item{set_orientation(rotation, flip_h, flip_v)}{Function updating orientation calibration.}
#'     \item{set_reticle(visible)}{Function toggling viewfinder reticle.}
#'     \item{set_zoom(is_zoomed)}{Function toggling 1:1 pixel center zoom.}
#'     \item{select_device(device_id)}{Function switching active camera device.}
#'   }
#' @export
usbCameraServer <- function(id, filter = "", preferred_resolution = c(1280, 960), auto_connect = TRUE) {
  shiny::moduleServer(id, function(input, output, session) {

    status_rv <- shiny::reactiveVal(list(working = FALSE, message = "Offline", activeDevice = ""))
    devices_rv <- shiny::reactiveVal(data.frame(deviceId = character(0), label = character(0), stringsAsFactors = FALSE))
    snapshot_rv <- shiny::reactiveVal(NULL)

    # Receive status updates from browser
    shiny::observeEvent(input$status, {
      req(input$status)
      status_rv(input$status)
    })

    # Receive enumerated device list from browser
    shiny::observeEvent(input$devices, {
      req(input$devices)
      df <- tryCatch({
        as.data.frame(input$devices, stringsAsFactors = FALSE)
      }, error = function(e) {
        data.frame(deviceId = character(0), label = character(0), stringsAsFactors = FALSE)
      })
      devices_rv(df)
    })

    # Receive snapshot payload from browser
    shiny::observeEvent(input$snapshot, {
      req(input$snapshot)
      payload <- input$snapshot
      raw_bytes <- decode_base64_image(payload$dataUrl)

      snap_obj <- list(
        raw_bytes = raw_bytes,
        data_url = payload$dataUrl,
        width = payload$width %||% preferred_resolution[1],
        height = payload$height %||% preferred_resolution[2],
        time_str = payload$timeString %||% format(Sys.time(), "%H:%M:%S"),
        timestamp = Sys.time(),
        as_ebimage = function() as_ebimage(raw_bytes),
        save = function(filepath) save_camera_image(raw_bytes, filepath)
      )
      snapshot_rv(snap_obj)
    })

    # Controls UI event handlers
    shiny::observeEvent(input$btn_capture, {
      session$sendCustomMessage(session$ns("capture"), list(format = "jpeg", quality = 0.95))
    })

    shiny::observe({
      rot <- as.integer(input$rot_select %||% 0)
      fh <- isTRUE(input$flip_h)
      fv <- isTRUE(input$flip_v)
      session$sendCustomMessage(session$ns("setOrientation"), list(rotation = rot, flipH = fh, flipV = fv))
    })

    shiny::observe({
      session$sendCustomMessage(session$ns("setReticle"), list(visible = isTRUE(input$show_reticle)))
    })

    shiny::observe({
      session$sendCustomMessage(session$ns("setZoom"), list(isZoomed = isTRUE(input$zoom_center)))
    })

    # Public API object
    list(
      status = status_rv,
      devices = devices_rv,
      snapshot = snapshot_rv,
      capture = function(format = "jpeg", quality = 0.95) {
        session$sendCustomMessage(session$ns("capture"), list(format = format, quality = quality))
      },
      set_orientation = function(rotation = 0, flip_h = FALSE, flip_v = FALSE) {
        session$sendCustomMessage(session$ns("setOrientation"), list(rotation = rotation, flipH = flip_h, flipV = flip_v))
      },
      set_reticle = function(visible = TRUE) {
        session$sendCustomMessage(session$ns("setReticle"), list(visible = visible))
      },
      set_zoom = function(is_zoomed = TRUE) {
        session$sendCustomMessage(session$ns("setZoom"), list(isZoomed = is_zoomed))
      },
      select_device = function(device_id) {
        session$sendCustomMessage(session$ns("selectDevice"), list(deviceId = device_id))
      }
    )
  })
}
