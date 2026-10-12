/**
 * FAQPFormPDFExtensionTest
 * ---------------------------------------------------------------------------
 * Covers FAQPFormPDFExtension (mass "generate & attach PDF" set controller):
 *  - happy path: selected forms -> ContentVersion + ContentDocumentLink created
 *  - empty selection -> error message, no files
 *
 * Notes:
 *  - The extension calls addFields() in its constructor, which is only legal on
 *    a query-locator-backed StandardSetController AND only before any data is
 *    loaded. So the controller is built from Database.getQueryLocator and the
 *    extension is constructed BEFORE getRecords()/setSelected() touch data.
 *  - ContentDocumentLink can only be filtered by a single Id or an Id set on
 *    LinkedEntityId (no sObject list, no semi-join), so queries use a Set<Id>.
 *  - In test context the extension uses a stub blob (Test.isRunningTest()).
 *  - No SeeAllData.
 * ---------------------------------------------------------------------------
 */
@isTest
private class FAQPFormPDFExtensionTest {

    private static final String ROSTER = 'PDF-EXT-ROSTER';

    private static void seedForms() {
        List<Account> people = TestDataFactory.createPersonAccounts(2, false);
        List<Id> contactIds = new List<Id>{
            TestDataFactory.personContactId(people[0].Id),
            TestDataFactory.personContactId(people[1].Id)
        };
        TestDataFactory.createForms(ROSTER, contactIds, TestDataFactory.currentUserId());
    }

    // A query-locator-backed set controller - required because the extension
    // calls addFields(), which is illegal on a list-backed set controller.
    private static ApexPages.StandardSetController newSetController() {
        return new ApexPages.StandardSetController(
            Database.getQueryLocator([
                SELECT Id, Name, Test_Date__c
                FROM FIR_Qualification_Form__c
                WHERE Qual_Roster_Label__c = :ROSTER
            ])
        );
    }

    private static Set<Id> rosterFormIds() {
        return new Map<Id, FIR_Qualification_Form__c>([
            SELECT Id FROM FIR_Qualification_Form__c WHERE Qual_Roster_Label__c = :ROSTER
        ]).keySet();
    }

    @isTest
    static void testGenerateAndAttach_happy() {
        seedForms();

        ApexPages.StandardSetController ssc = newSetController();
        // Construct the extension FIRST so its addFields() runs before any data
        // is loaded; select a separately-queried list afterward.
        FAQPFormPDFExtension ext = new FAQPFormPDFExtension(ssc);
        List<FIR_Qualification_Form__c> forms = [
            SELECT Id, Name FROM FIR_Qualification_Form__c WHERE Qual_Roster_Label__c = :ROSTER
        ];
        ssc.setSelected(forms);

        Test.startTest();
        PageReference pr = ext.generateAndAttachPDFs();
        Test.stopTest();

        System.assertEquals(null, pr, 'Stays on page (returns null)');

        // One ContentDocumentLink per selected form (filter by Id set).
        Set<Id> formIds = rosterFormIds();
        List<ContentDocumentLink> links = [
            SELECT Id, LinkedEntityId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :formIds
        ];
        System.assertEquals(forms.size(), links.size(),
            'A PDF file should be linked to each selected form');

        Boolean hasConfirm = false;
        for (ApexPages.Message m : ApexPages.getMessages()) {
            if (m.getSeverity() == ApexPages.Severity.CONFIRM) hasConfirm = true;
        }
        System.assert(hasConfirm, 'A success/confirm message should be added');
    }

    @isTest
    static void testGenerateAndAttach_noSelection() {
        seedForms();

        ApexPages.StandardSetController ssc = newSetController();
        FAQPFormPDFExtension ext = new FAQPFormPDFExtension(ssc); // nothing selected

        Test.startTest();
        PageReference pr = ext.generateAndAttachPDFs();
        Test.stopTest();

        System.assertEquals(null, pr, 'Returns null on empty selection');

        Set<Id> formIds = rosterFormIds();
        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink WHERE LinkedEntityId IN :formIds
        ];
        System.assert(links.isEmpty(), 'No files should be created when nothing is selected');

        Boolean hasError = false;
        for (ApexPages.Message m : ApexPages.getMessages()) {
            if (m.getSeverity() == ApexPages.Severity.ERROR) hasError = true;
        }
        System.assert(hasError, 'An error message should be shown when nothing is selected');
    }
}