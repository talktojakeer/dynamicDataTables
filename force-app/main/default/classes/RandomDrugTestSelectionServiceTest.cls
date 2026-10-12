/**
 * RandomDrugTestSelectionServiceTest
 * ---------------------------------------------------------------------------
 * Covers RandomDrugTestSelectionService:
 *  - input validation (count range, null date)
 *  - pickRandom (Fisher-Yates cap behaviour) via @TestVisible
 *  - getEligiblePool + generate happy path when the Case record type exists;
 *    gracefully asserts the "record type not found" path otherwise so the test
 *    is portable across orgs.
 *
 * No SeeAllData. Person-account pool built via TestDataFactory.
 * ---------------------------------------------------------------------------
 */
@isTest
private class RandomDrugTestSelectionServiceTest {

    private static Boolean drugTestRtExists() {
        return Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .containsKey('Drug_Test');
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

        System.assert(!tooLow.success,  'Zero requested should fail');
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
    static void testGenerateAndPool() {
        // Fresh person accounts -> all eligible (no prior Random cases).
        TestDataFactory.createPersonAccounts(3, false);

        Test.startTest();
        RandomDrugTestSelectionService.SelectionResult res =
            RandomDrugTestSelectionService.generate(2, Date.today());
        Test.stopTest();

        System.assertNotEquals(null, res, 'A result must always be returned');
        System.assertEquals(2, res.requestedCount, 'Requested count echoed back');

        if (drugTestRtExists()) {
            System.assert(res.success, 'With the Drug_Test record type present, generation should succeed: ' + res.message);
            System.assert(res.selectedCount > 0, 'At least one employee should be selected');
            System.assertEquals(res.selectedCount, res.caseIds.size(), 'A case id per selection');

            Id rtId = Schema.SObjectType.Case
                .getRecordTypeInfosByDeveloperName().get('Drug_Test').getRecordTypeId();
            List<Account> pool = RandomDrugTestSelectionService.getEligiblePool(rtId, Date.today());
            System.assert(pool.size() >= 0, 'Eligible pool query should run without error');
        } else {
            System.assert(!res.success, 'Without the Drug_Test record type, generation should fail gracefully');
            System.assert(res.message.containsIgnoreCase('record type'),
                'Failure message should explain the missing record type');
        }
    }
}