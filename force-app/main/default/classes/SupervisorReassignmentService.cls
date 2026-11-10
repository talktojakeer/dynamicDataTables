/**
 * Backend logic for the "Reassign Supervisor" screen (Jira MSADT-21).
 *
 * No custom object is used - reassignment state lives entirely on the
 * Account (Person Account) record itself, via the Reassignment_* fields.
 *
 * This is a supervisor-level, bulk reassignment: every Person Account whose
 * PersonReportsToId currently equals the chosen Primary Supervisor is moved
 * to the Temporary Supervisor for the Start/End Date window. Each moved
 * employee's own record keeps a snapshot of the primary and temporary
 * supervisor so SupervisorReassignmentRevertBatch can restore it later
 * without touching anyone it didn't move.
 */
public with sharing class SupervisorReassignmentService {

    public class ReassignRequest {
        public Id primarySupervisorId;
        public Id temporarySupervisorId;
        public String reason;
        public Date startDate;
        public Date endDate;
    }

    public class ReassignResult {
        public Boolean success = false;
        public String message;
        public Integer employeeCount = 0;
    }

    public static ReassignResult reassign(ReassignRequest req) {
        ReassignResult res = new ReassignResult();

        if (req.primarySupervisorId == null) {
            return fail(res, 'A primary supervisor must be selected.');
        }
        if (req.temporarySupervisorId == null) {
            return fail(res, 'A temporary supervisor must be selected.');
        }
        if (req.primarySupervisorId == req.temporarySupervisorId) {
            return fail(res, 'Temporary supervisor must be different from the primary supervisor.');
        }
        if (req.startDate == null || req.endDate == null) {
            return fail(res, 'Start Date and End Date are both required.');
        }
        if (req.endDate < req.startDate) {
            return fail(res, 'End Date cannot be before Start Date.');
        }
        if (String.isBlank(req.reason)) {
            return fail(res, 'A reason for reassignment is required.');
        }

        // PersonReportsToId is a lookup to Contact, so supervisors are matched
        // by their Person Contact Id, not their Account Id.
        Map<Id, Account> supervisors = new Map<Id, Account>([
            SELECT Id, PersonContactId FROM Account
            WHERE IsPersonAccount = true
              AND Id IN (:req.primarySupervisorId, :req.temporarySupervisorId)
        ]);
        Account primarySup = supervisors.get(req.primarySupervisorId);
        Account tempSup    = supervisors.get(req.temporarySupervisorId);
        if (primarySup == null || tempSup == null) {
            return fail(res, 'Both supervisors must be Person Accounts.');
        }

        List<Account> employees = [
            SELECT Id, PersonReportsToId, Reassignment_Active__c
            FROM Account
            WHERE IsPersonAccount = true AND PersonReportsToId = :primarySup.PersonContactId
        ];
        if (employees.isEmpty()) {
            return fail(res, 'No employees currently report to the selected primary supervisor.');
        }

        for (Account a : employees) {
            if (a.Reassignment_Active__c) {
                return fail(res, 'One or more employees under this primary supervisor already have an active reassignment. Revert it before creating a new one.');
            }
        }

        for (Account a : employees) {
            a.Reassignment_Active__c             = true;
            a.Reassignment_Primary_Supervisor__c  = req.primarySupervisorId;
            a.Reassignment_Temporary_Supervisor__c= req.temporarySupervisorId;
            a.Reassignment_Reason__c              = req.reason;
            a.Reassignment_Start_Date__c          = req.startDate;
            a.Reassignment_End_Date__c            = req.endDate;
            a.Reassignment_Reverted_Date__c       = null;
            if (req.startDate <= Date.today()) {
                a.PersonReportsToId = tempSup.PersonContactId;
            }
        }

        List<Database.SaveResult> results = Database.update(employees, false);
        Integer failed = 0;
        for (Database.SaveResult r : results) {
            if (!r.isSuccess()) failed++;
        }
        if (failed > 0) {
            res.employeeCount = employees.size() - failed;
            return fail(res, failed + ' of ' + employees.size() + ' employee(s) could not be updated. Check field-level security on the Reassignment fields and PersonReportsToId.');
        }

        res.success = true;
        res.employeeCount = employees.size();
        res.message = employees.size() + ' employee(s) reassigned to the temporary supervisor' +
            (req.startDate > Date.today() ? ' (effective ' + req.startDate.format() + ').' : '.');
        return res;
    }

    private static ReassignResult fail(ReassignResult res, String msg) {
        res.success = false;
        res.message = msg;
        return res;
    }
}