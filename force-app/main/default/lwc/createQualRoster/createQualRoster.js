import { LightningElement, track, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getRecruitClassMembers from '@salesforce/apex/QualRosterController.getRecruitClassMembers';
import addToRoster           from '@salesforce/apex/QualRosterController.addToRoster';
import removeFromRoster      from '@salesforce/apex/QualRosterController.removeFromRoster';

// ─── Datatable columns ────────────────────────────────────────────────────
const COLUMNS = [
    {
        label: 'Employee Name',
        fieldName: 'ContactUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'ContactName' },
            target: '_blank'
        },
        sortable: true,
        initialWidth: 180
    },
    {
        label: 'TINS',
        fieldName: 'TINS__c',        // Contact_Member__c formula → Contact__r.FAQP_TINS_NUMBER__c
        type: 'text',
        sortable: true,
        initialWidth: 100
    },
    {
        label: 'Division',
        fieldName: 'Division__c',    // Contact_Member__c formula → Contact__r.FAQP_Division__c
        type: 'text',
        sortable: true,
        initialWidth: 180
    },
    {
        label: 'Region',
        fieldName: 'Region__c',      // Contact_Member__c formula → TEXT(Contact__r.FAQP_Region__c)
        type: 'text',
        sortable: true,
        initialWidth: 100
    },
    {
        label: 'FIR Form',
        fieldName: 'FIRFormUrl',
        type: 'url',
        typeAttributes: {
            label: { fieldName: 'FIRFormName' },
            target: '_blank'
        },
        initialWidth: 140
    },
    {
        label: 'Test Date',
        fieldName: 'FIRTestDate',    // FIR_Form__c.Test_Date__c
        type: 'date',
        sortable: true,
        initialWidth: 120
    },
    {
        label: 'Location',
        fieldName: 'FIRLocation',    // FIR_Form__c.Location__c
        type: 'text',
        initialWidth: 160
    },
    {
        label: 'Instructor',
        fieldName: 'FIRInstructor',  // FIR_Form__c.Firearm_Instructor__r.Name
        type: 'text',
        initialWidth: 160
    }
];

export default class CreateQualRoster extends LightningElement {

    // recordId = Account (Recruit Class) Id — auto-set when on Record Page
    @api recordId;

    // ─── Filter fields (written to FIR_Form__c on Add To Roster) ─────────
    @track testDate          = '';
    @track firearmInstructor = '';   // freeform; resolved to User Id in Apex
    @track location          = '';

    // ─── Table state ──────────────────────────────────────────────────────
    @track selectedRows = [];
    @track isLoading    = false;
    @track allMembers   = [];
    wiredResult;

    columns = COLUMNS;
    filteredRecords = [];
    // ─── Wire: Contact_Member__c for this Recruit Class ───────────────────
    @wire(getRecruitClassMembers, { recruitClassId: '$recordId' })
    wiredMembers(result) {
        this.wiredResult = result;
        if (result.data) {
            this.allMembers = result.data.map(m => {
                const fir = m.Contact__r && m.Contact__r.FIR_Form__r;
                return {
                    ...m,
                    // Contact display
                    ContactName : m.Contact__r ? m.Contact__r.Name : '—',
                    ContactUrl  : m.Contact__c
                        ? `/lightning/r/Contact/${m.Contact__c}/view`
                        : null,
                    // FIR Form display (may not exist yet)
                    FIRFormName : fir ? fir.Name       : 'Not Created',
                    FIRFormUrl  : fir ? `/lightning/r/FIR_Form__c/${m.Contact__r.FIR_Form__c}/view` : null,
                    FIRTestDate : fir ? fir.Test_Date__c : null,
                    FIRLocation : fir ? fir.Location__c  : '',
                    FIRInstructor: fir && fir.Firearm_Instructor__r
                        ? fir.Firearm_Instructor__r.Name
                        : ''
                };
            });
            this.isLoading = false;
        } else if (result.error) {
            this.showErrorToast('Error loading members: ' + this.reduceErrors(result.error));
            this.isLoading = false;
        }
    }

