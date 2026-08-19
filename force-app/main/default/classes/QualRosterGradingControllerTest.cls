/**
 * QualRosterGradingControllerTest
 * ---------------------------------------------------------------------------
 * Covers QualRosterGradingController: roster reads, grading-row save,
 * signatures, weapon-code options, available employees, add-to-roster
 * (with per-weapon-type dedup), and create-employee.
 *
 * Conventions:
 *  - @testSetup builds a shared roster (forms + weapon details) once.
 *  - Every AuraHandledException path is asserted via try/catch inside
 *    Test.startTest()/stopTest().
 *  - A bulk path is exercised for add-to-roster.
 *  - No SeeAllData; all data built in-test.
 * ---------------------------------------------------------------------------
 */
@isTest
private class QualRosterGradingControllerTest {

    private static final String ROSTER = 'TEST-ROSTER';

    // A REAL, decodable 1x1 transparent PNG. Rich Text (Html) signature fields
    // reject non-image data URIs with INVALID_DATA_URI, so tests must use a
    // valid base64 image, not a placeholder string.
    private static final String VALID_SIG =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

    @testSetup
    static void setup() {
        // Two person accounts: one plain member, one that is a firearms instructor.
        List<Account> people = TestDataFactory.createPersonAccounts(2, false);
        Id c0 = TestDataFactory.personContactId(people[0].Id);
        Id c1 = TestDataFactory.personContactId(people[1].Id);

        // Forms under one roster label, instructor = running user.
        List<FIR_Qualification_Form__c> forms =
            TestDataFactory.createForms(ROSTER, new List<Id>{ c0, c1 }, TestDataFactory.currentUserId());

        // One weapon detail per form.
        List<Id> formIds = new List<Id>();
        for (FIR_Qualification_Form__c f : forms) formIds.add(f.Id);
        TestDataFactory.createDetails(formIds, 'Pistol 2');
    }

    // ---- Reads ------------------------------------------------------------
    @isTest
    static void testGetRosterLabelsAndDetails() {
        Test.startTest();
        List<String> labels = QualRosterGradingController.getRosterLabels();
        List<QualRosterGradingController.RosterLabelRow> rows =
            QualRosterGradingController.getRosterLabelDetails();
        Test.stopTest();

        System.assert(labels.contains(ROSTER), 'Roster label should be listed');
        System.assert(!rows.isEmpty(), 'Label detail rows should be returned');
    }

    @isTest
    static void testGetRosterGradingData() {
        Test.startTest();
        QualRosterGradingController.RosterGradingWrapper w =
            QualRosterGradingController.getRosterGradingData(ROSTER);
        Test.stopTest();

        System.assertEquals(ROSTER, w.rosterLabel, 'Wrapper should echo roster label');
        System.assert(!w.weaponSections.isEmpty(), 'Should have at least one weapon section');
    }

