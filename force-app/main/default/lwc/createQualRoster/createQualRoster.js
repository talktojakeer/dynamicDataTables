import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent }               from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue }     from 'lightning/uiRecordApi';
import USER_ID                          from '@salesforce/user/Id';
import NAME_FIELD                       from '@salesforce/schema/User.Name';
import TITLE_FIELD                      from '@salesforce/schema/User.Title';
import searchRecruitClassAndContacts    from '@salesforce/apex/QualRosterController.searchRecruitClassAndContacts';
import searchUsers                      from '@salesforce/apex/QualRosterController.searchUsers';
import getContactMembers                from '@salesforce/apex/QualRosterController.getContactMembers';
import addToRoster                      from '@salesforce/apex/QualRosterController.addToRoster';
import checkRosterLabelExists           from '@salesforce/apex/QualRosterController.checkRosterLabelExists';
import DPS_BADGE                        from '@salesforce/resourceUrl/FaqpDpsLogo';

const WEAPON_TYPE_VALUES = [
    'Pistol 1', 'Pistol 2', 'Shotgun', 'Rifle', 'Automatic Weapon', 'Precision Rifle'
];

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

export default class CreateQualRoster extends LightningElement {

    _selectedData = [];
    _rcRaw        = [];
    _conRaw       = [];
    dpsBadgeUrl   = DPS_BADGE;

    _manuallyRemovedIds = new Set();

    @track lookupSearchKey    = '';
    @track showLookupDropdown = false;
    @track isLookupSearching  = false;

    @track _rcResults  = [];
    @track _conResults = [];
    @track _tags       = [];

    lookupSearchTimeout;

    get hasSelections()        { return this._selectedData.length > 0; }
    get hasRcResults()         { return this._rcResults.length > 0; }
    get hasContactResults()    { return this._conResults.length > 0; }
    get hasAnyResults()        { return this.hasRcResults || this.hasContactResults; }
    get selectedItems()        { return this._tags; }
    get rcSearchResults()      { return this._rcResults; }
    get contactSearchResults() { return this._conResults; }

    @track rcRowData  = [];   // Recruit class members
    @track indRowData = [];   // Individual person account members

    @track rcTableSearchKey  = '';
    @track indTableSearchKey = '';

    get hasRcSelection()   { return this._selectedData.some(i => i.type === 'rc'); }
    get selectedRcName()   { const rc = this._selectedData.find(i => i.type === 'rc'); return rc ? rc.name : ''; }
    get rcMemberCount()    { return this.rcRowData.length; }
    get hasRcCheckedRows() { return this.rcRowData.some(r => r.selected); }
    get allRcRowsChecked() { return this.rcRowData.length > 0 && this.rcRowData.every(r => r.selected); }

    get filteredRcRows() {
        if (!this.rcTableSearchKey || !this.rcTableSearchKey.trim()) return this.rcRowData;
        const key = this.rcTableSearchKey.toLowerCase();
        return this.rcRowData.filter(r =>
            (r.contactName && r.contactName.toLowerCase().includes(key)) ||
            (r.tins        && r.tins.toLowerCase().includes(key))        ||
            (r.division    && r.division.toLowerCase().includes(key))
        );
    }

    get hasIndividualRows()  { return this.indRowData.length > 0; }
    get individualMemberCount() { return this.indRowData.length; }
    get hasIndCheckedRows()  { return this.indRowData.some(r => r.selected); }
    get allIndRowsChecked()  { return this.indRowData.length > 0 && this.indRowData.every(r => r.selected); }

    get filteredIndRows() {
        if (!this.indTableSearchKey || !this.indTableSearchKey.trim()) return this.indRowData;
        const key = this.indTableSearchKey.toLowerCase();
        return this.indRowData.filter(r =>
            (r.contactName && r.contactName.toLowerCase().includes(key)) ||
            (r.tins        && r.tins.toLowerCase().includes(key))        ||
            (r.division    && r.division.toLowerCase().includes(key))
        );
    }

