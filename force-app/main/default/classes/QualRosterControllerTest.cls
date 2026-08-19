/**
 * QualRosterControllerTest
 * ---------------------------------------------------------------------------
 * Covers QualRosterController: search (recruit class + contacts, users),
 * getContactMembers, checkRosterLabelExists, and addToRoster (JSON payload ->
 * FIR forms + weapon details).
 * ---------------------------------------------------------------------------
 */
@isTest
private class QualRosterControllerTest {

    @testSetup
    static void setup() {
        // Person accounts (searchable employees) + a business account (recruit class)
        List<Account> ppl = TestDataFactory.createPersonAccounts(3, false);
        Account rc = TestDataFactory.createRecruitClass('A-2026');

        // Link one person to the recruit class via ACR so getContactMembers'
        // loop body executes (coverage for the recruitClassId branch).
        Id c0 = TestDataFactory.personContactId(ppl[0].Id);
        TestDataFactory.linkContactToAccount(rc.Id, c0);
    }

    // ---- Search -----------------------------------------------------------
    @isTest
    static void testSearchRecruitClassAndContacts() {
        Test.startTest();
        QualRosterController.SearchResultWrapper w =
            QualRosterController.searchRecruitClassAndContacts('Test');   // matches person "Test PersonN"
        QualRosterController.SearchResultWrapper classHit =
            QualRosterController.searchRecruitClassAndContacts('A-2026'); // matches recruit class
        Test.stopTest();

        System.assert(!w.contacts.isEmpty(), 'Should find person-account contacts');
        System.assert(!classHit.recruitClasses.isEmpty(), 'Should find recruit class by name');
    }

    @isTest
    static void testSearch_blankReturnsEmpty() {
        Test.startTest();
        QualRosterController.SearchResultWrapper w =
            QualRosterController.searchRecruitClassAndContacts('');
        Test.stopTest();
        System.assert(w.recruitClasses.isEmpty() && w.contacts.isEmpty(), 'Blank key returns empty wrapper');
    }

    @isTest
    static void testSearchUsers() {
        // The running user is guaranteed to exist and be active
        String namePart = UserInfo.getLastName();
        Test.startTest();
        List<QualRosterController.UserResult> hits = QualRosterController.searchUsers(namePart);
        List<QualRosterController.UserResult> empty = QualRosterController.searchUsers('');
        Test.stopTest();
        System.assert(!hits.isEmpty(), 'Should find at least the running user');
        System.assert(empty.isEmpty(), 'Blank key returns empty list');
    }

    // ---- Roster label existence ------------------------------------------
    @isTest
    static void testCheckRosterLabelExists() {
        // Create a form with a known label
        List<Account> ppl = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true LIMIT 1];
        TestDataFactory.createForms('LABEL-EXISTS',
            new List<Id>{ ppl[0].PersonContactId }, TestDataFactory.currentUserId());

        Test.startTest();
        Boolean exists    = QualRosterController.checkRosterLabelExists('LABEL-EXISTS');
        Boolean notExists = QualRosterController.checkRosterLabelExists('NOPE-404');
        Boolean blank     = QualRosterController.checkRosterLabelExists('');
        Test.stopTest();

