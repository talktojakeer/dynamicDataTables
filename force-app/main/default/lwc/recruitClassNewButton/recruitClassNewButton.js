import { LightningElement, track, wire, api } from 'lwc';
import searchEmployees             from '@salesforce/apex/recruitClassController.searchEmployees';
import findEmployeesByTins         from '@salesforce/apex/recruitClassController.findEmployeesByTins';
import linkEmployeesToRecruitClass from '@salesforce/apex/recruitClassController.linkEmployeesToRecruitClass';
import checkRecruitClassDuplicate  from '@salesforce/apex/recruitClassController.checkRecruitClassDuplicate';
import { ShowToastEvent }          from 'lightning/platformShowToastEvent';
import { createRecord }            from 'lightning/uiRecordApi';
import RECRUIT_CLASS               from '@salesforce/schema/Account';
import CLASS_NAME                  from '@salesforce/schema/Account.Name';
import RECORD_TYPE_ID              from '@salesforce/schema/Account.RecordTypeId';
import { getObjectInfo }           from 'lightning/uiObjectInfoApi';

const FAQP_ACCOUNT_RT = 'FAQP_Account';
const NAME_PATTERN    = /^[A-Z]20[0-9]{2}$/;

export default class RecruitClassNewButton extends LightningElement {

    // --- State ---------------------------------------------------------------
    recruitClassName    = '';
    @track groupType    = '';   // no default; user must choose
     @api newAccountId   = null;   // exposed as a Flow output (created group's Id)
    groupTypeOptions    = [
        { label: 'Recruit Class', value: 'Recruit Class' },
        { label: 'FTU Group',     value: 'FTU Group' }
    ];

    // Name field appears only after a Group Type is chosen.
    get showNameField() {
        return this.groupType === 'Recruit Class' || this.groupType === 'FTU Group';
    }

    get nameFieldLabel() {
        return this.groupType === 'FTU Group' ? 'FTU Group Name' : 'Recruit Class Name';
    }
    get isRecruitClassType() {
        return this.groupType === 'Recruit Class';
    }

    handleGroupTypeChange(event) {
        this.groupType = event.detail.value;
        // Re-run formatting/validation against the new type as the user switches.
        if (this.recruitClassName) {
            this.handleNameChange({ target: { value: this.recruitClassName } });
        }
    }
    selectedModel       = '';
    showFileUpload      = false;
    showManualSelection = false;
    showScreenOne       = true;
    showDataTable       = false;
    newAccountId        = null;
    searchKey           = '';

    @track fileName          = '';
    @track fileIcon          = 'doctype:attachment';
    @track isOpen            = true;
    @track employees         = [];
    @track selectedEmployeeIds = [];
    @track isTooltipVisible  = false;

    selectedIdSet          = new Set();
    isDuplicateClassName   = true;
    recordTypeId           = null;

    // --- Datatable columns ---------------------------------------------------
    columns = [
        { label: 'Last name',      fieldName: 'LastName' },
        { label: 'First name',     fieldName: 'FirstName' },
        { label: 'Employee TINS',  fieldName: 'TINS_NUMBER__c' }
    ];

    // --- Wire: resolve FAQP_Account record type Id --------------------------
    @wire(getObjectInfo, { objectApiName: RECRUIT_CLASS })
    handleObjectInfo({ data, error }) {
        if (data) {
            const rtMap = data.recordTypeInfos;
            this.recordTypeId = Object.keys(rtMap).find(
                id => rtMap[id].name === FAQP_ACCOUNT_RT
            );
        } else if (error) {
            this.showToast('Error', 'Failed to load record type info.', 'error');
        }
    }

    // --- Computed getters ----------------------------------------------------
    get selectedCount() {
        return this.selectedIdSet.size;
    }

    get visibleEmployees() {
        const list = this.employees || [];
        if (this.searchKey && this.searchKey.trim()) {
            const key = this.searchKey.toLowerCase();
            return list.filter(emp =>
                emp.FirstName?.toLowerCase().includes(key) ||
                emp.LastName?.toLowerCase().includes(key)  ||
               emp.TINS_NUMBER__c === Number(key)
            );
        }
        if (this.selectedModel === 'File Upload') {
            const selected = new Set(this.selectedEmployeeIds);
            return list.filter(emp => selected.has(emp.Id));
        }
        return list;
    }

    // --- Tooltip -------------------------------------------------------------
    showTooltip() { this.isTooltipVisible = true; }
    hideTooltip() { this.isTooltipVisible = false; }

