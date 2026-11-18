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

## Production Robustness & Error Handling Nuances

Deploying WebRTC USB hardware in production Shiny apps involves specific browser and operating system requirements:

### 1. Secure Context Requirement
Modern browsers restrict `navigator.mediaDevices.getUserMedia` to **secure contexts**:
- `https://...` (production domains with TLS)
- `http://localhost:...` or `http://127.0.0.1:...` (local machine loopback)

If a Shiny app is served over an unencrypted local network IP (e.g. `http://192.168.1.50:8000`), the browser will completely disable camera APIs.

### 2. User Gesture Requirement for Permission Prompts
On macOS and modern versions of Chrome and Safari, automated `getUserMedia()` calls on page load without direct user interaction may be silently blocked or suppressed. Provide an explicit button wired to `cam$request_permission()` so users can invoke the permission dialog via a direct click gesture:
```r
actionButton("ask_perm_btn", "Allow Camera", class = "btn-warning btn-sm")

observeEvent(input$ask_perm_btn, {
  cam$request_permission()
})
```

### 3. RStudio Viewer Pane Limitation
On macOS and Linux, the embedded RStudio Viewer pane (Qt WebKit) lacks camera privacy entitlements. Calling `getUserMedia` inside the Viewer pane is immediately rejected with `NotAllowedError`. Always launch apps with:
```r
options(shiny.launch.browser = .rs.invokeShinyWindowExternal) # Opens in default system browser
```
or open the Shiny URL directly in Google Chrome, Microsoft Edge, or Safari.

### 4. Shiny Custom Message Handler Arity (`handler.length === 1`)
Shiny's JavaScript engine enforces that custom message handlers take exactly one argument:
```javascript
Shiny.addCustomMessageHandler('type', function(message) { ... }); // Correct
Shiny.addCustomMessageHandler('type', () => { ... });             // Throws: handler must be a function that takes one argument!
```
`USBCamera` includes an automatic global monkey-patch for Shiny and an internal `addSafeHandler` wrapper with error logging, ensuring callbacks never throw uncaught arity errors.

### 5. Reactive Watchdogs & Cable Disconnection
When a camera is unplugged or its USB bus resets:
- `cam$status()$working` reactively updates to `FALSE`.
- `cam$status()$message` explains the disconnect reason.
- The built-in JavaScript watchdog monitors `devicechange` events and automatically reconnects once the device is plugged back in.
- App developers can inspect `cam$diagnostics()` to surface `permissionState`, `rawDeviceCount`, and driver error messages (`lastError`) to end users.

## License

MIT © Jay Warrick
