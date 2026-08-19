/**
 * recruitClassControllerTest
 * ---------------------------------------------------------------------------
 * Covers recruitClassController: searchEmployees, linkEmployeesToRecruitClass
 * (ACR creation + dedup), findEmployeesByTins, getRecruitClasses, and
 * checkRecruitClassDuplicate.
 * ---------------------------------------------------------------------------
 */
@isTest
private class recruitClassControllerTest {

    @testSetup
    static void setup() {
        TestDataFactory.createPersonAccounts(3, false);
        TestDataFactory.createRecruitClass('A-2026');   // year name -> Recruit Class
        TestDataFactory.createRecruitClass('John Group'); // no year -> FTU Group
    }

    // ---- searchEmployees --------------------------------------------------
    @isTest
    static void testSearchEmployees() {
        Test.startTest();
        List<Account> all      = recruitClassController.searchEmployees('', false);
        List<Account> filtered = recruitClassController.searchEmployees('Person', true);
        Test.stopTest();
        System.assert(!all.isEmpty(), 'Unfiltered search should return employees');
        System.assert(!filtered.isEmpty(), 'Filtered search should find matching employees');
    }

    // ---- getRecruitClasses (returns both types) --------------------------
    @isTest
    static void testGetRecruitClasses() {
        Test.startTest();
        List<Account> classes = recruitClassController.getRecruitClasses();
        Test.stopTest();
        System.assert(classes.size() >= 2, 'Should return the FAQP_Account records');
    }

    // ---- checkRecruitClassDuplicate --------------------------------------
    @isTest
    static void testCheckRecruitClassDuplicate() {
        Test.startTest();
        Boolean dup   = recruitClassController.checkRecruitClassDuplicate('A-2026');
        Boolean noDup = recruitClassController.checkRecruitClassDuplicate('Z-9999');
        Boolean blank = recruitClassController.checkRecruitClassDuplicate('');
        Test.stopTest();
        System.assert(dup, 'Existing name should be a duplicate');
        System.assert(!noDup, 'New name should not be a duplicate');
        System.assert(!blank, 'Blank name should return false');
    }

    // ---- linkEmployeesToRecruitClass (ACR + dedup) -----------------------
    @isTest
    static void testLinkEmployees() {
        Account rc = [SELECT Id FROM Account WHERE Name = 'A-2026' LIMIT 1];
        List<Id> empIds = new List<Id>();
        for (Account a : [SELECT Id FROM Account WHERE IsPersonAccount = true]) empIds.add(a.Id);

        Test.startTest();
        // Link once, then link again - the second should dedup (no error, no dups)
        recruitClassController.linkEmployeesToRecruitClass(rc.Id, empIds);
        recruitClassController.linkEmployeesToRecruitClass(rc.Id, empIds);
        Test.stopTest();

        // Assert relationships exist (each person account also has its own direct ACR,
        // so just assert the indirect links to the recruit class were created)
        Integer count = [
            SELECT COUNT() FROM AccountContactRelation WHERE AccountId = :rc.Id
        ];
        System.assert(count >= empIds.size(), 'Each employee should be linked to the recruit class');
    }

    @isTest
    static void testLinkEmployees_validation() {
        Test.startTest();
        try {
            recruitClassController.linkEmployeesToRecruitClass(null, new List<Id>());
            System.assert(false, 'Missing inputs should throw');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }

    // ---- findEmployeesByTins ---------------------------------------------
    @isTest
    static void testFindEmployeesByTins() {
        Account p = [SELECT Id, TINS_NUMBER__c FROM Account WHERE IsPersonAccount = true LIMIT 1];
        // Match the exact stored value; strip any trailing ".0" a Decimal may render.
        String tinsStr = String.valueOf(p.TINS_NUMBER__c);
        if (tinsStr.endsWith('.0')) tinsStr = tinsStr.removeEnd('.0');
        List<Map<String, String>> data = new List<Map<String, String>>{
            new Map<String, String>{ 'tins' => tinsStr }
        };

        Test.startTest();
        List<Account> found = recruitClassController.findEmployeesByTins(data);
        Test.stopTest();

        System.assert(!found.isEmpty(), 'Should find the person account by TINS ' + tinsStr);
    }

    @isTest
    static void testFindEmployeesByTins_empty() {
        Test.startTest();
        try {
            recruitClassController.findEmployeesByTins(new List<Map<String, String>>());
            System.assert(false, 'Empty data should throw');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }
}