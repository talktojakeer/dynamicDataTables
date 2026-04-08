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

const WEAPON_FIELDS = ['pistol', 'shotgun', 'rifle', 'autoWeapon', 'precisionRifle'];

export default class CreateQualRoster extends LightningElement {

    
    _selectedData = [];   // [{ id, name, type: 'rc'|'contact' }]
    _rcRaw        = [];   // raw Account results from Apex
    _conRaw       = [];   // raw Contact results from Apex

    // ── Lookup UI state ────────────────────────────────────────────────────
    @track lookupSearchKey    = '';
    @track showLookupDropdown = false;
    @track isLookupSearching  = false;

    
    @track _rcResults  = [];   // enriched with alreadySelected + itemClass
    @track _conResults = [];   // enriched with alreadySelected + itemClass
    @track _tags       = [];   // enriched with tagClass + icon

    lookupSearchTimeout;

    // ── Computed getters ───────────────────────────────────────────────────
    get hasSelections()     { return this._selectedData.length > 0; }
    get hasRcResults()      { return this._rcResults.length > 0; }
    get hasContactResults() { return this._conResults.length > 0; }
    get hasAnyResults()     { return this.hasRcResults || this.hasContactResults; }
    get selectedItems()     { return this._tags; }
    get rcSearchResults()   { return this._rcResults; }
    get contactSearchResults() { return this._conResults; }

