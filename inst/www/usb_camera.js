/**
 * USBCamera: High-reliability WebRTC camera streaming and canvas capture for Shiny
 * Author: Jay Warrick
 */
(function() {
  'use strict';

  // Per-instance state registry keyed by Shiny module namespace ID
  window.USBCameraInstances = window.USBCameraInstances || {};

  class USBCameraInstance {
    constructor(id, options) {
      this.id = id;
      this.options = Object.assign({
        filter: '',
        preferredWidth: 1280,
        preferredHeight: 960,
        autoConnect: true,
        cooldownMs: 400
      }, options || {});

      this.currentStream = null;
      this.isWorking = false;
      this.devices = [];
      this.selectedDeviceId = null;
      this.rotation = 0;
      this.flipH = false;
      this.flipV = false;
      this.isZoomed = false;
      this.reconnectTimer = null;

      this.initDOMElements();
      this.bindShinyHandlers();

      if (this.options.autoConnect) {
        this.startDeviceWorkflow();
      }
    }

    initDOMElements() {
      this.containerEl = document.getElementById(this.id + '-container');
      this.videoEl = document.getElementById(this.id + '-video');
      this.statusDot = document.getElementById(this.id + '-status-dot');
      this.statusText = document.getElementById(this.id + '-status-text');
      this.reticleEl = document.getElementById(this.id + '-reticle');
      this.flashEl = document.getElementById(this.id + '-flash');

      if (this.videoEl) {
        this.videoEl.muted = true;
        this.videoEl.playsInline = true;
      }
    }

    log(level, msg, details) {
      const fullMsg = `[USBCamera:${this.id}][${level.toUpperCase()}] ${msg}` + (details ? ` | ${details}` : '');
      if (level === 'error') console.error(fullMsg);
      else if (level === 'warn') console.warn(fullMsg);
      else console.log(fullMsg);
    }

    reportStatus(working, message, activeDeviceLabel) {
      this.isWorking = working;
      if (this.statusDot) {
        this.statusDot.classList.toggle('active', working);
      }
      if (this.statusText) {
        this.statusText.textContent = message || (working ? 'Connected' : 'Offline');
      }

      if (window.Shiny && Shiny.setInputValue) {
        Shiny.setInputValue(this.id + '-status', {
          working: Boolean(working),
          message: message || '',
          activeDevice: activeDeviceLabel || '',
          timestamp: Date.now()
        }, { priority: 'event' });
      }
    }

    reportDevices() {
      if (window.Shiny && Shiny.setInputValue) {
        Shiny.setInputValue(this.id + '-devices', this.devices.map(d => ({
          deviceId: d.deviceId,
          label: d.label || 'Camera'
        })), { priority: 'event' });
      }
    }

    async probePermissions() {
      if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) {
        throw new Error('navigator.mediaDevices.enumerateDevices is not supported.');
      }

      let devices = await navigator.mediaDevices.enumerateDevices();
      let videoDevices = devices.filter(d => d.kind === 'videoinput');

      // If device labels are blank/masked, prompt user once via getUserMedia
      const hasLabels = videoDevices.some(d => d.label && d.label.length > 0);
      if (!hasLabels || videoDevices.length === 0) {
        this.log('info', 'Requesting camera access to enumerate device labels...');
        try {
          const probe = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
          probe.getTracks().forEach(t => t.stop());
          await new Promise(r => setTimeout(r, this.options.cooldownMs));
          devices = await navigator.mediaDevices.enumerateDevices();
          videoDevices = devices.filter(d => d.kind === 'videoinput');
        } catch (e) {
          this.log('warn', `Camera permission prompt rejected or failed: ${e.message}`);
        }
      }

      this.devices = videoDevices;
      this.reportDevices();
      return videoDevices;
    }

    matchesFilter(label, filterStr) {
      if (!filterStr || !filterStr.trim()) return true;
      try {
        const regex = new RegExp(filterStr, 'i');
        return regex.test(label);
      } catch (e) {
        return label.toLowerCase().includes(filterStr.toLowerCase());
      }
    }

    selectMatchingDevice(devices) {
      if (!devices || devices.length === 0) return null;

      // 1. If explicit selectedDeviceId was provided
      if (this.selectedDeviceId) {
        const found = devices.find(d => d.deviceId === this.selectedDeviceId);
        if (found) return found;
      }

      // 2. Match against filter string/regex
      if (this.options.filter) {
        const match = devices.find(d => this.matchesFilter(d.label || '', this.options.filter));
        if (match) return match;
      }

      // 3. Fallback: If only 1 video camera exists on system, auto-select it
      if (devices.length === 1) {
        this.log('info', `Single video camera detected ("${devices[0].label || 'Camera 1'}"). Auto-selecting.`);
        return devices[0];
      }

      // 4. Default to first device
      return devices[0];
    }

    async startDeviceWorkflow() {
      try {
        const videoDevices = await this.probePermissions();
        if (videoDevices.length === 0) {
          this.reportStatus(false, 'No video input devices found.');
          return;
        }

        const targetDevice = this.selectMatchingDevice(videoDevices);
        if (!targetDevice) {
          this.reportStatus(false, 'No camera matched filter: ' + this.options.filter);
          return;
        }

        await this.startStream(targetDevice.deviceId, targetDevice.label);
      } catch (e) {
        this.reportStatus(false, `Initialization error: ${e.message}`);
      }
    }

    async startStream(deviceId, deviceLabel) {
      this.stopStream();

      // USB bus cooldown to prevent hardware controller lockup
      await new Promise(r => setTimeout(r, this.options.cooldownMs));

      const attempts = [
        {
          name: 'Preferred Resolution Exact ID',
          constraints: {
            video: {
              deviceId: { exact: deviceId },
              width: { ideal: this.options.preferredWidth },
              height: { ideal: this.options.preferredHeight }
            },
            audio: false
          }
        },
        {
          name: 'Ideal ID Fallback',
          constraints: {
            video: {
              deviceId: { ideal: deviceId }
            },
            audio: false
          }
        },
        {
          name: 'Generic Video Fallback',
          constraints: {
            video: true,
            audio: false
          }
        }
      ];

      let stream = null;
      let lastError = null;

      for (const attempt of attempts) {
        try {
          this.log('info', `Attempting stream: ${attempt.name}...`);
          stream = await navigator.mediaDevices.getUserMedia(attempt.constraints);
          if (stream && stream.getVideoTracks().length > 0) {
            this.log('info', `Stream acquired successfully with ${attempt.name}`);
            break;
          }
        } catch (err) {
          lastError = err;
          this.log('warn', `Attempt "${attempt.name}" failed: ${err.name} - ${err.message}`);
          await new Promise(r => setTimeout(r, 150));
        }
      }

      if (!stream) {
        this.reportStatus(false, `Failed to acquire video stream: ${lastError ? lastError.message : 'Unknown'}`);
        return;
      }

      this.currentStream = stream;
      this.selectedDeviceId = deviceId;

      const track = stream.getVideoTracks()[0];
      const activeLabel = track ? track.label : deviceLabel;

      if (this.videoEl) {
        this.videoEl.srcObject = stream;
        try {
          await this.videoEl.play();
        } catch (e) {
          this.log('warn', `Video play error: ${e.message}`);
        }
      }

      this.updateTransforms();
      this.reportStatus(true, activeLabel, activeLabel);

      // Listen for unexpected track termination (e.g. cable unplugged)
      track.onended = () => {
        this.log('warn', `Video track ended unexpectedly: ${activeLabel}`);
        this.reportStatus(false, 'Camera disconnected or unplugged.');
        this.scheduleReconnect();
      };
    }

    scheduleReconnect() {
      if (this.reconnectTimer) clearTimeout(this.reconnectTimer);
      this.reconnectTimer = setTimeout(() => {
        this.log('info', 'Attempting automatic reconnection...');
        this.startDeviceWorkflow();
      }, 2500);
    }

    stopStream() {
      if (this.currentStream) {
        this.currentStream.getTracks().forEach(track => {
          track.stop();
          track.onended = null;
        });
        this.currentStream = null;
      }
      if (this.videoEl) {
        this.videoEl.srcObject = null;
      }
      this.isWorking = false;
    }

    updateTransforms() {
      if (!this.videoEl) return;
      const sx = this.flipH ? -1 : 1;
      const sy = this.flipV ? -1 : 1;
      const scale = this.isZoomed ? ' scale(1.5)' : '';
      this.videoEl.style.transform = `rotate(${this.rotation}deg) scale(${sx}, ${sy})${scale}`;
      this.videoEl.style.transformOrigin = 'center center';
    }

    setOrientation(rotation, flipH, flipV) {
      if (rotation !== undefined) this.rotation = parseInt(rotation, 10) || 0;
      if (flipH !== undefined) this.flipH = Boolean(flipH);
      if (flipV !== undefined) this.flipV = Boolean(flipV);
      this.updateTransforms();
    }

    setReticle(visible, options) {
      if (!this.reticleEl) return;
      this.reticleEl.style.display = visible ? 'flex' : 'none';
      if (options) {
        const circle = this.reticleEl.querySelector('.usb-camera-reticle-circle');
        if (circle && options.circleRadius) {
          circle.style.width = (options.circleRadius * 2) + 'px';
          circle.style.height = (options.circleRadius * 2) + 'px';
        }
      }
    }

    setZoom(isZoomed) {
      this.isZoomed = Boolean(isZoomed);
      if (this.videoEl) {
        this.videoEl.style.objectFit = this.isZoomed ? 'none' : 'contain';
      }
      this.updateTransforms();
    }

    triggerFlash() {
      if (!this.flashEl) return;
      this.flashEl.classList.remove('flashing');
      void this.flashEl.offsetWidth;
      this.flashEl.classList.add('flashing');
      setTimeout(() => {
        this.flashEl.classList.remove('flashing');
      }, 150);
    }

    capture(options) {
      options = Object.assign({ format: 'jpeg', quality: 0.95 }, options || {});

      if (!this.videoEl || !this.currentStream || !this.isWorking) {
        this.log('warn', 'Cannot capture frame: Camera is offline.');
        if (window.Shiny && Shiny.setInputValue) {
          Shiny.setInputValue(this.id + '-error', 'Camera is offline.', { priority: 'event' });
        }
        return null;
      }

      const videoWidth = this.videoEl.videoWidth || 1280;
      const videoHeight = this.videoEl.videoHeight || 960;

      const isSideways = (this.rotation === 90 || this.rotation === 270);
      const canvas = document.createElement('canvas');
      canvas.width = isSideways ? videoHeight : videoWidth;
      canvas.height = isSideways ? videoWidth : videoHeight;
      const ctx = canvas.getContext('2d');

      ctx.save();
      ctx.translate(canvas.width / 2, canvas.height / 2);
      ctx.rotate((this.rotation * Math.PI) / 180);
      ctx.scale(this.flipH ? -1 : 1, this.flipV ? -1 : 1);
      ctx.drawImage(this.videoEl, -videoWidth / 2, -videoHeight / 2, videoWidth, videoHeight);
      ctx.restore();

      this.triggerFlash();

      const mimeType = options.format === 'png' ? 'image/png' : 'image/jpeg';
      const dataUrl = canvas.toDataURL(mimeType, options.quality);
      const timeStr = new Date().toLocaleTimeString();

      const payload = {
        dataUrl: dataUrl,
        width: canvas.width,
        height: canvas.height,
        timeString: timeStr,
        timestamp: Date.now()
      };

      if (window.Shiny && Shiny.setInputValue) {
        Shiny.setInputValue(this.id + '-snapshot', payload, { priority: 'event' });
      }

      return payload;
    }

    bindShinyHandlers() {
      if (!window.Shiny || !Shiny.addCustomMessageHandler) return;

      Shiny.addCustomMessageHandler(this.id + '-capture', (msg) => {
        this.capture(msg || {});
      });

      Shiny.addCustomMessageHandler(this.id + '-setOrientation', (msg) => {
        if (!msg) return;
        this.setOrientation(msg.rotation, msg.flipH, msg.flipV);
      });

      Shiny.addCustomMessageHandler(this.id + '-setReticle', (msg) => {
        this.setReticle(Boolean(msg && msg.visible), msg);
      });

      Shiny.addCustomMessageHandler(this.id + '-setZoom', (msg) => {
        this.setZoom(Boolean(msg && msg.isZoomed));
      });

      Shiny.addCustomMessageHandler(this.id + '-selectDevice', (msg) => {
        if (msg && msg.deviceId) {
          const device = this.devices.find(d => d.deviceId === msg.deviceId);
          const label = device ? device.label : 'Selected Camera';
          this.startStream(msg.deviceId, label);
        }
      });
    }
  }

  // Global factory function called on widget creation
  window.initUSBCamera = function(id, options) {
    if (window.USBCameraInstances[id]) {
      window.USBCameraInstances[id].stopStream();
    }
    const inst = new USBCameraInstance(id, options);
    window.USBCameraInstances[id] = inst;
    return inst;
  };

  // Device change listener on mediaDevices
  if (navigator.mediaDevices && navigator.mediaDevices.addEventListener) {
    navigator.mediaDevices.addEventListener('devicechange', async () => {
      console.log('[USBCamera] Hardware device change detected.');
      for (const id in window.USBCameraInstances) {
        const inst = window.USBCameraInstances[id];
        if (inst) {
          await inst.probePermissions();
          if (!inst.isWorking && inst.options.autoConnect) {
            inst.startDeviceWorkflow();
          }
        }
      }
    });
  }

  // Immediate teardown on page refresh, unload, or shiny disconnect
  window.addEventListener('beforeunload', () => {
    for (const id in window.USBCameraInstances) {
      window.USBCameraInstances[id].stopStream();
    }
  });

  window.addEventListener('pagehide', () => {
    for (const id in window.USBCameraInstances) {
      window.USBCameraInstances[id].stopStream();
    }
  });

  $(document).on('shiny:disconnected', () => {
    for (const id in window.USBCameraInstances) {
      window.USBCameraInstances[id].stopStream();
    }
  });
})();
