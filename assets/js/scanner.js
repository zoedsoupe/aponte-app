// Door scanner — camera QR reading for ScannerLive.
//
// Shipped as a SEPARATE esbuild entry (jsQR is ~250 KB) so the public bundle
// stays lean; the layout only loads this on /admin/validar. It registers a
// LiveView hook on `window.SeshHooks` BEFORE app.js boots the LiveSocket
// (deferred scripts run in DOM order), and app.js merges that registry in.
import jsQR from "../vendor/jsqr.js";

const FRAME_INTERVAL_MS = 100; // ~10 fps — enough for QR, easy on the battery
const DEBOUNCE_MS = 3000; // same code within 3s = one scan
const MUTE_KEY = "aponte.scanner.mute"; // persisted sound preference

// Door ergonomics: two distinct tones so the operator can tell ok from error by
// ear, without looking down at the screen while a queue is waiting. Oscillator
// only (no assets); the AudioContext is created on the "Ativar câmera" gesture
// so autoplay policies don't block it.
function audioCtx() {
  const Ctx = window.AudioContext || window.webkitAudioContext;
  if (!Ctx) return null;
  if (!audioCtx._ctx) audioCtx._ctx = new Ctx();
  if (audioCtx._ctx.state === "suspended") audioCtx._ctx.resume();
  return audioCtx._ctx;
}

function beep(kind) {
  if (localStorage.getItem(MUTE_KEY) === "1") return;
  const ctx = audioCtx();
  if (!ctx) return;

  const now = ctx.currentTime;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = "sine";
  osc.connect(gain).connect(ctx.destination);

  const [freq, dur, peak] = kind === "ok" ? [880, 0.18, 0.2] : [220, 0.32, 0.25];
  osc.frequency.setValueAtTime(freq, now);
  gain.gain.setValueAtTime(0.0001, now);
  gain.gain.exponentialRampToValueAtTime(peak, now + 0.01);
  gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);
  osc.start(now);
  osc.stop(now + dur + 0.02);
}

const Scanner = {
  mounted() {
    this.video = this.el.querySelector("[data-scanner-video]");
    this.activateBtn = this.el.querySelector("[data-scanner-activate]");
    this.canvas = document.createElement("canvas");
    this.ctx = this.canvas.getContext("2d", { willReadFrequently: true });

    this.running = false;
    this.lastCode = null;
    this.lastAt = 0;
    this.lastFrame = 0;
    this.tick = this.tick.bind(this);

    if (this.activateBtn) {
      this.activateBtn.addEventListener("click", () => {
        audioCtx(); // unlock audio on this gesture
        this.start();
      });
    }

    this.bindMute();

    // The result panel is server-rendered (inside this.el on the door page,
    // beside it on the counter), so watch the DOM and beep when one appears.
    this.lastResult = "";
    this.resultObserver = new MutationObserver(() => this.checkResult());
    this.resultObserver.observe(document.body, { childList: true, subtree: true });
    this.checkResult();

    // iOS/Android: stop the camera loop when the tab is backgrounded.
    this.onVisibility = () => {
      if (document.hidden) this.pause();
      else if (this.stream) this.resume();
    };
    document.addEventListener("visibilitychange", this.onVisibility);
  },

  checkResult() {
    const el = document.querySelector(".scan-result");
    const sig = el ? `${el.className}|${(el.textContent || "").trim().slice(0, 40)}` : "";
    if (sig === this.lastResult) return;
    this.lastResult = sig;
    if (!el) return;
    beep(el.classList.contains("scan-result--ok") ? "ok" : "err");
  },

  bindMute() {
    this.muteBtn = this.el.querySelector("[data-scanner-mute]");
    if (!this.muteBtn) return;

    const sync = () => {
      const muted = localStorage.getItem(MUTE_KEY) === "1";
      this.muteBtn.textContent = muted ? "Som desligado" : "Som ligado";
      this.muteBtn.setAttribute("aria-pressed", String(muted));
    };

    this.muteBtn.addEventListener("click", () => {
      const muted = localStorage.getItem(MUTE_KEY) === "1";
      localStorage.setItem(MUTE_KEY, muted ? "0" : "1");
      sync();
    });

    sync();
  },

  async start() {
    if (this.stream) return this.resume();

    try {
      // Explicit user gesture above triggers the iOS permission prompt.
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: "environment" } },
        audio: false,
      });
      this.video.srcObject = this.stream;
      await this.video.play();
      this.el.setAttribute("data-camera", "on");
      this.resume();
    } catch (err) {
      this.pushEvent("camera_error", { name: (err && err.name) || "erro" });
    }
  },

  resume() {
    if (this.running) return;
    this.running = true;
    requestAnimationFrame(this.tick);
  },

  pause() {
    this.running = false;
  },

  tick(ts) {
    if (!this.running) return;
    requestAnimationFrame(this.tick);

    if (ts - this.lastFrame < FRAME_INTERVAL_MS) return;
    this.lastFrame = ts;

    const v = this.video;
    if (!v || v.readyState !== v.HAVE_ENOUGH_DATA) return;

    const w = v.videoWidth;
    const h = v.videoHeight;
    if (!w || !h) return;

    this.canvas.width = w;
    this.canvas.height = h;
    this.ctx.drawImage(v, 0, 0, w, h);

    const image = this.ctx.getImageData(0, 0, w, h);
    // QR is dark-on-light (our render) — skip inversion attempts, ~2× faster.
    const result = jsQR(image.data, w, h, { inversionAttempts: "dontInvert" });

    if (result && result.data) this.handleCode(result.data);
  },

  handleCode(code) {
    const now = Date.now();
    if (code === this.lastCode && now - this.lastAt < DEBOUNCE_MS) return;
    this.lastCode = code;
    this.lastAt = now;

    if (navigator.vibrate) navigator.vibrate(60);
    this.pushEvent("scan", { code });
  },

  destroyed() {
    this.pause();
    document.removeEventListener("visibilitychange", this.onVisibility);
    if (this.resultObserver) this.resultObserver.disconnect();
    if (this.stream) this.stream.getTracks().forEach((t) => t.stop());
  },
};

window.SeshHooks = window.SeshHooks || {};
window.SeshHooks.Scanner = Scanner;
