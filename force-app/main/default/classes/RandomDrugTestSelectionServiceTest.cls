/**
 * RandomDrugTestSelectionServiceTest
 * ---------------------------------------------------------------------------
 * Covers RandomDrugTestSelectionService against the real schema:
 *  - input validation (count range, null date)
 *  - pickRandom (Fisher-Yates cap behaviour) via @TestVisible
 *  - getEligibleJobCodes: only Active + Eligible_For_Random_Testing job codes
 *  - getEligiblePool / generate: Job Code match plus Rule 1/2/3 + override fields
 *  - gracefully asserts the "record type not found" path if MSA_Drug_Test
 *    isn't deployed in this org, so the test is still portable
 *
 * No SeeAllData. Person-account pool built via TestDataFactory + direct field sets,
 * since Job Code matching is now a plain text-value match (Account.Job_Code__c is
 * Text, not a lookup).
 * ---------------------------------------------------------------------------
 */
@isTest
private class RandomDrugTestSelectionServiceTest {

    private static Boolean recordTypeExists() {
        return Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .containsKey('MSA_Drug_Test');
    }

    private static Job_Code__c makeJobCode(String code, Boolean active, Boolean eligible) {
        Job_Code__c jc = new Job_Code__c(
            Name = 'Test ' + code,
            Job_Code__c = code,
            Job_Title__c = 'Test Title',
            Division__c = 'TOD',
            Active__c = active,
            Eligible_For_Random_Testing__c = eligible
        );
        insert jc;
        return jc;
    }

    private static Account makeEmployee(String lastName, String jobCode) {
        Account a = TestDataFactory.buildPersonAccount('Test', lastName, 7100000000L + Math.mod(Math.abs(Crypto.getRandomInteger()), 999999));
        a.Job_Code__c = jobCode;
        insert a;
        return a;
    }

    @isTest
    static void testValidation() {
        Test.startTest();
        RandomDrugTestSelectionService.SelectionResult tooLow =
            RandomDrugTestSelectionService.generate(0, Date.today());
        RandomDrugTestSelectionService.SelectionResult tooHigh =
            RandomDrugTestSelectionService.generate(1001, Date.today());
        RandomDrugTestSelectionService.SelectionResult nullCount =
            RandomDrugTestSelectionService.generate(null, Date.today());
        RandomDrugTestSelectionService.SelectionResult nullDate =
            RandomDrugTestSelectionService.generate(5, null);
        Test.stopTest();

        System.assert(!tooLow.success, 'Zero requested should fail');
        System.assert(!tooHigh.success, 'Over max requested should fail');
        System.assert(!nullCount.success, 'Null count should fail');
        System.assert(!nullDate.success, 'Null date should fail');
        System.assert(nullDate.message.containsIgnoreCase('date'),
            'Null date message should mention the date');
    }

    @isTest
    static void testPickRandom() {
        List<Account> pool = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            pool.add(new Account(Name = 'Pool ' + i));
        }

        Test.startTest();
        List<Account> three = RandomDrugTestSelectionService.pickRandom(pool.clone(), 3);
        List<Account> capped = RandomDrugTestSelectionService.pickRandom(pool.clone(), 10);
        Test.stopTest();

        System.assertEquals(3, three.size(), 'Should take exactly the requested count');
        System.assertEquals(5, capped.size(), 'Should cap at pool size when requested exceeds it');
    }

    @isTest
    static void testGetEligibleJobCodes() {
        makeJobCode('JC-ACTIVE-ELIGIBLE', true, true);
        makeJobCode('JC-ACTIVE-NOT-ELIGIBLE', true, false);
        makeJobCode('JC-INACTIVE-ELIGIBLE', false, true);

        Test.startTest();
        Set<String> codes = RandomDrugTestSelectionService.getEligibleJobCodes();
        Test.stopTest();

        System.assert(codes.contains('JC-ACTIVE-ELIGIBLE'), 'Active + eligible code should be included');
        System.assert(!codes.contains('JC-ACTIVE-NOT-ELIGIBLE'), 'Active-but-not-eligible code should be excluded');
        System.assert(!codes.contains('JC-INACTIVE-ELIGIBLE'), 'Inactive code should be excluded even if eligible');
    }

    @isTest
    static void testGenerateHonoursJobCodeAndOverrideFields() {
        Job_Code__c eligible = makeJobCode('JC-ELIGIBLE', true, true);
        Job_Code__c notEligible = makeJobCode('JC-NOT-ELIGIBLE', true, false);

        Account qualifies   = makeEmployee('Qualifies', eligible.Job_Code__c);
        Account wrongCode   = makeEmployee('WrongCode', notEligible.Job_Code__c);

        Account onLeave = makeEmployee('OnLeave', eligible.Job_Code__c);
        onLeave.On_Leave__c = true;

        Account openAbsence = makeEmployee('OpenAbsence', eligible.Job_Code__c);
        openAbsence.Has_Open_Absence_Case__c = true;

        Account onHold = makeEmployee('OnHold', eligible.Job_Code__c);
        onHold.Pool_Hold_Until__c = Date.today().addDays(30);

        Account excluded = makeEmployee('Excluded', eligible.Job_Code__c);
        excluded.Exclude_From_Selection__c = true;

        update new List<Account>{ onLeave, openAbsence, onHold, excluded };

        Test.startTest();
        RandomDrugTestSelectionService.SelectionResult res =
            RandomDrugTestSelectionService.generate(10, Date.today());
        Test.stopTest();

        System.assertNotEquals(null, res, 'A result must always be returned');

        if (recordTypeExists()) {
            System.assert(res.success, 'With MSA_Drug_Test present, generation should succeed: ' + res.message);
            // Only "qualifies" should be in the eligible pool.
            System.assertEquals(1, res.eligibleCount,
                'Only the one fully-eligible employee should be in the pool: ' + res.message);
            System.assertEquals(1, res.selectedCount);
        } else {
            System.assert(!res.success, 'Without MSA_Drug_Test, generation should fail gracefully');
            System.assert(res.message.containsIgnoreCase('record type'),
                'Failure message should explain the missing record type');
        }
    }

    @isTest
    static void testNoEligibleJobCodesConfigured() {
        // No Job_Code__c records at all.
        Test.startTest();
        RandomDrugTestSelectionService.SelectionResult res =
            RandomDrugTestSelectionService.generate(5, Date.today());
        Test.stopTest();

        System.assert(!res.success, 'No eligible job codes configured should fail gracefully');
        System.assert(res.message.containsIgnoreCase('job code'));
    }
}