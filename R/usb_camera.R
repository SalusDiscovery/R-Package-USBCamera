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
#' @param filter Optional regex or string filter to auto-select a specific camera by label.
#' @return Shiny UI tag list.
#' @export
usbCameraUI <- function(id, width = "100%", height = "480px", show_status = TRUE, reticle = FALSE, overlay = NULL, filter = "") {
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
      htmltools::div(
        id = ns("custom-overlay"),
        class = "usb-camera-overlay-layer",
        if (!is.null(overlay)) overlay else NULL
      ),
      htmltools::div(
        id = ns("no-match-overlay"),
        class = "usb-camera-no-match-overlay",
        style = "display: none;",
        htmltools::div(
          class = "usb-camera-no-match-card",
          htmltools::div(class = "usb-camera-no-match-icon", "\u26a0"),
          htmltools::div(class = "usb-camera-no-match-title", "No Matching Camera Found"),
          htmltools::div(
            class = "usb-camera-no-match-regex",
            "Filter Pattern: ",
            htmltools::tags$code(id = ns("no-match-filter"), "")
          ),
          htmltools::div(class = "usb-camera-no-match-devices-header", "Attached Cameras Detected:"),
          htmltools::tags$ul(id = ns("no-match-devices-list"), class = "usb-camera-no-match-list"),
          htmltools::div(class = "usb-camera-no-match-hint", "Adjust your filter regex or select an attached camera from the dropdown.")
        )
      ),
      htmltools::div(id = ns("flash"), class = "usb-camera-flash-overlay"),
      tags$script(HTML(sprintf(
        "$(function() {
          var initialized = false;
          function init() {
            if (initialized) return;
            if (window.initUSBCamera) {
              initialized = true;
              window.initUSBCamera('%s', { filter: %s });
            }
          }
          $(document).one('shiny:connected', init);
          init();
          setTimeout(init, 200);
        });",
        ns(NULL),
        jsonlite::toJSON(as.character(filter %||% ""), auto_unbox = TRUE)
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
#' frame capture, stream properties, and conversion to EBImage objects.
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
#'     \item{stream_info}{Reactive list of hardware stream properties: \code{width}, \code{height}, \code{frameRate}, \code{aspectRatio}, \code{channels}, \code{bitDepth}, \code{colorMode}, \code{label}.}
#'     \item{snapshot}{Reactive list representing the latest captured frame, containing \code{raw_bytes}, \code{data_url}, \code{width}, \code{height}, \code{channels}, \code{bit_depth}, \code{color_mode}, \code{time_str}, and helper methods \code{as_ebimage()} and \code{save(path)}.}
#'     \item{capture(format = "jpeg", quality = 0.95)}{Function triggering an immediate capture.}
#'     \item{set_orientation(rotation, flip_h, flip_v)}{Function updating orientation calibration.}
#'     \item{set_reticle(visible)}{Function toggling viewfinder reticle.}
#'     \item{set_zoom(is_zoomed)}{Function toggling 1:1 pixel center zoom.}
#'     \item{set_overlay_html(html)}{Function dynamically replacing or setting custom overlay HTML/SVG.}
#'     \item{select_device(device_id)}{Function switching active camera device.}
#'     \item{configure(filter, preferred_resolution)}{Function dynamically updating camera filter or resolution.}
#'     \item{refresh_devices()}{Function triggering a hardware device rescan.}
#'     \item{refresh_stream_info()}{Function requesting updated live stream metadata from the browser.}
#'   }
#' @export
usbCameraServer <- function(id, filter = "", preferred_resolution = c(1280, 960), auto_connect = TRUE) {
  shiny::moduleServer(id, function(input, output, session) {

    status_rv <- shiny::reactiveVal(list(working = FALSE, message = "Offline", activeDevice = ""))
    devices_rv <- shiny::reactiveVal(data.frame(deviceId = character(0), label = character(0), stringsAsFactors = FALSE))
    stream_info_rv <- shiny::reactiveVal(list(
      width = 0,
      height = 0,
      frameRate = 0,
      aspectRatio = 1.333,
      channels = 3,
      bitDepth = 8,
      colorMode = "Color (RGB)",
      label = "",
      deviceId = ""
    ))
    snapshot_rv <- shiny::reactiveVal(NULL)

    # Initial device scan request
    session$sendCustomMessage(session$ns("getDevices"), list())
    session$sendCustomMessage(session$ns("getStreamInfo"), list())

    # Receive status updates from browser
    shiny::observeEvent(input$status, {
      req(input$status)
      status_rv(input$status)
    })

    # Receive hardware stream info from browser
    shiny::observeEvent(input$stream_info, {
      req(input$stream_info)
      stream_info_rv(input$stream_info)
    })

    # Receive enumerated device list from browser
    shiny::observeEvent(input$devices, {
      req(input$devices)
      df <- tryCatch({
        if (is.data.frame(input$devices)) {
          input$devices
        } else if (is.list(input$devices)) {
          data.frame(
            deviceId = vapply(input$devices, function(x) as.character(x$deviceId %||% ""), character(1)),
            label = vapply(input$devices, function(x) as.character(x$label %||% ""), character(1)),
            stringsAsFactors = FALSE
          )
        } else {
          data.frame(deviceId = character(0), label = character(0), stringsAsFactors = FALSE)
        }
      }, error = function(e) {
        data.frame(deviceId = character(0), label = character(0), stringsAsFactors = FALSE)
      })
      devices_rv(df)
    })

    # Wire up built-in toolbar buttons if usbCameraControlsUI is present
    shiny::observeEvent(input$btn_capture, {
      session$sendCustomMessage(session$ns("capture"), list(format = "jpeg", quality = 0.95))
    })

    shiny::observe({
      rot <- as.integer(input$rot_select %||% 0)
      fh <- isTRUE(input$flip_h)
      fv <- isTRUE(input$flip_v)
      session$sendCustomMessage(session$ns("setOrientation"), list(rotation = rot, flipH = fh, flipV = fv))
    })

    shiny::observeEvent(input$show_reticle, {
      session$sendCustomMessage(session$ns("setReticle"), list(visible = isTRUE(input$show_reticle)))
    })

    shiny::observeEvent(input$zoom_center, {
      session$sendCustomMessage(session$ns("setZoom"), list(isZoomed = isTRUE(input$zoom_center)))
    })

    # Process captured snapshots
    shiny::observeEvent(input$snapshot, {
      req(input$snapshot)
      data_url <- input$snapshot$dataUrl
      raw_bytes <- decode_base64_image(data_url)

      snap_obj <- list(
        raw_bytes = raw_bytes,
        data_url = data_url,
        width = input$snapshot$width,
        height = input$snapshot$height,
        channels = 3,
        bit_depth = 8,
        color_mode = "Color (RGB)",
        time_str = input$snapshot$timeString %||% format(Sys.time(), "%H:%M:%S"),
        timestamp = input$snapshot$timestamp %||% as.numeric(Sys.time()),
        as_ebimage = function() {
          as_ebimage(raw_bytes)
        },
        save = function(path) {
          save_camera_image(raw_bytes, path)
        }
      )
      snapshot_rv(snap_obj)
    })

    list(
      status = shiny::reactive(status_rv()),
      devices = shiny::reactive(devices_rv()),
      stream_info = shiny::reactive(stream_info_rv()),
      snapshot = shiny::reactive(snapshot_rv()),
      capture = function(format = "jpeg", quality = 0.95) {
        session$sendCustomMessage(session$ns("capture"), list(format = format, quality = quality))
      },
      set_orientation = function(rotation = 0, flip_h = FALSE, flip_v = FALSE) {
        session$sendCustomMessage(session$ns("setOrientation"), list(
          rotation = as.integer(rotation),
          flipH = as.logical(flip_h),
          flipV = as.logical(flip_v)
        ))
      },
      set_reticle = function(visible = TRUE, circle_radius = 40) {
        session$sendCustomMessage(session$ns("setReticle"), list(
          visible = as.logical(visible),
          circleRadius = as.integer(circle_radius)
        ))
      },
      set_zoom = function(is_zoomed = TRUE) {
        session$sendCustomMessage(session$ns("setZoom"), list(isZoomed = as.logical(is_zoomed)))
      },
      set_overlay_html = function(html) {
        session$sendCustomMessage(session$ns("setOverlayHTML"), list(html = as.character(html %||% "")))
      },
      select_device = function(device_id) {
        session$sendCustomMessage(session$ns("selectDevice"), list(deviceId = as.character(device_id)))
      },
      configure = function(filter = NULL, preferred_resolution = NULL) {
        msg <- list()
        if (!is.null(filter)) msg$filter <- as.character(filter)
        if (!is.null(preferred_resolution) && length(preferred_resolution) >= 2) {
          msg$preferredWidth <- as.integer(preferred_resolution[1])
          msg$preferredHeight <- as.integer(preferred_resolution[2])
        }
        session$sendCustomMessage(session$ns("configure"), msg)
      },
      refresh_devices = function() {
        session$sendCustomMessage(session$ns("getDevices"), list())
      },
      refresh_stream_info = function() {
        session$sendCustomMessage(session$ns("getStreamInfo"), list())
      }
    )
  })
}

#' Package HTML and Script Dependency Loader
#'
#' @keywords internal
#' @export
usb_camera_dependency <- function() {
  htmltools::htmlDependency(
    name = "usb-camera",
    version = "0.1.0",
    src = c(file = system.file("www", package = "USBCamera")),
    script = "usb_camera.js",
    stylesheet = "usb_camera.css"
  )
}

# Internal null coalescing operator
`%||%` <- function(a, b) {
  if (is.null(a) || length(a) == 0 || is.na(a)) b else a
}
