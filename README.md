# USBCamera

> High-reliability WebRTC-powered USB camera streaming, orientation calibration, reticle overlays, and direct EBImage pixel analysis for R Shiny.

## Overview

`USBCamera` abstracts reliable hardware camera controls into a plug-and-play R Shiny package. Built on lessons learned from deploying microscope cameras (such as the Dino-Lite Edge 3.0 / Cypress FX3 USB controllers) in clinical and lab instrumentation environments, it resolves common browser and hardware pitfalls:

- **Browser Permission Probing**: Automatically probes camera permissions on startup so real hardware labels (`"Dino-Lite Edge3.0"`, `"Logitech C920"`) are never masked by browser security sandboxes.
- **USB Controller Protection**: Implements automatic 400ms USB bus cooldowns to protect UVC and FX3 endpoints from locking up during stream switching or device changes.
- **Zero-Latency Live Viewport Transformation**: Applies rotation (0°, 90°, 180°, 270°) and horizontal/vertical flips client-side via CSS transforms.
- **Matrix-Baked Snapshots**: When capturing frames, transforms are automatically baked into `<canvas>` pixels before transmission to R.
- **Direct EBImage Integration**: Helper method `as_ebimage()` converts captured raw byte payloads directly into `EBImage::Image` arrays for downstream computer vision, thresholding, and fluorescent curve quantification.
- **Unplug & Disconnection Watchdog**: Automatically monitors `devicechange` and stream termination events with reconnect backoff when cameras are unplugged and re-connected.
- **Clean Hardware Teardown**: Automatically releases USB camera endpoints upon Shiny disconnect, tab switching, or page unloads.

## Installation

```r
# Install from GitHub
devtools::install_github("jaywarrick/R-Package-USBCamera")
```

## Quick Start

```r
library(shiny)
library(USBCamera)

ui <- fluidPage(
  usbCameraUI("cam", width = "100%", height = "480px"),
  usbCameraControlsUI("cam")
)

server <- function(input, output, session) {
  cam <- usbCameraServer("cam", filter = "dino|microscope")

  observeEvent(cam$snapshot(), {
    snap <- cam$snapshot()
    # Convert directly to an EBImage object
    img <- snap$as_ebimage()
    message("Image dimensions: ", paste(dim(img), collapse = "x"))
  })
}

shinyApp(ui, server)
```

## License

MIT © Jay Warrick