    get hasCheckedRows()    { return this.hasRcCheckedRows || this.hasIndCheckedRows; }
    get hasTotalRows()      { return this.rcRowData.length > 0 || this.indRowData.length > 0; }
    get totalMemberCount()  { return this.rcRowData.length + this.indRowData.length; }
    get isAddDisabled()     { return !this.testDate; }

    _refreshDropdownState() {
        const selectedIds = new Set(this._selectedData.map(i => i.id));
        this._rcResults  = this._rcRaw.map(r => ({
            Id: r.Id, Name: r.Name,
            alreadySelected: selectedIds.has(r.Id),
            itemClass: selectedIds.has(r.Id) ? 'lookup-item lookup-item-selected' : 'lookup-item'
        }));
        this._conResults = this._conRaw.map(c => ({
            Id: c.Id, Name: c.Name, tins: c.tins,
            alreadySelected: selectedIds.has(c.Id),
            itemClass: selectedIds.has(c.Id) ? 'lookup-item lookup-item-selected' : 'lookup-item'
        }));
    }

    _refreshTags() {
        this._tags = this._selectedData.map(item => ({
            id      : item.id,
            name    : item.name,
            type    : item.type,
            tagClass: item.type === 'rc' ? 'selection-tag tag-rc' : 'selection-tag tag-contact',
            icon    : item.type === 'rc' ? 'standard:account'     : 'standard:contact'
        }));
    }

    @track selectedInstructor     = null;
    @track instructorSearchKey    = '';
    @track showInstructorDropdown = false;
    @track isInstructorSearching  = false;
    @track instructorResults      = [];
    instructorSearchTimeout;

    currentUserId = USER_ID;

    @wire(getRecord, { recordId: '$currentUserId', fields: [NAME_FIELD, TITLE_FIELD] })
    wiredCurrentUser({ data, error }) {
        if (data) {
            this.selectedInstructor = { Id: this.currentUserId, Name: getFieldValue(data, NAME_FIELD) };
        } else if (error) {
            this.showErrorToast('Failed to load current user.');
        }
    }

    handleInstructorSearch(event) {
        this.instructorSearchKey = event.target.value;
        clearTimeout(this.instructorSearchTimeout);
        if (!this.instructorSearchKey || this.instructorSearchKey.trim().length < 1) {
            this.showInstructorDropdown = false;
            this.instructorResults      = [];
            return;
        }
        this.isInstructorSearching  = true;
        this.showInstructorDropdown = true;
        this.instructorSearchTimeout = setTimeout(() => {
            searchUsers({ searchKey: this.instructorSearchKey })
                .then(result => { this.instructorResults = result || []; this.isInstructorSearching = false; })
                .catch(error => { this.isInstructorSearching = false; this.showErrorToast('Instructor search failed: ' + this.reduceErrors(error)); });
        }, 300);
    }

    handleInstructorFocus() {
        if (this.instructorSearchKey && this.instructorSearchKey.trim().length >= 1) this.showInstructorDropdown = true;
    }

    handleInstructorSelect(event) {
        this.selectedInstructor     = { Id: event.currentTarget.dataset.id, Name: event.currentTarget.dataset.name };
        this.instructorSearchKey    = '';
        this.showInstructorDropdown = false;
        this.instructorResults      = [];
    }

    handleClearInstructor() { this.selectedInstructor = null; this.instructorSearchKey = ''; }

    @track testDate           = '';
    @track location           = '';
    @track lightningCondition = '';
    @track isLoadingMembers   = false;

    @track massWeaponType   = '';
    @track massManufacturer = '';
    @track massModel        = '';
    @track massSightType    = '';