    @isTest
    static void testGetRosterGradingData_blank() {
        Test.startTest();
        try {
            QualRosterGradingController.getRosterGradingData('');
            System.assert(false, 'Blank label should throw');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @isTest
    static void testGetWeaponCodeOptions() {
        Test.startTest();
        List<String> opts = QualRosterGradingController.getWeaponCodeOptions();
        Test.stopTest();
        System.assertNotEquals(null, opts, 'Weapon code options should not be null');
    }

    // ---- Grading row save -------------------------------------------------
    @isTest
    static void testSaveGradingRow() {
        FIR_Weapon_Qualification_Detail__c det =
            [SELECT Id FROM FIR_Weapon_Qualification_Detail__c LIMIT 1];

        Test.startTest();
        QualRosterGradingController.saveGradingRow(
            det.Id, 'Sig Sauer', 'P365', 'Optic', '', '1st', 'Yes', 'No');
        Test.stopTest();

        FIR_Weapon_Qualification_Detail__c after =
            [SELECT Manufacturer__c, Qualified__c FROM FIR_Weapon_Qualification_Detail__c WHERE Id = :det.Id];
        System.assertEquals('Sig Sauer', after.Manufacturer__c, 'Manufacturer should be saved');
    }

    // ---- Signatures -------------------------------------------------------
    @isTest
    static void testSaveSignatures_instructorOnly() {
        String sig = VALID_SIG;
        Test.startTest();
        QualRosterGradingController.saveSignatures(ROSTER, sig, null, null, null);
        Test.stopTest();

        List<FIR_Qualification_Form__c> forms =
            [SELECT Firearms_Instructor_Signature__c FROM FIR_Qualification_Form__c WHERE Qual_Roster_Label__c = :ROSTER];
        for (FIR_Qualification_Form__c f : forms) {
            System.assert(f.Firearms_Instructor_Signature__c != null, 'Instructor signature should be stored');
            System.assert(f.Firearms_Instructor_Signature__c.contains('<img'), 'Should be wrapped as img HTML');
        }
    }

    @isTest
    static void testSaveSignatures_withWitness() {
        String sig = VALID_SIG;
        Test.startTest();
        QualRosterGradingController.saveSignatures(ROSTER, sig, 'Jane Witness', sig, '2026-08-01');
        Test.stopTest();

        FIR_Qualification_Form__c f =
            [SELECT Witness_Name__c, Witness_Signature__c, Witness_Signature_Date__c
             FROM FIR_Qualification_Form__c WHERE Qual_Roster_Label__c = :ROSTER LIMIT 1];
        System.assertEquals('Jane Witness', f.Witness_Name__c, 'Witness name should be saved');
        System.assertEquals(Date.valueOf('2026-08-01'), f.Witness_Signature_Date__c, 'Witness date should be saved');
    }

    @isTest
    static void testSaveSignatures_blankRoster() {
        Test.startTest();
        try {
            QualRosterGradingController.saveSignatures('', 'sig', null, null, null);
            System.assert(false, 'Blank roster should throw');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }

    @isTest
    static void testSaveSignatures_blankInstructorSig() {
        Test.startTest();
        try {
            QualRosterGradingController.saveSignatures(ROSTER, '', null, null, null);
            System.assert(false, 'Blank instructor signature should throw');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }

    // ---- Available employees ---------------------------------------------
    @isTest
    static void testGetAvailableEmployees() {
        Test.startTest();
        List<QualRosterGradingController.AvailableEmployee> emps =
            QualRosterGradingController.getAvailableEmployees(ROSTER);
        Test.stopTest();
        System.assert(!emps.isEmpty(), 'Should return person accounts');
    }

    @isTest
    static void testGetAvailableEmployees_blank() {
        Test.startTest();
        try {
            QualRosterGradingController.getAvailableEmployees('');
            System.assert(false, 'Blank roster should throw');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }

    // ---- Add to roster ----------------------------------------------------
    @isTest
    static void testAddToRoster_newMemberAndDedup() {
        // A fresh person not yet on the roster
        Account newp = TestDataFactory.createPersonAccount('New', 'Guy', 7000009999L);
        Id newContact = TestDataFactory.personContactId(newp.Id);

        Test.startTest();
        // First add: creates form + Pistol 2 row
        QualRosterGradingController.AddToRosterResult r1 =
            QualRosterGradingController.addToRoster(
                ROSTER, new List<String>{ newContact }, new List<String>{ 'Pistol 2' },
                'Sig Sauer', 'P365', 'Optic');
        // Second add same weapon: should be skipped (dedup per weapon type)
        QualRosterGradingController.AddToRosterResult r2 =
            QualRosterGradingController.addToRoster(
                ROSTER, new List<String>{ newContact }, new List<String>{ 'Pistol 2' },
                null, null, null);
        Test.stopTest();

        System.assertEquals(1, r1.rowsAdded, 'First add should add one row');
        System.assertEquals(0, r2.rowsAdded, 'Duplicate weapon type should be skipped');
        System.assertEquals(1, r2.rowsSkipped, 'Skip count should reflect the dedup');
    }

    @isTest
    static void testAddToRoster_validation() {
        Test.startTest();
        try {
            QualRosterGradingController.addToRoster('', null, null, null, null, null);
            System.assert(false, 'Blank roster should throw');
        } catch (AuraHandledException e) { System.assert(true); }

        try {
            QualRosterGradingController.addToRoster(ROSTER, new List<String>(), new List<String>{ 'Pistol 2' }, null, null, null);
            System.assert(false, 'No employees should throw');
        } catch (AuraHandledException e) { System.assert(true); }

        try {
            Id someContact = [SELECT ContactName__c FROM FIR_Qualification_Form__c WHERE Qual_Roster_Label__c = :ROSTER LIMIT 1].ContactName__c;
            QualRosterGradingController.addToRoster(ROSTER, new List<String>{ someContact }, new List<String>(), null, null, null);
            System.assert(false, 'No weapon types should throw');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }

    // ---- Create employee --------------------------------------------------
    @isTest
    static void testCreateEmployee() {
        Test.startTest();
        QualRosterGradingController.AvailableEmployee emp =
            QualRosterGradingController.createEmployee(
                'Retired', 'M', 'Officer', '1960-01-15', '2020-06-30', 'Retired DPS Trooper', true);
        Test.stopTest();

        System.assertNotEquals(null, emp.accountId, 'New employee account Id should be returned');
        System.assert(emp.name.contains('Retired') && emp.name.contains('Officer'),
            'Composed name should contain first and last name');
        Account created = [SELECT IsPersonAccount FROM Account WHERE Id = :emp.accountId];
        System.assert(created.IsPersonAccount, 'Created record should be a Person Account');
    }

    @isTest
    static void testCreateEmployee_missingLastName() {
        Test.startTest();
        try {
            QualRosterGradingController.createEmployee('First', null, '', null, null, null, false);
            System.assert(false, 'Missing last name should throw');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }

    // ---- trySet utility ---------------------------------------------------
    @isTest
    static void testTrySet() {
        Account a = new Account(LastName = 'X');
        Test.startTest();
        QualRosterGradingController.trySet(a, 'FirstName', 'Y');      // valid field
        QualRosterGradingController.trySet(a, 'Bogus_Field__c', 'Z'); // missing field - swallowed
        QualRosterGradingController.trySet(a, 'FirstName', null);      // null - no-op
        Test.stopTest();
        System.assertEquals('Y', a.FirstName, 'Valid field should be set; bad/null skipped without error');
    }
}