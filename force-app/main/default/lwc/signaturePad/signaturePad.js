import { LightningElement, api, track } from 'lwc';

const MAX_BASE64_BYTES = 125000; // stay safely under the ~131072 Long Text Area limit

export default class SignaturePad extends LightningElement {

    @api signerName = '';          // e.g. the firearm instructor's name
    @track isOpen   = false;
    @track isEmpty  = true;
    @track isSaving = false;

    _ctx        = null;
    _canvas     = null;
    _drawing    = false;
    _lastX      = 0;
    _lastY      = 0;
    _hasRendered = false;

    // ── Public API ──────────────────────────────────────────────────────────
    @api
    open() {
        this.isOpen  = true;
        this.isEmpty = true;
        this.isSaving = false;
        // canvas is set up in renderedCallback once the DOM paints
        this._hasRendered = false;
    }

    @api
    close() {
        this.isOpen = false;
    }

    // ── Lifecycle ───────────────────────────────────────────────────────────
    renderedCallback() {
        if (this.isOpen && !this._hasRendered) {
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

    // ── Buttons ─────────────────────────────────────────────────────────────
    handleClear() {
        if (!this._ctx || !this._canvas) return;
        this._ctx.fillStyle = '#ffffff';
        this._ctx.fillRect(0, 0, this._canvas.width, this._canvas.height);
        this.isEmpty = true;
    }

    handleCancel() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleSave() {
        if (this.isEmpty || !this._canvas) return;

        // Export as PNG base64. Try to keep it under the field limit.
        let dataUrl = this._canvas.toDataURL('image/png');

        // If too large, fall back to JPEG at reducing quality
        if (this._byteLength(dataUrl) > MAX_BASE64_BYTES) {
            let quality = 0.7;
            dataUrl = this._canvas.toDataURL('image/jpeg', quality);
            while (this._byteLength(dataUrl) > MAX_BASE64_BYTES && quality > 0.3) {
                quality -= 0.1;
                dataUrl = this._canvas.toDataURL('image/jpeg', quality);
            }
        }

        if (this._byteLength(dataUrl) > MAX_BASE64_BYTES) {
            this.dispatchEvent(new CustomEvent('error', {
                detail: { message: 'Signature image is too large to store. Please try a simpler signature.' }
            }));
            return;
        }

        this.isSaving = true;
        // Emit the base64 string to the parent, which saves it via Apex
        this.dispatchEvent(new CustomEvent('signaturesave', {
            detail: { signature: dataUrl }
        }));
    }

    // Parent calls this after Apex save completes to close the modal
    @api
    finishSaving() {
        this.isSaving = false;
        this.isOpen   = false;
    }

    @api
    saveFailed() {
        this.isSaving = false;
    }

    // ── Utility: byte length of a base64 data URL string ────────────────────
    _byteLength(str) {
        // approximate stored character length (Long Text Area counts characters)
        return str ? str.length : 0;
    }
}