    get weaponTypeOptions()        { return WEAPON_TYPE_VALUES; }
    get massManufacturerOptions()  { return !this.massWeaponType ? [] : (MANUFACTURER_BY_WEAPON[this.massWeaponType] || []); }
    get isMassManufacturerDisabled() { return !this.massWeaponType; }
    get massModelOptions()         { return !this.massManufacturer ? [] : (MODEL_BY_MANUFACTURER[this.massManufacturer] || []); }
    get isMassModelDisabled()      { return !this.massManufacturer; }
    get massSightTypeOptions()     { return !this.massWeaponType ? [] : (SIGHT_BY_WEAPON[this.massWeaponType] || []); }
    get isMassSightTypeDisabled()  { return !this.massWeaponType; }
    get isMassApplyDisabled()      { return !this.massWeaponType || !this.hasCheckedRows; }

    handleMassWeaponTypeChange(event)   { this.massWeaponType = event.target.value; this.massManufacturer = ''; this.massModel = ''; this.massSightType = ''; }
    handleMassManufacturerChange(event) { this.massManufacturer = event.target.value; this.massModel = ''; }
    handleMassModelChange(event)        { this.massModel = event.target.value; }
    handleMassSightTypeChange(event)    { this.massSightType = event.target.value; }
    handleMassClear()                   { this.massWeaponType = ''; this.massManufacturer = ''; this.massModel = ''; this.massSightType = ''; }

    handleMassApply() {
        if (!this.massWeaponType) { this.showErrorToast('Please select at least a Weapon Type before applying.'); return; }

        const totalChecked = [...this.rcRowData, ...this.indRowData].filter(r => r.selected).length;
        if (totalChecked === 0) { this.showErrorToast('Please select one or more rows to apply weapon details.'); return; }

        const newEntry = {
            weaponType   : this.massWeaponType,
            manufacturer : this.massManufacturer || '',
            model        : this.massModel        || '',
            sightType    : this.massSightType     || ''
        };

        const applyToRows = (rows) => rows.map(r => {
            if (!r.selected) return r;
            const entries = [...(r.weaponEntries || [])];
            const isDuplicate = entries.some(e =>
                e.weaponType === newEntry.weaponType && e.manufacturer === newEntry.manufacturer &&
                e.model === newEntry.model && e.sightType === newEntry.sightType
            );
            if (!isDuplicate) entries.push(newEntry);
            return this._computeWeaponDisplay({ ...r, weaponEntries: entries });
        });

        this.rcRowData  = applyToRows(this.rcRowData);
        this.indRowData = applyToRows(this.indRowData);

        this.dispatchEvent(new ShowToastEvent({ title: 'Applied', message: `Weapon details applied to ${totalChecked} member(s).`, variant: 'success' }));
    }

    @track showRosterLabelModal = false;
    @track rosterLabel          = '';
    @track rosterLabelError     = '';
    @track isSavingRoster       = false;

    _pendingRosterPayload = null;
    _pendingFirstRc       = null;

    get rosterLabelInputClass() { return this.rosterLabelError ? 'modal-input modal-input-error' : 'modal-input'; }

    handleRosterLabelInput(event) { this.rosterLabel = event.target.value; this.rosterLabelError = ''; }
    handleModalBackdropClick()    { this.handleRosterLabelCancel(); }

    handleRosterLabelCancel() {
        this.showRosterLabelModal = false; this.rosterLabel = ''; this.rosterLabelError = '';
        this.isSavingRoster = false; this._pendingRosterPayload = null; this._pendingFirstRc = null;
    }

    handleRosterLabelConfirm() {
        const label = (this.rosterLabel || '').trim();
        if (!label) { this.rosterLabelError = 'Roster Label is required.'; return; }
        this.isSavingRoster = true; this.rosterLabelError = '';
        checkRosterLabelExists({ rosterLabel: label })
            .then(isDuplicate => {
                if (isDuplicate) { this.rosterLabelError = 'Roster Label already exists. Please choose a different label.'; this.isSavingRoster = false; }
                else { this._submitRoster(label); }
            })
            .catch(error => { this.isSavingRoster = false; this.rosterLabelError = 'Unable to validate label: ' + this.reduceErrors(error); });
    }

    handleLookupFocus() {
        if (this.lookupSearchKey && this.lookupSearchKey.trim().length >= 1) this.showLookupDropdown = true;
    }