    // --- Duplicate check on name change --------------------------------------
    async handleNameChange(event) {
        // Keep the name as typed (FTU names may be mixed case). The recruit-class
        // format/uppercase is applied only when it matches the letter+4-digit rule.
        this.recruitClassName = event.target.value;
        const formatted = this.formatClassName(this.recruitClassName);
        try {
            const isDuplicate = await checkRecruitClassDuplicate({ recruitClassName: formatted });
            this.isDuplicateClassName = !isDuplicate;
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        }
    }

    // --- Recruit model toggle ------------------------------------------------
    handleRecruitModelSelect(event) {
        const clicked = event.currentTarget;
        const buttons = this.refs.modelBtnGroup.children;
        for (const btn of buttons) {
            btn.variant = 'neutral';
        }
        clicked.variant = 'brand';
        this.selectedModel = event.target.label;
    }

    // --- Navigation ----------------------------------------------------------
    handleNext() {
        if (!this.validateScreenOne()) return;
        if (this.selectedModel === 'Manual') {
            this.showFileUpload      = false;
            this.showManualSelection = true;
            this.showScreenOne       = false;
            this.showDataTable       = true;
            this.loadEmployees('', false);
        } else if (this.selectedModel === 'File Upload') {
            this.showFileUpload      = true;
            this.showManualSelection = false;
            this.showScreenOne       = false;
            this.loadEmployees('', false);
        }
    }

    handleBack() {
        this.showScreenOne       = true;
        this.showDataTable       = false;
        this.selectedEmployeeIds = [];
        this.employees           = [];
        this.selectedIdSet.clear();
        this.fileName            = '';
    }

    // --- Create Recruit Class Account ----------------------------------------
    handleCreateRecruitClass() {
        const fields = {
            [CLASS_NAME.fieldApiName]    : this.formatClassName(this.recruitClassName),
            [RECORD_TYPE_ID.fieldApiName]: this.recordTypeId,
            FAQP_Group_Type__c           : this.groupType
        };
        return createRecord({ apiName: RECRUIT_CLASS.objectApiName, fields })
            .then(record => { this.newAccountId = record.id; })
            .catch(error => { throw error; });
    }

    // Recruit Class = exactly ONE letter followed by FOUR digits (e.g. A2026).
    // Anything else is an FTU Group and is kept exactly as the user typed it.
    isRecruitClassName(value) {
        const clean = (value || '').replace(/[^a-zA-Z0-9]/g, '');
        return /^[A-Za-z]\d{4}$/.test(clean);
    }

    formatClassName(value) {
        if (!value) return value;
        // Only apply the X-XXXX format when the user chose Recruit Class AND the
        // name matches the letter+4-digit rule. FTU groups keep the name as typed.
        if (this.isRecruitClassType && this.isRecruitClassName(value)) {
            const clean = value.replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
            return clean.substring(0, 1) + '-' + clean.substring(1, 5);
        }
        return value.trim();
    }

    // --- Submit --------------------------------------------------------------
    async handleSubmit() {
        if (!this.validateScreenTwo()) return;
        try {
            await this.handleCreateRecruitClass();
            if (this.newAccountId) {
                await linkEmployeesToRecruitClass({
                    recruitClassId: this.newAccountId,
                    employeeIds   : this.selectedEmployeeIds
                });
                this.showToast('Success', 'Recruit Class created successfully.', 'success');
                this.dispatchEvent(new CustomEvent('refresh'));
                this.handleClose();
            }
        } catch (error) {
            this.showToast('Error', this.reduceError(error), 'error');
        }
    }

    // --- Validation ----------------------------------------------------------
    validateScreenOne() {
        if (!this.groupType) {
            this.showToast('Error', 'Please select a Group Type.', 'error');
            return false;
        }
        if (!this.recruitClassName) {
            this.showToast('Error', 'Please enter a ' + this.nameFieldLabel + '.', 'error');
            return false;
        }
        if (!this.selectedModel) {
            this.showToast('Error', 'Please select a Recruit model.', 'error');
            return false;
        }
        if (!this.isDuplicateClassName) {
            this.showToast('Error', 'This name already exists.', 'error');
            return false;
        }
        // Recruit Class must be a single letter followed by 4 digits (e.g. A2026).
        // FTU Group allows any name, so this check is skipped for it.
        if (this.isRecruitClassType && !this.isRecruitClassName(this.recruitClassName)) {
            this.showToast('Error', 'Recruit Class name must be one letter followed by 4 digits (e.g. A2026).', 'error');
            return false;
        }
        return true;
    }

