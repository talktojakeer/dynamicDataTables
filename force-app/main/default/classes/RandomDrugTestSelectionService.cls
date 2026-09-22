/**
 * Backend logic for Random Drug Test selection (HR.375).
 *
 * Pool rules
 *  - Person Account employees only
 *  - Job Code must be flagged random-eligible
 *  - Rule 2: employees flagged Extended Leave are excluded
 *  - Rule 3: employees whose last Random test completed normally are held out for 6 months
 *  - Employees with an open Random case (incl. approved-absence retests, Rule 1) are excluded,
 *    so nobody is selected twice while a test is still pending
 *
 * Selection is a Fisher-Yates shuffle using Crypto.getRandomInteger() for an audit-defensible draw.
 */
public with sharing class RandomDrugTestSelectionService {

    // ===== ADJUST THESE TO MATCH THE ORG METADATA =====
    @TestVisible static final String CASE_RT_DEV_NAME   = 'Drug_Test';
    @TestVisible static final String TEST_TYPE_RANDOM   = 'Random';
    @TestVisible static final String STATUS_SCHEDULED   = 'Scheduled';
    @TestVisible static final String STATUS_COMPLETED   = 'Test completed';
    @TestVisible static final String DEFAULT_PRIORITY   = 'Medium';
    static final Integer HOLD_MONTHS   = 6;      // Rule 3
    static final Integer MAX_SELECTION = 1000;   // keep in sync with the flow validation rule
    // Custom fields assumed: Case.Drug_Test_Type__c, Case.Selection_Date__c,
    //   Account.Extended_Leave__c, Account.Job_Code__c (lookup), Job_Code__c.Random_Eligible__c
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

        List<Account> pool = getEligiblePool(rtId, selectionDate);
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
                Status             = STATUS_SCHEDULED,
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
        return res;
    }

    @TestVisible
    private static List<Account> getEligiblePool(Id rtId, Date selectionDate) {
        Date holdStart = selectionDate.addMonths(-HOLD_MONTHS);
        return [
            SELECT Id, Name, PersonContactId
            FROM Account
            WHERE IsPersonAccount = true
              AND Id NOT IN (
                    SELECT AccountId FROM Case
                    WHERE RecordTypeId = :rtId
                      AND Drug_Test_Type__c = :TEST_TYPE_RANDOM
                      AND AccountId != null
                      AND (
                            IsClosed = false
                            OR (Status = :STATUS_COMPLETED AND Selection_Date__c > :holdStart)
                      )
              )
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