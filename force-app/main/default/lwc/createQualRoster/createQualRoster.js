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

// All weapon field keys — used for validation
const WEAPON_FIELDS = ['pistol', 'shotgun', 'rifle', 'autoWeapon', 'precisionRifle'];

export default class CreateQualRoster extends LightningElement {

    // ── Recruit Class Lookup ───────────────────────────────────────────────
    @track selectedRecruitClass = null;
    @track lookupSearchKey      = '';
    @track showLookupDropdown   = false;
    @track isLookupSearching    = false;
    @track rcSearchResults      = [];
    @track contactSearchResults = [];
    lookupSearchTimeout;

    get hasRcResults()      { return this.rcSearchResults.length > 0; }
    get hasContactResults() { return this.contactSearchResults.length > 0; }
    get hasAnyResults()     { return this.hasRcResults || this.hasContactResults; }

    // ── Instructor Lookup — auto-populated with current user ───────────────
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

    // ── Computed ───────────────────────────────────────────────────────────
    get memberCount() { return this.rowData.length; }

    // Disabled only when no test date — weapon validation happens on submit
    get isAddDisabled() { return !this.testDate; }

    get filteredRows() {
        if (!this.tableSearchKey || !this.tableSearchKey.trim()) return this.rowData;
        const key = this.tableSearchKey.toLowerCase();
        return this.rowData.filter(r =>
            (r.contactName && r.contactName.toLowerCase().includes(key)) ||
            (r.tins        && r.tins.toLowerCase().includes(key))        ||
            (r.division    && r.division.toLowerCase().includes(key))
        );
    }

    // ── Per-column "select all" header checkbox state ──────────────────────
    get allPistol()        { return this.rowData.length > 0 && this.rowData.every(r => r.pistol); }
    get allShotgun()       { return this.rowData.length > 0 && this.rowData.every(r => r.shotgun); }
    get allRifle()         { return this.rowData.length > 0 && this.rowData.every(r => r.rifle); }
    get allAutoWeapon()    { return this.rowData.length > 0 && this.rowData.every(r => r.autoWeapon); }
    get allPrecisionRifle(){ return this.rowData.length > 0 && this.rowData.every(r => r.precisionRifle); }

    // ── RC Lookup handlers ─────────────────────────────────────────────────
    handleLookupFocus() {
        if (this.lookupSearchKey && this.lookupSearchKey.trim().length >= 1) {
            this.showLookupDropdown = true;
        }
    }

    handleLookupSearch(event) {
        this.lookupSearchKey = event.target.value;
        clearTimeout(this.lookupSearchTimeout);
        if (!this.lookupSearchKey || this.lookupSearchKey.trim().length < 1) {
            this.showLookupDropdown   = false;
            this.rcSearchResults      = [];
            this.contactSearchResults = [];
            return;
        }
        this.isLookupSearching  = true;
        this.showLookupDropdown = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.lookupSearchTimeout = setTimeout(() => {
            this.runLookupSearch(this.lookupSearchKey);
        }, 300);
    }

    runLookupSearch(key) {
        searchRecruitClassAndContacts({ searchKey: key })
            .then(result => {
                this.rcSearchResults = result.recruitClasses || [];
                this.contactSearchResults = (result.contacts || []).map(c => ({
                    ...c,
                    recruitClassId  : c.RecruitClassId,
                    recruitClassName: c.RecruitClassName,
                    tins            : c.TINS
                }));
                this.isLookupSearching = false;
            })
            .catch(error => {
                this.isLookupSearching = false;
                this.showErrorToast('Search failed: ' + this.reduceErrors(error));
            });
    }

    handleLookupSelect(event) {
        const type        = event.currentTarget.dataset.type;
        const rcId        = event.currentTarget.dataset.id;        // always the RC Id
        const rcName      = event.currentTarget.dataset.name;      // always the RC name
        const displayName = event.currentTarget.dataset.displayName; // contact's own name (only for contacts)

        if (!rcId) {
            this.showErrorToast('This contact has no linked Recruit Class.');
            return;
        }

        // If a contact was selected, show the contact name in the pill
        // but still load members of their Recruit Class
        const pillName = (type === 'contact' && displayName)
            ? displayName
            : rcName;

        this.selectedRecruitClass = {
            Id     : rcId,
            Name   : pillName,
            RcName : (type === 'contact') ? rcName : null  // subtitle for contact selections
        };
        this.lookupSearchKey      = '';
        this.showLookupDropdown   = false;
        this.rcSearchResults      = [];
        this.contactSearchResults = [];
        this.rowData              = [];
        this.tableSearchKey       = '';
        this.loadMembers(rcId);
    }

    handleClearClass() {
        this.selectedRecruitClass = null;
        this.lookupSearchKey      = '';
        this.showLookupDropdown   = false;
        this.rcSearchResults      = [];
        this.contactSearchResults = [];
        this.rowData              = [];
        this.tableSearchKey       = '';
    }