    // ─── Getters ──────────────────────────────────────────────────────────
    get recruitClassMembers() { return this.allMembers; }
    get hasRecords()   { return this.allMembers && this.allMembers.length > 0; }
    get hasSelection() { return this.selectedRows.length > 0; }

    get isAddDisabled() {
        // Require at least Test Date before creating FIR Forms
        return this.selectedRows.length === 0 || !this.testDate;
    }

    get isRemoveDisabled() {
        return this.selectedRows.length === 0;
    }

    get selectedRowIds() {
        return this.selectedRows.map(r => r.Id);
    }

    // ─── Handlers ─────────────────────────────────────────────────────────
    handleTestDateChange(event)     { this.testDate          = event.target.value; }
    handleInstructorChange(event)   { this.firearmInstructor = event.target.value; }
    handleLocationChange(event)     { this.location          = event.target.value; }
    handleRowSelection(event)       { this.selectedRows      = event.detail.selectedRows; }

    // ─── Add To Roster ────────────────────────────────────────────────────
    // Creates one FIR_Form__c per selected member, then:
    //   • Sets Contact.FIR_Form__c = new FIR Form Id
    //   • Creates 3 Weapon_Qualification__c children (Pistol, Shot Gun, Riffle)
    handleAddToRoster() {
        if (!this.selectedRows.length) return;

        if (!this.testDate) {
            this.showErrorToast('Please select a Test Date before adding to roster.');
            return;
        }

        const contactMemberIds = this.selectedRows.map(r => r.Id);
        this.isLoading = true;

        addToRoster({
            contactMemberIds,
            recruitClassId   : this.recordId,
            testDate         : this.testDate,
            firearmInstructor: this.firearmInstructor,
            location         : this.location
        })
        .then(count => {
            this.showSuccessToast(`${count} FIR Form(s) created successfully.`);
            this.selectedRows = [];
            return refreshApex(this.wiredResult);
        })
        .catch(error => {
            this.showErrorToast('Add to Roster failed: ' + this.reduceErrors(error));
        })
        .finally(() => { this.isLoading = false; });
    }

    // ─── Remove From Roster ───────────────────────────────────────────────
    // Nulls Contact.FIR_Form__c then deletes FIR_Form__c
    // (Weapon_Qualification__c cascade-deletes via Master-Detail)
    handleRemove() {
        if (!this.selectedRows.length) return;

        // eslint-disable-next-line no-alert
        if (!confirm(
            `Remove ${this.selectedRows.length} member(s) from the roster?\n` +
            `This will delete their FIR Form and Weapon Qualification records.`
        )) return;

        const contactMemberIds = this.selectedRows.map(r => r.Id);
        this.isLoading = true;

        removeFromRoster({ contactMemberIds })
        .then(() => {
            this.showSuccessToast(`${contactMemberIds.length} member(s) removed from roster.`);
            this.selectedRows = [];
            return refreshApex(this.wiredResult);
        })
        .catch(error => {
            this.showErrorToast('Remove failed: ' + this.reduceErrors(error));
        })
        .finally(() => { this.isLoading = false; });
    }

    // ─── Toast helpers ────────────────────────────────────────────────────
    showSuccessToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Success', message, variant: 'success' }));
    }
    showErrorToast(message) {
        this.dispatchEvent(new ShowToastEvent({ title: 'Error', message, variant: 'error' }));
    }

    // ─── Error reducer ────────────────────────────────────────────────────
    reduceErrors(errors) {
        if (typeof errors === 'string') return errors;
        if (Array.isArray(errors)) {
            return errors.filter(e => !!e).map(e => {
                if (typeof e === 'string') return e;
                if (e.message) return e.message;
                if (e.body && e.body.message) return e.body.message;
                return JSON.stringify(e);
            }).join(', ');
        }
        if (errors?.body?.message) return errors.body.message;
        if (errors?.message)       return errors.message;
        return 'Unknown error';
    }
}