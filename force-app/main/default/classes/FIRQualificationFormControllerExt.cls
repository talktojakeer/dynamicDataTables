public class FIRQualificationFormControllerExt {

    private final ApexPages.StandardController stdCtrl;

    // Signature image Attachment Ids, exposed to the VF page.
    public Id instructorSigAttId { get; private set; }
    public Id witnessSigAttId    { get; private set; }

    public FIRQualificationFormControllerExt(ApexPages.StandardController controller) {
        this.stdCtrl = controller;
    }

    // Current date/time in Central Time (America/Chicago)
    public String getCurrentCentralDateTime() {
        return DateTime.now().format('MMMM dd, yyyy hh:mm a', 'America/Chicago');
    }

    public PageReference prepareSignatureImages() {
        Id recId = stdCtrl.getId();
        if (recId == null) {
            recId = ApexPages.currentPage().getParameters().get('id');
        }
        if (recId == null) return null;

        FIR_Qualification_Form__c f;
        try {
            f = [
                SELECT Id,
                       Firearms_Instructor_Signature__c,
                       Witness_Signature__c
                FROM   FIR_Qualification_Form__c
                WHERE  Id = :recId
                LIMIT  1
            ];
        } catch (Exception e) {
            return null;
        }

        instructorSigAttId = upsertSigAttachment(
            f.Id, 'Instructor_Signature.png', f.Firearms_Instructor_Signature__c);
        witnessSigAttId = upsertSigAttachment(
            f.Id, 'Witness_Signature.png', f.Witness_Signature__c);
        return null;
    }

    // Decode the base64 payload into a PNG Attachment on the record,
    // reusing an existing one (by name) if present. Returns the Attachment Id.
    private Id upsertSigAttachment(Id parentId, String attName, String stored) {
        String b64 = extractBase64(stored);
        if (String.isBlank(b64)) return null;

        Blob body;
        try {
            body = EncodingUtil.base64Decode(b64);
        } catch (Exception e) {
            return null;
        }

        List<Attachment> existing = [
            SELECT Id
            FROM   Attachment
            WHERE  ParentId = :parentId AND Name = :attName
            LIMIT  1
        ];
        Attachment att = existing.isEmpty()
            ? new Attachment(ParentId = parentId, Name = attName)
            : existing[0];
        att.ContentType = 'image/png';
        att.Body        = body;
        try {
            upsert att;
        } catch (Exception e) {
            return null;
        }
        return att.Id;
    }

    // Pull the base64 payload out of either a raw "data:image/png;base64,XXXX"
    // value or an <img src="data:image/png;base64,XXXX"> Rich Text value.
    private String extractBase64(String val) {
        if (String.isBlank(val)) return null;
        Integer idx = val.indexOf('base64,');
        if (idx < 0) return null;
        String rest = val.substring(idx + 7);
        Integer q = rest.indexOf('"');   // stop at the closing quote if HTML-wrapped
        if (q > 0) rest = rest.substring(0, q);
        return rest.trim();
    }
}