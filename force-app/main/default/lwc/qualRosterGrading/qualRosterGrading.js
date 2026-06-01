import { LightningElement, track } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import getRosterLabelDetails       from '@salesforce/apex/QualRosterGradingController.getRosterLabelDetails';
import getRosterGradingData        from '@salesforce/apex/QualRosterGradingController.getRosterGradingData';
import saveGradingRow              from '@salesforce/apex/QualRosterGradingController.saveGradingRow';

export default class QualRosterGrading extends LightningElement {

    // ═══════════════════════════════════════════════════════════════════════
    // List View state
    // ═══════════════════════════════════════════════════════════════════════
    @track currentView       = 'list';   // 'list' or 'grading'
    @track rosterRows        = [];       // RosterLabelRow[] from Apex
    @track isLoadingList     = false;
    @track listSearchKey     = '';

    get isListView()    { return this.currentView === 'list'; }
    get isGradingView() { return this.currentView === 'grading'; }

    get rosterRowCount() { return this.rosterRows.length; }

    get hasRosterRows() { return this.rosterRows.length > 0; }

    get noRosterRows() { return !this.isLoadingList && this.rosterRows.length === 0; }

    get filteredRosterRows() {
        if (!this.listSearchKey || !this.listSearchKey.trim()) return this.rosterRows;
        const key = this.listSearchKey.toLowerCase();
        return this.rosterRows.filter(r =>
            (r.rosterLabel    && r.rosterLabel.toLowerCase().includes(key))    ||
            (r.instructorName && r.instructorName.toLowerCase().includes(key)) ||
            (r.location       && r.location.toLowerCase().includes(key))       ||
            (r.testDate       && r.testDate.toLowerCase().includes(key))
        );
    }

    get filteredRosterCount() { return this.filteredRosterRows.length; }

    // ═══════════════════════════════════════════════════════════════════════
    // Grading View state (existing)
    // ═══════════════════════════════════════════════════════════════════════
    @track gradingData      = null;
    @track selectedLabel    = '';
    @track selectedWeapon   = '';
    @track isLoadingGrading = false;

    _pendingChanges = {};

    get hasGradingData() {
        return this.gradingData &&
               this.gradingData.weaponSections &&
               this.gradingData.weaponSections.length > 0;
    }

    get weaponNavItems() {
        if (!this.hasGradingData) return [];
        return this.gradingData.weaponSections.map(section => {
            const total  = section.rows.length;
            const graded = section.rows.filter(r =>
                (r.qualified || '').toLowerCase() === 'yes' ||
                (r.qualified || '').toLowerCase() === 'no'
            ).length;
            const pct      = total > 0 ? Math.round((graded / total) * 100) : 0;
            const isActive = this.selectedWeapon === section.weaponType;
            return {
                weaponType  : section.weaponType,
                label       : section.weaponType,
                total, graded, pct,
                statText    : graded + ' of ' + total + ' graded',
                dotClass    : 'weapon-dot weapon-dot-' + this.weaponCssKey(section.weaponType),
                itemClass   : isActive ? 'weapon-nav-item weapon-nav-active' : 'weapon-nav-item',
                pctBarStyle : 'width:' + pct + '%',
                barClass    : 'pct-bar-fill pct-bar-' + this.weaponCssKey(section.weaponType)
            };
        });
    }

    get activeSection() {
        if (!this.hasGradingData || !this.selectedWeapon) return null;
        return this.gradingData.weaponSections.find(s => s.weaponType === this.selectedWeapon) || null;
    }

    get activeRows() {
        return this.activeSection ? this.activeSection.rows : [];
    }

    get hasActiveRows() {
        return this.activeRows.length > 0;
    }

    get activeSummary() {
        if (!this.activeSection) return null;
        const rows      = this.activeSection.rows;
        const total     = rows.length;
        const qualified = rows.filter(r => (r.qualified || '').toLowerCase() === 'yes').length;
        const at90      = rows.filter(r => (r.qualified90 || '').toLowerCase() === 'yes').length;
        const notQual   = total - qualified;
        const members   = new Set(rows.map(r => r.firFormId)).size;
        const graded    = rows.filter(r =>
            (r.qualified || '').toLowerCase() === 'yes' ||
            (r.qualified || '').toLowerCase() === 'no'
        ).length;
        return {
            weaponType  : this.selectedWeapon,
            total, members, qualified, at90,
            notQualified: notQual, graded,
            badgeText   : total + ' attempts - ' + members + ' members',
            dotClass    : 'weapon-badge-dot weapon-dot-' + this.weaponCssKey(this.selectedWeapon),
            gradedText  : graded + '/' + total + ' graded'
        };
    }

