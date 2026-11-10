/**
 * Daily scheduled batch: for every Account with Reassignment_Active__c = true
 * whose Reassignment_End_Date__c has passed, restores PersonReportsToId to
 * Reassignment_Primary_Supervisor__c - but only if PersonReportsToId still
 * equals Reassignment_Temporary_Supervisor__c, i.e. nothing else moved this
 * employee in the meantime. Clears Reassignment_Active__c either way once
 * the end date has passed, and stamps Reassignment_Reverted_Date__c.
 *
 * Schedule once, e.g. from anonymous Apex:
 *   System.schedule('Supervisor Reassignment Daily Revert', '0 10 0 * * ?',
 *                    new SupervisorReassignmentRevertBatch());
 */
public with sharing class SupervisorReassignmentRevertBatch implements Database.Batchable<SObject>, Schedulable {

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, PersonReportsToId, Reassignment_Primary_Supervisor__c, Reassignment_Temporary_Supervisor__c,
                   Reassignment_Primary_Supervisor__r.PersonContactId, Reassignment_Temporary_Supervisor__r.PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
              AND Reassignment_Active__c = true
              AND Reassignment_End_Date__c < TODAY
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        for (Account a : scope) {
            // PersonReportsToId references a Contact, so compare Person Contact Ids.
            if (a.PersonReportsToId == a.Reassignment_Temporary_Supervisor__r.PersonContactId) {
                a.PersonReportsToId = a.Reassignment_Primary_Supervisor__r.PersonContactId;
            }
            // else: someone else changed this employee's supervisor during the
            // window - leave PersonReportsToId alone, but still close out the
            // reassignment fields below so it doesn't get picked up again.
            a.Reassignment_Active__c = false;
            a.Reassignment_Reverted_Date__c = Date.today();
        }
        Database.update(scope, false);
    }

    public void finish(Database.BatchableContext bc) {
        // Hook for notification/logging if needed later.
    }

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new SupervisorReassignmentRevertBatch(), 200);
    }
}