    handleLookupSearch(event) {
        this.lookupSearchKey = event.target.value;
        clearTimeout(this.lookupSearchTimeout);
        if (!this.lookupSearchKey || this.lookupSearchKey.trim().length < 1) {
            this.showLookupDropdown = false; this._rcRaw = []; this._conRaw = []; this._rcResults = []; this._conResults = [];
            return;
        }
        this.isLookupSearching = true; this.showLookupDropdown = true;
        this.lookupSearchTimeout = setTimeout(() => {
            searchRecruitClassAndContacts({ searchKey: this.lookupSearchKey })
                .then(result => {
                    this._rcRaw = result.recruitClasses || [];
                    const seen  = new Set();
                    this._conRaw = (result.contacts || [])
                        .filter(c => { const key = (c.Name || '').toLowerCase().trim(); if (seen.has(key)) return false; seen.add(key); return true; })
                        .map(c => ({ Id: c.Id, Name: c.Name, tins: c.TINS, personContactId: c.PersonContactId }));
                    this.isLookupSearching = false;
                    this._refreshDropdownState();
                })
                .catch(error => { this.isLookupSearching = false; this.showErrorToast('Search failed: ' + this.reduceErrors(error)); });
        }, 300);
    }

    handleLookupSelect(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        const type = event.currentTarget.dataset.type;
        const tins = event.currentTarget.dataset.tins || '';
        if (!id) return;

        const existingIdx = this._selectedData.findIndex(i => i.id === id);
        if (existingIdx >= 0) {
            this._selectedData = [...this._selectedData.slice(0, existingIdx), ...this._selectedData.slice(existingIdx + 1)];
        } else {
            if (type === 'contact') {
                const raw = this._conRaw.find(c => c.Id === id);
                const shadowContactId = raw ? raw.personContactId : null;
                if (shadowContactId && this._manuallyRemovedIds.has(shadowContactId)) this._manuallyRemovedIds.delete(shadowContactId);
                if (this._manuallyRemovedIds.has(id)) this._manuallyRemovedIds.delete(id);
            }
            if (type === 'rc') {
                this._selectedData = this._selectedData.filter(i => i.type !== 'rc');
                this._manuallyRemovedIds = new Set();
            }
            this._selectedData = [...this._selectedData, { id, name, type, tins }];
        }

        this.lookupSearchKey = ''; this.showLookupDropdown = false;
        this._rcRaw = []; this._conRaw = []; this._rcResults = []; this._conResults = [];
        this._refreshTags();
        this._reloadAllMembers();
    }

    handleRemoveSelection(event) {
        const id = event.currentTarget.dataset.id;
        this._selectedData = this._selectedData.filter(i => i.id !== id);
        this._refreshTags();
        this._reloadAllMembers();
    }

    handleClearAll() {
        this._selectedData = []; this._manuallyRemovedIds = new Set();
        this._refreshTags();
        this.rcRowData = []; this.indRowData = [];
        this.rcTableSearchKey = ''; this.indTableSearchKey = '';
    }

