public class FAQPFormPDFExtension {

    public ApexPages.StandardSetController setCon { get; set; }

    public FAQPFormPDFExtension(ApexPages.StandardSetController controller) {
        setCon = controller;
        // Needed for the Classic getSelected() fallback path
        setCon.addFields(new List<String>{ 'Name', 'Test_Date__c' });
    }

    // Action to generate and attach a PDF to each selected FIR Qualification Form.
    public PageReference generateAndAttachPDFs() {

        // 1) Resolve which forms to process.
        // Primary (Lightning-safe): comma-separated Ids from the ?ids= URL param.
        // Fallback (Classic list button): StandardSetController getSelected(),
        // which does NOT work from a Lightning list view.
        List<FIR_Qualification_Form__c> selectedForms;
        String idsParam = ApexPages.currentPage().getParameters().get('ids');

        if (String.isNotBlank(idsParam)) {
            Set<Id> ids = new Set<Id>();
            for (String s : idsParam.split(',')) {
                if (String.isNotBlank(s)) {
                    try { ids.add((Id) s.trim()); } catch (Exception ignore) {}
                }
            }
            selectedForms = [
                SELECT Id, Name, Test_Date__c
                FROM   FIR_Qualification_Form__c
                WHERE  Id IN :ids
            ];
        } else {
            selectedForms = (List<FIR_Qualification_Form__c>) setCon.getSelected();
        }

        if (selectedForms == null || selectedForms.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'No Fire Arms Qualification Forms selected. Please select at least one Fire Arms Qualification Form.'));
            return null;
        }

        // 2) Generate a PDF per form. Track the form Id alongside each
        // ContentVersion so a failed PDF (which hits 'continue') can't shift
        // the file-to-record alignment.
        List<ContentVersion> filesToInsert = new List<ContentVersion>();
        List<Id>             fileFormIds   = new List<Id>();

        for (FIR_Qualification_Form__c c : selectedForms) {
            PageReference pdfPage = Page.FAQPFormPage;
            pdfPage.getParameters().put('id', c.Id);

            Blob pdfBlob;
            try {
                pdfBlob = !Test.isRunningTest()
                    ? pdfPage.getContentAsPDF()
                    : Blob.valueOf('Test PDF');
            } catch (Exception e) {
                ApexPages.addMessage(new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Error generating PDF for FireArms Qualification Form ' + c.Name + ': ' + e.getMessage()));
                continue;
            }

            ContentVersion cv = new ContentVersion();
            cv.Title          = 'FIR_Qualification_Form Report - ' + c.Name;
            cv.PathOnClient   = 'FIR_Qualification_Form_Report_' + c.Name + '.pdf';
            cv.VersionData    = pdfBlob;
            cv.IsMajorVersion = true;
            filesToInsert.add(cv);
            fileFormIds.add(c.Id);
        }

        if (filesToInsert.isEmpty()) {
            return null; // errors already added above
        }

        // 3) Insert files and link each to its form.
        try {
            insert filesToInsert;

            // One bulk query instead of a SOQL per iteration
            Map<Id, Id> cvToDoc = new Map<Id, Id>();
            for (ContentVersion cvx : [
                SELECT Id, ContentDocumentId
                FROM   ContentVersion
                WHERE  Id IN :filesToInsert
            ]) {
                cvToDoc.put(cvx.Id, cvx.ContentDocumentId);
            }

            List<ContentDocumentLink> linksToInsert = new List<ContentDocumentLink>();
            for (Integer i = 0; i < filesToInsert.size(); i++) {
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.LinkedEntityId    = fileFormIds[i];               // correct form, even after failures
                cdl.ContentDocumentId = cvToDoc.get(filesToInsert[i].Id);
                cdl.ShareType         = 'V';
                cdl.Visibility        = 'AllUsers';
                linksToInsert.add(cdl);
            }
            insert linksToInsert;

            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.CONFIRM,
                'PDFs generated and attached successfully to ' + filesToInsert.size() + ' FIR Qualification Form(s).'));

        } catch (Exception e) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR, 'Error attaching PDFs: ' + e.getMessage()));
        }

        return null;
    }
}