    // ── Instructor Lookup handlers ─────────────────────────────────────────
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
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.instructorSearchTimeout = setTimeout(() => {
            this.runInstructorSearch(this.instructorSearchKey);
        }, 300);
    }

    runInstructorSearch(key) {
        searchUsers({ searchKey: key })
            .then(users => {
                this.instructorResults     = users || [];
                this.isInstructorSearching = false;
            })
            .catch(error => {
                this.isInstructorSearching = false;
                this.showErrorToast('User search failed: ' + this.reduceErrors(error));
            });
    }

    handleInstructorSelect(event) {
        const id   = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name;
        this.selectedInstructor     = { Id: id, Name: name };
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

    // ── Load Members ───────────────────────────────────────────────────────
    loadMembers(recruitClassId) {
        this.isLoadingMembers = true;
        getContactMembers({ recruitClassId })
            .then(members => {
                this.rowData          = members.map(m => this.buildRow(m));
                this.isLoadingMembers = false;
            })
            .catch(error => {
                this.isLoadingMembers = false;
                this.showErrorToast('Failed to load members: ' + this.reduceErrors(error));
            });
    }

    buildRow(m) {
        const contact = m.Contact__r || {};
        return {
            memberId      : m.Id,
            contactName   : contact.Name             || '—',
            contactUrl    : m.Contact__c ? `/lightning/r/Contact/${m.Contact__c}/view` : null,
            tins          : contact.TINS_NUMBER__c   || '',
            division      : contact.FAQP_Division__c || '',
            region        : contact.FAQP_Region__c != null
                            ? String(contact.FAQP_Region__c) : '',
            pistol        : false,
            shotgun       : false,
            rifle         : false,
            autoWeapon    : false,
            precisionRifle: false,
            rowClass      : 'member-row'
        };
    }

    // ── Session field handlers ─────────────────────────────────────────────
    handleTestDateChange(event) { this.testDate = event.target.value; }
    handleLocationChange(event) { this.location = event.target.value; }

    handleLightningConditionChange(event) {
        this.lightningCondition = event.target.value;
        this.lcDaytime          = this.lightningCondition === 'DayTime/Norrmal Lighting';
        this.lcNighttime        = this.lightningCondition === 'NightTime/Reduced Lighting';
    }

    // ── Table search ───────────────────────────────────────────────────────
    handleTableSearch(event) { this.tableSearchKey = event.target.value; }

    // ── Weapon checkbox — individual cell ──────────────────────────────────
    handleWeaponCheck(event) {
        const memberId = event.target.dataset.memberId;
        const field    = event.target.dataset.field;
        const value    = event.target.checked;
        this.rowData = this.rowData.map(r =>
            r.memberId === memberId ? { ...r, [field]: value } : r
        );
    }

    // ── Select all rows for one weapon column ──────────────────────────────
    handleSelectAllWeapon(event) {
        const field   = event.target.dataset.field;
        const checked = event.target.checked;
        this.rowData = this.rowData.map(r => ({ ...r, [field]: checked }));
    }

    // ── Add To Roster ──────────────────────────────────────────────────────
    handleAddToRoster() {
        if (!this.testDate) {
            this.showErrorToast('Please select a Test Date before adding to roster.');
            return;
        }

        // ── Weapon validation: every member must have at least one weapon checked
        const membersWithNoWeapon = this.rowData.filter(
            r => !WEAPON_FIELDS.some(f => r[f])
        );

        if (membersWithNoWeapon.length > 0) {
            // Show up to 3 names, then "and X more"
            const names = membersWithNoWeapon
                .slice(0, 3)
                .map(r => r.contactName)
                .join(', ');
            const extra = membersWithNoWeapon.length > 3
                ? ` and ${membersWithNoWeapon.length - 3} more` : '';
            this.showErrorToast(
                `Please select at least one weapon for: ${names}${extra}`
            );
            return;
        }

        // Build payload — only 'Yes'/'No' per weapon, Apex will skip 'No' weapons
        const rosterPayload = this.rowData.map(r => ({
            memberId          : r.memberId,
            pistol            : r.pistol         ? 'Yes' : 'No',
            shotgun           : r.shotgun        ? 'Yes' : 'No',
            rifle             : r.rifle          ? 'Yes' : 'No',
            autoWeapon        : r.autoWeapon     ? 'Yes' : 'No',
            precisionRifle    : r.precisionRifle ? 'Yes' : 'No',
            lightningCondition: this.lightningCondition
        }));

        addToRoster({
            rosterPayload : JSON.stringify(rosterPayload),
            recruitClassId: this.selectedRecruitClass.Id,
            testDate      : this.testDate,
            instructorId  : this.selectedInstructor ? this.selectedInstructor.Id : null,
            location      : this.location
        })
        .then(count => {
            this.showSuccessToast(`${count} FIR Form(s) created successfully!`);
            this.loadMembers(this.selectedRecruitClass.Id);
        })
        .catch(error => {
            this.showErrorToast('Add to Roster failed: ' + this.reduceErrors(error));
        });
    }

    // ── Toast helpers ──────────────────────────────────────────────────────
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