
@isTest
private class FIRFormEmailActionTest {

    private static final String ROSTER = 'EMAIL-ROSTER';

    // Deterministic CC seams, independent of the org's Custom Label values.
    private static void stubCcLabels() {
        FIRFormEmailAction.CC_TOD_ADMINISTRATION = 'tod1@example.com; tod2@example.com';
        FIRFormEmailAction.CC_HR_SERVICE_TEAM    = 'hr1@example.com, hr2@example.com';
        FIRFormEmailAction.CC_SPECIAL_RANGERS    = 'rangers@example.com';
    }

    // Qualifying individual (person account with email) + a form + an attached PDF.
    private static Id buildFormWithPdf() {
        return buildFormWithPdf('Mem', 'Ber', 7200000001L, ROSTER, 'member.faqp@example.com');
    }

    private static Id buildFormWithPdf(String fn, String ln, Decimal tins, String roster, String email) {
        Account a = TestDataFactory.buildPersonAccount(fn, ln, tins);
        a.PersonEmail = email;
        insert a;
        Id contactId = TestDataFactory.personContactId(a.Id);

        List<FIR_Qualification_Form__c> forms =
            TestDataFactory.createForms(roster, new List<Id>{ contactId }, TestDataFactory.currentUserId());
        Id formId = forms[0].Id;

        ContentVersion cv = new ContentVersion(
            Title         = 'FIR Form PDF',
            PathOnClient  = 'fir_form.pdf',
            VersionData   = Blob.valueOf('%PDF-1.4 test'),
            IsMajorVersion= true
        );
        insert cv;
        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId    = formId,
            ShareType         = 'V',
            Visibility        = 'AllUsers'
        );
        return formId;
    }

    @isTest
    static void testSend_inlineWithCc() {
        Id formId = buildFormWithPdf();
        FIRFormEmailAction.EMAIL_TEMPLATE_DEV_NAME = 'NO_SUCH_TEMPLATE_XYZ'; // force inline body
        stubCcLabels();

        FIRFormEmailAction.Request req = new FIRFormEmailAction.Request();
        req.formId = formId;

        Test.startTest();
        List<FIRFormEmailAction.Result> results =
            FIRFormEmailAction.send(new List<FIRFormEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        System.assertEquals(true, results[0].success, 'Send should succeed: ' + results[0].message);
        System.assert(results[0].message.contains('1 email'), 'One email should be sent: ' + results[0].message);

        // The emailed form is marked Completed.
        FIR_Qualification_Form__c done = [SELECT Status__c FROM FIR_Qualification_Form__c WHERE Id = :formId];
        System.assertEquals('Completed', done.Status__c, 'Emailed form should be marked Completed');
    }

    @isTest
    static void testSendBulk_multiple() {
        Id form1 = buildFormWithPdf('Bulk', 'One', 7200000011L, 'BULK-R1', 'bulk1@example.com');
        Id form2 = buildFormWithPdf('Bulk', 'Two', 7200000012L, 'BULK-R2', 'bulk2@example.com');
        FIRFormEmailAction.EMAIL_TEMPLATE_DEV_NAME = 'NO_SUCH_TEMPLATE_XYZ';
        stubCcLabels();

        FIRFormEmailAction.Request req = new FIRFormEmailAction.Request();
        req.formIds = new List<Id>{ form1, form2 };

        Test.startTest();
        List<FIRFormEmailAction.Result> results =
            FIRFormEmailAction.send(new List<FIRFormEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Bulk send should succeed: ' + results[0].message);
        System.assert(results[0].message.contains('2 email'), 'Two emails should be sent: ' + results[0].message);

        Map<Id, FIR_Qualification_Form__c> done = new Map<Id, FIR_Qualification_Form__c>([
            SELECT Status__c FROM FIR_Qualification_Form__c WHERE Id IN (:form1, :form2)]);
        System.assertEquals('Completed', done.get(form1).Status__c, 'Form 1 should be Completed');
        System.assertEquals('Completed', done.get(form2).Status__c, 'Form 2 should be Completed');
    }

    @isTest
    static void testCcAddressesFor_scopingAndDedup() {
        // TOD + HR with a case-duplicate; rangers scoped to Special Ranger only.
        FIRFormEmailAction.CC_TOD_ADMINISTRATION = 'a@x.com, b@x.com';
        FIRFormEmailAction.CC_HR_SERVICE_TEAM    = 'A@X.COM';          // dupe of a@x.com (case)
        FIRFormEmailAction.CC_SPECIAL_RANGERS    = 'rangers@x.com';

        // Commissioned officer -> TOD + HR only, dupe collapsed.
        List<String> comm = FIRFormEmailAction.ccAddressesFor('Commissioned Officer');
        System.assertEquals(2, comm.size(), 'Only de-duplicated TOD/HR addresses: ' + comm);
        System.assert(!comm.contains('rangers@x.com'), 'Ranger CC must not apply to a commissioned officer');

        // Special Ranger -> TOD + HR + ranger address.
        List<String> ranger = FIRFormEmailAction.ccAddressesFor('Special Ranger');
        System.assertEquals(3, ranger.size(), 'TOD/HR + ranger address: ' + ranger);
        System.assert(ranger.contains('rangers@x.com'), 'Ranger CC should apply to a Special Ranger');
    }

    @isTest
    static void testSend_noAttachmentAndEmpty() {
        // Form with NO attached PDF -> skipped, zero emails.
        Account a = TestDataFactory.buildPersonAccount('No', 'Pdf', 7200000002L);
        a.PersonEmail = 'nopdf.faqp@example.com';
        insert a;
        Id contactId = TestDataFactory.personContactId(a.Id);
        List<FIR_Qualification_Form__c> forms =
            TestDataFactory.createForms('EMAIL-ROSTER-2', new List<Id>{ contactId }, TestDataFactory.currentUserId());

        stubCcLabels();

        Test.startTest();
        Integer sentNoPdf = FIRFormEmailAction.sendForForms(new Set<Id>{ forms[0].Id });
        Integer sentEmpty = FIRFormEmailAction.sendForForms(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, sentNoPdf, 'No attached PDF -> nothing sent');
        System.assertEquals(0, sentEmpty, 'Empty input -> nothing sent');
    }
}