    weaponCssKey(weaponType) {
        const map = {
            'Pistol 1'         : 'pistol',
            'Pistol 2'         : 'pistol',
            'Shotgun'          : 'shotgun',
            'Rifle'            : 'rifle',
            'Automatic Weapon' : 'auto',
            'Precision Rifle'  : 'precision'
        };
        return map[weaponType] || 'pistol';
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Lifecycle
    // ═══════════════════════════════════════════════════════════════════════
    connectedCallback() {
        this.loadRosterList();
    }

    // ── List View methods ──────────────────────────────────────────────────
    loadRosterList() {
        this.isLoadingList = true;
        getRosterLabelDetails()
            .then(rows => {
                this.rosterRows    = rows || [];
                this.isLoadingList = false;
            })
            .catch(error => {
                this.isLoadingList = false;
                this.showErrorToast(this.reduceError(error));
            });
    }

    handleListSearch(event) {
        this.listSearchKey = event.target.value;
    }

    handleRosterRowClick(event) {
        const label = event.currentTarget.dataset.label;
        if (!label) return;
        this.selectedLabel = label;
        this.currentView   = 'grading';
        this.loadGradingData(label);
    }

    handleBackToList() {
        this.currentView   = 'list';
        this.selectedLabel = '';
        this.gradingData   = null;
        this.selectedWeapon = '';
        this._pendingChanges = {};
        // Refresh the list in case grading changed data
        this.loadRosterList();
    }

    // ── Grading View methods (existing) ────────────────────────────────────
    loadGradingData(label) {
        this.isLoadingGrading = true;
        getRosterGradingData({ rosterLabel: label })
            .then(data => {
                this.isLoadingGrading = false;
                if (!data) return;
                this.gradingData = this.enrichData(data);
                if (this.gradingData.weaponSections && this.gradingData.weaponSections.length > 0) {
                    this.selectedWeapon = this.gradingData.weaponSections[0].weaponType;
                }
            })
            .catch(error => {
                this.isLoadingGrading = false;
                this.showErrorToast(this.reduceError(error));
            });
    }

    enrichData(data) {
        const enriched = Object.assign({}, data);
        enriched.weaponSections = (data.weaponSections || []).map(section => ({
            weaponType : section.weaponType,
            rows       : (section.rows || []).map(row => this.enrichRow(row))
        }));
        return enriched;
    }

    enrichRow(row) {
        const isQualified   = (row.qualified   || '').toLowerCase() === 'yes';
        const isQualified90 = (row.qualified90  || '').toLowerCase() === 'yes';
        return {
            ...row,
            qualifiedChecked   : isQualified,
            qualified90Checked : isQualified90,
            qualifiedYes       : isQualified,
            qualifiedNo        : !isQualified,
            qualified90Yes     : isQualified90,
            qualified90No      : !isQualified90,
            isWeaponCodeABC    : row.weaponCode === 'ABC',
            isWeaponCodeZXC    : row.weaponCode === 'ZXC',
            is1st              : row.qualificationAttempt === '1st',
            is2nd              : row.qualificationAttempt === '2nd',
            is3rd              : row.qualificationAttempt === '3rd',
            is4th              : row.qualificationAttempt === '4th'
        };
    }

    handleWeaponSelect(event) {
        this.selectedWeapon = event.currentTarget.dataset.weapon;
    }

    handleFieldBlur(event) {
        const detailId = event.target.dataset.detailId;
        const field    = event.target.dataset.field;
        const value    = event.target.value;
        this.trackChange(detailId, field, value);
        this.autoSaveRow(detailId);
    }

    handleSelectChange(event) {
        const detailId = event.target.dataset.detailId;
        const field    = event.target.dataset.field;
        const value    = event.target.value;
        this.trackChange(detailId, field, value);
        this.autoSaveRow(detailId);
    }

    handleCheckboxChange(event) {
        const detailId = event.target.dataset.detailId;
        const field    = event.target.dataset.field;
        const value    = event.target.checked ? 'Yes' : 'No';
        this.trackChange(detailId, field, value);
        this.updateRowField(detailId, field, value);
        this.autoSaveRow(detailId);
    }

    updateRowField(detailId, field, value) {
        if (!this.gradingData) return;
        const updated = Object.assign({}, this.gradingData);
        updated.weaponSections = updated.weaponSections.map(section => ({
            ...section,
            rows: section.rows.map(row => {
                if (row.detailId !== detailId) return row;
                const newRow = { ...row, [field]: value };
                return this.enrichRow(newRow);
            })
        }));
        this.gradingData = updated;
    }

    trackChange(detailId, field, value) {
        if (!this._pendingChanges[detailId]) {
            const currentRow = this.findRow(detailId);
            this._pendingChanges[detailId] = currentRow
                ? {
                    manufacturer        : currentRow.manufacturer        || '',
                    model               : currentRow.model               || '',
                    sightType           : currentRow.sightType           || '',
                    weaponCode          : currentRow.weaponCode          || '',
                    qualificationAttempt: currentRow.qualificationAttempt || '',
                    qualified           : currentRow.qualified           || '',
                    qualified90         : currentRow.qualified90         || ''
                }
                : {};
        }
        this._pendingChanges[detailId][field] = value;
    }

    findRow(detailId) {
        if (!this.gradingData) return null;
        for (const section of this.gradingData.weaponSections) {
            const found = section.rows.find(r => r.detailId === detailId);
            if (found) return found;
        }
        return null;
    }

    autoSaveRow(detailId) {
        const changes = this._pendingChanges[detailId];
        if (!changes) return;
        saveGradingRow({
            detailId            : detailId,
            manufacturer        : changes.manufacturer        || '',
            model               : changes.model               || '',
            sightType           : changes.sightType           || '',
            weaponCode          : changes.weaponCode          || '',
            qualificationAttempt: changes.qualificationAttempt || '',
            qualified           : changes.qualified           || '',
            qualified90         : changes.qualified90         || ''
        })
        .then(() => {
            delete this._pendingChanges[detailId];
        })
        .catch(error => {
            this.showErrorToast('Auto-save failed: ' + this.reduceError(error));
        });
    }

    // ── Utilities ──────────────────────────────────────────────────────────
    showErrorToast(msg) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        return JSON.stringify(error);
    }
}