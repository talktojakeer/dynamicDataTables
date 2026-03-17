import { LightningElement, track, wire } from 'lwc';
import searchContacts from '@salesforce/apex/recruitClassController.searchContacts';
import findContacts from '@salesforce/apex/recruitClassController.findContacts';
import updateContactsWithRecruitClass from '@salesforce/apex/recruitClassController.updateContactsWithRecruitClass';
import recruitClassDupblicateCheck from '@salesforce/apex/recruitClassController.recruitClassDupblicateCheck';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { createRecord } from 'lightning/uiRecordApi';
import RECRUIT_CLASS from '@salesforce/schema/Account';
import CLASS_NAME from '@salesforce/schema/Account.Name';
import RECORDTYPEID from '@salesforce/schema/Account.RecordTypeId';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

export default class RecruitClassNewButton extends LightningElement {

    recruitClassName = '';
    selectedModel ='';
    showFileUpload = false;
    showManualSelection = false;
    showScreenOne = true;
    showDataTable = false;
    accountId;
    @track fileName;
    @track fileIcon = 'doctype:attachment';

    @track isOpen = true;
    @track contacts = [];
    @track selectedContactIds = [];
    selectedIdSet = new Set();

    columns = [
        { label: 'lastName', fieldName: 'lastName' },
        { label: 'FirstName', fieldName: 'FirstName' },        
        { label: 'Employee TINS', fieldName: 'TINS_NUMBER__C' }
    ];

    recordTypeId;

    @wire(getObjectInfo, { objectApiName: RECRUIT_CLASS })
    objectInfo({ data, error }) {
        if (data) {
            const rtis = data.recordTypeInfos;

            this.recordTypeId = Object.keys(rtis).find(rti =>
                rtis[rti].name === 'FAQP_Account'
            );
        }
    }

    get selectedCount() {
        return this.selectedIdSet.size;
    }

    @track isTooltipVisible = false;
    showTooltip() { this.isTooltipVisible = true;  }
    hideTooltip() { this.isTooltipVisible = false; }

    isDuplicateRecruitClass= true;
    async handleNameChange(event){        
        this.recruitClassName = event.target.value.toUpperCase();
        let formattedName = this.formatRecruitClass(this.recruitClassName);
        console.log('formattedName', formattedName)
        try {
            const isDuplicate = await recruitClassDupblicateCheck({ accName: formattedName });
            this.isDuplicateRecruitClass  = isDuplicate ? false : true;
        } catch (error) {
            let message = 'Unexpected error';
            if (error?.body?.message) {
                message = error.body.message;
                this.showToast('Error', message, 'error');
            }
        }
                
    }
    
    handlerecruitmodel(event){
        let clickedButton = event.currentTarget;
        let allButtonsInGrp = this.refs.dataViewBtnGrp.children;
        for (let btn of allButtonsInGrp) {
            btn.variant = 'neutral';
        }
        clickedButton.variant = 'brand';
        this.selectedModel = event.target.label;
    }

    get getContacts(){
        const contacts = this.contacts || [];

        if (this.searchKey && this.searchKey.trim() !== '') {
            const searchLower = this.searchKey.toLowerCase();
            return contacts.filter(contact =>
                contact.FirstName?.toLowerCase().includes(searchLower) ||
                contact.LastName?.toLowerCase().includes(searchLower) ||
                contact.Employee_TINS__c?.toLowerCase().includes(searchLower)
            );
        }

        if (this.selectedModel === 'File Upload') {
            const selectedSet = new Set(this.selectedContactIds);
            return contacts.filter( contact => selectedSet.has(contact.Id));
        }
        return contacts;
    }

    handleNext(){
        if(this.validationScreenOne()){
            if(this.selectedModel === 'Manual'){
                this.showFileUpload = false;
                this.showManualSelection = true;
                this.showScreenOne = false;
                this.showDataTable = true;
                this.handleSearchContacts('',false);
            }else if(this.selectedModel === 'File Upload'){
                this.showFileUpload = true;
                this.showManualSelection = false;
                this.showScreenOne = false;
                this.handleSearchContacts('',true);
            }            
        }
        
    }

    handleInsertRecruitClass() {
        const fields = {};
        let formattedName = this.formatRecruitClass(this.recruitClassName);
        fields[CLASS_NAME.fieldApiName] = formattedName;
        fields[RECORDTYPEID.fieldApiName] = this.recordTypeId;

        const recordInput = {
            apiName: RECRUIT_CLASS.objectApiName,
            fields
        };
        return createRecord(recordInput)
            .then(record => {
                this.accountId = record.id; 
                console.log('Created accountId:', this.accountId);
            })
            .catch(error => {
                console.error('Error creating record', error);
                this.handleError(error);
            });
    }

    formatRecruitClass(value) {
        if (!value) return value;
        value = value.replace(/[^a-zA-Z0-9]/g, '');

        value = value.toUpperCase();
        if (value.length >= 5) {
            value = value.substring(0, 1) + '-' + value.substring(1, 5);
        }
        return value;
    }

    handleError(error) {
        let message = 'Something went wrong';
        if(error?.body?.output?.errors && error?.body?.output?.errors?.length > 0){
            message = error?.body?.output?.errors[0].message;
        }else if(error?.body?.message){
            message = error?.body?.message;
        }else if(error?.message){
            message = error?.message;
        }
        this.showToast('Error', message, 'error');
    }