        System.assert(exists, 'Existing label should return true');
        System.assert(!notExists, 'Unknown label should return false');
        System.assert(!blank, 'Blank label should return false');
    }

    // ---- getContactMembers (all three branches) --------------------------
    @isTest
    static void testGetContactMembers() {
        Account rc = [SELECT Id FROM Account WHERE IsPersonAccount = false LIMIT 1];
        Account p  = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true LIMIT 1];

        Test.startTest();
        // Branch 1: by recruit class (ACR loop runs - member was linked in setup)
        List<QualRosterController.MemberRow> byClass =
            QualRosterController.getContactMembers(rc.Id, null);
        // Branch 2: by contact only
        List<QualRosterController.MemberRow> byContact =
            QualRosterController.getContactMembers(null, p.PersonContactId);
        // Branch 3: both null -> empty
        List<QualRosterController.MemberRow> neither =
            QualRosterController.getContactMembers(null, null);
        Test.stopTest();

        System.assert(!byClass.isEmpty(), 'Recruit-class branch should return the linked member');
        System.assertNotEquals(null, byContact, 'Contact branch should return a list');
        System.assert(neither.isEmpty(), 'Both-null should return empty');
    }

    // ---- addToRoster (JSON payload) --------------------------------------
    @isTest
    static void testAddToRoster() {
        Account p = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true LIMIT 1];
        Account rc = [SELECT Id FROM Account WHERE IsPersonAccount = false LIMIT 1];

        // Build the JSON payload the LWC would send
        Map<String, Object> weapon = new Map<String, Object>{
            'weaponType' => 'Pistol 2', 'manufacturer' => 'Sig Sauer',
            'model' => 'P365', 'sightType' => 'Optic'
        };
        Map<String, Object> member = new Map<String, Object>{
            'contactId'    => p.PersonContactId,
            'contactName'  => 'Test Person',
            'weaponEntries'=> new List<Object>{ weapon }
        };
        String payload = JSON.serialize(new List<Object>{ member });

        Test.startTest();
        Integer added = QualRosterController.addToRoster(
            payload, rc.Id, Date.today(), TestDataFactory.currentUserId(), 'HQ Range', 'JSON-ROSTER');
        Test.stopTest();

        System.assert(added > 0, 'Should create at least one FIR form');
        List<FIR_Qualification_Form__c> forms =
            [SELECT Id FROM FIR_Qualification_Form__c WHERE Qual_Roster_Label__c = 'JSON-ROSTER'];
        System.assert(!forms.isEmpty(), 'Form should exist for the new roster label');
        List<FIR_Weapon_Qualification_Detail__c> dets =
            [SELECT Id FROM FIR_Weapon_Qualification_Detail__c WHERE FIR_Qualification_Form__c IN :forms];
        System.assert(!dets.isEmpty(), 'Weapon detail should be created from weaponEntries');
    }

    @isTest
    static void testAddToRoster_emptyPayload() {
        Test.startTest();
        Integer added = QualRosterController.addToRoster(
            JSON.serialize(new List<Object>()), null, Date.today(), null, null, 'EMPTY');
        Test.stopTest();
        System.assertEquals(0, added, 'Empty payload should add nothing');
    }

    @isTest
    static void testAddToRoster_skipBranches() {
        Account p = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true LIMIT 1];

        // One item with a blank contactId (skipped), one valid item with NO
        // weaponEntries (form created, no details) - exercises the continue/guard paths.
        List<Object> members = new List<Object>{
            new Map<String, Object>{ 'contactId' => '', 'contactName' => 'Skip' },
            new Map<String, Object>{ 'contactId' => p.PersonContactId, 'contactName' => 'NoWeapons' }
        };
        String payload = JSON.serialize(members);

        Test.startTest();
        Integer added = QualRosterController.addToRoster(
            payload, null, Date.today(), null, null, 'EDGE-ROSTER');
        Test.stopTest();

        System.assertEquals(1, added, 'Only the valid member should produce a form');
        System.assertEquals(0, [SELECT COUNT() FROM FIR_Weapon_Qualification_Detail__c
            WHERE FIR_Qualification_Form__c IN
                (SELECT Id FROM FIR_Qualification_Form__c WHERE Qual_Roster_Label__c = 'EDGE-ROSTER')],
            'No weapon details when weaponEntries is absent');
    }

    // ---- Bulk -------------------------------------------------------------
    @isTest
    static void testAddToRoster_bulk() {
        List<Account> ppl = [SELECT Id, PersonContactId FROM Account WHERE IsPersonAccount = true];
        List<Object> members = new List<Object>();
        for (Account a : ppl) {
            members.add(new Map<String, Object>{
                'contactId'     => a.PersonContactId,
                'contactName'   => 'Bulk',
                'weaponEntries' => new List<Object>{
                    new Map<String, Object>{ 'weaponType' => 'Rifle' }
                }
            });
        }
        String payload = JSON.serialize(members);

        Test.startTest();
        Integer added = QualRosterController.addToRoster(
            payload, null, Date.today(), TestDataFactory.currentUserId(), 'Range', 'BULK-ROSTER');
        Test.stopTest();

        System.assertEquals(ppl.size(), added, 'Should create one form per member in bulk');
    }
}