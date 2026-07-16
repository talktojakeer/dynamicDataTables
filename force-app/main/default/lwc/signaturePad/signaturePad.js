import { LightningElement, api, track } from 'lwc';

const MAX_BASE64_BYTES = 125000; // stay safely under the ~131072 field limit
const MAX_OUTPUT_WIDTH = 320;     // target signature width (px) after trimming
const INK_BRIGHTNESS   = 240;     // a pixel is "ink" if darker than this (0-255)
const INK_ALPHA        = 20;      // ...and more opaque than this (0-255)
const TRIM_PADDING     = 6;       // px of whitespace kept around the signature

// Reusable signature CANVAS widget only - no modal chrome, no Save/Cancel
// buttons, no isOpen state. The parent component owns the modal and decides
// when/how many of these to show (e.g. instructor + witness together).
export default class SignaturePad extends LightningElement {

    @api signerName = '';          // e.g. the firearm instructor's or witness's name
    @track isEmpty  = true;

    _ctx         = null;
    _canvas      = null;
    _drawing     = false;
    _lastX       = 0;
    _lastY       = 0;
    _hasRendered = false;

    // ── Lifecycle ───────────────────────────────────────────────────────────
    renderedCallback() {
        if (!this._hasRendered) {
            this._hasRendered = true;
            this._setupCanvas();
        }
    }

    _setupCanvas() {
        this._canvas = this.template.querySelector('.sig-canvas');
        if (!this._canvas) return;

        // Size the canvas to its displayed size for crisp lines
        const rect = this._canvas.getBoundingClientRect();
        // Use a modest resolution to keep the base64 small
        this._canvas.width  = rect.width  || 600;
        this._canvas.height = rect.height || 200;

        this._ctx = this._canvas.getContext('2d');
        this._ctx.lineWidth   = 2;
        this._ctx.lineCap     = 'round';
        this._ctx.lineJoin    = 'round';
        this._ctx.strokeStyle = '#1a1a1a';
        // white background so exported PNG isn't transparent (renders cleanly in PDF)
        this._ctx.fillStyle = '#ffffff';
        this._ctx.fillRect(0, 0, this._canvas.width, this._canvas.height);
    }

    // ── Coordinate helpers ──────────────────────────────────────────────────
    _pos(clientX, clientY) {
        const rect = this._canvas.getBoundingClientRect();
        const scaleX = this._canvas.width  / rect.width;
        const scaleY = this._canvas.height / rect.height;
        return {
            x: (clientX - rect.left) * scaleX,
            y: (clientY - rect.top)  * scaleY
        };
    }

    _startAt(x, y) {
        this._drawing = true;
        this._lastX = x;
        this._lastY = y;
    }

    _drawTo(x, y) {
        if (!this._drawing || !this._ctx) return;
        this._ctx.beginPath();
        this._ctx.moveTo(this._lastX, this._lastY);
        this._ctx.lineTo(x, y);
        this._ctx.stroke();
        this._lastX = x;
        this._lastY = y;
        if (this.isEmpty) this.isEmpty = false;
    }

    // ── Mouse events ────────────────────────────────────────────────────────
    handlePointerDown(event) {
        const p = this._pos(event.clientX, event.clientY);
        this._startAt(p.x, p.y);
    }

    handlePointerMove(event) {
        if (!this._drawing) return;
        const p = this._pos(event.clientX, event.clientY);
        this._drawTo(p.x, p.y);
    }

    handlePointerUp() {
        this._drawing = false;
    }

    // ── Touch events (tablet/mobile) ────────────────────────────────────────
    handleTouchStart(event) {
        event.preventDefault();
        const t = event.touches[0];
        const p = this._pos(t.clientX, t.clientY);
        this._startAt(p.x, p.y);
    }

    handleTouchMove(event) {
        event.preventDefault();
        if (!this._drawing) return;
        const t = event.touches[0];
        const p = this._pos(t.clientX, t.clientY);
        this._drawTo(p.x, p.y);
    }

