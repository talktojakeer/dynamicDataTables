import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getRecruitClasses from '@salesforce/apex/recruitClassController.getRecruitClasses';

export default class CreateGroupCard extends LightningElement {
    // ---- App Builder configurable properties ----
    @api cardTitle        = 'Groups Overview';
    @api buttonLabel      = 'New';
    @api recruitTileLabel = 'Recruit Class Accounts';
    @api ftuTileLabel     = 'FTU Group Accounts';
    @api showIcon         = false;
    @api iconName         = 'standard:groups';
    @api hideCard         = false;   // retained for existing pages; unused

    showModal    = false;
    recruitCount = 0;
    ftuCount     = 0;
    _wired;

    @wire(getRecruitClasses)
    wiredGroups(result) {
        this._wired = result;
        if (result.data) {
            let rc = 0, ftu = 0;
            result.data.forEach(row => {
                if (this.resolveType(row) === 'Recruit Class') rc++; else ftu++;
            });
            this.recruitCount = rc;
            this.ftuCount     = ftu;
        }
    }

    // Same rule as the tab: field wins; else a single letter + 4 digits is a
    // Recruit Class, everything else is an FTU Group.
    resolveType(row) {
        if (row.FAQP_Group_Type__c) return row.FAQP_Group_Type__c;
        const clean = (row.Name || '').replace(/[^a-zA-Z0-9]/g, '');
        return /^[A-Za-z]\d{4}$/.test(clean) ? 'Recruit Class' : 'FTU Group';
    }

    get computedIcon() { return this.showIcon ? this.iconName : undefined; }

    openModal()  { this.showModal = true; }
    closeModal() { this.showModal = false; }

    // A group was created -> close modal and refresh the counts (and the page).
    handleRefresh() {
        this.showModal = false;
        refreshApex(this._wired);                       // update these tiles
        this.dispatchEvent(new CustomEvent('groupcreated'));
    }
}