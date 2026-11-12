/**
 * After a Random Drug Test selection creates Cases, send ONE email per supervisor
 * listing that supervisor's selected employees, and stamp each Case so the reply
 * handler (step 3) knows who may answer.
 *
 * Supervisor = Person Account's PersonReportsToId (a Contact). Email goes to that
 * Contact's Email (the supervisor's own Person Account email).
 */
public with sharing class AvailabilityRequestService {

    @TestVisible static final String STATUS_REQUESTED = 'Requested';

    public class RequestResult {
        public Integer supervisorsEmailed = 0;
        public Integer casesRequested = 0;
        public Integer casesSkipped = 0;
        public List<String> skippedReasons = new List<String>();
    }

    public static RequestResult sendRequests(List<Id> caseIds) {
        RequestResult res = new RequestResult();
        if (caseIds == null || caseIds.isEmpty()) return res;

        List<Case> cases = [
            SELECT Id, CaseNumber, Selection_Date__c, Account.Name, Account.PersonReportsToId
            FROM Case WHERE Id IN :caseIds
        ];

        Set<Id> supervisorContactIds = new Set<Id>();
        for (Case c : cases) {
            if (c.Account.PersonReportsToId != null) supervisorContactIds.add(c.Account.PersonReportsToId);
        }
        Map<Id, Contact> supervisors = new Map<Id, Contact>([
            SELECT Id, FirstName, LastName, Email FROM Contact WHERE Id IN :supervisorContactIds
        ]);

        // Group cases by supervisor.
        Map<Id, List<Case>> bySupervisor = new Map<Id, List<Case>>();
        for (Case c : cases) {
            Contact sup = supervisors.get(c.Account.PersonReportsToId);
            if (sup == null) {
                res.casesSkipped++;
                res.skippedReasons.add(c.CaseNumber + ': employee has no supervisor');
            } else if (String.isBlank(sup.Email)) {
                res.casesSkipped++;
                res.skippedReasons.add(c.CaseNumber + ': supervisor ' + sup.LastName + ' has no email');
            } else {
                if (!bySupervisor.containsKey(sup.Id)) bySupervisor.put(sup.Id, new List<Case>());
                bySupervisor.get(sup.Id).add(c);
            }
        }
        if (bySupervisor.isEmpty()) return res;

        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        List<Id> mailSupervisorOrder = new List<Id>();
        for (Id supId : bySupervisor.keySet()) {
            mails.add(buildEmail(supervisors.get(supId), bySupervisor.get(supId)));
            mailSupervisorOrder.add(supId);
        }

        List<Messaging.SendEmailResult> sendResults = Messaging.sendEmail(mails, false);

        List<Case> toUpdate = new List<Case>();
        Datetime now = Datetime.now();
        for (Integer i = 0; i < sendResults.size(); i++) {
            Id supId = mailSupervisorOrder[i];
            if (sendResults[i].isSuccess()) {
                res.supervisorsEmailed++;
                for (Case c : bySupervisor.get(supId)) {
                    toUpdate.add(new Case(
                        Id = c.Id,
                        Availability_Request_Status__c   = STATUS_REQUESTED,
                        Availability_Requested_Date__c   = now,
                        Availability_Supervisor_Email__c = supervisors.get(supId).Email
                    ));
                    res.casesRequested++;
                }
            } else {
                for (Case c : bySupervisor.get(supId)) {
                    res.casesSkipped++;
                    res.skippedReasons.add(c.CaseNumber + ': email failed - ' + sendResults[i].getErrors()[0].getMessage());
                }
            }
        }
        if (!toUpdate.isEmpty()) update toUpdate;
        return res;
    }

    private static Messaging.SingleEmailMessage buildEmail(Contact sup, List<Case> supCases) {
        Messaging.SingleEmailMessage m = new Messaging.SingleEmailMessage();
        m.setToAddresses(new List<String>{ sup.Email });
        m.setSaveAsActivity(false);
        String replyTo = Label.Availability_Reply_To_Address;
        if (String.isNotBlank(replyTo) && replyTo != 'not-configured') m.setReplyTo(replyTo);
        m.setSubject(Label.Availability_Request_Subject);

        String greeting = 'Hello ' + (String.isBlank(sup.FirstName) ? '' : sup.FirstName + ' ') + sup.LastName + ',';
        Date d = supCases[0].Selection_Date__c;
        String periodText = d == null ? '' : ' (selection date: ' + d.format() + ')';

        String lines = '';
        for (Case c : supCases) {
            lines += c.CaseNumber + '  -  ' + c.Account.Name + '\n';
        }

        String body = greeting + '\n\n'
            + Label.Availability_Request_Intro + periodText + '\n\n'
            + lines + '\n'
            + 'Please REPLY to this email with one line per employee, in this format:\n\n'
            + '  <Case number> | <Available / Not Available / Partially Available> | <Yes / No> | <comment>\n'
            + '  (If Not/Partially Available, add dates: <Case number> | Not Available | Yes | 2026-12-01 to 2026-12-10 | <comment>)\n\n'
            + 'Example:\n'
            + '  ' + supCases[0].CaseNumber + ' | Available | Yes | No issues\n\n'
            + 'Replies are only accepted from this email address. Thank you.';
        m.setPlainTextBody(body);
        return m;
    }
}