    // ── Public API for the parent modal ────────────────────────────────────
    @api
    clear() {
        if (!this._ctx || !this._canvas) return;
        this._ctx.fillStyle = '#ffffff';
        this._ctx.fillRect(0, 0, this._canvas.width, this._canvas.height);
        this.isEmpty = true;
    }

    @api
    get hasSignature() {
        return !this.isEmpty;
    }

    // Returns { dataUrl, error }. dataUrl is null when there is nothing drawn,
    // or when the drawing can't be shrunk below the storage limit.
    // The image is trimmed to the drawn strokes and scaled down before export,
    // which greatly reduces the stored size (and removes empty whitespace).
    @api
    captureSignature() {
        if (this.isEmpty || !this._canvas) {
            return { dataUrl: null, error: null };
        }

        // 1) Trim to the ink bounding box and scale down; fall back to the
        //    full canvas if pixel data can't be read for any reason.
        const source = this._trimAndScale() || this._canvas;

        // 2) Export - PNG first (crisp line art, small when trimmed), then
        //    JPEG at reducing quality only if still over the limit.
        let dataUrl = source.toDataURL('image/png');
        if (this._byteLength(dataUrl) > MAX_BASE64_BYTES) {
            let quality = 0.7;
            dataUrl = source.toDataURL('image/jpeg', quality);
            while (this._byteLength(dataUrl) > MAX_BASE64_BYTES && quality > 0.3) {
                quality -= 0.1;
                dataUrl = source.toDataURL('image/jpeg', quality);
            }
        }

        if (this._byteLength(dataUrl) > MAX_BASE64_BYTES) {
            return {
                dataUrl: null,
                error: 'Signature image is too large to store. Please try a simpler signature.'
            };
        }

        return { dataUrl, error: null };
    }

    // Crop the canvas to just the drawn strokes (dropping empty margins) and
    // scale the result down to MAX_OUTPUT_WIDTH. Returns a new canvas, or
    // null if pixels can't be read or nothing was drawn.
    _trimAndScale() {
        const w = this._canvas.width;
        const h = this._canvas.height;
        let data;
        try {
            data = this._ctx.getImageData(0, 0, w, h).data;
        } catch (e) {
            return null;
        }

        // Find the bounding box of "ink" pixels
        let minX = w, minY = h, maxX = -1, maxY = -1;
        for (let y = 0; y < h; y++) {
            for (let x = 0; x < w; x++) {
                const i      = (y * w + x) * 4;
                const alpha  = data[i + 3];
                const bright = (data[i] + data[i + 1] + data[i + 2]) / 3;
                if (alpha > INK_ALPHA && bright < INK_BRIGHTNESS) {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }

        if (maxX < 0) return null; // no ink detected

        // Pad the box, clamped to the canvas
        minX = Math.max(0, minX - TRIM_PADDING);
        minY = Math.max(0, minY - TRIM_PADDING);
        maxX = Math.min(w - 1, maxX + TRIM_PADDING);
        maxY = Math.min(h - 1, maxY + TRIM_PADDING);

        const cropW = maxX - minX + 1;
        const cropH = maxY - minY + 1;

        // Scale down (never up) to the target width
        const scale = Math.min(1, MAX_OUTPUT_WIDTH / cropW);
        const outW  = Math.max(1, Math.round(cropW * scale));
        const outH  = Math.max(1, Math.round(cropH * scale));

        const out  = document.createElement('canvas');
        out.width  = outW;
        out.height = outH;
        const octx = out.getContext('2d');
        octx.fillStyle = '#ffffff'; // clean white background, JPEG-safe
        octx.fillRect(0, 0, outW, outH);
        octx.drawImage(this._canvas, minX, minY, cropW, cropH, 0, 0, outW, outH);
        return out;
    }

    // ── Utility: byte length of a base64 data URL string ────────────────────
    _byteLength(str) {
        // approximate stored character length (Long Text Area counts characters)
        return str ? str.length : 0;
    }
}