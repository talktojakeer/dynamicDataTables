import { LightningElement, track } from 'lwc';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import getRosterLabelDetails       from '@salesforce/apex/QualRosterGradingController.getRosterLabelDetails';
import getRosterGradingData        from '@salesforce/apex/QualRosterGradingController.getRosterGradingData';
import saveGradingRow              from '@salesforce/apex/QualRosterGradingController.saveGradingRow';
import deleteGradingRows           from '@salesforce/apex/QualRosterGradingController.deleteGradingRows';
import getWeaponCodeOptions        from '@salesforce/apex/QualRosterGradingController.getWeaponCodeOptions';
import saveSignatures              from '@salesforce/apex/QualRosterGradingController.saveSignatures';
import getAvailableEmployees       from '@salesforce/apex/QualRosterGradingController.getAvailableEmployees';
import addToRoster                 from '@salesforce/apex/QualRosterGradingController.addToRoster';
import createEmployee              from '@salesforce/apex/QualRosterGradingController.createEmployee';

// Dependent-picklist maps - mirrors createQualRoster so the weapon details
// in "Add to Roster" cascade the same way (weapon -> manufacturer -> model,
// and weapon -> sight type).
const MANUFACTURER_BY_WEAPON = {
    'Pistol 1'         : ['Sig Sauer'],
    'Pistol 2'         : ['Sig Sauer'],
    'Shotgun'          : ['Mossberg', 'Remington'],
    'Rifle'            : ['Daniel Defense', 'FN Herstal', 'Heckler Koch', 'Hodge Defense'],
    'Automatic Weapon' : ['Daniel Defense'],
    'Precision Rifle'  : ['Hodge Defense']
};
const MODEL_BY_MANUFACTURER = {
    'Sig Sauer'       : ['P320', 'P365', 'P226', 'P229'],
    'Daniel Defense'  : ['DDM4V7', 'DDM4 V7 RIS 3'],
    'Hodge Defense'   : ['Mod 1', 'Mod 2'],
    'FN Herstal'      : ['P90'],
    'Heckler Koch'    : ['416', '762 A1'],
    'Mossberg'        : ['590A1'],
    'Remington'       : ['870', '1187']
};
const SIGHT_BY_WEAPON = {
    'Pistol 1'         : ['Iron Sight', 'Optic'],
    'Pistol 2'         : ['Iron Sight', 'Optic'],
    'Shotgun'          : ['Iron Sight', 'Optic'],
    'Rifle'            : ['Iron Sight', 'Optic', 'Magnified Optic'],
    'Automatic Weapon' : ['Iron Sight', 'Optic', 'Magnified Optic'],
    'Precision Rifle'  : ['Scope']
};

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

    // ---- Roster list pagination (10 per page) ----------------------------
    rosterPageSize = 10;
    @track rosterListPage = 1;

    get rosterListTotalPages() {
        return Math.max(1, Math.ceil(this.filteredRosterCount / this.rosterPageSize));
    }
    get pagedRosterRows() {
        const start = (this.rosterListPage - 1) * this.rosterPageSize;
        return this.filteredRosterRows.slice(start, start + this.rosterPageSize);
    }
    get rosterListPrevDisabled() { return this.rosterListPage <= 1; }
    get rosterListNextDisabled() { return this.rosterListPage >= this.rosterListTotalPages; }
    get rosterListPageLabel()    { return `Page ${this.rosterListPage} of ${this.rosterListTotalPages}`; }
    get showRosterListPager()    { return this.filteredRosterCount > this.rosterPageSize; }

    rosterListPrev() { if (this.rosterListPage > 1) this.rosterListPage -= 1; }
    rosterListNext() { if (this.rosterListPage < this.rosterListTotalPages) this.rosterListPage += 1; }

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

    // Roster is locked once status is Ready for Pdf / Completed (from Apex).
    get isReadOnly() {
        return !!(this.gradingData && this.gradingData.isReadOnly);
    }
    get canEdit() {
        return this.hasGradingData && !this.isReadOnly;
    }
    get statusBanner() {
        if (!this.isReadOnly) return '';
        const instr = (this.gradingData.instructorName || 'the Firearms Instructor');
        const date  = (this.gradingData.testDate || '');
        return date
            ? `This form has been completed by ${instr} on ${date}.`
            : `This form has been completed by ${instr}.`;
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

    // Every row across all weapon sections (used to save defaults + edits).
    get allGradingRows() {
        if (!this.hasGradingData) return [];
        const rows = [];
        this.gradingData.weaponSections.forEach(s => {
            (s.rows || []).forEach(r => rows.push(r));
        });
        return rows;
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
                // Clamp the page in case a reload shrank the list.
                if (this.rosterListPage > this.rosterListTotalPages) {
                    this.rosterListPage = this.rosterListTotalPages;
                }
                this.isLoadingList = false;
            })
            .catch(error => {
                this.isLoadingList = false;
                this.showErrorToast(this.reduceError(error));
            });
    }

    handleListSearch(event) {
        this.listSearchKey = event.target.value;
        this.rosterListPage = 1; // reset to first page on new search
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
    @track addWeaponType      = '';   // single selected weapon type (dropdown)

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

    _allWeaponTypes = ['Pistol 1', 'Pistol 2', 'Shotgun', 'Rifle', 'Automatic Weapon', 'Precision Rifle', 'Other'];

    // Single Weapon Type dropdown (mirrors createQualRoster mass-apply).
    get weaponTypeSelectOptions() { return this._toOptions(this._allWeaponTypes); }
    get isOtherWeaponType()       { return this.addWeaponType === 'Other'; }

    // Manufacturer/Sight depend on the selected weapon type; Model depends on Manufacturer.
    get manufacturerOptions() {
        return (!this.addWeaponType || this.isOtherWeaponType)
            ? [] : this._toOptions(MANUFACTURER_BY_WEAPON[this.addWeaponType] || []);
    }
    get modelOptions() {
        return this.addManufacturer ? this._toOptions(MODEL_BY_MANUFACTURER[this.addManufacturer] || []) : [];
    }
    get sightTypeOptions() {
        return (!this.addWeaponType || this.isOtherWeaponType)
            ? [] : this._toOptions(SIGHT_BY_WEAPON[this.addWeaponType] || []);
    }

    get isManufacturerDisabled() { return !this.addWeaponType || this.isOtherWeaponType; }
    get isModelDisabled()        { return !this.addManufacturer; }
    get isSightTypeDisabled()    { return !this.addWeaponType || this.isOtherWeaponType; }

    _toOptions(vals) { return (vals || []).map(v => ({ label: v, value: v })); }

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
        this.addWeaponType       = '';
        this._fetchAvailableEmployees();
    }

    closeAddEmployeeModal() {
        this.showAddModal = false;
    }

    _fetchAvailableEmployees(selectContactId) {
        this.isLoadingEmployees = true;
        // Preserve whatever is currently checked so a reload doesn't lose it.
        const keepSelected = new Set(
            (this._availableEmployees || []).filter(e => e.selected).map(e => e.contactId)
        );
        if (selectContactId) keepSelected.add(selectContactId);
        getAvailableEmployees({ rosterLabel: this.selectedLabel })
            .then(list => {
                this._availableEmployees = (list || []).map(e => ({
                    ...e,
                    selected: keepSelected.has(e.contactId)
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
        const matched = this._availableEmployees
            .filter(e => !key || (e.name && e.name.toLowerCase().includes(key)));

        // Always keep any selected employees visible, then fill up to 15.
        const selected = matched.filter(e => e.selected);
        const rest     = matched.filter(e => !e.selected).slice(0, Math.max(0, 15 - selected.length));
        const shown    = [...selected, ...rest];

        this._matchedCount = matched.length;
        this.availableEmployees = shown.map(e => {
            const existing = e.existingWeaponTypes || [];
            let retiredLabel = '';
            if (e.isRetiredOfficer) {
                const parts = [];
                if (e.dateOfBirth) parts.push(`DOB: ${this._fmtDate(e.dateOfBirth)}`);
                if (e.yearRetired) parts.push(`Retirement: ${this._fmtDate(e.yearRetired)}`);
                retiredLabel = parts.join('   ');
            }
            return {
                ...e,
                rowClass       : e.selected ? 'emp-row emp-row--selected' : 'emp-row',
                hasExisting    : existing.length > 0,
                existingLabel  : existing.length > 0 ? `On roster: ${existing.join(', ')}` : '',
                hasRetiredInfo : retiredLabel !== '',
                retiredLabel   : retiredLabel
            };
        });
    }

    @track _matchedCount = 0;
    get employeeCountHint() {
        return this._matchedCount > 15
            ? `Showing 15 of ${this._matchedCount} — search to narrow`
            : '';
    }

    // Format an ISO date string (yyyy-MM-dd...) as MM/DD/YYYY for display.
    _fmtDate(iso) {
        if (!iso) return '';
        const p = String(iso).substring(0, 10).split('-');
        return p.length === 3 ? `${p[1]}/${p[2]}/${p[0]}` : iso;
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

    handleAddWeaponType(event) {
        this.addWeaponType   = event.detail.value;
        // Weapon type drives the dependent details - reset them.
        this.addManufacturer = '';
        this.addModel        = '';
        this.addSightType    = '';
        this.addError = '';
    }

    handleAddManufacturer(event) { this.addManufacturer = event.detail.value; this.addModel = ''; }
    handleAddModel(event)        { this.addModel        = event.detail.value; }
    handleAddSightType(event)    { this.addSightType    = event.detail.value; }

    handleAddEmployees() {
        const contactIds  = this._availableEmployees.filter(e => e.selected).map(e => e.contactId);
        const weaponTypes = this.addWeaponType ? [this.addWeaponType] : [];

        if (contactIds.length === 0) { this.addError = 'Select at least one employee.'; return; }
        if (weaponTypes.length === 0) { this.addError = 'Select a weapon type.'; return; }

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
                let msg = `${res.rowsAdded} row(s) added across ${res.employeesAffected} employee(s).`;
                if (res.rowsSkipped > 0) {
                    msg += ` ${res.rowsSkipped} already existed and were skipped.`;
                }
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Added to Roster',
                    message: msg,
                    variant: res.rowsAdded > 0 ? 'success' : 'info'
                }));

                // Keep the popup OPEN so the user can add another weapon batch.
                // Reset the weapon selection + details and clear checked employees,
                // then refresh the picker so newly-added weapons show as "on roster".
                this.addWeaponType   = '';
                this.addManufacturer = '';
                this.addModel        = '';
                this.addSightType    = '';
                // Keep the selected members checked (reload preserves selection),
                // so the user can see who they picked earlier.
                this._fetchAvailableEmployees();   // re-pull existing weapon types per employee

                // Refresh the grading table underneath so it reflects the new rows.
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
    handleNewRetiredType(event) { this.newRetiredType = event.detail.value; }

    // Picklist values for FAQP_Retired_Peace_Officer_Type__c
    get retiredTypeOptions() {
        return [
            { label: 'Retired Peace Officer/Non-DPS', value: 'Retired Peace Officer/Non-DPS' },
            { label: 'Retired DPS Trooper',           value: 'Retired DPS Trooper' },
            { label: 'Special Ranger',                value: 'Special Ranger' },
            { label: 'Special Texas Ranger',          value: 'Special Texas Ranger' }
        ];
    }

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
                const hiCls    = row.isHighAttempt ? ' high-attempt' : '';
                if (row.firFormId !== lastMember) {
                    row.showName   = true;
                    row.groupFirst = true;
                    row.groupClass = 'grading-row group-first' + instrCls + hiCls;
                    lastMember     = row.firFormId;
                    groupIndex++;
                } else {
                    row.showName   = false;
                    row.groupFirst = false;
                    row.groupClass = 'grading-row group-cont' + instrCls + hiCls;
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

        // Attempt options 1st..10th with a selected flag for declarative binding.
        const ATTEMPTS = ['1st','2nd','3rd','4th','5th','6th','7th','8th','9th','10th'];
        const attemptOptionsForRow = ATTEMPTS.map(a => ({
            value: a, selected: a === qualificationAttempt
        }));

        // 5th..10th attempt -> highlight the row in a light red.
        const attemptNum   = ATTEMPTS.indexOf(qualificationAttempt) + 1; // 0 if none
        const isHighAttempt = attemptNum >= 5;

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
            attemptOptionsForRow,
            isHighAttempt,
            rowHighlightClass  : isHighAttempt ? 'grading-row high-attempt' : 'grading-row',
            isOtherType        : (row.weaponType || '') === 'Other',
            qualifiedYes       : isQualified,
            qualifiedNo        : !isQualified,
            qualified90Yes     : isQualified90,
            qualified90No      : !isQualified90,
            qualified90Disabled: !isQualified
        };
    }

    handleWeaponSelect(event) {
        this.selectedWeapon = event.currentTarget.dataset.weapon;
        this._selectedRowIds = [];   // selection is per-weapon view
    }

    handleFieldBlur(event) {
        if (this.isReadOnly) return;
        const detailId = event.target.dataset.detailId;
        const field    = event.target.dataset.field;
        const value    = event.target.value;
        this.trackChange(detailId, field, value);
        this.updateRowField(detailId, field, value);
    }

    handleSelectChange(event) {
        if (this.isReadOnly) return;
        const detailId = event.target.dataset.detailId;
        const field    = event.target.dataset.field;
        const value    = event.target.value;
        this.trackChange(detailId, field, value);
        this.updateRowField(detailId, field, value);
    }

    handleQualifiedToggle(event) {
        if (this.isReadOnly) return;
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
        if (this.isReadOnly) return;
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

    // ---- Row selection for mass delete -----------------------------------
    @track _selectedRowIds = [];

    get hasSelectedRows() { return this._selectedRowIds.length > 0; }
    get selectedRowCount() { return this._selectedRowIds.length; }
    get deleteButtonLabel() { return `Delete ${this._selectedRowIds.length} Selected`; }

    // Whether the header "select all" is checked (all active rows selected)
    get allRowsSelected() {
        const rows = this.activeRows;
        return rows.length > 0 && rows.every(r => this._selectedRowIds.includes(r.detailId));
    }

    handleRowSelect(event) {
        const id = event.target.dataset.detailId;
        const checked = event.target.checked;
        const set = new Set(this._selectedRowIds);
        if (checked) set.add(id); else set.delete(id);
        this._selectedRowIds = Array.from(set);
        this._applyRowSelection();
    }

    handleSelectAllRows(event) {
        const checked = event.target.checked;
        if (checked) {
            this._selectedRowIds = this.activeRows.map(r => r.detailId);
        } else {
            this._selectedRowIds = [];
        }
        this._applyRowSelection();
    }

    // Re-stamp the `rowSelected` flag on the enriched rows so checkboxes reflect state.
    _applyRowSelection() {
        if (!this.hasGradingData) return;
        const sel = new Set(this._selectedRowIds);
        this.gradingData = {
            ...this.gradingData,
            weaponSections: this.gradingData.weaponSections.map(s => ({
                ...s,
                rows: s.rows.map(r => ({ ...r, rowSelected: sel.has(r.detailId) }))
            }))
        };
    }

    handleDeleteSelected() {
        if (!this.hasSelectedRows || this.isReadOnly) return;
        // eslint-disable-next-line no-alert
        deleteGradingRows({ detailIds: this._selectedRowIds })
            .then(() => {
                const n = this._selectedRowIds.length;
                this._selectedRowIds = [];
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Deleted',
                    message: `${n} row(s) deleted.`,
                    variant: 'success'
                }));
                this.loadGradingData(this.selectedLabel);
            })
            .catch(error => {
                this.dispatchEvent(new ShowToastEvent({
                    title  : 'Delete failed',
                    message: this.reduceError(error),
                    variant: 'error'
                }));
            });
    }

    handleSaveAll() {
        if (!this.hasGradingData || this.isReadOnly) return;
        // Always allow saving - the displayed values (including defaults like
        // "No" / "1st") are valid results to record and certify, even if the
        // grader did not manually change anything.
        this.openSignatureModal();
    }

    // ── Signature capture ───────────────────────────────────────────────────
    @track showSignatureModal = false;
    @track witnessName        = '';
    @track witnessDate        = '';
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

    // ISO (yyyy-MM-dd) form of today's date, sent to Apex for the witness date.
    get certificationDateIso() {
        const d = new Date();
        const mm = String(d.getMonth() + 1).padStart(2, '0');
        const dd = String(d.getDate()).padStart(2, '0');
        return `${d.getFullYear()}-${mm}-${dd}`;
    }

    handleWitnessNameInput(event) {
        this.witnessName    = event.target.value;
        this.signatureError = '';
    }

    handleWitnessDateInput(event) {
        this.witnessDate    = event.target.value;
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
        this.witnessDate        = this.certificationDateIso; // default to today, editable
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

        // Save EVERY visible row using its current value, overlaying any pending
        // edits. This persists default selections (e.g. "No" / "1st") even when
        // the grader did not manually change a field.
        const rowsToSave = this.allGradingRows;
        const detailIds  = rowsToSave.map(r => r.detailId);

        const gradingPromises = rowsToSave.map(row => {
            const changes = this._pendingChanges[row.detailId] || {};
            const val = (field, fallback) =>
                (changes[field] !== undefined ? changes[field] : (row[field] !== undefined ? row[field] : fallback));
            return saveGradingRow({
                detailId            : row.detailId,
                manufacturer        : val('manufacturer', '')        || '',
                model               : val('model', '')               || '',
                sightType           : val('sightType', '')           || '',
                weaponCode          : val('weaponCode', '')          || '',
                qualificationAttempt: val('qualificationAttempt', '') || '',
                qualified           : val('qualified', 'No')          || 'No',
                qualified90         : val('qualified90', 'No')        || 'No'
            });
        });

        Promise.all(gradingPromises)
            .then(() => {
                // 2) Only after grading saves, save the signature(s)
                return saveSignatures({
                    rosterLabel          : this.selectedLabel,
                    instructorSignature  : fiCapture.dataUrl,
                    witnessName          : this.needsWitnessSignature ? this.witnessName.trim() : null,
                    witnessSignature     : witnessDataUrl,
                    witnessSignatureDate : this.needsWitnessSignature ? (this.witnessDate || this.certificationDateIso) : null
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
                // Return to the Qual Roster list view after certifying/saving.
                this.handleBackToList();
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