/**
 * FIRFormEmailActionTest
 * ---------------------------------------------------------------------------
 * Covers FIRFormEmailAction: invocable entry point, attached-PDF lookup,
 * Group-Admin (public group) email resolution, the inline-body send path,
 * and the no-attachment / empty-input branches.
 *
 * The email template path is not exercised (templates need a folder and can't
 * be reliably built in-test); EMAIL_TEMPLATE_DEV_NAME is forced to a missing
 * name so the inline body is used. Setup-object DML (User/Group/GroupMember)
 * runs inside System.runAs to avoid MIXED_DML_OPERATION. No SeeAllData.
 * ---------------------------------------------------------------------------
 */
@isTest
private class FIRFormEmailActionTest {

    private static final String ROSTER = 'EMAIL-ROSTER';

    // Person-account member (with email) + a form + an attached PDF file.
    private static Id buildFormWithPdf() {
        Account a = TestDataFactory.buildPersonAccount('Mem', 'Ber', 7200000001L);
        a.PersonEmail = 'member.faqp@example.com';
        insert a;
        Id contactId = TestDataFactory.personContactId(a.Id);

        List<FIR_Qualification_Form__c> forms =
            TestDataFactory.createForms(ROSTER, new List<Id>{ contactId }, TestDataFactory.currentUserId());
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
    static void testSend_inlineWithAdmins() {
        Id formId = buildFormWithPdf();

        // A public group with one active user member = the Group Admins.
        Group g;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            User u = new User(
                FirstName = 'Adm', LastName = 'In',
                Alias = 'admn', Email = 'admin.faqp@example.com',
                Username = 'admin.faqp.' + System.now().getTime() + '@example.com',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Chicago',
                ProfileId = UserInfo.getProfileId()
            );
            insert u;
            g = new Group(
                Name = 'FIR Group Admins',
                DeveloperName = 'FIR_Grp_' + String.valueOf(System.now().getTime()).right(8),
                Type = 'Regular'
            );
            insert g;
            insert new GroupMember(GroupId = g.Id, UserOrGroupId = u.Id);
        }

        FIRFormEmailAction.ADMIN_GROUP_DEV_NAME   = g.DeveloperName;
        FIRFormEmailAction.EMAIL_TEMPLATE_DEV_NAME = 'NO_SUCH_TEMPLATE_XYZ'; // force inline body

        FIRFormEmailAction.Request req = new FIRFormEmailAction.Request();
        req.formId = formId;

        Test.startTest();
        List<FIRFormEmailAction.Result> results =
            FIRFormEmailAction.send(new List<FIRFormEmailAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result per request');
        System.assertEquals(true, results[0].success, 'Send should succeed: ' + results[0].message);
        System.assert(results[0].message.contains('1 email'), 'One email should be sent: ' + results[0].message);
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

        Test.startTest();
        Integer sentNoPdf = FIRFormEmailAction.sendForForms(new Set<Id>{ forms[0].Id });
        Integer sentEmpty = FIRFormEmailAction.sendForForms(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, sentNoPdf, 'No attached PDF -> nothing sent');
        System.assertEquals(0, sentEmpty, 'Empty input -> nothing sent');
    }
}