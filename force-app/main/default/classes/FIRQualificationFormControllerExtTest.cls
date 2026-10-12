/**
 * FIRQualificationFormControllerExtTest
 * ---------------------------------------------------------------------------
 * Covers FIRQualificationFormControllerExt (the FAQPFormPage VF extension):
 *  - getCurrentCentralDateTime
 *  - getInstructorSignatureUrl / getWitnessSignatureUrl (both quote styles,
 *    blank, and no-record paths via extractImageUrl)
 *  - getWeaponRows: official-order + extra ("Other") ordering, buildWeaponRow
 *    field mapping, Other_Weapon_Type__c label, attempt date formatting
 *
 * No SeeAllData; all data built in-test through TestDataFactory.
 * ---------------------------------------------------------------------------
 */
@isTest
private class FIRQualificationFormControllerExtTest {

    private static final String ROSTER = 'EXT-TEST-ROSTER';

    // Build one form (member + roster instructor = running user) with details.
    private static FIR_Qualification_Form__c buildFormWithDetails() {
        List<Account> people = TestDataFactory.createPersonAccounts(1, false);
        Id c0 = TestDataFactory.personContactId(people[0].Id);
        List<FIR_Qualification_Form__c> forms =
            TestDataFactory.createForms(ROSTER, new List<Id>{ c0 }, TestDataFactory.currentUserId());
        FIR_Qualification_Form__c form = forms[0];

        // A normal weapon (in official order) with an attempt date,
        // plus an "Other" weapon to exercise the extra-ordering + label branch.
        FIR_Weapon_Qualification_Detail__c normal = new FIR_Weapon_Qualification_Detail__c(
            FIR_Qualification_Form__c = form.Id,
            Weapon_Type__c            = 'Rifle',
            Sight_Type__c             = 'Optic',
            Manufacturer__c           = 'Sig Sauer',
            Model__c                  = 'MCX',
            Weapon_Code__c            = 'DI',
            Qualified__c              = 'Yes',
            Qualified_at_90__c        = 'No',
            Qualification_Attempt__c  = '1st',
            Attempt_Date__c           = Date.today()
        );
        FIR_Weapon_Qualification_Detail__c other = new FIR_Weapon_Qualification_Detail__c(
            FIR_Qualification_Form__c = form.Id,
            Weapon_Type__c            = 'Other',
            Other_Weapon_Type__c      = 'Taser X2',
            Sight_Type__c             = 'Iron Sight',
            Qualified__c              = 'No'
        );
        insert new List<FIR_Weapon_Qualification_Detail__c>{ normal, other };
        return form;
    }

    private static FIRQualificationFormControllerExt extFor(FIR_Qualification_Form__c form) {
        return new FIRQualificationFormControllerExt(new ApexPages.StandardController(form));
    }

    @isTest
    static void testDateTimeAndWeaponRows() {
        FIR_Qualification_Form__c form = buildFormWithDetails();

        Test.startTest();
        FIRQualificationFormControllerExt ext = extFor(form);
        String dt = ext.getCurrentCentralDateTime();
        List<FIRQualificationFormControllerExt.WeaponRow> rows = ext.getWeaponRows();
        Test.stopTest();

        System.assert(String.isNotBlank(dt), 'Central date/time should be returned');
        System.assertEquals(2, rows.size(), 'Both weapon rows should be returned');

        // Official-order weapon comes first.
        FIRQualificationFormControllerExt.WeaponRow first = rows[0];
        System.assertEquals('Rifle', first.weaponLabel, 'Official-order weapon first');
        System.assertEquals('Sig Sauer MCX', first.manufacturerModel, 'Manufacturer + Model joined');
        System.assertEquals('1st', first.qualAttempt, 'Qual attempt mapped');
        System.assert(String.isNotBlank(first.attemptDate), 'Attempt date formatted');

        // "Other" weapon shows its custom name and appears after the ordered one.
        FIRQualificationFormControllerExt.WeaponRow second = rows[1];
        System.assertEquals('Taser X2', second.weaponLabel, 'Other weapon shows custom name');
        System.assertEquals('', second.attemptDate, 'No attempt date -> blank');
    }

    @isTest
    static void testSignatureUrls_bothQuoteStyles() {
        FIR_Qualification_Form__c form = buildFormWithDetails();
        // Double-quoted src with an HTML-encoded ampersand in the URL.
        form.Firearms_Instructor_Signature__c =
            '<img src="https://example.com/sig.png?a=1&amp;b=2" alt="sig"/>';
        // Single-quoted src.
        form.Witness_Signature__c =
            '<img src=\'https://example.com/witness.png\'/>';
        update form;

        Test.startTest();
        FIRQualificationFormControllerExt ext = extFor(form);
        String instrUrl   = ext.getInstructorSignatureUrl();
        String witnessUrl = ext.getWitnessSignatureUrl();
        Test.stopTest();

        System.assertEquals('https://example.com/sig.png?a=1&b=2', instrUrl,
            'Double-quoted src extracted and &amp; decoded');
        System.assertEquals('https://example.com/witness.png', witnessUrl,
            'Single-quoted src extracted');
    }

    @isTest
    static void testSignatureUrls_blank() {
        FIR_Qualification_Form__c form = buildFormWithDetails();
        // No signatures set -> both getters return ''.
        Test.startTest();
        FIRQualificationFormControllerExt ext = extFor(form);
        System.assertEquals('', ext.getInstructorSignatureUrl(), 'Blank instructor signature -> empty');
        System.assertEquals('', ext.getWitnessSignatureUrl(), 'Blank witness signature -> empty');
        Test.stopTest();
    }

    @isTest
    static void testNoRecordId() {
        // StandardController with an empty record -> getId() null -> empty results.
        FIRQualificationFormControllerExt ext =
            new FIRQualificationFormControllerExt(
                new ApexPages.StandardController(new FIR_Qualification_Form__c()));

        Test.startTest();
        List<FIRQualificationFormControllerExt.WeaponRow> rows = ext.getWeaponRows();
        String instrUrl = ext.getInstructorSignatureUrl();
        Test.stopTest();

        System.assert(rows.isEmpty(), 'No form id -> no weapon rows');
        System.assertEquals('', instrUrl, 'No form id -> empty signature url');
    }
}