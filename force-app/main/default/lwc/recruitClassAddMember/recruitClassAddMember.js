import { LightningElement, track, api } from 'lwc';
import searchContacts from '@salesforce/apex/recruitClassController.searchContacts';
import updateContactsWithRecruitClass from '@salesforce/apex/recruitClassController.updateContactsWithRecruitClass';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from "lightning/actions";

export default class RecruitClassAddMember extends LightningElement {
    isShowModal = true;
    @api recordId;
    columns = [
        { label: 'lastName', fieldName: 'LastName' },
        { label: 'FirstName', fieldName: 'FirstName' },        
        { label: 'Employee TINS', fieldName: 'TINS_NUMBER__c' }
    ];

    @track contacts =[];
    selectedContactIds = [];
    selectedIdSet = new Set();
    showDataTable = false;

    get getContacts(){
        const contacts = this.contacts || [];      
        if (this.searchKey && this.searchKey.trim() !== '') {
            const searchLower = this.searchKey.toLowerCase();
            return contacts.filter(contact =>
                contact.FirstName?.toLowerCase().includes(searchLower) ||
                contact.LastName?.toLowerCase().includes(searchLower) ||
                contact.TINS_NUMBER__c?.toLowerCase().includes(searchLower)
            );
        }

        if (this.selectedModel === 'File Upload') {
            const selectedSet = new Set(this.selectedContactIds);
            return contacts.filter( contact => selectedSet.has(contact.Id));
        }  
        return contacts;
    }

    handleContactSearch(event){
        const searchKey = event.target.value;
        searchContacts({ searchKey: searchKey, selectedModel: true  })
        .then(result => {
            this.contacts = [...result];
            this.showDataTable = true;
            this.selectedContactIds = Array.from(this.selectedIdSet);       
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const visibleIds = new Set(this.getContacts.map(r => r.Id));
        visibleIds.forEach(id => {
            this.selectedIdSet.delete(id);
        });

        selectedRows.forEach(row => {
            this.selectedIdSet.add(row.Id);
        });
        console.log('selectedRows '+this.selectedContactIds)
        this.selectedContactIds = Array.from(this.selectedIdSet); 
    }

    handleSubmit(event){
        console.log('recordId '+this.recordId);
        if(this.selectedContactIds.length === 0){
            this.showToast('Error', 'Please select at least one contact', 'error');
            return false;
        }
        updateContactsWithRecruitClass({
            recruitClassId: this.recordId,
            contactIds: this.selectedContactIds
        })
        .then(() => {
            this.showToast('Success', 'Recruit Class Updated Successfully', 'success');
            this.handleClose();
            /*setTimeout(() => {
                window.location.reload();
            }, 300);*/
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    handleClose() {
       this.dispatchEvent(new CloseActionScreenEvent());
    }
}