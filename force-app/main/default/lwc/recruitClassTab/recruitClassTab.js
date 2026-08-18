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

    get recruitCount() { return this.recruitClasses.length; }
    get ftuCount()     { return this.ftuGroups.length; }
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
    }

    // Prefer the FAQP_Group_Type__c picklist. Fall back to the name rule for
    // records created before the field existed: a name containing a 20xx year
    // (e.g. "A-2026") is a Recruit Class; anything else is an FTU Group.
    resolveGroupType(row) {
        if (row.FAQP_Group_Type__c) {
            return row.FAQP_Group_Type__c;
        }
        return /20\d{2}/.test(row.Name || '') ? 'Recruit Class' : 'FTU Group';
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
        refreshApex(this.wiredResult);
    }
}