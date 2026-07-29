import { LightningElement, track } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import getRosterLabelDetails       from '@salesforce/apex/QualRosterGradingController.getRosterLabelDetails';
import getRosterGradingData        from '@salesforce/apex/QualRosterGradingController.getRosterGradingData';
import saveGradingRow              from '@salesforce/apex/QualRosterGradingController.saveGradingRow';
import getWeaponCodeOptions        from '@salesforce/apex/QualRosterGradingController.getWeaponCodeOptions';
import saveSignatures              from '@salesforce/apex/QualRosterGradingController.saveSignatures';
import getAvailableEmployees       from '@salesforce/apex/QualRosterGradingController.getAvailableEmployees';
import addToRoster                 from '@salesforce/apex/QualRosterGradingController.addToRoster';
import createEmployee              from '@salesforce/apex/QualRosterGradingController.createEmployee';

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
            'Precision Rifle'  : 'precision',
            'Other'            : 'other'
        };
        return map[weaponType] || 'other';
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Lifecycle
    // ═══════════════════════════════════════════════════════════════════════
    @track weaponCodeOptions = [];

    connectedCallback() {
        this.loadRosterList();
        getWeaponCodeOptions()
            .then(options => {
                this.weaponCodeOptions = options || [];
                // If grading data already loaded before options arrived, re-enrich
                if (this.gradingData) {
                    this.gradingData = this.enrichData(this.gradingData);
                }
            })
            .catch(() => { this.weaponCodeOptions = []; });
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

    // ═══════════════════════════════════════════════════════════════════════
    // Add to Roster - employees x weapon types (+ optional weapon details)
    // ═══════════════════════════════════════════════════════════════════════
    @track showAddModal       = false;
    @track isLoadingEmployees = false;
    @track isAddingEmployees  = false;
    @track employeeSearchKey  = '';
    @track addError           = '';
    _availableEmployees       = [];   // full list from Apex (with existingWeaponTypes)
    @track availableEmployees = [];   // filtered + decorated view
    @track weaponTypeOptions  = [];   // { value, label, checked }

    // Optional weapon details applied to all newly created rows
    @track addManufacturer = '';
    @track addModel        = '';
    @track addSightType    = '';

    // Create-new-employee sub-form
    @track showCreateEmployee = false;
    @track newFirstName       = '';
    @track newLastName        = '';
    @track newIsRetired       = false;
    @track newMiddleName      = '';
    @track newDob             = '';
    @track newYearRetired     = '';
    @track newRetiredType     = '';
    @track isCreatingEmployee = false;

    // Static picklist option sets (mirror the field metadata)
    _manufacturerValues = ['Sig Sauer', 'Daniel Defense', 'Hodge Defense', 'FN Herstal', 'Heckler Koch', 'Mossberg', 'Remington'];
    _modelValues        = ['P320', 'P365', 'P226', 'P229', 'DDM4V7', 'DDM4 V7 RIS 3', 'Mod 1', 'Mod 2', 'P90', '416', '762 A1', '590A1', '870', '1187'];
    _sightTypeValues    = ['Iron Sight', 'Optic', 'Magnified Optic', 'Scope'];

    _allWeaponTypes = ['Pistol 1', 'Pistol 2', 'Shotgun', 'Rifle', 'Automatic Weapon', 'Precision Rifle', 'Other'];

    get manufacturerOptions() { return this._toOptions(this._manufacturerValues); }
    get modelOptions()        { return this._toOptions(this._modelValues); }
    get sightTypeOptions()    { return this._toOptions(this._sightTypeValues); }
    _toOptions(vals) { return vals.map(v => ({ label: v, value: v })); }

    get selectedEmployeeCount() {
        return this._availableEmployees.filter(e => e.selected).length;
    }

    get addButtonLabel() {
        const n = this.selectedEmployeeCount;
        return n > 0 ? `Add ${n} to Roster` : 'Add to Roster';
    }

    get noEmployeesFound() {
        return !this.isLoadingEmployees && this.availableEmployees.length === 0;
    }

    openAddEmployeeModal() {
        this.showAddModal        = true;
        this.addError            = '';
        this.employeeSearchKey   = '';
        this._availableEmployees = [];
        this.availableEmployees  = [];
        this.addManufacturer     = '';
        this.addModel            = '';
        this.addSightType        = '';
        this.showCreateEmployee  = false;
        this.newFirstName        = '';
        this.newLastName         = '';
        this.newIsRetired        = false;
        this._initWeaponTypeOptions();
        this._fetchAvailableEmployees();
    }

    closeAddEmployeeModal() {
        this.showAddModal = false;
    }

    _initWeaponTypeOptions() {
        // Pre-check the weapon types already present on this roster.
        const onRoster = new Set(
            this.hasGradingData ? this.gradingData.weaponSections.map(s => s.weaponType) : []
        );
        this.weaponTypeOptions = this._allWeaponTypes.map(wt => ({
            value  : wt,
            label  : wt,
            checked: onRoster.has(wt)
        }));
    }

    _fetchAvailableEmployees(selectContactId) {
        this.isLoadingEmployees = true;
        getAvailableEmployees({ rosterLabel: this.selectedLabel })
            .then(list => {
                this._availableEmployees = (list || []).map(e => ({
                    ...e,
                    selected: selectContactId ? e.contactId === selectContactId : false
                }));
                this._applyEmployeeFilter();
            })
            .catch(error => {
                this.addError = this.reduceError(error);
            })
            .finally(() => {
                this.isLoadingEmployees = false;
            });
    }

    handleEmployeeSearch(event) {
        this.employeeSearchKey = event.target.value || '';
        this._applyEmployeeFilter();
    }

    _applyEmployeeFilter() {
        const key = this.employeeSearchKey.trim().toLowerCase();
        this.availableEmployees = this._availableEmployees
            .filter(e => !key || (e.name && e.name.toLowerCase().includes(key)))
            .map(e => {
                const existing = e.existingWeaponTypes || [];
                return {
                    ...e,
                    rowClass       : e.selected ? 'emp-row emp-row--selected' : 'emp-row',
                    hasExisting    : existing.length > 0,
                    existingLabel  : existing.length > 0 ? `On roster: ${existing.join(', ')}` : ''
                };
            });
    }

    handleEmployeeToggle(event) {
        const contactId = event.currentTarget.dataset.id;
        const match = this._availableEmployees.find(e => e.contactId === contactId);
        if (match) {
            match.selected = !match.selected;
            this.addError = '';
            this._applyEmployeeFilter();
        }
    }

    handleWeaponTypeToggle(event) {
        const value = event.target.value;
        this.weaponTypeOptions = this.weaponTypeOptions.map(opt =>
            opt.value === value ? { ...opt, checked: event.target.checked } : opt
        );
        this.addError = '';
    }

    handleAddManufacturer(event) { this.addManufacturer = event.detail.value; }
    handleAddModel(event)        { this.addModel        = event.detail.value; }
    handleAddSightType(event)    { this.addSightType    = event.detail.value; }

    handleAddEmployees() {
        const contactIds  = this._availableEmployees.filter(e => e.selected).map(e => e.contactId);
        const weaponTypes = this.weaponTypeOptions.filter(o => o.checked).map(o => o.value);

        if (contactIds.length === 0) { this.addError = 'Select at least one employee.'; return; }
        if (weaponTypes.length === 0) { this.addError = 'Select at least one weapon type.'; return; }

        this.addError          = '';
        this.isAddingEmployees = true;
        addToRoster({
            rosterLabel : this.selectedLabel,
            contactIds  : contactIds,
            weaponTypes : weaponTypes,
            manufacturer: this.addManufacturer || null,
            model       : this.addModel || null,
            sightType   : this.addSightType || null
        })
            .then(res => {
                this.showAddModal = false;
                let msg = `${res.rowsAdded} row(s) added across ${res.employeesAffected} employee(s).`;
                if (res.rowsSkipped > 0) {
                    msg += ` ${res.rowsSkipped} already existed and were skipped.`;
                }
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Added to Roster',
                    message: msg,
                    variant: res.rowsAdded > 0 ? 'success' : 'info'
                }));
                this.loadGradingData(this.selectedLabel);
            })
            .catch(error => { this.addError = this.reduceError(error); })
            .finally(() => { this.isAddingEmployees = false; });
    }

    // ── Create new employee (e.g. retired officer) ──────────────────────────
    toggleCreateEmployee() {
        this.showCreateEmployee = !this.showCreateEmployee;
        this.addError = '';
    }
    handleNewFirstName(event) { this.newFirstName = event.target.value; }
    handleNewLastName(event)  { this.newLastName  = event.target.value; }
    handleNewIsRetired(event) { this.newIsRetired = event.target.checked; }
    handleNewMiddleName(event)  { this.newMiddleName  = event.target.value; }
    handleNewDob(event)         { this.newDob         = event.target.value; }
    handleNewYearRetired(event) { this.newYearRetired = event.target.value; }
    handleNewRetiredType(event) { this.newRetiredType = event.target.value; }

    handleCreateEmployee() {
        if (!this.newLastName || !this.newLastName.trim()) {
            this.addError = 'Last name is required to create an employee.';
            return;
        }
        this.isCreatingEmployee = true;
        this.addError = '';
        createEmployee({
            firstName  : this.newFirstName ? this.newFirstName.trim() : null,
            middleName : this.newMiddleName ? this.newMiddleName.trim() : null,
            lastName   : this.newLastName.trim(),
            dateOfBirth: this.newDob || null,
            yearRetired: this.newYearRetired || null,
            retiredType: this.newRetiredType ? this.newRetiredType.trim() : null,
            isRetired  : this.newIsRetired
        })
            .then(emp => {
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Employee Created',
                    message: `${emp.name} created and selected.`,
                    variant: 'success'
                }));
                this.newFirstName       = '';
                this.newLastName        = '';
                this.newIsRetired       = false;
                this.newMiddleName      = '';
                this.newDob             = '';
                this.newYearRetired     = '';
                this.newRetiredType     = '';
                this.showCreateEmployee = false;
                this.employeeSearchKey  = '';
                // Reload list and auto-select the new employee
                this._fetchAvailableEmployees(emp.contactId);
            })
            .catch(error => { this.addError = this.reduceError(error); })
            .finally(() => { this.isCreatingEmployee = false; });
    }

    enrichData(data) {
        const enriched = Object.assign({}, data);
        enriched.weaponSections = (data.weaponSections || []).map(section => {
            const enrichedRows = (section.rows || []).map(row => this.enrichRow(row));

            // Sort by memberName so same-member rows are adjacent
            enrichedRows.sort((a, b) => (a.memberName || '').localeCompare(b.memberName || ''));

            // Mark first row of each member group to show the name
            let lastMember = null;
            let groupIndex = 0;
            enrichedRows.forEach(row => {
                const instrCls = row.isFirearmsInstructor ? ' instructor-row' : '';
                if (row.firFormId !== lastMember) {
                    row.showName   = true;
                    row.groupFirst = true;
                    row.groupClass = 'grading-row group-first' + instrCls;
                    lastMember     = row.firFormId;
                    groupIndex++;
                } else {
                    row.showName   = false;
                    row.groupFirst = false;
                    row.groupClass = 'grading-row group-cont' + instrCls;
                }
                row.groupEven = (groupIndex % 2 === 0);
            });

            return { weaponType: section.weaponType, rows: enrichedRows };
        });
        return enriched;
    }

    enrichRow(row) {
        // Null-safe all string fields
        const manufacturer        = row.manufacturer        || '';
        const model               = row.model               || '';
        const sightType           = row.sightType           || '';
        const weaponCode          = row.weaponCode          || '';
        const qualificationAttempt = row.qualificationAttempt || '';

        // Default Qualified to 'Yes' if not set
        let qualified = (row.qualified || '').trim();
        if (!qualified) qualified = 'Yes';

        let qualified90 = (row.qualified90 || '').trim();

        // If Qualified = No, force Qualified at 90% to No
        if (qualified.toLowerCase() === 'no') {
            qualified90 = 'No';
        }

        const isQualified   = qualified.toLowerCase() === 'yes';
        const isQualified90 = qualified90.toLowerCase() === 'yes';

        // Build per-row weapon code options with selected flag (declarative selection)
        const weaponCodeOptionsForRow = (this.weaponCodeOptions || []).map(opt => ({
            value   : opt,
            selected: opt === weaponCode
        }));

        return {
            ...row,
            manufacturer,
            model,
            sightType,
            weaponCode,
            qualificationAttempt,
            qualified,
            qualified90,
            weaponCodeOptionsForRow,
            isOtherType        : (row.weaponType || '') === 'Other',
            qualifiedYes       : isQualified,
            qualifiedNo        : !isQualified,
            qualified90Yes     : isQualified90,
            qualified90No      : !isQualified90,
            qualified90Disabled: !isQualified,
            is1st              : qualificationAttempt === '1st',
            is2nd              : qualificationAttempt === '2nd',
            is3rd              : qualificationAttempt === '3rd',
            is4th              : qualificationAttempt === '4th'
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
        this.updateRowField(detailId, field, value);
    }

    handleSelectChange(event) {
        const detailId = event.target.dataset.detailId;
        const field    = event.target.dataset.field;
        const value    = event.target.value;
        this.trackChange(detailId, field, value);
        this.updateRowField(detailId, field, value);
    }

    handleQualifiedToggle(event) {
        const detailId = event.currentTarget.dataset.detailId;
        const value    = event.currentTarget.dataset.value;
        this.trackChange(detailId, 'qualified', value);
        this.updateRowField(detailId, 'qualified', value);

        // If Qualified = No, auto-set Qualified at 90% to No
        if (value === 'No') {
            this.trackChange(detailId, 'qualified90', 'No');
            this.updateRowField(detailId, 'qualified90', 'No');
        }
    }

    handleQualified90Toggle(event) {
        const detailId = event.currentTarget.dataset.detailId;
        const value    = event.currentTarget.dataset.value;
        this.trackChange(detailId, 'qualified90', value);
        this.updateRowField(detailId, 'qualified90', value);
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

    get hasUnsavedChanges() {
        return Object.keys(this._pendingChanges).length > 0;
    }

    @track isSavingGrading = false;

    handleSaveAll() {
        if (!this.hasGradingData) return;
        // Always require a signature to certify the roster, even when no row
        // edits are pending (e.g. the roster was already fully graded).
        // Nothing is committed until the modal is signed and saved.
        this.openSignatureModal();
    }

    // ── Signature capture ───────────────────────────────────────────────────
    @track showSignatureModal = false;
    @track witnessName        = '';
    @track signatureError     = '';

    // Certification statements (FAQP-150) - both required to save.
    @track certifyAccurate    = false;
    @track certifyProficiency = false;
    get certifyStatementsChecked() {
        return this.certifyAccurate && this.certifyProficiency;
    }

    get instructorNameForSignature() {
        return this.gradingData ? (this.gradingData.instructorName || '') : '';
    }

    // A witness signature is required whenever the firearm instructor
    // themselves shows up as one of the graded members on this roster
    // (row.isFirearmsInstructor is set server-side in getRosterGradingData).
    get needsWitnessSignature() {
        if (!this.hasGradingData) return false;
        return this.gradingData.weaponSections.some(section =>
            section.rows.some(row => row.isRosterInstructor === true)
        );
    }

    // Two columns side-by-side when a witness is required, single column otherwise.
    get signatureRowClass() {
        return this.needsWitnessSignature ? 'sig-row sig-row--two' : 'sig-row';
    }

    // Certification date shown (read-only) next to each signature - the day
    // the roster is being signed. Formatted MM/DD/YYYY to match TEST DATE.
    get certificationDate() {
        const d = new Date();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${mm}/${dd}/${d.getFullYear()}`;
    }

    handleWitnessNameInput(event) {
        this.witnessName    = event.target.value;
        this.signatureError = '';
    }

    handleCertifyAccurate(event) {
        this.certifyAccurate = event.target.checked;
        this.signatureError  = '';
    }
    handleCertifyProficiency(event) {
        this.certifyProficiency = event.target.checked;
        this.signatureError     = '';
    }

    openSignatureModal() {
        this.witnessName        = '';
        this.signatureError     = '';
        this.certifyAccurate    = false;
        this.certifyProficiency = false;
        this.showSignatureModal = true;
    }

    handleClearAllSignatures() {
        const fiPad = this.template.querySelector('[data-pad="instructor"]');
        if (fiPad) fiPad.clear();
        const witnessPad = this.template.querySelector('[data-pad="witness"]');
        if (witnessPad) witnessPad.clear();
    }

    handleSignatureSave() {
        if (!this.certifyStatementsChecked) {
            this.signatureError = 'Please confirm both certification statements before signing.';
            return;
        }
        const fiPad = this.template.querySelector('[data-pad="instructor"]');
        if (!fiPad || !fiPad.hasSignature) {
            this.signatureError = 'Firearm instructor signature is required.';
            return;
        }

        const fiCapture = fiPad.captureSignature();
        if (fiCapture.error) {
            this.signatureError = fiCapture.error;
            return;
        }

        let witnessDataUrl = null;
        if (this.needsWitnessSignature) {
            const witnessPad = this.template.querySelector('[data-pad="witness"]');
            if (!this.witnessName || !this.witnessName.trim()) {
                this.signatureError = 'Witness name is required.';
                return;
            }
            if (!witnessPad || !witnessPad.hasSignature) {
                this.signatureError = 'Witness signature is required.';
                return;
            }
            const witnessCapture = witnessPad.captureSignature();
            if (witnessCapture.error) {
                this.signatureError = witnessCapture.error;
                return;
            }
            witnessDataUrl = witnessCapture.dataUrl;
        }

        this.signatureError  = '';
        this.isSavingGrading = true;

        const detailIds = Object.keys(this._pendingChanges);

        // 1) Save all pending grading row edits
        const gradingPromises = detailIds.map(detailId => {
            const changes = this._pendingChanges[detailId];
            return saveGradingRow({
                detailId            : detailId,
                manufacturer        : changes.manufacturer        || '',
                model               : changes.model               || '',
                sightType           : changes.sightType           || '',
                weaponCode          : changes.weaponCode          || '',
                qualificationAttempt: changes.qualificationAttempt || '',
                qualified           : changes.qualified            || 'Yes',
                qualified90         : changes.qualified90          || ''
            });
        });

        Promise.all(gradingPromises)
            .then(() => {
                // 2) Only after grading saves, save the signature(s)
                return saveSignatures({
                    rosterLabel         : this.selectedLabel,
                    instructorSignature : fiCapture.dataUrl,
                    witnessName         : this.needsWitnessSignature ? this.witnessName.trim() : null,
                    witnessSignature    : witnessDataUrl
                });
            })
            .then(() => {
                // 3) Everything saved successfully
                this._pendingChanges    = {};
                this.isSavingGrading    = false;
                this.showSignatureModal = false;
                const msg = detailIds.length > 0
                    ? `${detailIds.length} record(s) and signature(s) saved successfully.`
                    : 'Signature(s) saved successfully.';
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Saved',
                    message: msg,
                    variant: 'success'
                }));
            })
            .catch(error => {
                this.isSavingGrading = false;
                this.showErrorToast('Save failed: ' + this.reduceError(error));
            });
    }

    handleSignatureCancel() {
        this.showSignatureModal = false;
        // Instructor cancelled - nothing is saved, changes remain pending
        this.dispatchEvent(new ShowToastEvent({
            title  : 'Not Saved',
            message: 'Signature is required to save. Your changes have not been saved yet.',
            variant: 'warning'
        }));
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