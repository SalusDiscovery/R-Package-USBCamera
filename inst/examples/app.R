# Interactive Standalone Demo of the USBCamera Package
# Demonstrates dynamic regex filtering, device listing, live streaming,
# transformations, snapshot capture, and EBImage analysis.

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
      h4("Orientation & Viewfinder Guides"),
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

    choices <- stats::setNames(devs$deviceId, devs$label)
    selectInput(
      "active_camera_id",
      label = "Matching USB Cameras:",
      choices = choices,
      selected = devs$deviceId[1]
    )
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
      Camera_Label = devs$label,
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
      p(sprintf("Dimensions: %d x %d px", snap$width, snap$height), style = "font-weight: bold; margin-bottom: 2px;"),
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
  output$demo_code_display <- renderText({
    app_path <- system.file("examples", "app.R", package = "USBCamera")
    if (!nzchar(app_path) || !file.exists(app_path)) {
      candidates <- c(
        "inst/examples/app.R",
        "app.R",
        file.path("..", "inst", "examples", "app.R"),
        "/Users/jaywarrick/Documents/GitHub/R-Package-USBCamera/inst/examples/app.R"
      )
      for (cand in candidates) {
        if (file.exists(cand)) {
          app_path <- cand
          break
        }
      }
    }
    if (file.exists(app_path)) {
      paste(readLines(app_path, warn = FALSE), collapse = "\n")
    } else {
      "# Demo app source code could not be located on disk."
    }
  })
}

if (interactive()) {
  shinyApp(ui, server)
}
