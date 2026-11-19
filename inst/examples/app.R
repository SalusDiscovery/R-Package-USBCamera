# Interactive Standalone Demo of the USBCamera Package
# Demonstrates dynamic regex filtering, device listing, live streaming,
# real-time hardware stream querying, SVG/HTML overlays, and EBImage analysis.

if (!requireNamespace("USBCamera", quietly = TRUE)) {
  if (requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all()
  } else if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all()
  }
}
library(shiny)
library(USBCamera)


ui <- fluidPage(
  titlePanel("USBCamera Package Interactive Demo & Reference"),
  sidebarLayout(
    sidebarPanel(
      width = 4,
      h4("Camera Device & Filter Selection"),
      textInput(
        "camera_regex",
        label = "Filter Regex Pattern:",
        value = "",
        placeholder = "e.g. dino|edge, logitech, or macbook"
      ),
      helpText(
        "Enter a regex pattern to match camera labels. ",
        "When empty (\"\"), all detected cameras are available and the first is selected."
      ),
      uiOutput("device_selector_ui"),
      actionButton("refresh_devs_btn", "Rescan Cameras", icon = icon("sync"), class = "btn-default btn-xs", style = "margin-top: 5px;"),
      hr(),
      h4("Hardware Stream Properties"),
      helpText("Queried directly from WebRTC driver metadata (no image capture or EBImage required):"),
      uiOutput("hardware_stream_info_ui"),
      hr(),
      h4("Orientation & Viewfinder Guides"),
      selectInput(
        "active_overlay_choice",
        label = "Active Overlay Layer:",
        choices = c(
          "None" = "none",
          "Built-in Crosshair Reticle" = "reticle",
          "SVG Calibration Grid (1280x960 Pixel Space)" = "svg"
        ),
        selected = "none"
      ),
      usbCameraControlsUI("cam1"),
      hr(),
      h4("Snapshot EBImage Analysis"),
      uiOutput("snapshot_summary_ui"),
      actionButton("analyze_btn", "Analyze with EBImage", class = "btn-success btn-sm"),
      hr(),
      verbatimTextOutput("ebimage_summary")
    ),
    mainPanel(
      width = 8,
      tabsetPanel(
        id = "main_tabs",
        tabPanel(
          "Live Camera & Viewport",
          br(),
          h4("Live Viewfinder"),
          usbCameraUI("cam1", width = "100%", height = "480px", reticle = FALSE),
          br(),
          h4("Detected System Cameras"),
          p("All video capture devices detected on this computer by the browser WebRTC API:"),
          tableOutput("detected_cameras_table"),
          br(),
          h4("Captured Snapshot Viewport"),
          imageOutput("snapshot_display", height = "300px")
        ),
        tabPanel(
          "Adding Overlays",
          br(),
          h3("Designing Custom SVG Overlays with 1:1 Pixel Alignment"),
          p(
            "USBCamera utilizes SVG vector overlays for live viewfinder guides, calibration grids, reticles, ",
            "and target regions of interest (ROI). SVG is uniquely suited for live camera streams because it offers ",
            strong("rock-solid mathematical alignment directly to camera sensor pixels.")
          ),
          hr(),
          h4("Why SVG Guarantees Perfect Sensor Pixel Mapping"),
          p(
            "The camera video is rendered inside a responsive UI container using CSS ",
            tags$code("object-fit: contain"), ". When container aspect ratios vary, the browser adds black letterboxing or pillarboxing bars. ",
            "By setting ", tags$code("preserveAspectRatio=\"xMidYMid meet\""), " on an SVG overlay with a ",
            tags$code("viewBox=\"0 0 <width> <height>\""), ", the SVG's vector canvas scales and centers ",
            "using the exact same mathematical formula as the video stream. ",
            "Every SVG coordinate ", tags$code("(x, y)"), " directly targets that exact camera sensor pixel, ",
            "regardless of screen size, browser window resizing, or UI container aspect ratio!"
          ),
          h4("SVG Example: Pixel-Exact Reticle & Calibration Grid"),
          tags$pre(
            tags$code(
'library(USBCamera)
library(htmltools)

# Define an SVG overlay registered to the 1280 x 960 native camera resolution
my_svg_overlay <- cameraOverlaySVG(
  width = 1280,
  height = 960,
  # Horizontal reference line at pixel row y=480
  tags$line(x1 = 0, y1 = 480, x2 = 1280, y2 = 480, stroke = "#ef4444", stroke_width = "2"),
  # Vertical reference line at pixel column x=640
  tags$line(x1 = 640, y1 = 0, x2 = 640, y2 = 960, stroke = "#ef4444", stroke_width = "2"),
  # Center inspection circle (radius = 120 pixels) centered on pixel (640, 480)
  tags$circle(cx = 640, cy = 480, r = 120, fill = "none", stroke = "#38bdf8", stroke_width = "2", stroke_dasharray = "6"),
  # Region of Interest (ROI) box from pixel (340, 280) with width 600px and height 400px
  tags$rect(x = 340, y = 280, width = 600, height = 400, fill = "none", stroke = "#22c55e", stroke_width = "2"),
  # Calibration label placed directly above the ROI
  tags$text(x = 345, y = 270, "Target Region [600 x 400 px]", fill = "#22c55e", font_size = "18px", font_family = "sans-serif")
)

# 1. Embed statically in Shiny UI:
usbCameraUI("my_cam", width = "100%", height = "480px", overlay = my_svg_overlay)

# 2. Or update dynamically from Shiny server:
cam$set_overlay_svg(my_svg_overlay)
'
            )
          )
        ),
        tabPanel(
          "Troubleshooting & Architecture Guide",
          br(),
          h3("Hardware & Browser Error Handling Nuances"),
          p(
            "Integrating hardware video capture into web applications involves browser security policies ",
            "and operating system nuances that do not exist with purely server-side R packages. ",
            "USBCamera handles these internally, but understanding them ensures robust deployment:"
          ),
          hr(),
          h4("1. Browser Permission Prompts & User Gestures"),
          p(
            "Modern browsers (especially macOS Chrome and Safari) frequently suppress automated ",
            tags$code("getUserMedia()"), " calls on initial page load if not initiated by a direct user interaction. ",
            "In production apps, provide an explicit button wired to ", tags$code("cam$request_permission()"),
            " so the user can summon the browser dialog via a direct click gesture."
          ),
          h4("2. RStudio Embedded Viewer Pane Limitation"),
          p(
            "On macOS and Linux, the embedded RStudio Viewer pane (Qt WebKit) lacks OS camera privacy entitlements. ",
            "Attempting to connect to cameras inside the Viewer pane is immediately rejected with ",
            tags$code("NotAllowedError"), " without ever displaying a prompt. ",
            "Always run camera applications in an external browser (Google Chrome, Edge, or Safari)."
          ),
          h4("3. Secure Context Requirement (HTTPS / Localhost)"),
          p(
            "WebRTC APIs are disabled by modern browsers unless served from a Secure Context: ",
            tags$code("https://"), " or local loopback (", tags$code("http://localhost"), " or ", tags$code("http://127.0.0.1"), "). ",
            "Serving an unencrypted app over an internal LAN IP (e.g. ", tags$code("http://192.168.1.50:8000"), ") will cause the browser to block all camera enumeration."
          ),
          h4("4. Shiny Custom Message Handler Arity (handler.length === 1)"),
          p(
            "Shiny's JavaScript runtime strictly asserts that all custom message handlers take exactly one argument (",
            tags$code("handler.length === 1"), "). Registering a zero-argument callback (", tags$code("() => { ... }"), ") ",
            "causes Shiny to throw an uncaught exception (", tags$code("handler must be a function that takes one argument"), ") ",
            "which halts subsequent script execution. USBCamera includes an internal patch and wraps all handlers with ",
            tags$code("addSafeHandler"), " to guard against this pitfall."
          ),
          h4("5. Unplug Watchdogs & USB Bus Cooldowns"),
          p(
            "USB microscopy controllers (such as Cypress FX3 / Dino-Lite) can lock up if rapid stream open/close cycles occur. ",
            "USBCamera enforces a 400ms bus cooldown before re-opening streams and monitors ", tags$code("devicechange"),
            " and stream termination events so that temporary unplugs automatically reconnect when plugged back in."
          )
        ),
        tabPanel(
          "Demo Code",
          br(),
          h4("Integration Code (inst/examples/app.R)"),
          p("This tab displays the live source code of this demo app, read directly from disk so it stays automatically up to date with package updates:"),
          verbatimTextOutput("demo_code_display")
        )
      )
    )
  )
)