    _reloadAllMembers() {
        if (this._selectedData.length === 0) { this.rcRowData = []; this.indRowData = []; return; }

        const snapshot = {};
        [...this.rcRowData, ...this.indRowData].forEach(r => {
            if (r.contactId) {
                snapshot[r.contactId] = { weaponEntries: r.weaponEntries || [], selected: r.selected || false, personAccountId: r.personAccountId || null };
            }
        });

        this.isLoadingMembers = true;

        const rcItems      = this._selectedData.filter(i => i.type === 'rc');
        const contactItems = this._selectedData.filter(i => i.type === 'contact');

        const rcPromises = rcItems.map(item =>
            getContactMembers({ recruitClassId: item.id, contactId: null }).then(r => r || []).catch(() => [])
        );

        const conPromises = contactItems.map(item =>
            getContactMembers({ recruitClassId: null, contactId: item.id }).then(r => r || []).catch(() => [])
        );

        Promise.all([Promise.all(rcPromises), Promise.all(conPromises)])
            .then(([rcResults, conResults]) => {
                const rcSeen = new Set();
                const rcRows = [];
                rcResults.forEach(list => {
                    (list || []).forEach(row => {
                        if (row.contactId && this._manuallyRemovedIds.has(row.contactId)) return;
                        if (row.personAccountId && this._manuallyRemovedIds.has(row.personAccountId)) return;
                        if (row.contactId && rcSeen.has(row.contactId)) return;
                        if (row.contactId) rcSeen.add(row.contactId);
                        rcRows.push(row);
                    });
                });
                rcRows.sort((a, b) => (a.contactName || '').localeCompare(b.contactName || ''));

                const indRows = [];
                conResults.forEach(list => {
                    (list || []).forEach(row => {
                        if (row.contactId && this._manuallyRemovedIds.has(row.contactId)) return;
                        if (row.personAccountId && this._manuallyRemovedIds.has(row.personAccountId)) return;
                        if (row.contactId && rcSeen.has(row.contactId)) return; // skip if already in RC
                        indRows.push(row);
                    });
                });
                indRows.sort((a, b) => (a.contactName || '').localeCompare(b.contactName || ''));

                this.rcRowData = rcRows.map(row => {
                    const built = this.buildRow(row);
                    const snap  = snapshot[built.contactId];
                    if (snap) { built.weaponEntries = snap.weaponEntries; built.selected = snap.selected; }
                    return this._computeWeaponDisplay(built);
                });

                this.indRowData = indRows.map(row => {
                    const built = this.buildRow(row);
                    const snap  = snapshot[built.contactId];
                    if (snap) { built.weaponEntries = snap.weaponEntries; built.selected = snap.selected; }
                    return this._computeWeaponDisplay(built);
                });

                this.isLoadingMembers = false;
            })
            .catch(error => { this.isLoadingMembers = false; this.showErrorToast('Failed to load members: ' + this.reduceErrors(error)); });
    }

    buildRow(row) {
        const recordLink = row.personAccountId
            ? `/lightning/r/Account/${row.personAccountId}/view`
            : (row.contactId ? `/lightning/r/Contact/${row.contactId}/view` : '#');
        return {
            memberId: row.memberId || null, contactId: row.contactId || null,
            personAccountId: row.personAccountId || null, contactName: row.contactName || '',
            contactUrl: recordLink, tins: row.tins || '', division: row.division || '',
            region: row.region || '', selected: false, weaponEntries: [],
            weaponType: '', manufacturer: '', model: '', sightType: '', rowClass: 'member-row'
        };
    }

    _computeWeaponDisplay(row) {
        const entries = row.weaponEntries || [];
        const uniq = (arr) => [...new Set(arr.filter(Boolean))];
        return {
            ...row,
            weaponType   : uniq(entries.map(e => e.weaponType)).join(', '),
            manufacturer : uniq(entries.map(e => e.manufacturer)).join(', '),
            model        : uniq(entries.map(e => e.model)).join(', '),
            sightType    : uniq(entries.map(e => e.sightType)).join(', ')
        };
    }

    handleTestDateChange(event)  { this.testDate           = event.target.value; }
    handleLocationChange(event)  { this.location           = event.target.value; }
    handleLightningChange(event) { this.lightningCondition = event.target.value; }
    handleRcTableSearch(event)   { this.rcTableSearchKey   = event.target.value; }
    handleIndTableSearch(event)  { this.indTableSearchKey  = event.target.value; }

    handleSelectAllRcRows(event) {
        const checked = event.target.checked;
        this.rcRowData = this.rcRowData.map(r => ({ ...r, selected: checked, rowClass: checked ? 'member-row row-selected' : 'member-row' }));
    }

    handleSelectAllIndRows(event) {
        const checked = event.target.checked;
        this.indRowData = this.indRowData.map(r => ({ ...r, selected: checked, rowClass: checked ? 'member-row row-selected' : 'member-row' }));
    }