    async handleSubmit(){
        try{
            if(!this.validationScreenTwo()){
                return;
            }
            await this.handleInsertRecruitClass();
            if(this.accountId){
                await updateContactsWithRecruitClass({
                    recruitClassId: this.accountId,
                    contactIds: this.selectedContactIds
                })
                this.showToast('Success', 'Recruit Class Created Successfully', 'success');
                 this.dispatchEvent(new CustomEvent('refresh'));
                this.handleClose();
            }
            
        }catch(error){
            this.showToast('Error', error.body.message, 'error');
        }
    }

    validationScreenOne(){
        if(this.recruitClassName === ''){
            this.showToast('Error', 'Please enter Recruit Class Name', 'error');
            return false;
        }else if(this.selectedModel === ''){
            this.showToast('Error', 'Please select Recruit model', 'error');
            return false;
        }else if(!this.isDuplicateRecruitClass){
            this.showToast('Error', 'The following name already exists and cannot be used again', 'error');
            return false;           
        }else{
            const pattern = /^[A-Z]20[0-9]{2}$/;
            if(!pattern.test(this.recruitClassName)){
                this.showToast('Error', 'Please enter Recruit Class Name in format A 2026', 'error');
                return false;
            }
        }
        return true;
    }

    validationScreenTwo(){
        if(this.selectedModel === 'Manual' && this.selectedContactIds.length === 0){
            this.showToast('Error', 'Please select at least one contact', 'error');
            return false;
        }else if(this.selectedModel === 'File Upload' && !this.fileName){
            this.showToast('Error', 'Please provide excel file and Proceed', 'error');
            return false;
        }
        return true;
    }

    handleback(){
        this.showScreenOne = true;
        this.showDataTable = false;
        this.selectedContactIds = [];
        this.contacts = [];
        this.selectedIdSet.clear();
        this.fileName = '';
    }

    handleSearchContacts(searchKey, selectedModel){
        searchContacts({ searchKey: searchKey, selectedModel: selectedModel })
        .then(result => {
            console.log('result ',JSON.stringify(result));
            console.log('this.contacts ',JSON.stringify(this.contacts));
            this.contacts = [...result];
            this.selectedContactIds = Array.from(this.selectedIdSet);       
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }
    searchKey = '';
    handleContactSearch(event) {
        console.log(' handleContactSearch ')
        const searchKey = event.target.value;
        this.searchKey = searchKey;
        if (!searchKey || searchKey.length < 2) {
            this.contacts =[];
            this.handleSearchContacts('',false);            
            return;
        }            
        this.handleSearchContacts(searchKey,true);           
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
        
        this.selectedContactIds = Array.from(this.selectedIdSet); 
        console.log('selectedRows '+this.selectedContactIds)
    }

    handleUpload(event){
        console.log('File uploaded');
        const file = event.target.files[0];
        if (!file) return;        
        
        this.fileName = file.name;

        if (!file.name.toLowerCase().endsWith('.csv')) {
            this.showToast('Error', 'The File you have entered could not be accepted. Please try another file.', 'error');
            this.fileName = '';
            return;
        }
        
        const reader = new FileReader();
        reader.onload = () => {
            const csvText = reader.result;
            const contacts = this.parseCSV(csvText);

            if (!contacts.length) {
                this.showToast('Error', 'The file does not have contain required data', 'error');
                this.fileName = '';
                return;
            }

            findContacts({
                contactsData: contacts
            })
            .then(result => {
                this.contacts = [...result];
                this.contacts.forEach(row => {
                    this.selectedIdSet.add(row.Id);
                });
        
                this.selectedContactIds = Array.from(this.selectedIdSet);
                this.showDataTable = true;
                this.showManualSelection = true;
                this.showToast('Success', 'Excel File uploaded Successfully', 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body.message, 'error');
            });
            
        };
        
        reader.readAsText(file);
    }

    parseCSV(csvText) {
        const rows = csvText.split(/\r?\n/).filter(r => r.trim());
    
        const headers = this.parseCsvRow(rows[0]);
        console.log('headers', headers);
    
        const nameIdx   = headers.indexOf('Cadet Name');
        const tinsIdx   = headers.indexOf('TINS');
        const regionIdx = headers.indexOf('Region');
    
        if (nameIdx === -1 || tinsIdx === -1 || regionIdx === -1) {
            this.showToast(
                'Error',
                'CSV must contain Cadet Name, TINS, and Region columns',
                'error'
            );
            return [];
        }
    
        const contacts = [];
    
        for (let i = 1; i < rows.length; i++) {
            const cols = this.parseCsvRow(rows[i]);
    
            if (!cols[tinsIdx]) continue;
    
            contacts.push({
                name: cols[nameIdx]?.replace(/^"|"$/g, '').trim(),
                tins: cols[tinsIdx]?.replace(/^"|"$/g, '').trim(),
                region: cols[regionIdx]?.replace(/^"|"$/g, '').trim(),
            });
        }
    
        console.log('parsed contacts', JSON.stringify(contacts));
        return contacts;
    }

    parseCsvRow(row) {
        const cols = [];
        let current = '';
        let inQuotes = false;
    
        for (let i = 0; i < row.length; i++) {
            const char = row[i];
    
            if (char === '"' && row[i + 1] === '"') {
                current += '"';
                i++;
            } else if (char === '"') {
                inQuotes = !inQuotes;
            } else if (char === ',' && !inQuotes) {
                cols.push(current.trim());
                current = '';
            } else {
                current += char;
            }
        }
    
        cols.push(current.trim());
        return cols;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }

    handleClose() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCancel(){
        this.handleClose();
    }
    
}