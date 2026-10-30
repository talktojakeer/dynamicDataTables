public with sharing class FIRFormEmailAction {

    // ===== CONFIG =====
    // Classic email template (FAQP-274). Blank / not-found -> inline body.
    @TestVisible private static String EMAIL_TEMPLATE_DEV_NAME = 'FIR_HR74_Qualification_Completed';

    // Officer-type tokens (FAQP-273 / FAQP-275).
    @TestVisible private static final String OFFICER_TYPE_SPECIAL_RANGER = 'Special Ranger';
    @TestVisible private static final String OFFICER_TYPE_RETIRED_PEACE  = 'Retired Peace Officer';
    @TestVisible private static final String OFFICER_TYPE_COMMISSIONED   = 'Commissioned Officer';

    // CC addresses, sourced from Custom Labels. @TestVisible + reassignable so
    // tests inject deterministic values instead of the configured label text.
    @TestVisible private static String CC_TOD_ADMINISTRATION     = System.Label.FIR_CC_TOD_Administration;
    @TestVisible private static String CC_HR_SERVICE_TEAM        = System.Label.FIR_CC_HR_Service_Team;
    @TestVisible private static String CC_SPECIAL_RANGERS        = System.Label.FIR_CC_Special_Rangers_Program;
    // ==================

    public class Request {
        @InvocableVariable(label='FIR Form Record Id'
            description='Single form Id - record-page / per-record use.')
        public Id formId;
        @InvocableVariable(label='FIR Form Record Ids'
            description='Collection of form Ids - list-view bulk use. Pass the whole selection in ONE call; do not loop.')
        public List<Id> formIds;
    }

    public class Result {
        @InvocableVariable(label='Success') public Boolean success;
        @InvocableVariable(label='Message') public String  message;
    }

    /**
     * Single invocable for both entry points:
     *   - record page / per-record: set Request.formId
     *   - list-view bulk: set Request.formIds to the whole selection and call
     *     this action ONCE (do not loop). One invocation = one bulk send, which
     *     avoids the 10-sendEmail-per-transaction limit and stays bulk-safe.
     */
    @InvocableMethod(
        label='Send FIR Form PDF'
        description='Emails the attached HR-74 PDF of FIR Qualification Form(s) to the qualifying individual and the CC audiences. Accepts a single formId or an formIds collection; pass bulk selections in one call.'
        category='FAQP')
    public static List<Result> send(List<Request> requests) {
        Set<Id> formIds = new Set<Id>();
        if (requests != null) {
            for (Request r : requests) {
                if (r == null) continue;
                if (r.formId != null)  formIds.add(r.formId);
                if (r.formIds != null) formIds.addAll(r.formIds);
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

    // Core - also callable directly from Apex (used by the list-view mass button).
    public static Integer sendForForms(Set<Id> formIds) {
        if (formIds == null || formIds.isEmpty()) return 0;

        Map<Id, FIR_Qualification_Form__c> forms = new Map<Id, FIR_Qualification_Form__c>([
            SELECT Id, Name, ContactName__c,
                   ContactName__r.Email, ContactName__r.Name,
                   ContactName__r.FAQP_Is_Retired_Officer__c,
                   ContactName__r.FAQP_Retired_Peace_Officer_Type__c
            FROM   FIR_Qualification_Form__c
            WHERE  Id IN :formIds
        ]);
        if (forms.isEmpty()) return 0;

        Map<Id, Id> formToPdfCv = latestPdfPerForm(forms.keySet());
        Id          tmplId      = templateId();

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> formIdByEmail = new List<Id>(); // parallel to emails - result[i] <-> form[i]

        for (FIR_Qualification_Form__c f : forms.values()) {
            Id cvId = formToPdfCv.get(f.Id);
            if (cvId == null) continue; // no attached HR-74 PDF -> skip this form

            String memberEmail  = (f.ContactName__r != null) ? f.ContactName__r.Email : null;
            String officerType  = resolveOfficerType(f);
            List<String> ccList = ccAddressesFor(officerType);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setSaveAsActivity(false);
            msg.setEntityAttachments(new List<Id>{ cvId });

            Boolean useTemplate = (tmplId != null
                                   && f.ContactName__c != null
                                   && String.isNotBlank(memberEmail));

            if (useTemplate) {
                // Template (FAQP-274) renders against the member Contact; form = whatId.
                msg.setTemplateId(tmplId);
                msg.setTargetObjectId(f.ContactName__c);
                msg.setWhatId(f.Id);
                if (!ccList.isEmpty()) msg.setCcAddresses(ccList);
            } else {
                List<String> toList = new List<String>();
                if (String.isNotBlank(memberEmail)) toList.add(memberEmail);
                if (toList.isEmpty()) toList.addAll(ccList); // no member email -> CC audiences only
                if (toList.isEmpty()) continue;              // no recipients at all
                msg.setToAddresses(toList);
                if (String.isNotBlank(memberEmail) && !ccList.isEmpty()) {
                    msg.setCcAddresses(ccList);
                }
                msg.setSubject('Firearms Qualification Completed - HR-74 Results Available');
                msg.setHtmlBody(defaultBody(f));
            }
            emails.add(msg);
            formIdByEmail.add(f.Id);
        }

        if (emails.isEmpty()) return 0;

        // Partial-success send: one bad address/message does not roll back the
        // whole batch. Results come back in the same order as the input list.
        List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(emails, false);

        // Mark 'Sent to HR' only the forms whose email actually sent.
        Integer sentCount = 0;
        List<FIR_Qualification_Form__c> toComplete = new List<FIR_Qualification_Form__c>();
        for (Integer i = 0; i < sendResults.size(); i++) {
            if (sendResults[i] != null && sendResults[i].isSuccess()) {
                sentCount++;
                toComplete.add(new FIR_Qualification_Form__c(
                    Id = formIdByEmail[i], Status__c = 'Sent to HR'));
            }
        }
        if (!toComplete.isEmpty()) Database.update(toComplete, false);

        return sentCount;
    }

    // ---- helpers ----------------------------------------------------------

    // Resolve the qualifying individual's officer type (FAQP-273 / FAQP-275).
    // A "Special Ranger" / "Special Texas Ranger" (FAQP_Retired_Peace_Officer_Type__c)
    // routes the Special Rangers Program CC; otherwise retired vs commissioned.
    @TestVisible
    private static String resolveOfficerType(FIR_Qualification_Form__c f) {
        if (f.ContactName__r != null) {
            String t = f.ContactName__r.FAQP_Retired_Peace_Officer_Type__c;
            if (t == 'Special Ranger' || t == 'Special Texas Ranger') {
                return OFFICER_TYPE_SPECIAL_RANGER;
            }
            if (f.ContactName__r.FAQP_Is_Retired_Officer__c == true) {
                return OFFICER_TYPE_RETIRED_PEACE;
            }
        }
        return OFFICER_TYPE_COMMISSIONED;
    }

    // TOD Admin + HR CC on every email; Special Rangers Program only for a
    // Special Ranger. De-duplicated case-insensitively.
    @TestVisible
    private static List<String> ccAddressesFor(String officerType) {
        List<String> rawValues = new List<String>{ CC_TOD_ADMINISTRATION, CC_HR_SERVICE_TEAM };
        if (OFFICER_TYPE_SPECIAL_RANGER.equalsIgnoreCase(officerType)) {
            rawValues.add(CC_SPECIAL_RANGERS);
        }

        Set<String> seen    = new Set<String>();
        List<String> result = new List<String>();
        for (String val : rawValues) {
            if (String.isBlank(val)) continue;
            for (String part : val.split('[,;\\n\\r]')) {
                String addr = (part == null) ? '' : part.trim();
                if (String.isBlank(addr)) continue;
                String key = addr.toLowerCase();
                if (seen.contains(key)) continue;
                seen.add(key);
                result.add(addr);
            }
        }
        return result;
    }

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

    private static Id templateId() {
        if (String.isBlank(EMAIL_TEMPLATE_DEV_NAME)) return null;
        List<EmailTemplate> t = [
            SELECT Id FROM EmailTemplate WHERE DeveloperName = :EMAIL_TEMPLATE_DEV_NAME LIMIT 1
        ];
        return t.isEmpty() ? null : t[0].Id;
    }

    // Inline fallback - mirrors the FAQP-274 template content.
    private static String defaultBody(FIR_Qualification_Form__c f) {
        String member = (f.ContactName__r != null && String.isNotBlank(f.ContactName__r.Name))
                        ? f.ContactName__r.Name : 'Qualifying Individual';
        return '<p>Dear ' + member + ',</p>'
             + '<p>This email is to notify you that your firearms qualification has been '
             + 'successfully completed and your results are now available for review.</p>'
             + '<p>Attached is a copy of your completed HR-74 Firearms Qualification Form '
             + 'for your records.</p>'
             + '<p>Please retain a copy of the attached form for future reference.</p>'
             + '<p>Thank you,<br/>Texas Department of Public Safety<br/>'
             + 'Firearms Training Unit<br/>Training Operations Division</p>';
    }
}