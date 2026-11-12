
public with sharing class RandomDrugTestSelectionService {

    // ===== ADJUST THESE TO MATCH THE ORG METADATA =====
    @TestVisible static final String CASE_RT_DEV_NAME = 'MSA_Drug_Test';
    @TestVisible static final String TEST_TYPE_RANDOM = 'Random';
    @TestVisible static final String STATUS_NEW        = 'New';
    @TestVisible static final String STATUS_COMPLETED  = 'Completed';
    @TestVisible static final String DEFAULT_PRIORITY  = 'Medium';
    static final Integer MAX_SELECTION = 1000;   // keep in sync with the flow validation rule
    // ===================================================

    public class SelectionResult {
        public Boolean success = false;
        public String message;
        public Integer requestedCount = 0;
        public Integer eligibleCount = 0;
        public Integer selectedCount = 0;
        public List<String> caseIds = new List<String>();
    }

    public static SelectionResult generate(Integer requested, Date selectionDate) {
        SelectionResult res = new SelectionResult();
        res.requestedCount = requested;

        if (requested == null || requested < 1 || requested > MAX_SELECTION) {
            return fail(res, 'Number of employees must be between 1 and ' + MAX_SELECTION + '.');
        }
        if (selectionDate == null) {
            return fail(res, 'Selection date is required.');
        }

        Schema.RecordTypeInfo rtInfo = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get(CASE_RT_DEV_NAME);
        if (rtInfo == null) {
            return fail(res, 'Case record type "' + CASE_RT_DEV_NAME + '" was not found.');
        }
        Id rtId = rtInfo.getRecordTypeId();

        Set<String> eligibleJobCodes = getEligibleJobCodes();
        if (eligibleJobCodes.isEmpty()) {
            return fail(res, 'No active, random-eligible job codes are configured.');
        }

        List<Account> pool = getEligiblePool(eligibleJobCodes);
        res.eligibleCount = pool.size();
        if (pool.isEmpty()) {
            return fail(res, 'No eligible employees are available for random selection.');
        }

        List<Account> picked = pickRandom(pool, requested);

        List<Case> cases = new List<Case>();
        for (Account a : picked) {
            cases.add(new Case(
                RecordTypeId       = rtId,
                AccountId          = a.Id,
                ContactId          = a.PersonContactId,
                Drug_Test_Type__c  = TEST_TYPE_RANDOM,
                Status             = STATUS_NEW,
                Priority           = DEFAULT_PRIORITY,
                Selection_Date__c  = selectionDate,
                Subject            = 'Random Drug Test - ' + a.Name
            ));
        }

        try {
            insert cases; // all-or-none: counts below are always accurate
        } catch (DmlException e) {
            return fail(res, 'Could not create drug test cases: ' + e.getDmlMessage(0));
        }

        for (Case c : cases) {
            res.caseIds.add(c.Id);
        }
        res.selectedCount = cases.size();
        res.success = true;
        res.message = (cases.size() < requested)
            ? 'Only ' + cases.size() + ' eligible employee(s) were available, so all of them were selected (requested ' + requested + ').'
            : cases.size() + ' employee(s) randomly selected.';

                // Ask each supervisor to confirm availability. An email problem must never undo the selection.
        try {
            AvailabilityRequestService.RequestResult ar = AvailabilityRequestService.sendRequests(res.caseIds);
            res.message += ' Availability requests sent to ' + ar.supervisorsEmailed + ' supervisor(s)';
            res.message += ar.casesSkipped > 0
                ? '; ' + ar.casesSkipped + ' employee(s) skipped (no supervisor/email or send failed).'
                : '.';
        } catch (Exception e) {
            res.message += ' Availability emails could not be sent: ' + e.getMessage();
        }
        return res;
    }

    @TestVisible
    private static Set<String> getEligibleJobCodes() {
        Set<String> codes = new Set<String>();
        for (Job_Code__c jc : [
            SELECT Job_Code__c
            FROM Job_Code__c
            WHERE Active__c = true
              AND Eligible_For_Random_Testing__c = true
              AND Job_Code__c != null
        ]) {
            codes.add(jc.Job_Code__c);
        }
        return codes;
    }

    @TestVisible
    private static List<Account> getEligiblePool(Set<String> eligibleJobCodes) {
        return [
            SELECT Id, Name, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
              AND Job_Code__c IN :eligibleJobCodes
              AND Exclude_From_Selection__c = false
              AND On_Leave__c = false
              AND Has_Open_Absence_Case__c = false
              AND (Pool_Hold_Until__c = null OR Pool_Hold_Until__c < TODAY)
            LIMIT 50000
        ];
    }

    // Partial Fisher-Yates: only shuffles as many positions as we need to take.
    @TestVisible
    private static List<Account> pickRandom(List<Account> pool, Integer requested) {
        Integer take = Math.min(requested, pool.size());
        for (Integer i = 0; i < take; i++) {
            Integer j = i + Math.abs(Math.mod(Crypto.getRandomInteger(), pool.size() - i));
            Account tmp = pool[i];
            pool[i] = pool[j];
            pool[j] = tmp;
        }
        List<Account> picked = new List<Account>();
        for (Integer i = 0; i < take; i++) {
            picked.add(pool[i]);
        }
        return picked;
    }

    private static SelectionResult fail(SelectionResult res, String msg) {
        res.success = false;
        res.message = msg;
        return res;
    }
}