server <- function(input, output, session) {
  # Initialize USBCamera server instance with empty initial filter
  cam <- usbCameraServer("cam1", filter = "", preferred_resolution = c(1280, 960))

  # Hardware stream properties UI (populated without taking an image or calling EBImage)
  output$hardware_stream_info_ui <- renderUI({
    info <- cam$stream_info()
    if (is.null(info) || info$width == 0) {
      return(p("Waiting for camera connection...", style = "color: #64748b; font-style: italic; font-size: 12px;"))
    }
    tags$table(
      class = "table table-condensed",
      style = "font-size: 12px; margin-bottom: 0px;",
      tags$tbody(
        tags$tr(tags$td(strong("Resolution:")), tags$td(sprintf("%d x %d px", info$width, info$height))),
        tags$tr(tags$td(strong("Frame Rate:")), tags$td(sprintf("%.1f fps", info$frameRate))),
        tags$tr(tags$td(strong("Aspect Ratio:")), tags$td(sprintf("%.3f", info$aspectRatio))),
        tags$tr(tags$td(strong("Channels:")), tags$td(sprintf("%d (Red, Green, Blue)", info$channels))),
        tags$tr(tags$td(strong("Bit Depth:")), tags$td(sprintf("%d-bit per channel", info$bitDepth))),
        tags$tr(tags$td(strong("Color Mode:")), tags$td(info$colorMode %||% "Color (RGB)"))
      )
    )
  })

  # Reactive calculation of cameras matching the user-entered regex
  matching_devs <- reactive({
    devs <- cam$devices()
    if (nrow(devs) == 0) return(devs)
    pattern <- trimws(input$camera_regex %||% "")
    if (!nzchar(pattern)) {
      return(devs)
    }
    idx <- grepl(pattern, devs$label, ignore.case = TRUE)
    devs[idx, , drop = FALSE]
  })

  # Dynamically render dropdown containing ONLY matching cameras
  output$device_selector_ui <- renderUI({
    devs <- matching_devs()
    all_devs <- cam$devices()
    cat("[DEBUG APP] renderUI device_selector_ui called: nrow(all_devs)=", nrow(all_devs), " nrow(devs)=", nrow(devs), "\n")

    if (nrow(all_devs) == 0) {
      return(p("Scanning for USB cameras...", style = "color: #64748b; font-style: italic;"))
    }

    if (nrow(devs) == 0) {
      return(tagList(
        p(
          sprintf("No cameras match '%s' (%d detected)", input$camera_regex, nrow(all_devs)),
          style = "color: #dc2626; font-size: 13px; font-weight: bold; margin-bottom: 4px;"
        ),
        p("Update your filter pattern above or clear it to view all cameras.", style = "color: #64748b; font-size: 11px;")
      ))
    }

    choices <- stats::setNames(devs$deviceId, tolower(devs$label))
    selectInput(
      "active_camera_id",
      label = "Matching USB Cameras:",
      choices = choices,
      selected = devs$deviceId[1]
    )
  })

  # Switch active overlay layer interactively
  observeEvent(input$active_overlay_choice, {
    choice <- input$active_overlay_choice
    if (choice == "reticle") {
      cam$set_reticle(TRUE)
      cam$set_overlay_svg("")
    } else if (choice == "svg") {
      cam$set_reticle(FALSE)
      svg_html <- as.character(cameraOverlaySVG(
        width = 1280, height = 960,
        tags$line(x1 = 0, y1 = 480, x2 = 1280, y2 = 480, stroke = "#ef4444", stroke_width = "2"),
        tags$line(x1 = 640, y1 = 0, x2 = 640, y2 = 960, stroke = "#ef4444", stroke_width = "2"),
        tags$circle(cx = 640, cy = 480, r = 120, fill = "none", stroke = "#38bdf8", stroke_width = "2", stroke_dasharray = "6"),
        tags$rect(x = 340, y = 280, width = 600, height = 400, fill = "none", stroke = "#22c55e", stroke_width = "2"),
        tags$text(x = 345, y = 270, "Target Region [600 x 400 px]", fill = "#22c55e", font_size = "18px", font_family = "sans-serif")
      ))
      cam$set_overlay_svg(svg_html)
    } else {
      cam$set_reticle(FALSE)
      cam$set_overlay_svg("")
    }
  })

  # When user changes active selection in dropdown, switch camera stream
  observeEvent(input$active_camera_id, {
    req(input$active_camera_id)
    cam$select_device(input$active_camera_id)
  })

  # When user updates regex input, reconfigure camera client filter
  observeEvent(input$camera_regex, {
    cam$configure(filter = input$camera_regex)
  }, ignoreInit = TRUE)

  # Manual rescan button
  observeEvent(input$refresh_devs_btn, {
    cam$refresh_devices()
  })

  # Table listing all detected cameras and their regex match status
  output$detected_cameras_table <- renderTable({
    devs <- cam$devices()
    if (nrow(devs) == 0) {
      return(data.frame(Status = "Scanning for video devices...", stringsAsFactors = FALSE))
    }
    pattern <- trimws(input$camera_regex %||% "")
    matches <- if (!nzchar(pattern)) {
      rep(TRUE, nrow(devs))
    } else {
      grepl(pattern, devs$label, ignore.case = TRUE)
    }

    data.frame(
      Index = seq_len(nrow(devs)),
      Camera_Label = tolower(devs$label),
      Device_ID = paste0(substr(devs$deviceId, 1, 14), "..."),
      Matches_Regex = ifelse(matches, "YES (Matching)", "NO"),
      stringsAsFactors = FALSE
    )
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # Snapshot details UI
  output$snapshot_summary_ui <- renderUI({
    snap <- cam$snapshot()
    if (is.null(snap)) {
      return(p("No snapshots captured yet. Click 'Take Snapshot' above.", style = "color: #94a3b8; font-size: 12px;"))
    }
    tagList(
      p(sprintf("Dimensions: %d x %d px (%d channels, %d-bit)", snap$width, snap$height, snap$channels, snap$bit_depth), style = "font-weight: bold; margin-bottom: 2px;"),
      p(sprintf("Captured at: %s (%.1f KB)", snap$time_str, length(snap$raw_bytes) / 1024), style = "font-size: 12px; color: #475569;")
    )
  })

  # Render captured image in viewport
  output$snapshot_display <- renderImage({
    snap <- cam$snapshot()
    if (is.null(snap)) {
      return(list(src = "", alt = "No image"))
    }
    tf <- tempfile(fileext = ".jpg")
    snap$save(tf)
    list(src = tf, contentType = "image/jpeg", width = "100%", alt = "Captured snapshot")
  }, deleteFile = TRUE)

  # EBImage pixel analysis
  eb_analysis_rv <- reactiveVal(NULL)

  observeEvent(input$analyze_btn, {
    snap <- cam$snapshot()
    req(snap)
    if (!requireNamespace("EBImage", quietly = TRUE)) {
      showNotification("EBImage is not installed. Run BiocManager::install('EBImage') to test image analysis.", type = "error")
      return()
    }
    img <- snap$as_ebimage()
    dims <- dim(img)
    mean_val <- mean(img)
    sd_val <- stats::sd(img)
    eb_analysis_rv(list(dims = dims, mean = mean_val, sd = sd_val, class = class(img)))
  })

  output$ebimage_summary <- renderPrint({
    res <- eb_analysis_rv()
    if (is.null(res)) {
      cat("Click 'Analyze with EBImage' to extract raw pixel statistics from captured frame.")
    } else {
      cat("EBImage Image Data Extracted Successfully:\n")
      cat(sprintf("  Dimensions  : %s\n", paste(res$dims, collapse = " x ")))
      cat(sprintf("  Mean pixel  : %.4f\n", res$mean))
      cat(sprintf("  Std Dev     : %.4f\n", res$sd))
      cat(sprintf("  Object Class: %s\n", paste(res$class, collapse = ", ")))
    }
  })

  # Live demo code reader that stays updated with the file on disk
  demo_code_text <- reactive({
    candidates <- c(
      system.file("examples", "app.R", package = "USBCamera"),
      system.file("examples/app.R", package = "USBCamera"),
      "inst/examples/app.R",
      "app.R",
      file.path("..", "inst", "examples", "app.R"),
      "/Users/jaywarrick/Documents/GitHub/R-Package-USBCamera/inst/examples/app.R"
    )
    for (cand in candidates) {
      if (nzchar(cand) && file.exists(cand)) {
        return(paste(readLines(cand, warn = FALSE), collapse = "\n"))
      }
    }
    "# Demo app source code could not be located on disk."
  })

  output$demo_code_display <- renderPrint({
    cat(demo_code_text())
  })
  outputOptions(output, "demo_code_display", suspendWhenHidden = FALSE)
}

shinyApp(ui, server)
