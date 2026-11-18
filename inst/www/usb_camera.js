/**
 * USBCamera: High-reliability WebRTC camera streaming and canvas capture for Shiny
 * Author: Jay Warrick
 */
(function() {
  'use strict';

  // Defensive patch for Shiny: prevent Shiny's strict arity assertion
  // (which throws "handler must be a function that takes one argument" when callback has 0 parameters)
  // from ever crashing any widget or user script on this page.
  const patchShinyHandler = () => {
    if (window.Shiny && typeof Shiny.addCustomMessageHandler === 'function' && !Shiny.__usbCameraArityPatched) {
      const origAddHandler = Shiny.addCustomMessageHandler;
      Shiny.addCustomMessageHandler = function(type, handler) {
        if (typeof handler === 'function' && handler.length !== 1) {
          const safeWrapper = function(msg) {
            return handler(msg);
          };
          return origAddHandler.call(Shiny, type, safeWrapper);
        }
        return origAddHandler.call(Shiny, type, handler);
      };
      Shiny.__usbCameraArityPatched = true;
    }
  };
  patchShinyHandler();
  $(document).on('shiny:connected', patchShinyHandler);

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
      this.streamInfo = null;
      this.isStartingWorkflow = false;
      this.lastError = null;

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
      this.customOverlayEl = document.getElementById(this.id + '-custom-overlay');
      this.flashEl = document.getElementById(this.id + '-flash');
      this.noMatchOverlay = document.getElementById(this.id + '-no-match-overlay');
      this.noMatchFilterEl = document.getElementById(this.id + '-no-match-filter');
      this.noMatchDevicesList = document.getElementById(this.id + '-no-match-devices-list');

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

      if (window.Shiny && typeof Shiny.setInputValue === 'function') {
        if (level === 'error' || level === 'warn' || this.options.debug) {
          Shiny.setInputValue(this.id + '-client_log', {
            level: level,
            message: fullMsg,
            timestamp: Date.now()
          }, { priority: 'event' });
        }
      }
    }

    reportStatus(working, message, activeDeviceLabel) {
      this.isWorking = working;
      if (this.statusDot) {
        this.statusDot.classList.toggle('active', working);
      }
      if (this.statusText) {
        this.statusText.textContent = message || (working ? 'Connected' : 'Offline');
      }

      const payload = {
        working: Boolean(working),
        message: message || '',
        activeDevice: activeDeviceLabel || '',
        timestamp: Date.now()
      };

      const send = () => {
        if (window.Shiny && typeof Shiny.setInputValue === 'function') {
          Shiny.setInputValue(this.id + '-status', payload, { priority: 'event' });
          return true;
        }
        return false;
      };

      if (!send()) {
        let attempts = 0;
        const interval = setInterval(() => {
          attempts++;
          if (send() || attempts >= 20) {
            clearInterval(interval);
          }
        }, 250);
      }
    }

    reportDevices() {
      const payload = (this.devices || []).map(d => ({
        deviceId: d.deviceId,
        label: d.label || 'Camera'
      }));

      this.log('info', `Reporting ${payload.length} devices to Shiny.`);

      const send = () => {
        if (window.Shiny && typeof Shiny.setInputValue === 'function') {
          Shiny.setInputValue(this.id + '-devices', JSON.stringify(payload), { priority: 'event' });
          return true;
        }
        return false;
      };

      if (!send()) {
        let attempts = 0;
        const interval = setInterval(() => {
          attempts++;
          if (send() || attempts >= 20) {
            clearInterval(interval);
          }
        }, 250);
      }
    }

    reportStreamInfo() {
      if (!this.currentStream) return;
      const track = this.currentStream.getVideoTracks()[0];
      const settings = (track && track.getSettings) ? track.getSettings() : {};
      const vw = (this.videoEl && this.videoEl.videoWidth) ? this.videoEl.videoWidth : (settings.width || this.options.preferredWidth || 1280);
      const vh = (this.videoEl && this.videoEl.videoHeight) ? this.videoEl.videoHeight : (settings.height || this.options.preferredHeight || 960);
      const fps = settings.frameRate || 0;
      const ar = (vw && vh) ? (vw / vh) : (settings.aspectRatio || 1.3333);

      const info = {
        width: vw,
        height: vh,
        frameRate: Math.round(fps * 10) / 10,
        aspectRatio: Math.round(ar * 1000) / 1000,
        channels: 3,
        bitDepth: 8,
        colorMode: 'Color (RGB)',
        deviceId: this.selectedDeviceId || '',
        label: track ? track.label : 'Active Camera',
        timestamp: Date.now()
      };

      this.streamInfo = info;

      const send = () => {
        if (window.Shiny && typeof Shiny.setInputValue === 'function') {
          Shiny.setInputValue(this.id + '-stream_info', info, { priority: 'event' });
          return true;
        }
        return false;
      };

      if (!send()) {
        let attempts = 0;
        const interval = setInterval(() => {
          attempts++;
          if (send() || attempts >= 20) {
            clearInterval(interval);
          }
        }, 250);
      }
    }

    async reportDiagnostics() {
      let permState = 'unknown';
      if (navigator.permissions && navigator.permissions.query) {
        try {
          const p = await navigator.permissions.query({ name: 'camera' });
          permState = p.state;
        } catch (e) {
          permState = 'unsupported';
        }
      }

      let rawDevs = [];
      if (navigator.mediaDevices && navigator.mediaDevices.enumerateDevices) {
        try {
          const all = await navigator.mediaDevices.enumerateDevices();
          rawDevs = all.filter(d => d.kind === 'videoinput').map((d, i) => ({
            index: i + 1,
            deviceId: d.deviceId ? (d.deviceId.substring(0, 10) + '...') : '(empty)',
            label: d.label || '(masked/empty)',
            groupId: d.groupId ? (d.groupId.substring(0, 10) + '...') : ''
          }));
        } catch (e) {
          this.log('warn', `enumerateDevices diagnostic query failed: ${e.message}`);
        }
      }

      const diag = {
        mediaDevicesSupported: Boolean(navigator.mediaDevices && navigator.mediaDevices.enumerateDevices),
        isSecureContext: Boolean(window.isSecureContext),
        origin: window.location.origin,
        permissionState: permState,
        rawDeviceCount: rawDevs.length,
        rawDevices: rawDevs,
        lastError: this.lastError ? `${this.lastError.name || 'Error'}: ${this.lastError.message || this.lastError}` : 'None',
        isWorking: this.isWorking,
        activeDevice: this.selectedDeviceId || ''
      };

      this.log('info', `Diagnostics: PermState=${permState}, VideoInputs=${rawDevs.length}, Error=${diag.lastError}`);

      if (window.Shiny && typeof Shiny.setInputValue === 'function') {
        Shiny.setInputValue(this.id + '-diagnostics', diag, { priority: 'event' });
      }
    }

    async probePermissions(forceProbe) {
      if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) {
        this.log('error', 'navigator.mediaDevices.enumerateDevices is not supported.');
        this.reportStatus(false, 'MediaDevices API not supported in this browser context.');
        await this.reportDiagnostics();
        return [];
      }

      let devices = await navigator.mediaDevices.enumerateDevices();
      let videoDevices = devices.filter(d => d.kind === 'videoinput');

      // If device labels are blank/masked, request permission once via getUserMedia
      const hasLabels = videoDevices.some(d => d.label && d.label.length > 0);
      if (!hasLabels || videoDevices.length === 0 || forceProbe) {
        this.log('info', 'Requesting getUserMedia probe to unmask device labels...');
        let probeStream = null;
        try {
          probeStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
          // Call enumerateDevices WHILE probeStream is actively running so browser unmasks labels!
          devices = await navigator.mediaDevices.enumerateDevices();
          videoDevices = devices.filter(d => d.kind === 'videoinput');
          this.lastError = null;
          this.log('info', `Device probe successful. Discovered ${videoDevices.length} video inputs.`);
        } catch (e) {
          this.lastError = e;
          this.log('warn', `Camera permission probe error: ${e.name} - ${e.message}`);
          this.reportStatus(false, `Camera permission needed: ${e.message}`);
        } finally {
          if (probeStream) {
            try {
              probeStream.getTracks().forEach(t => t.stop());
            } catch (err) {}
            await new Promise(r => setTimeout(r, this.options.cooldownMs));
          }
        }
      } else {
        this.log('info', `Using existing device list (${videoDevices.length} devices with labels).`);
      }

      this.devices = videoDevices;
      this.reportDevices();
      await this.reportDiagnostics();
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

    showNoMatchOverlay(filterStr, devices) {
      if (this.noMatchOverlay) {
        if (this.noMatchFilterEl) {
          this.noMatchFilterEl.textContent = filterStr || '(none)';
        }
        if (this.noMatchDevicesList) {
          this.noMatchDevicesList.innerHTML = '';
          if (devices && devices.length > 0) {
            devices.forEach((d, idx) => {
              const li = document.createElement('li');
              li.textContent = `${idx + 1}. "${d.label || 'Camera without label'}" (ID: ${d.deviceId ? d.deviceId.substring(0, 8) : 'unknown'}...)`;
              this.noMatchDevicesList.appendChild(li);
            });
          } else {
            const li = document.createElement('li');
            li.textContent = 'No video input devices detected on this system.';
            this.noMatchDevicesList.appendChild(li);
          }
        }
        this.noMatchOverlay.style.display = 'flex';
      }
    }

    hideNoMatchOverlay() {
      if (this.noMatchOverlay) {
        this.noMatchOverlay.style.display = 'none';
      }
    }

    selectMatchingDevice(devices) {
      if (!devices || devices.length === 0) {
        this.showNoMatchOverlay(this.options.filter, []);
        return null;
      }

      const filterVal = (typeof this.options.filter === 'string') ? this.options.filter.trim() : '';

      // 1. If explicit selectedDeviceId was provided AND (filter is empty OR selected device matches filter)
      if (this.selectedDeviceId) {
        const found = devices.find(d => d.deviceId === this.selectedDeviceId);
        if (found) {
          if (!filterVal || this.matchesFilter(found.label || '', filterVal)) {
            this.hideNoMatchOverlay();
            return found;
          }
        }
      }

      // 2. If regex/filter was provided (non-empty), ONLY select if a device matches!
      if (filterVal.length > 0) {
        const match = devices.find(d => this.matchesFilter(d.label || '', filterVal));
        if (match) {
          this.hideNoMatchOverlay();
          return match;
        } else {
          this.log('warn', `No camera matched filter regex: "${filterVal}". Attached: ${devices.map(d => d.label).join(', ')}`);
          this.showNoMatchOverlay(filterVal, devices);
          return null;
        }
      }

      // 3. Only if filter is empty (""), default to first available camera
      this.hideNoMatchOverlay();
      return devices[0];
    }

    async startDeviceWorkflow() {
      if (this.isStartingWorkflow) {
        this.log('info', 'Device workflow already in progress, skipping concurrent trigger.');
        return;
      }
      this.isStartingWorkflow = true;

      try {
        const videoDevices = await this.probePermissions();
        if (videoDevices.length === 0) {
          this.reportStatus(false, 'No video input devices found.');
          this.showNoMatchOverlay(this.options.filter, []);
          await this.reportDiagnostics();
          return;
        }

        const targetDevice = this.selectMatchingDevice(videoDevices);
        if (!targetDevice) {
          this.stopStream();
          const devLabels = videoDevices.map(d => d.label || 'Unlabeled Camera').join(', ');
          this.reportStatus(false, `No camera matched filter: "${this.options.filter}". Available: [${devLabels}]`);
          await this.reportDiagnostics();
          return;
        }

        await this.startStream(targetDevice.deviceId, targetDevice.label);
      } catch (e) {
        this.lastError = e;
        this.reportStatus(false, `Initialization error: ${e.message}`);
      } finally {
        this.isStartingWorkflow = false;
        await this.reportDiagnostics();
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
        this.lastError = lastError;
        this.reportStatus(false, `Failed to acquire video stream: ${lastError ? lastError.message : 'Unknown'}`);
        await this.reportDiagnostics();
        return;
      }

      this.currentStream = stream;
      this.selectedDeviceId = deviceId;
      this.lastError = null;
      this.hideNoMatchOverlay();

      const track = stream.getVideoTracks()[0];
      const activeLabel = track ? track.label : deviceLabel;

      if (this.videoEl) {
        this.videoEl.srcObject = stream;
        this.videoEl.onloadedmetadata = () => {
          this.reportStreamInfo();
          this.reportDiagnostics();
        };
        try {
          await this.videoEl.play();
        } catch (e) {
          this.log('warn', `Video play error: ${e.message}`);
        }
      }

      this.updateTransforms();
      this.reportStatus(true, activeLabel, activeLabel);
      this.reportStreamInfo();
      await this.reportDiagnostics();

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

    addSafeHandler(suffix, handler) {
      if (!window.Shiny || !Shiny.addCustomMessageHandler) return;
      const type = this.id + '-' + suffix;
      // Always pass a function with formal arity 1 so Shiny's check (handler.length === 1) is unconditionally satisfied.
      Shiny.addCustomMessageHandler(type, (msg) => {
        try {
          const res = handler.call(this, msg);
          if (res && typeof res.catch === 'function') {
            res.catch(err => {
              this.log('error', `Async error in handler '${suffix}': ${err.message}`, err.stack);
            });
          }
          return res;
        } catch (err) {
          this.log('error', `Error executing handler '${suffix}': ${err.message}`, err.stack);
        }
      });
    }

    bindShinyHandlers() {
      $(document).on('shiny:connected shiny:sessioninitialized', () => {
        this.reportDevices();
        this.reportDiagnostics();
        if (this.isWorking) {
          this.reportStatus(true, this.videoEl ? this.videoEl.title || 'Connected' : 'Connected', this.selectedDeviceId);
          this.reportStreamInfo();
        }
      });

      this.addSafeHandler('capture', (msg) => this.capture(msg || {}));

      this.addSafeHandler('setOrientation', (msg) => {
        if (!msg) return;
        this.setOrientation(msg.rotation, msg.flipH, msg.flipV);
      });

      this.addSafeHandler('setReticle', (msg) => {
        this.setReticle(Boolean(msg && msg.visible), msg);
      });

      this.addSafeHandler('setZoom', (msg) => {
        this.setZoom(Boolean(msg && msg.isZoomed));
      });

      this.addSafeHandler('getDevices', () => {
        this.log('info', 'Received getDevices request from Shiny.');
        this.probePermissions(true).then(() => this.reportDevices());
      });

      this.addSafeHandler('getDiagnostics', () => {
        this.reportDiagnostics();
      });

      this.addSafeHandler('requestPermissionPrompt', async () => {
        this.log('info', 'User explicitly requested camera permission prompt from button.');
        try {
          const probe = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
          this.log('info', 'Camera permission GRANTED!');
          probe.getTracks().forEach(t => t.stop());
          this.lastError = null;
          await this.startDeviceWorkflow();
        } catch (err) {
          this.lastError = err;
          this.log('error', `Manual permission prompt failed: ${err.name} - ${err.message}`);
          this.reportStatus(false, `Permission failed: ${err.message}`);
        }
        await this.reportDiagnostics();
      });

      this.addSafeHandler('getStreamInfo', () => {
        this.reportStreamInfo();
      });

      this.addSafeHandler('setOverlaySVG', (msg) => {
        if (this.customOverlayEl) {
          const content = (msg && (msg.svg || msg.html)) ? (msg.svg || msg.html) : '';
          this.customOverlayEl.innerHTML = content;
        }
      });

      this.addSafeHandler('setOverlayHTML', (msg) => {
        if (this.customOverlayEl) {
          const content = (msg && (msg.svg || msg.html)) ? (msg.svg || msg.html) : '';
          this.customOverlayEl.innerHTML = content;
        }
      });

      this.addSafeHandler('configure', (msg) => {
        if (!msg) return;
        if (msg.filter !== undefined) this.options.filter = msg.filter;
        if (msg.preferredWidth !== undefined) this.options.preferredWidth = msg.preferredWidth;
        if (msg.preferredHeight !== undefined) this.options.preferredHeight = msg.preferredHeight;
        this.reportDevices();
        this.startDeviceWorkflow();
      });

      this.addSafeHandler('selectDevice', (msg) => {
        if (msg && msg.deviceId) {
          const device = this.devices.find(d => d.deviceId === msg.deviceId);
          const label = device ? device.label : 'Selected Camera';
          this.selectedDeviceId = msg.deviceId;
          this.hideNoMatchOverlay();
          this.startStream(msg.deviceId, label);
        }
      });
    }
  }

  // Global factory function called on widget creation
  window.initUSBCamera = function(id, options) {
    try {
      if (window.USBCameraInstances[id]) {
        const existing = window.USBCameraInstances[id];
        if (options && options.filter !== undefined) {
          existing.options.filter = options.filter;
        }
        existing.reportDevices();
        existing.reportStreamInfo();
        existing.reportDiagnostics();
        return existing;
      }
      const inst = new USBCameraInstance(id, options);
      window.USBCameraInstances[id] = inst;
      return inst;
    } catch (err) {
      console.error(`[USBCamera:${id}] FATAL INITIALIZATION ERROR:`, err);
      const container = document.getElementById(id + '-container');
      if (container) {
        container.innerHTML = `
          <div style="position: absolute; inset: 0; background: #7f1d1d; color: #fef2f2; padding: 20px; font-family: monospace; z-index: 9999; display: flex; flex-direction: column; justify-content: center; align-items: center; text-align: center;">
            <div style="font-weight: bold; font-size: 16px; margin-bottom: 8px;">USBCamera Initialization Error</div>
            <div style="font-size: 13px; max-width: 90%; word-break: break-word;">${err.message || err}</div>
            <div style="font-size: 11px; margin-top: 10px; color: #fca5a5;">Check browser console for details.</div>
          </div>
        `;
      }
    }
  };

  // Device change listener on mediaDevices
  if (navigator.mediaDevices && navigator.mediaDevices.addEventListener) {
    navigator.mediaDevices.addEventListener('devicechange', async () => {
      console.log('[USBCamera] Hardware device change detected.');
      for (const id in window.USBCameraInstances) {
        const inst = window.USBCameraInstances[id];
        if (inst) {
          await inst.probePermissions(true);
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
