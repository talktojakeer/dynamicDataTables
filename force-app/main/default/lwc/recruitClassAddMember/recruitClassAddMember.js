import { LightningElement, track, api } from 'lwc';
import searchEmployees             from '@salesforce/apex/recruitClassController.searchEmployees';
import linkEmployeesToRecruitClass from '@salesforce/apex/recruitClassController.linkEmployeesToRecruitClass';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent }  from 'lightning/actions';

export default class RecruitClassAddMember extends LightningElement {

    @api recordId;
    @track employees         = [];
    @track selectedEmployeeIds = [];
    @track showDataTable     = false;

    isShowModal   = true;
    selectedIdSet = new Set();
    searchKey     = '';

    columns = [
        { label: 'Last name',     fieldName: 'LastName' },
        { label: 'First name',    fieldName: 'FirstName' },
        { label: 'Employee TINS', fieldName: 'TINS_NUMBER__c' }
    ];

    // --- Computed: returns filtered employees for the datatable --------------
    get visibleEmployees() {
        const list = this.employees || [];
        if (this.searchKey && this.searchKey.trim()) {
            const key = this.searchKey.toLowerCase();
            return list.filter(emp =>
                emp.FirstName?.toLowerCase().includes(key) ||
                emp.LastName?.toLowerCase().includes(key)  ||
                emp.TINS_NUMBER__c?.toLowerCase().includes(key)
            );
        }
        return list;
    }

    // --- Search employees as user types --------------------------------------
    handleContactSearch(event) {
        const key = event.target.value;
        this.searchKey = key;
        searchEmployees({ searchKey: key, filterByKey: Boolean(key) })
            .then(result => {
                this.employees           = [...result];
                this.showDataTable       = true;
                this.selectedEmployeeIds = Array.from(this.selectedIdSet);
            })
            .catch(error => {
                this.showToast('Error', this.reduceError(error), 'error');
            });
    }

    // --- Row selection - preserves selection across search queries -----------
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const visibleIds   = new Set(this.visibleEmployees.map(r => r.Id));
        visibleIds.forEach(id => this.selectedIdSet.delete(id));
        selectedRows.forEach(row => this.selectedIdSet.add(row.Id));
        this.selectedEmployeeIds = Array.from(this.selectedIdSet);
    }

    // --- Submit: link selected employees to the Recruit Class ----------------
    handleSubmit() {
        if (this.selectedEmployeeIds.length === 0) {
            this.showToast('Error', 'Please select at least one employee.', 'error');
            return;
        }
        linkEmployeesToRecruitClass({
            recruitClassId: this.recordId,
            employeeIds   : this.selectedEmployeeIds
        })
            .then(() => {
                this.showToast('Success', 'Recruit Class members updated successfully.', 'success');
                this.handleClose();
            })
            .catch(error => {
                this.showToast('Error', this.reduceError(error), 'error');
            });
    }

    // --- Utility -------------------------------------------------------------
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.message) return error.body.message;
        if (error?.message)       return error.message;
        return 'An unexpected error occurred.';
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }
}