    // ── Helpers to rebuild reactive tracked arrays ─────────────────────────
    _refreshDropdownState() {
        const selectedIds = new Set(this._selectedData.map(i => i.id));
        this._rcResults  = this._rcRaw.map(r => ({
            Id             : r.Id,
            Name           : r.Name,
            alreadySelected: selectedIds.has(r.Id),
            itemClass      : selectedIds.has(r.Id) ? 'lookup-item lookup-item-selected' : 'lookup-item'
        }));
        this._conResults = this._conRaw.map(c => ({
            Id             : c.Id,
            Name           : c.Name,
            tins           : c.tins,
            alreadySelected: selectedIds.has(c.Id),
            itemClass      : selectedIds.has(c.Id) ? 'lookup-item lookup-item-selected' : 'lookup-item'
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

    // ── Instructor Lookup ─────────────────────────────────────────────────
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
            this.selectedInstructor = {
                Id  : this.currentUserId,
                Name: getFieldValue(data, NAME_FIELD)
            };
        } else if (error) {
            console.error('Failed to load current user:', error);
        }
    }

    // ── Session fields ─────────────────────────────────────────────────────
    @track testDate           = '';
    @track location           = '';
    @track lightningCondition = '';
    @track lcDaytime          = false;
    @track lcNighttime        = false;

    // ── Table ─────────────────────────────────────────────────────────────
    @track isLoadingMembers = false;
    @track tableSearchKey   = '';
    @track rowData          = [];

    get memberCount()  { return this.rowData.length; }
    get isAddDisabled(){ return !this.testDate; }

    get filteredRows() {
        if (!this.tableSearchKey || !this.tableSearchKey.trim()) return this.rowData;
        const key = this.tableSearchKey.toLowerCase();
        return this.rowData.filter(r =>
            (r.contactName && r.contactName.toLowerCase().includes(key)) ||
            (r.tins        && r.tins.toLowerCase().includes(key))        ||
            (r.division    && r.division.toLowerCase().includes(key))
        );
    }

    get allPistol()        { return this.rowData.length > 0 && this.rowData.every(r => r.pistol); }
    get allShotgun()       { return this.rowData.length > 0 && this.rowData.every(r => r.shotgun); }
    get allRifle()         { return this.rowData.length > 0 && this.rowData.every(r => r.rifle); }
    get allAutoWeapon()    { return this.rowData.length > 0 && this.rowData.every(r => r.autoWeapon); }
    get allPrecisionRifle(){ return this.rowData.length > 0 && this.rowData.every(r => r.precisionRifle); }

    handleLookupFocus() {
        if (this.lookupSearchKey && this.lookupSearchKey.trim().length >= 1) {
            this.showLookupDropdown = true;
        }
    }

    handleLookupSearch(event) {
        this.lookupSearchKey = event.target.value;
        clearTimeout(this.lookupSearchTimeout);

        if (!this.lookupSearchKey || this.lookupSearchKey.trim().length < 1) {
            this.showLookupDropdown = false;
            this._rcRaw    = [];
            this._conRaw   = [];
            this._rcResults  = [];
            this._conResults = [];
            return;
        }

        this.isLookupSearching  = true;
        this.showLookupDropdown = true;

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.lookupSearchTimeout = setTimeout(() => {
            searchRecruitClassAndContacts({ searchKey: this.lookupSearchKey })
                .then(result => {
                    this._rcRaw  = result.recruitClasses || [];

                    // Client-side dedup by name as safety net
                    const seen   = new Set();
                    this._conRaw = (result.contacts || [])
                        .filter(c => {
                            const key = (c.Name || '').toLowerCase().trim();
                            if (seen.has(key)) return false;
                            seen.add(key);
                            return true;
                        })
                        .map(c => ({
                            Id  : c.Id,
                            Name: c.Name,
                            tins: c.TINS
                        }));
                    this.isLookupSearching = false;
                    this._refreshDropdownState();
                })
                .catch(error => {
                    this.isLookupSearching = false;
                    this.showErrorToast('Search failed: ' + this.reduceErrors(error));
                });
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
            // Already selected → remove (toggle off)
            this._selectedData = [
                ...this._selectedData.slice(0, existingIdx),
                ...this._selectedData.slice(existingIdx + 1)
            ];
        } else {
            // Add new selection — store tins so synthetic rows can display it
            this._selectedData = [...this._selectedData, { id, name, type, tins }];
        }

        this.lookupSearchKey    = '';
        this.showLookupDropdown = false;
        this._rcRaw    = [];
        this._conRaw   = [];
        this._rcResults  = [];
        this._conResults = [];

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
        this._selectedData = [];
        this._refreshTags();
        this.rowData        = [];
        this.tableSearchKey = '';
    }

    _reloadAllMembers() {
        if (this._selectedData.length === 0) {
            this.rowData = [];
            return;
        }

        this.isLoadingMembers = true;
        console.log('Reloading members for:', JSON.parse(JSON.stringify(this._selectedData)));

        const promises = this._selectedData.map(item => {
            const recruitClassId = item.type === 'rc'      ? item.id : null;
            const contactId      = item.type === 'contact' ? item.id : null;
            console.log(`Fetching → type:${item.type} name:${item.name}`);
            return getContactMembers({ recruitClassId, contactId })
                .then(result => {
                    const list = result || [];
                    console.log(`${item.name}: ${list.length} rows`, JSON.parse(JSON.stringify(list)));
                    return list;
                })
                .catch(err => {
                    console.error(`Error for ${item.name}:`, err);
                    return [];
                });
        });

        Promise.all(promises)
            .then(results => {
                const seenContactIds = new Set();
                const allRows        = [];

                results.forEach(list => {
                    (list || []).forEach(row => {
                        if (row.contactId && seenContactIds.has(row.contactId)) return;
                        if (row.contactId) seenContactIds.add(row.contactId);
                        allRows.push(row);
                    });
                });

                allRows.sort((a, b) =>
                    (a.contactName || '').localeCompare(b.contactName || '')
                );

                console.log('Final rows after dedup:', JSON.parse(JSON.stringify(allRows)));
                this.rowData          = allRows.map(row => this.buildRow(row));
                this.isLoadingMembers = false;
            })
            .catch(error => {
                this.isLoadingMembers = false;
                console.error('Promise.all error:', error);
                this.showErrorToast('Failed to load members: ' + this.reduceErrors(error));
            });
    }

    buildRow(row) {
        return {
            memberId      : row.memberId    || '',
            contactId     : row.contactId   || '',
            contactName   : row.contactName || '—',
            contactUrl    : row.contactId   ? `/lightning/r/Contact/${row.contactId}/view` : null,
            tins          : row.tins        || '',
            division      : row.division    || '',
            region        : row.region      || '',
            pistol        : false,
            shotgun       : false,
            rifle         : false,
            autoWeapon    : false,
            precisionRifle: false,
            rowClass      : 'member-row'
        };
    }

    _buildSyntheticMember(item) {
        return {
            memberId    : '',
            contactId   : item.id,
            contactName : item.name,
            tins        : item.tins     || '',
            division    : item.division || '',
            region      : item.region   || '',
            recruitClassId: null
        };
    }

    handleInstructorFocus() {
        if (this.instructorSearchKey && this.instructorSearchKey.trim().length >= 1) {
            this.showInstructorDropdown = true;
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
                .then(users => {
                    this.instructorResults     = users || [];
                    this.isInstructorSearching = false;
                })
                .catch(error => {
                    this.isInstructorSearching = false;
                    this.showErrorToast('User search failed: ' + this.reduceErrors(error));
                });
        }, 300);
    }

    handleInstructorSelect(event) {
        this.selectedInstructor = {
            Id  : event.currentTarget.dataset.id,
            Name: event.currentTarget.dataset.name
        };
        this.instructorSearchKey    = '';
        this.showInstructorDropdown = false;
        this.instructorResults      = [];
    }

    handleClearInstructor() {
        this.selectedInstructor     = null;
        this.instructorSearchKey    = '';
        this.showInstructorDropdown = false;
        this.instructorResults      = [];
    }

    handleTestDateChange(event) { this.testDate = event.target.value; }
    handleLocationChange(event) { this.location = event.target.value; }

    handleLightningConditionChange(event) {
        this.lightningCondition = event.target.value;
        this.lcDaytime          = this.lightningCondition === 'DayTime/Norrmal Lighting';
        this.lcNighttime        = this.lightningCondition === 'NightTime/Reduced Lighting';
    }

    handleTableSearch(event) { this.tableSearchKey = event.target.value; }

    handleWeaponCheck(event) {
        const contactId = event.target.dataset.contactId;
        const field     = event.target.dataset.field;
        const value     = event.target.checked;
        this.rowData = this.rowData.map(r =>
            r.contactId === contactId ? { ...r, [field]: value } : r
        );
    }

    handleSelectAllWeapon(event) {
        const field   = event.target.dataset.field;
        const checked = event.target.checked;
        this.rowData = this.rowData.map(r => ({ ...r, [field]: checked }));
    }

    handleAddToRoster() {
        if (!this.testDate) {
            this.showErrorToast('Please select a Test Date before adding to roster.');
            return;
        }

        const membersWithNoWeapon = this.rowData.filter(
            r => !WEAPON_FIELDS.some(f => r[f])
        );
        if (membersWithNoWeapon.length > 0) {
            const names = membersWithNoWeapon.slice(0, 3).map(r => r.contactName).join(', ');
            const extra = membersWithNoWeapon.length > 3
                ? ` and ${membersWithNoWeapon.length - 3} more` : '';
            this.showErrorToast(`Please select at least one weapon for: ${names}${extra}`);
            return;
        }

        const rosterPayload = this.rowData.map(r => ({
            memberId          : r.memberId   || null,
            contactId         : r.contactId  || null,
            contactName       : r.contactName,
            pistol            : r.pistol         ? 'Yes' : 'No',
            shotgun           : r.shotgun        ? 'Yes' : 'No',
            rifle             : r.rifle          ? 'Yes' : 'No',
            autoWeapon        : r.autoWeapon     ? 'Yes' : 'No',
            precisionRifle    : r.precisionRifle ? 'Yes' : 'No',
            lightningCondition: this.lightningCondition
        }));

        const firstRc = this._selectedData.find(i => i.type === 'rc');

        addToRoster({
            rosterPayload : JSON.stringify(rosterPayload),
            recruitClassId: firstRc ? firstRc.id : null,
            testDate      : this.testDate,
            instructorId  : this.selectedInstructor ? this.selectedInstructor.Id : null,
            location      : this.location
        })
        .then(count => {
            this.showSuccessToast(`${count} FIR Form(s) created successfully!`);
            this._resetForm();
        })
        .catch(error => {
            this.showErrorToast('Add to Roster failed: ' + this.reduceErrors(error));
        });
    }

    _resetForm() {
        this._selectedData      = [];
        this._rcRaw             = [];
        this._conRaw            = [];
        this._rcResults         = [];
        this._conResults        = [];
        this._tags              = [];
        this.lookupSearchKey    = '';
        this.showLookupDropdown = false;
        this.isLookupSearching  = false;
        clearTimeout(this.lookupSearchTimeout);

        this.testDate           = '';
        this.location           = '';
        this.lightningCondition = '';
        this.lcDaytime          = false;
        this.lcNighttime        = false;

        this.rowData          = [];
        this.tableSearchKey   = '';
        this.isLoadingMembers = false;

        this.instructorSearchKey    = '';
        this.showInstructorDropdown = false;
        this.isInstructorSearching  = false;
        this.instructorResults      = [];
        if (this.currentUserId && this.selectedInstructor) {
            this.selectedInstructor = {
                Id  : this.currentUserId,
                Name: this.selectedInstructor.Name
            };
        }
    }

    showSuccessToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }
    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }

    reduceErrors(errors) {
        if (typeof errors === 'string') return errors;
        if (Array.isArray(errors)) {
            return errors.filter(e => !!e).map(e => {
                if (typeof e === 'string') return e;
                if (e.message)            return e.message;
                if (e.body?.message)      return e.body.message;
                return JSON.stringify(e);
            }).join(', ');
        }
        if (errors?.body?.message) return errors.body.message;
        if (errors?.message)       return errors.message;
        return 'Unknown error';
    }
}