    validateScreenTwo() {
        if (this.selectedModel === 'Manual' && this.selectedEmployeeIds.length === 0) {
            this.showToast('Error', 'Please select at least one employee.', 'error');
            return false;
        }
        if (this.selectedModel === 'File Upload' && !this.fileName) {
            this.showToast('Error', 'Please upload a CSV file before submitting.', 'error');
            return false;
        }
        return true;
    }

    // --- Employee search -----------------------------------------------------
    loadEmployees(key, filterByKey) {
        searchEmployees({ searchKey: key, filterByKey: filterByKey })
            .then(result => {
                this.employees           = [...result];
                this.selectedEmployeeIds = Array.from(this.selectedIdSet);
            })
            .catch(error => {
                this.showToast('Error', this.reduceError(error), 'error');
            });
    }

    handleContactSearch(event) {
        const key = event.target.value;
        this.searchKey = key;
        if (!key || key.length < 2) {
            this.employees = [];
            this.loadEmployees('', false);
            return;
        }
        this.loadEmployees(key, true);
    }

    // --- Row selection -------------------------------------------------------
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const visibleIds   = new Set(this.visibleEmployees.map(r => r.Id));
        visibleIds.forEach(id => this.selectedIdSet.delete(id));
        selectedRows.forEach(row => this.selectedIdSet.add(row.Id));
        this.selectedEmployeeIds = Array.from(this.selectedIdSet);
    }

    // --- CSV file upload -----------------------------------------------------
    handleUpload(event) {
        const file = event.target.files[0];
        if (!file) return;
        this.fileName = file.name;

        if (!file.name.toLowerCase().endsWith('.csv')) {
            this.showToast('Error', 'Only CSV files are accepted.', 'error');
            this.fileName = '';
            return;
        }

        const reader = new FileReader();
        reader.onload = () => {
            const parsed = this.parseCsvFile(reader.result);
            if (!parsed.length) {
                this.fileName = '';
                return;
            }
            findEmployeesByTins({ employeesData: parsed })
                .then(result => {
                    this.employees = [...result];
                    this.employees.forEach(row => this.selectedIdSet.add(row.Id));
                    this.selectedEmployeeIds = Array.from(this.selectedIdSet);
                    this.showDataTable       = true;
                    this.showManualSelection = true;
                    this.showToast('Success', 'CSV uploaded successfully.', 'success');
                })
                .catch(error => {
                    this.showToast('Error', this.reduceError(error), 'error');
                });
        };
        reader.readAsText(file);
    }

    parseCsvFile(csvText) {
        const rows    = csvText.split(/\r?\n/).filter(r => r.trim());
        const headers = this.parseCsvRow(rows[0]);

        const nameIdx   = headers.indexOf('Cadet Name');
        const tinsIdx   = headers.indexOf('TINS');
        const regionIdx = headers.indexOf('Region');

        if (nameIdx === -1 || tinsIdx === -1 || regionIdx === -1) {
            this.showToast('Error', 'CSV must have columns: Cadet Name, TINS, Region.', 'error');
            return [];
        }

        const result = [];
        for (let i = 1; i < rows.length; i++) {
            const cols = this.parseCsvRow(rows[i]);
            if (!cols[tinsIdx]) continue;
            result.push({
                name  : cols[nameIdx]?.replace(/^"|"$/g, '').trim(),
                tins  : cols[tinsIdx]?.replace(/^"|"$/g, '').trim(),
                region: cols[regionIdx]?.replace(/^"|"$/g, '').trim()
            });
        }
        return result;
    }

    parseCsvRow(row) {
        const cols = [];
        let current  = '';
        let inQuotes = false;
        for (let i = 0; i < row.length; i++) {
            const ch = row[i];
            if (ch === '"' && row[i + 1] === '"') { current += '"'; i++; }
            else if (ch === '"')                   { inQuotes = !inQuotes; }
            else if (ch === ',' && !inQuotes)      { cols.push(current.trim()); current = ''; }
            else                                   { current += ch; }
        }
        cols.push(current.trim());
        return cols;
    }

    // --- Utility -------------------------------------------------------------
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (typeof error === 'string') return error;
        if (error?.body?.output?.errors?.length) return error.body.output.errors[0].message;
        if (error?.body?.message) return error.body.message;
        if (error?.message)       return error.message;
        return 'An unexpected error occurred.';
    }

    handleClose() {
        this.isOpen = false;
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleCancel() {
        this.handleClose();
    }
}