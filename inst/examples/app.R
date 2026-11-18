# Interactive Standalone Demo of the USBCamera Package
library(shiny)
library(USBCamera)

ui <- fluidPage(
  titlePanel("USBCamera Package Interactive Demo"),
  sidebarLayout(
    sidebarPanel(
      width = 4,
      h4("Camera Device Selection"),
      uiOutput("device_selector_ui"),
      hr(),
      h4("Orientation & Viewfinder Guides"),
      usbCameraControlsUI("cam1"),
      hr(),
      h4("Latest Snapshot Analysis"),
      uiOutput("snapshot_summary_ui"),
      actionButton("analyze_btn", "Analyze with EBImage", class = "btn-success btn-sm"),
      hr(),
      verbatimTextOutput("ebimage_summary")
    ),
    mainPanel(
      width = 8,
      h4("Live Viewfinder"),
      usbCameraUI("cam1", width = "100%", height = "520px", reticle = FALSE),
      br(),
      h4("Captured Snapshot Viewport"),
      imageOutput("snapshot_display", height = "300px")
    )
  )
)

server <- function(input, output, session) {
  cam <- usbCameraServer("cam1", filter = "", preferred_resolution = c(1280, 960))

  output$device_selector_ui <- renderUI({
    devs <- cam$devices()
    if (nrow(devs) == 0) {
      return(p("Scanning for USB cameras...", style = "color: #64748b; font-style: italic;"))
    }
    choices <- stats::setNames(devs$deviceId, devs$label)
    selectInput("active_camera_id", label = "Active USB Camera:", choices = choices, selected = devs$deviceId[1])
  })

  observeEvent(input$active_camera_id, {
    req(input$active_camera_id)
    cam$select_device(input$active_camera_id)
  })

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

  output$snapshot_display <- renderImage({
    snap <- cam$snapshot()
    if (is.null(snap)) {
      return(list(src = "", alt = "No image"))
    }
    tf <- tempfile(fileext = ".jpg")
    snap$save(tf)
    list(src = tf, contentType = "image/jpeg", width = "100%", alt = "Captured snapshot")
  }, deleteFile = TRUE)

  # EBImage pixel data analysis demo
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
      cat(sprintf("  Dimensions : %s\n", paste(res$dims, collapse = " x ")))
      cat(sprintf("  Mean pixel : %.4f\n", res$mean))
      cat(sprintf("  Std Dev    : %.4f\n", res$sd))
      cat(sprintf("  Object Class: %s\n", paste(res$class, collapse = ", ")))
    }
  })
}

if (interactive()) {
  shinyApp(ui, server)
}
