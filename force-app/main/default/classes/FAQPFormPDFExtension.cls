public class FAQPFormPDFExtension {
    
    public ApexPages.StandardSetController setCon { get; set; }
    
    public FAQPFormPDFExtension(ApexPages.StandardSetController controller) {
        setCon = controller;
        
        setCon.addFields(new List<String>{ 'Name' });
        /*setCon.addFields(new List<String>{ 'Firearms_Instructor__c' });
setCon.addFields(new List<String>{ 'Light_Condition__c' });
setCon.addFields(new List<String>{ 'Location__c' });
setCon.addFields(new List<String>{ 'Test_Date__c' });
setCon.addFields(new List<String>{ 'Qualification_Attempt__c' });
setCon.addFields(new List<String>{ 'RecordTypeId' });

//Add fields needed (minimal for attachment...)
setCon.addFields(new List<String>{ 'FIR_Qualification_FormNumber' });*/
    }
    
    // Action to generate and attach PDFs
    public PageReference generateAndAttachPDFs() {
        List<FIR_Qualification_Form__c> selectedForms = (List<FIR_Qualification_Form__c>) setCon.getSelected();
        
        if (selectedForms.isEmpty()) {
            ApexPages.addMessage(new ApexPages.Message(
                ApexPages.Severity.ERROR,
                'No Fire Arms Qualification Forms selected. Please select at least one Fire Arms Qualification Form.'));
            return null;
        }
        
        List<ContentVersion> filesToInsert = new List<ContentVersion>();
        
        for (FIR_Qualification_Form__c c : selectedForms) {
            PageReference pdfPage = Page.FAQPFormPage;
            pdfPage.getParameters().put('id', c.Id);
            
            Blob pdfBlob;
            try {
                pdfBlob = !Test.isRunningTest()
                    ? pdfPage.getContentAsPDF()
                    : Blob.valueOf('Test PDF');
            } catch (Exception e) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Error generating PDF for FireArms Qualification Forms' + c.Test_Date__c+ ': ' + e.getMessage()));
                continue;
            }
            
            ContentVersion cv = new ContentVersion();
            cv.Title = 'FIR_Qualification_Form Report - ' + c.Name;
            cv.PathOnClient = 'FIR_Qualification_Form_Report_' + c.Name + '.pdf';
            cv.VersionData = pdfBlob;
            cv.IsMajorVersion = true;
            filesToInsert.add(cv);
        }
        
        if (!filesToInsert.isEmpty()) {
            try {
                insert filesToInsert;
                
                List<ContentDocumentLink> linksToInsert  = new List<ContentDocumentLink>();
                for (Integer i = 0; i < selectedForms.size(); i++) {
                    FIR_Qualification_Form__c c = selectedForms[i];
                    ContentVersion cv = filesToInsert[i]; // Matches order
                    
                    ContentDocumentLink cdl = new ContentDocumentLink();
                    cdl.LinkedEntityId = c.Id; // Attach to this FIR Qualification_Form
                    cdl.ContentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1]. ContentDocumentId;
                    cdl.ShareType = 'V'; // Viewer permission
                    cdl.Visibility = 'AllUsers'; // Visible to all (adjust if needed, e.g., 'InternalUsers')
                    linksToInsert.add(cdl);
                }
                
                
                insert linksToInsert;
                
                ApexPages.addMessage(
                    new ApexPages.Message(
                        ApexPages.Severity.CONFIRM,
                        'PDFs generated and attached successfully to' + selectedForms.size() + 'FIR_Qualification_Form(s).'));
            } catch (Exception e) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Error attaching PDFs: ' + e.getMessage()));
            }
        }
        
        return null;
    }
}