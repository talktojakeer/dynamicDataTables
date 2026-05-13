import { LightningElement, track } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import getRosterLabels             from '@salesforce/apex/QualRosterGradingController.getRosterLabels';
import getRosterGradingData        from '@salesforce/apex/QualRosterGradingController.getRosterGradingData';
import saveGradingRow              from '@salesforce/apex/QualRosterGradingController.saveGradingRow';

export default class QualRosterGrading extends LightningElement {

    @track rosterLabels     = [];
    @track gradingData      = null;
    @track selectedLabel    = '';
    @track selectedWeapon   = '';
    @track isLoadingLabels  = false;
    @track isLoadingGrading = false;

    _pendingChanges = {};

    get noLabels() {
        return !this.isLoadingLabels && this.rosterLabels.length === 0;
    }

    get hasGradingData() {
        return this.gradingData &&
               this.gradingData.weaponSections &&
               this.gradingData.weaponSections.length > 0;
    }

    // --- Sidebar weapon list with stats ---
    get weaponNavItems() {
        if (!this.hasGradingData) return [];
        return this.gradingData.weaponSections.map(section => {
            const total     = section.rows.length;
            const graded    = section.rows.filter(r =>
                (r.qualified || '').toLowerCase() === 'yes' ||
                (r.qualified || '').toLowerCase() === 'no'
            ).length;
            const pct       = total > 0 ? Math.round((graded / total) * 100) : 0;
            const isActive  = this.selectedWeapon === section.weaponType;
            return {
                weaponType : section.weaponType,
                label      : section.weaponType,
                total      : total,
                graded     : graded,
                pct        : pct,
                statText   : graded + ' of ' + total + ' graded',
                dotClass   : 'weapon-dot weapon-dot-' + this.weaponCssKey(section.weaponType),
                itemClass  : isActive ? 'weapon-nav-item weapon-nav-active' : 'weapon-nav-item',
                pctBarStyle: 'width:' + pct + '%',
                barClass   : 'pct-bar-fill pct-bar-' + this.weaponCssKey(section.weaponType)
            };
        });
    }

    // --- Active weapon section rows ---
    get activeSection() {
        if (!this.hasGradingData || !this.selectedWeapon) return null;
        return this.gradingData.weaponSections.find(
            s => s.weaponType === this.selectedWeapon
        ) || null;
    }

    get activeRows() {
        return this.activeSection ? this.activeSection.rows : [];
    }

    get hasActiveRows() {
        return this.activeRows.length > 0;
    }

    // --- Active section summary badges ---
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
            total       : total,
            members     : members,
            qualified   : qualified,
            at90        : at90,
            notQualified: notQual,
            graded      : graded,
            badgeText   : total + ' attempts - ' + members + ' members',
            dotClass    : 'weapon-badge-dot weapon-dot-' + this.weaponCssKey(this.selectedWeapon),
            gradedText  : graded + '/' + total + ' graded'
        };
    }

    weaponCssKey(weaponType) {
        const map = {
            'Pistol'           : 'pistol',
            'Shot Gun'         : 'shotgun',
            'Riffle'           : 'rifle',
            'Automatic Weapon' : 'auto',
            'Precision Riffle' : 'precision'
        };
        return map[weaponType] || 'pistol';
    }

    connectedCallback() {
        this.loadRosterLabels();
    }

    loadRosterLabels() {
        this.isLoadingLabels = true;
        getRosterLabels()
            .then(labels => {
                this.rosterLabels    = labels || [];
                this.isLoadingLabels = false;
            })
            .catch(error => {
                this.isLoadingLabels = false;
                this.showErrorToast(this.reduceError(error));
            });
    }

    handleLabelChange(event) {
        this.selectedLabel   = event.target.value;
        this.gradingData     = null;
        this.selectedWeapon  = '';
        this._pendingChanges = {};
        if (!this.selectedLabel) return;
        this.loadGradingData(this.selectedLabel);
    }

    loadGradingData(label) {
        this.isLoadingGrading = true;
        getRosterGradingData({ rosterLabel: label })
            .then(data => {
                this.isLoadingGrading = false;
                if (!data) return;
                this.gradingData = this.enrichData(data);
                // Auto-select first weapon
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
        enriched.weaponSections = (data.weaponSections || []).map(section => {
            return {
                weaponType : section.weaponType,
                rows       : (section.rows || []).map(row => this.enrichRow(row))
            };
        });
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
            isIronSight        : row.sightType === 'Iron Sight',
            isOptic            : row.sightType === 'Optic',
            isMagnifiedOptic   : row.sightType === 'Magnified Optic',
            is1st              : row.qualificationAttempt === '1st',
            is2nd              : row.qualificationAttempt === '2nd',
            is3rd              : row.qualificationAttempt === '3rd',
            is4th              : row.qualificationAttempt === '4th'
        };
    }

    // --- Weapon sidebar click ---
    handleWeaponSelect(event) {
        this.selectedWeapon = event.currentTarget.dataset.weapon;
    }

    // --- Inline field handlers ---
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

    handleQualifiedToggle(event) {
        const detailId = event.currentTarget.dataset.detailId;
        const value    = event.currentTarget.dataset.value;
        this.trackChange(detailId, 'qualified', value);
        this.updateRowField(detailId, 'qualified', value);
        this.autoSaveRow(detailId);
    }

    handleQualified90Toggle(event) {
        const detailId = event.currentTarget.dataset.detailId;
        const value    = event.currentTarget.dataset.value;
        this.trackChange(detailId, 'qualified90', value);
        this.updateRowField(detailId, 'qualified90', value);
        this.autoSaveRow(detailId);
    }

    // Update local row data so UI refreshes without re-fetching from Apex
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
                    qualified           : currentRow.qualified           || 'No',
                    qualified90         : currentRow.qualified90         || 'No'
                  }
                : {};
        }
        this._pendingChanges[detailId][field] = value;
    }

    autoSaveRow(detailId) {
        const changes = this._pendingChanges[detailId];
        if (!changes) return;
        saveGradingRow({
            detailId            : detailId,
            manufacturer        : changes.manufacturer         || null,
            model               : changes.model                || null,
            sightType           : changes.sightType            || null,
            weaponCode          : changes.weaponCode           || null,
            qualificationAttempt: changes.qualificationAttempt || null,
            qualified           : changes.qualified            || 'No',
            qualified90         : changes.qualified90          || 'No'
        })
        .then(() => {
            delete this._pendingChanges[detailId];
        })
        .catch(error => {
            this.showErrorToast('Save failed: ' + this.reduceError(error));
        });
    }

    findRow(detailId) {
        if (!this.gradingData || !this.gradingData.weaponSections) return null;
        for (const section of this.gradingData.weaponSections) {
            const row = section.rows.find(r => r.detailId === detailId);
            if (row) return row;
        }
        return null;
    }

    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message)       return error.message;
        return 'An unexpected error occurred.';
    }
}