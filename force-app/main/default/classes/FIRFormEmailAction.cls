/**
 * FIRFormEmailAction
 * ---------------------------------------------------------------------------
 * Emails the PDF already attached (as a File) to a FIR Qualification Form to:
 *   - the employee  (the form's member - ContactName__r.Email), and
 *   - the Group Admins (active members of a Public Group).
 *
 * Invocable from a Screen Flow (record-page Quick Action and list-view button).
 * The actual PDF is the latest attached .pdf File on the form (produced by the
 * attach script / FAQPFormPDFExtension); nothing is rendered here.
 *
 * If a classic/Lightning email template with DeveloperName = EMAIL_TEMPLATE_DEV_NAME
 * exists it is used; otherwise a built-in HTML body is sent. Both configs are
 * @TestVisible so the test can force the inline path.
 * ---------------------------------------------------------------------------
 */
public with sharing class FIRFormEmailAction {

    // ===== CONFIG - adjust to the org =====
    // Public Group whose ACTIVE user members are the "Group Admins".
    @TestVisible private static String ADMIN_GROUP_DEV_NAME   = 'FIR_Group_Admins';
    // Optional email template DeveloperName (blank/not-found -> inline body).
    @TestVisible private static String EMAIL_TEMPLATE_DEV_NAME = 'Fir_form_pdf_email_template';
    // ======================================

    public class Request {
        @InvocableVariable(label='FIR Form Record Id' required=true)
        public Id formId;
    }

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String  message;
    }

    @InvocableMethod(
        label='Send FIR Form PDF'
        description='Emails the attached PDF of a FIR Qualification Form to the employee and Group Admins.'
        category='FAQP')
    public static List<Result> send(List<Request> requests) {
        Set<Id> formIds = new Set<Id>();
        if (requests != null) {
            for (Request r : requests) {
                if (r != null && r.formId != null) formIds.add(r.formId);
            }
        }

        Result res = new Result();
        try {
            Integer sent = sendForForms(formIds);
            res.success = true;
            res.message = sent + ' email(s) sent.';
        } catch (Exception e) {
            res.success = false;
            res.message = 'Send failed: ' + e.getMessage();
        }

        // Flow expects one Result per input request.
        List<Result> out = new List<Result>();
        Integer n = (requests == null || requests.isEmpty()) ? 1 : requests.size();
        for (Integer i = 0; i < n; i++) out.add(res);
        return out;
    }

    // Core - also callable directly from Apex.
    public static Integer sendForForms(Set<Id> formIds) {
        if (formIds == null || formIds.isEmpty()) return 0;

        Map<Id, FIR_Qualification_Form__c> forms = new Map<Id, FIR_Qualification_Form__c>([
            SELECT Id, Name, ContactName__c, ContactName__r.Email, ContactName__r.Name
            FROM   FIR_Qualification_Form__c
            WHERE  Id IN :formIds
        ]);
        if (forms.isEmpty()) return 0;

        Map<Id, Id>  formToPdfCv = latestPdfPerForm(forms.keySet());
        List<String> adminEmails = adminGroupEmails();
        Id           tmplId      = templateId();

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (FIR_Qualification_Form__c f : forms.values()) {
            Id cvId = formToPdfCv.get(f.Id);
            if (cvId == null) continue; // no attached PDF -> skip this form

            String memberEmail = (f.ContactName__r != null) ? f.ContactName__r.Email : null;

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setSaveAsActivity(false);
            msg.setEntityAttachments(new List<Id>{ cvId });

            Boolean useTemplate = (tmplId != null
                                   && f.ContactName__c != null
                                   && String.isNotBlank(memberEmail));

            if (useTemplate) {
                // Template renders against the member Contact; form = whatId.
                msg.setTemplateId(tmplId);
                msg.setTargetObjectId(f.ContactName__c);
                msg.setWhatId(f.Id);
                if (!adminEmails.isEmpty()) msg.setCcAddresses(adminEmails);
            } else {
                List<String> toList = new List<String>();
                if (String.isNotBlank(memberEmail)) toList.add(memberEmail);
                if (toList.isEmpty()) toList.addAll(adminEmails); // nobody else -> admins only
                if (toList.isEmpty()) continue;                   // no recipients at all
                msg.setToAddresses(toList);
                if (String.isNotBlank(memberEmail) && !adminEmails.isEmpty()) {
                    msg.setCcAddresses(adminEmails);
                }
                msg.setSubject('Firearms Qualification Form - ' + f.Name);
                msg.setHtmlBody(defaultBody(f));
            }
            emails.add(msg);
        }

        if (!emails.isEmpty()) Messaging.sendEmail(emails);
        return emails.size();
    }

    // ---- helpers ----------------------------------------------------------

    // Newest attached .pdf ContentVersion for each form (one per form).
    private static Map<Id, Id> latestPdfPerForm(Set<Id> formIds) {
        Map<Id, List<Id>> formToDocs = new Map<Id, List<Id>>();
        Set<Id> allDocs = new Set<Id>();
        for (ContentDocumentLink l : [
            SELECT LinkedEntityId, ContentDocumentId
            FROM   ContentDocumentLink
            WHERE  LinkedEntityId IN :formIds
        ]) {
            if (!formToDocs.containsKey(l.LinkedEntityId)) {
                formToDocs.put(l.LinkedEntityId, new List<Id>());
            }
            formToDocs.get(l.LinkedEntityId).add(l.ContentDocumentId);
            allDocs.add(l.ContentDocumentId);
        }

        Map<Id, Id> docToCv = new Map<Id, Id>();
        if (!allDocs.isEmpty()) {
            for (ContentVersion cv : [
                SELECT Id, ContentDocumentId
                FROM   ContentVersion
                WHERE  ContentDocumentId IN :allDocs
                AND    IsLatest = true
                AND    FileExtension = 'pdf'
                ORDER BY CreatedDate DESC
            ]) {
                docToCv.put(cv.ContentDocumentId, cv.Id);
            }
        }

        Map<Id, Id> formToCv = new Map<Id, Id>();
        for (Id fId : formToDocs.keySet()) {
            for (Id dId : formToDocs.get(fId)) {
                if (docToCv.containsKey(dId)) {
                    formToCv.put(fId, docToCv.get(dId));
                    break;
                }
            }
        }
        return formToCv;
    }

    private static List<String> adminGroupEmails() {
        List<String> emails = new List<String>();
        if (String.isBlank(ADMIN_GROUP_DEV_NAME)) return emails;

        List<Group> groups = [
            SELECT Id FROM Group
            WHERE DeveloperName = :ADMIN_GROUP_DEV_NAME AND Type = 'Regular' LIMIT 1
        ];
        if (groups.isEmpty()) return emails;

        Set<Id> userIds = new Set<Id>();
        for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :groups[0].Id]) {
            if (String.valueOf(gm.UserOrGroupId).startsWith('005')) userIds.add(gm.UserOrGroupId);
        }
        if (userIds.isEmpty()) return emails;

        for (User u : [SELECT Email FROM User WHERE Id IN :userIds AND IsActive = true AND Email != null]) {
            emails.add(u.Email);
        }
        return emails;
    }

    private static Id templateId() {
        if (String.isBlank(EMAIL_TEMPLATE_DEV_NAME)) return null;
        List<EmailTemplate> t = [
            SELECT Id FROM EmailTemplate WHERE DeveloperName = :EMAIL_TEMPLATE_DEV_NAME LIMIT 1
        ];
        return t.isEmpty() ? null : t[0].Id;
    }

    private static String defaultBody(FIR_Qualification_Form__c f) {
        String member = (f.ContactName__r != null && String.isNotBlank(f.ContactName__r.Name))
                        ? f.ContactName__r.Name : 'Employee';
        return '<p>Dear ' + member + ',</p>'
             + '<p>Please find attached your Texas Department of Public Safety '
             + 'Firearms Qualification Form.</p>'
             + '<p><strong>Form:</strong> ' + f.Name + '</p>'
             + '<p>If you have any questions, please contact your firearms instructor '
             + 'or group administrator.</p>'
             + '<p>Regards,<br/>Texas DPS Firearms Qualification Program</p>';
    }
}