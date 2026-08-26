import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRecruitClasses from '@salesforce/apex/recruitClassController.getRecruitClasses';
import { refreshApex } from '@salesforce/apex';
import { deleteRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';


export default class RecruitClassTab extends NavigationMixin(LightningElement) {
    /*connectedCallback() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Account',
                actionName: 'list'
            }
        });
    }*/
   @track showModal = false;
    @track showRecruit = true;   // collapse state for Recruit Class section
    @track showFtu     = true;   // collapse state for FTU Groups section
    wiredResult;
    recruitClasses = [];
    ftuGroups      = [];

    // ---- Pagination (10 per section) -------------------------------------
    pageSize = 10;
    @track recruitPage = 1;
    @track ftuPage     = 1;

    get recruitCount() { return this.recruitClasses.length; }
    get ftuCount()     { return this.ftuGroups.length; }

    // Total pages (at least 1 so controls render sanely on empty lists)
    get recruitTotalPages() { return Math.max(1, Math.ceil(this.recruitCount / this.pageSize)); }
    get ftuTotalPages()     { return Math.max(1, Math.ceil(this.ftuCount / this.pageSize)); }

    // Current page slice
    get pagedRecruitClasses() {
        const start = (this.recruitPage - 1) * this.pageSize;
        return this.recruitClasses.slice(start, start + this.pageSize);
    }
    get pagedFtuGroups() {
        const start = (this.ftuPage - 1) * this.pageSize;
        return this.ftuGroups.slice(start, start + this.pageSize);
    }

    // Button disabled states
    get recruitPrevDisabled() { return this.recruitPage <= 1; }
    get recruitNextDisabled() { return this.recruitPage >= this.recruitTotalPages; }
    get ftuPrevDisabled()     { return this.ftuPage <= 1; }
    get ftuNextDisabled()     { return this.ftuPage >= this.ftuTotalPages; }

    // "Page X of Y" labels; only show controls when more than one page
    get recruitPageLabel()  { return `Page ${this.recruitPage} of ${this.recruitTotalPages}`; }
    get ftuPageLabel()      { return `Page ${this.ftuPage} of ${this.ftuTotalPages}`; }
    get showRecruitPager()  { return this.recruitCount > this.pageSize; }
    get showFtuPager()      { return this.ftuCount > this.pageSize; }

    recruitPrev() { if (this.recruitPage > 1) this.recruitPage -= 1; }
    recruitNext() { if (this.recruitPage < this.recruitTotalPages) this.recruitPage += 1; }
    ftuPrev()     { if (this.ftuPage > 1) this.ftuPage -= 1; }
    ftuNext()     { if (this.ftuPage < this.ftuTotalPages) this.ftuPage += 1; }

    get recruitCaret() { return this.showRecruit ? 'utility:chevrondown' : 'utility:chevronright'; }
    get ftuCaret()     { return this.showFtu ? 'utility:chevrondown' : 'utility:chevronright'; }

    columns = [
        { label: 'Recruit Class', 
            fieldName: 'recordLink',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'Name' },  // show Name as text
                target: '_self'                // open in same tab
            },
            cellAttributes: { alignment: 'left' },
            initialWidth: undefined  // let it stretch
        }
    ];

    @wire(getRecruitClasses)
    wiredData(result) {
        this.wiredResult = result; 
        const { data, error } = result;
        if (data) {
            console.log('Data '+JSON.stringify(data));
            this.prepareRecords(data);
        } else if (error) {
            console.error(error);
        }
    }    

    prepareRecords(data) {
        const baseUrl = window.location.origin;

        const all = data.map(row => {
            return {
                ...row,
                recordLink: `${baseUrl}/lightning/r/Account/${row.Id}/view`,
                groupType : this.resolveGroupType(row)
            };
        });

        this.recruitClasses = all.filter(r => r.groupType === 'Recruit Class');
        this.ftuGroups      = all.filter(r => r.groupType === 'FTU Group');

        // Reset to first page on reload, and clamp if the current page no longer
        // exists (e.g. after a delete removed the last row on a page).
        this.recruitPage = Math.min(this.recruitPage, this.recruitTotalPages);
        this.ftuPage     = Math.min(this.ftuPage, this.ftuTotalPages);
        if (this.recruitPage < 1) this.recruitPage = 1;
        if (this.ftuPage < 1) this.ftuPage = 1;
    }

    // Prefer the FAQP_Group_Type__c picklist. Fall back to the name rule for
    // records created before the field existed: a name that is exactly ONE
    // letter followed by FOUR digits (e.g. "A2026" / "A-2026") is a Recruit
    // Class; anything else is an FTU Group.
    resolveGroupType(row) {
        if (row.FAQP_Group_Type__c) {
            return row.FAQP_Group_Type__c;
        }
        const clean = (row.Name || '').replace(/[^a-zA-Z0-9]/g, '');
        return /^[A-Za-z]\d{4}$/.test(clean) ? 'Recruit Class' : 'FTU Group';
    }

    toggleRecruit() { this.showRecruit = !this.showRecruit; }
    toggleFtu()     { this.showFtu     = !this.showFtu; }

    handleRowAction(event){
        const actionValue = event.detail.value;
        const recordId = event.target.dataset.id;
        const recordName = event.target.dataset.name;
        if (actionValue === 'edit') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: recordId,
                    actionName: 'edit'
                }
            });

        }else if (actionValue === 'delete') {
            console.log('recordId '+recordId)
            console.log('recordName '+recordName)
            deleteRecord(recordId)
            .then(() => {
                console.log('Deleted');
                refreshApex(this.wiredResult);
            })
            .catch(error => {
                console.error(error);
            });
        }
    }


    openModal() {
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
    }

    handleSuccess() {
        this.showModal = false;
        this.refreshTable();
    }

    refreshTable() {
        this.recruitPage = 1;
        this.ftuPage     = 1;
        refreshApex(this.wiredResult);
    }
}