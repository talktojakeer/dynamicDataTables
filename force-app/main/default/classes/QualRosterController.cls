public with sharing class QualRosterController {

    private static final String FAQP_ACCOUNT_RT  = 'FAQP_Account';

    @AuraEnabled(cacheable=true)
    public static SearchResultWrapper searchRecruitClassAndContacts(String searchKey) {
        SearchResultWrapper result = new SearchResultWrapper();
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) return result;

        String keyword = '%' + searchKey.trim() + '%';

        result.recruitClasses = [
            SELECT Id, Name
            FROM   Account
            WHERE  Name LIKE :keyword
            AND    RecordType.DeveloperName = :FAQP_ACCOUNT_RT
            AND    IsPersonAccount = false
            ORDER BY Name ASC
            LIMIT  10
        ];

        List<Account> rawEmployees = [
            SELECT Id, Name, LastName, FirstName, TINS_NUMBER__pc, PersonContactId
            FROM   Account
            WHERE  IsPersonAccount = true
            AND    (Name LIKE :keyword OR TINS_NUMBER__pc LIKE :keyword)
            ORDER BY LastName ASC, FirstName ASC
            LIMIT  20
        ];

        Map<String, Account> uniqueByName = new Map<String, Account>();
        for (Account a : rawEmployees) {
            String key = a.Name.toLowerCase().trim();
            if (!uniqueByName.containsKey(key)) uniqueByName.put(key, a);
        }

        for (Account a : uniqueByName.values()) {
            ContactSearchItem item  = new ContactSearchItem();
            item.Id              = a.Id;
            item.Name            = formatName(a.LastName, a.FirstName);
            item.TINS            = a.TINS_NUMBER__pc;
            item.PersonContactId = a.PersonContactId;
            result.contacts.add(item);
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<UserResult> searchUsers(String searchKey) {
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) {
            return new List<UserResult>();
        }
        String keyword = '%' + searchKey.trim() + '%';
        List<UserResult> results = new List<UserResult>();
        for (User u : [
            SELECT Id, Name, Title
            FROM   User
            WHERE  Name LIKE :keyword
            AND    IsActive = true
            ORDER BY Name ASC
            LIMIT 10
        ]) {
            UserResult ur = new UserResult();
            ur.Id    = u.Id;
            ur.Name  = u.Name;
            ur.Title = u.Title;
            results.add(ur);
        }
        return results;
    }

    @AuraEnabled(cacheable=false)
    public static List<MemberRow> getContactMembers(Id recruitClassId, Id contactId) {
        List<MemberRow> rows = new List<MemberRow>();

        if (recruitClassId != null) {
            for (AccountContactRelation acr : [
                SELECT  Id,
                        ContactId,
                        Contact.Name,
                        Contact.LastName,
                        Contact.FirstName,
                        Contact.Account.Id,
                        Contact.TINS_NUMBER__c,
                        Contact.FAQP_Division__c,
                        Contact.FAQP_Region__c
                FROM    AccountContactRelation
                WHERE   AccountId = :recruitClassId
                AND     IsActive  = true
                ORDER BY Contact.LastName ASC, Contact.FirstName ASC
                LIMIT   500
            ]) {
                MemberRow row       = new MemberRow();
                row.memberId        = acr.Id;
                row.contactId       = acr.ContactId;
                row.personAccountId = acr.Contact?.Account?.Id;
                // Format as "LastName FirstName"
                String lastName  = acr.Contact?.LastName;
                String firstName = acr.Contact?.FirstName;
                row.contactName  = formatName(lastName, firstName);
                row.tins            = acr.Contact?.TINS_NUMBER__c;
                row.division        = acr.Contact?.FAQP_Division__c;
                row.region          = acr.Contact?.FAQP_Region__c != null
                                      ? String.valueOf(acr.Contact.FAQP_Region__c) : null;
                row.recruitClassId  = recruitClassId;
                rows.add(row);
            }
            return rows;
        }

        if (contactId != null) {
            List<Account> employees = [
                SELECT Id, Name, LastName, FirstName, TINS_NUMBER__pc, PersonContactId,
                       FAQP_Region__pc, FAQP_Division__pc
                FROM   Account
                WHERE  Id = :contactId
                AND    IsPersonAccount = true
                LIMIT  1
            ];

            if (!employees.isEmpty()) {
                Account emp = employees[0];
                if (emp.PersonContactId != null) {
                    MemberRow row       = new MemberRow();
                    row.memberId        = null;
                    row.contactId       = emp.PersonContactId;
                    row.personAccountId = emp.Id;
                    row.contactName     = formatName(emp.LastName, emp.FirstName);
                    row.tins            = emp.TINS_NUMBER__pc;
                    row.division        = emp.FAQP_Division__pc;
                    row.region          = String.valueOf(emp.FAQP_Region__pc);
                    row.recruitClassId  = null;
                    rows.add(row);
                }
            }
            return rows;
        }

        return rows;
    }

    @AuraEnabled(cacheable=false)
    public static Boolean checkRosterLabelExists(String rosterLabel) {
        if (String.isBlank(rosterLabel)) return false;
        String lowerLabel = rosterLabel.trim().toLowerCase();
        List<FIR_Qualification_Form__c> existing = [
            SELECT Id, Qual_Roster_Label__c
            FROM   FIR_Qualification_Form__c
            WHERE  Qual_Roster_Label__c != null
            LIMIT  2000
        ];
        for (FIR_Qualification_Form__c f : existing) {
            if (f.Qual_Roster_Label__c != null &&
                f.Qual_Roster_Label__c.trim().toLowerCase() == lowerLabel) {
                return true;
            }
        }
        return false;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // addToRoster — creates ONE FIR Qualification Form per contact,
    // then creates multiple FIR Weapon Qualification Detail records
    // from the weaponEntries array on each payload item.
    // ═══════════════════════════════════════════════════════════════════════
    @AuraEnabled
    public static Integer addToRoster(
        String rosterPayload,
        Id     recruitClassId,
        Date   testDate,
        Id     instructorId,
        String location,
        String rosterLabel
    ) {
        List<MemberPayload> payloadList =
            (List<MemberPayload>) JSON.deserialize(rosterPayload, List<MemberPayload>.class);

        if (payloadList == null || payloadList.isEmpty()) return 0;

        // Collect all contact Ids to resolve display names
        List<Id> allContactIds = new List<Id>();
        for (MemberPayload mp : payloadList) {
            if (String.isNotBlank(mp.contactId)) allContactIds.add(mp.contactId);
        }

        Map<Id, Contact> contactMap = allContactIds.isEmpty()
            ? new Map<Id, Contact>()
            : new Map<Id, Contact>([
                SELECT Id, Name FROM Contact WHERE Id IN :allContactIds
              ]);

        // Build one FIR Qualification Form per contact (per payload item)
        List<MemberPayload>             aligned  = new List<MemberPayload>();
        List<FIR_Qualification_Form__c> firForms = new List<FIR_Qualification_Form__c>();

        for (MemberPayload mp : payloadList) {
            if (String.isBlank(mp.contactId)) continue;

            Contact c           = contactMap.get(mp.contactId);
            String  displayName = (c != null ? c.Name : mp.contactName);
            if (String.isBlank(displayName)) continue;

            aligned.add(mp);

            FIR_Qualification_Form__c fir = new FIR_Qualification_Form__c(
                Name                 = displayName + ' - FIR',
                Test_Date__c         = testDate,
                Location__c          = location,
                Light_Condition__c   = mp.lightningCondition,
                ContactName__c       = mp.contactId,
                Qual_Roster_Label__c = String.isNotBlank(rosterLabel) ? rosterLabel.trim() : null
            );
            if (instructorId != null) fir.Firearms_Instrutor__c = instructorId;
            firForms.add(fir);
        }
        insert firForms;

        // Build FIR Weapon Qualification Detail records from weaponEntries
        List<FIR_Weapon_Qualification_Detail__c> weapons =
            new List<FIR_Weapon_Qualification_Detail__c>();

        for (Integer i = 0; i < aligned.size(); i++) {
            Id            firId = firForms[i].Id;
            MemberPayload mp    = aligned[i];

            if (mp.weaponEntries != null) {
                for (WeaponEntry we : mp.weaponEntries) {
                    FIR_Weapon_Qualification_Detail__c det = new FIR_Weapon_Qualification_Detail__c(
                        FIR_Qualification_Form__c = firId
                    );
                    if (String.isNotBlank(we.weaponType))   det.Weapon_Type__c   = we.weaponType;
                    if (String.isNotBlank(we.manufacturer)) det.Manufacturer__c  = we.manufacturer;
                    if (String.isNotBlank(we.model))        det.Model__c         = we.model;
                    if (String.isNotBlank(we.sightType))    det.Sight_Type__c    = we.sightType;
                    weapons.add(det);
                }
            }
        }
        if (!weapons.isEmpty()) insert weapons;

        return aligned.size();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Helper: format name as "LastName FirstName"
    // ═══════════════════════════════════════════════════════════════════════
    private static String formatName(String lastName, String firstName) {
        String ln = String.isNotBlank(lastName)  ? lastName.trim()  : '';
        String fn = String.isNotBlank(firstName) ? firstName.trim() : '';
        if (String.isNotBlank(ln) && String.isNotBlank(fn)) {
            return ln + ' ' + fn;
        }
        return String.isNotBlank(ln) ? ln : fn;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Inner classes
    // ═══════════════════════════════════════════════════════════════════════

    public class MemberRow {
        @AuraEnabled public String memberId;
        @AuraEnabled public String contactId;
        @AuraEnabled public String personAccountId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String tins;
        @AuraEnabled public String division;
        @AuraEnabled public String region;
        @AuraEnabled public String recruitClassId;
    }

    public class WeaponEntry {
        public String weaponType;
        public String manufacturer;
        public String model;
        public String sightType;
    }

    public class MemberPayload {
        public String memberId;
        public String contactId;
        public String contactName;
        public String lightningCondition;
        public List<WeaponEntry> weaponEntries;
    }

    public class SearchResultWrapper {
        @AuraEnabled public List<Account>           recruitClasses = new List<Account>();
        @AuraEnabled public List<ContactSearchItem> contacts       = new List<ContactSearchItem>();
    }

    public class ContactSearchItem {
        @AuraEnabled public Id     Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String TINS;
        @AuraEnabled public Id     PersonContactId;
    }

    public class UserResult {
        @AuraEnabled public Id     Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Title;
    }
}