/**
 * Inbound email handler for supervisor availability replies.
 *
 * Expected reply lines (one per employee), pipe-delimited:
 *   00012345 | Available | Yes | optional comment
 *   00012346 | Not Available | Yes | 2026-12-01 to 2026-12-10 | optional comment
 *
 * Security: a line only updates its Case if the sender's address matches that
 * Case's Availability_Supervisor_Email__c (the address we sent the request to).
 */
global without sharing class AvailabilityReplyHandler implements Messaging.InboundEmailHandler {

    static final Map<String, String> AVAIL = new Map<String, String>{
        'available' => 'Available',
        'not available' => 'Not Available',
        'partially available' => 'Partially Available'
    };
    static final Map<String, String> CONFIRM = new Map<String, String>{
        'yes' => 'Yes', 'no' => 'No'
    };
    // Matches "2026-12-01 to 2026-12-10"
    static final Pattern DATE_RANGE =
        Pattern.compile('(\\d{4}-\\d{2}-\\d{2})\\s*(?:to|-)\\s*(\\d{4}-\\d{2}-\\d{2})');

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email,
                                                           Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        String sender = (envelope != null && envelope.fromAddress != null)
            ? envelope.fromAddress.toLowerCase() : '';
        String bodyText = String.isNotBlank(email.plainTextBody) ? email.plainTextBody : email.htmlBody;

        // 1) Parse the reply into a map of CaseNumber -> parsed values.
        Map<String, ParsedLine> parsed = new Map<String, ParsedLine>();
        if (String.isNotBlank(bodyText)) {
            for (String raw : bodyText.split('\n')) {
                ParsedLine pl = parseLine(raw);
                if (pl != null) parsed.put(pl.caseNumber, pl);
            }
        }
        if (parsed.isEmpty()) {
            result.success = true; // nothing to do, don't bounce
            return result;
        }

        // 2) Load those Cases and apply, but only where the sender is authorised.
        List<Case> toUpdate = new List<Case>();
        for (Case c : [
            SELECT Id, CaseNumber, Availability_Supervisor_Email__c, Availability_Request_Status__c
            FROM Case WHERE CaseNumber IN :parsed.keySet()
        ]) {
            ParsedLine pl = parsed.get(c.CaseNumber);
            if (pl == null) continue;
            String authorised = c.Availability_Supervisor_Email__c == null
                ? '' : c.Availability_Supervisor_Email__c.toLowerCase();
            if (authorised == '' || authorised != sender) continue; // ignore unauthorised sender

            c.Availability_Response__c      = pl.availability;
            c.Availability_Confirmation__c  = pl.confirmation;
            c.Unavailable_From__c           = pl.fromDate;
            c.Unavailable_To__c             = pl.toDate;
            c.Availability_Comments__c      = pl.comment;
            c.Availability_Responded_Date__c = Datetime.now();
            c.Availability_Request_Status__c = 'Responded';
            toUpdate.add(c);
        }
        if (!toUpdate.isEmpty()) {
            try { update toUpdate; } catch (Exception e) { System.debug('Availability reply update failed: ' + e.getMessage()); }
        }
        result.success = true;
        return result;
    }

    class ParsedLine {
        String caseNumber, availability, confirmation, comment;
        Date fromDate, toDate;
    }

    private ParsedLine parseLine(String raw) {
        if (String.isBlank(raw) || !raw.contains('|')) return null;
        List<String> parts = raw.split('\\|');
        if (parts.size() < 3) return null;

        String caseNum = parts[0].trim();
        if (!Pattern.matches('\\d{1,}', caseNum)) return null; // first token must be a case number

        String availKey = parts[1].trim().toLowerCase();
        if (!AVAIL.containsKey(availKey)) return null; // not a real reply line

        ParsedLine pl = new ParsedLine();
        pl.caseNumber = caseNum;
        pl.availability = AVAIL.get(availKey);
        pl.confirmation = CONFIRM.get(parts.size() > 2 ? parts[2].trim().toLowerCase() : '');

        // Remaining tokens: a date range (if present) and/or a comment.
        List<String> commentBits = new List<String>();
        for (Integer i = 3; i < parts.size(); i++) {
            String tok = parts[i].trim();
            if (String.isBlank(tok)) continue;
            Matcher m = DATE_RANGE.matcher(tok);
            if (m.find()) {
                pl.fromDate = Date.valueOf(m.group(1));
                pl.toDate   = Date.valueOf(m.group(2));
            } else {
                commentBits.add(tok);
            }
        }
        if (!commentBits.isEmpty()) pl.comment = String.join(commentBits, ' ');
        return pl;
    }
}