    handleRowCheck(event) {
        const contactId = event.target.dataset.contactId;
        const source    = event.target.dataset.source;
        const checked   = event.target.checked;

        const updater = (r) => r.contactId === contactId
            ? { ...r, selected: checked, rowClass: checked ? 'member-row row-selected' : 'member-row' }
            : r;

        if (source === 'rc') {
            this.rcRowData = this.rcRowData.map(updater);
        } else {
            this.indRowData = this.indRowData.map(updater);
        }
    }

    handleRemoveSelectedRc() {
        const toRemove = this.rcRowData.filter(r => r.selected);
        toRemove.forEach(r => {
            if (r.contactId) this._manuallyRemovedIds.add(r.contactId);
            if (r.personAccountId) this._manuallyRemovedIds.add(r.personAccountId);
        });
        this.rcRowData = this.rcRowData.filter(r => !r.selected);
    }

    handleRemoveSelectedInd() {
        const toRemove = this.indRowData.filter(r => r.selected);
        toRemove.forEach(r => {
            if (r.contactId) this._manuallyRemovedIds.add(r.contactId);
            if (r.personAccountId) this._manuallyRemovedIds.add(r.personAccountId);
        });
        const removedAccountIds = new Set(toRemove.map(r => r.personAccountId).filter(Boolean));
        const removedContactIds = new Set(toRemove.map(r => r.contactId).filter(Boolean));
        this._selectedData = this._selectedData.filter(i => {
            if (i.type !== 'contact') return true;
            return !removedAccountIds.has(i.id) && !removedContactIds.has(i.id);
        });
        this._refreshTags();
        this.indRowData = this.indRowData.filter(r => !r.selected);
    }

    handleAddToRoster() {
        if (!this.testDate) { this.showErrorToast('Please select a Test Date before adding to roster.'); return; }

        const allRows = [...this.rcRowData, ...this.indRowData];
        const noWeapon = allRows.filter(r => !r.weaponEntries || r.weaponEntries.length === 0);
        if (noWeapon.length > 0) {
            const names = noWeapon.slice(0, 3).map(r => r.contactName).join(', ');
            const extra = noWeapon.length > 3 ? ` and ${noWeapon.length - 3} more` : '';
            this.showErrorToast(`Please assign a weapon type for: ${names}${extra}`);
            return;
        }

        this._pendingRosterPayload = allRows.map(r => ({
            memberId: r.memberId || null, contactId: r.contactId || null,
            contactName: r.contactName, lightningCondition: this.lightningCondition,
            weaponEntries: (r.weaponEntries || []).map(e => ({
                weaponType: e.weaponType || '', manufacturer: e.manufacturer || '',
                model: e.model || '', sightType: e.sightType || ''
            }))
        }));
        this._pendingFirstRc = this._selectedData.find(i => i.type === 'rc') || null;

        if (!this.rosterLabel && this._pendingFirstRc) this.rosterLabel = this._pendingFirstRc.name;
        this.rosterLabelError = ''; this.isSavingRoster = false; this.showRosterLabelModal = true;
    }

    _submitRoster(rosterLabel) {
        this.isSavingRoster = true;
        addToRoster({
            rosterPayload : JSON.stringify(this._pendingRosterPayload),
            recruitClassId: this._pendingFirstRc ? this._pendingFirstRc.id : null,
            testDate      : this.testDate,
            instructorId  : this.selectedInstructor ? this.selectedInstructor.Id : null,
            location      : this.location,
            rosterLabel   : rosterLabel
        })
        .then(count => {
            this.showRosterLabelModal = false; this.isSavingRoster = false;
            this._pendingRosterPayload = null; this._pendingFirstRc = null; this.rosterLabel = '';
            this.dispatchEvent(new ShowToastEvent({ title: 'Roster Saved', message: `${count} FIR Qualification Form(s) created successfully.`, variant: 'success' }));
        })
        .catch(error => { this.isSavingRoster = false; this.showErrorToast('Save failed: ' + this.reduceErrors(error)); });
    }

    showErrorToast(msg) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message: msg, variant: 'error' }));
    }

    reduceErrors(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        return JSON.stringify(error);
    }
}