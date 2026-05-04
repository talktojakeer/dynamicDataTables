public with sharing class QualRosterController {

    private static final String FAQP_ACCOUNT_RT  = 'FAQP_Account';
    private static final String PERSON_ACCOUNT_RT = 'PersonAccount';

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
            SELECT Id, Name, TINS_NUMBER__c, PersonContactId
            FROM   Account
            WHERE  IsPersonAccount = true
            AND    RecordType.DeveloperName = :PERSON_ACCOUNT_RT
            AND    (Name LIKE :keyword OR TINS_NUMBER__c LIKE :keyword)
            AND    TINS_NUMBER__c != null
            ORDER BY Name ASC
            LIMIT  10
        ];

        if (rawEmployees.isEmpty()) {
            rawEmployees = [
                SELECT Id, Name, TINS_NUMBER__c, PersonContactId
                FROM   Account
                WHERE  IsPersonAccount = true
                AND    RecordType.DeveloperName = :PERSON_ACCOUNT_RT
                AND    (Name LIKE :keyword OR TINS_NUMBER__c LIKE :keyword)
                ORDER BY TINS_NUMBER__c NULLS LAST, Name ASC
                LIMIT  10
            ];
        }

        Map<String, Account> uniqueByName = new Map<String, Account>();
        for (Account a : rawEmployees) {
            String key = a.Name.toLowerCase().trim();
            if (!uniqueByName.containsKey(key)) uniqueByName.put(key, a);
        }

        for (Account a : uniqueByName.values()) {
            ContactSearchItem item  = new ContactSearchItem();
            item.Id              = a.Id;
            item.Name            = a.Name;
            item.TINS            = a.TINS_NUMBER__c;
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
                        Contact.Account.Id,
                        Contact.Account.TINS_NUMBER__c,
                        Contact.FAQP_Division__c,
                        Contact.FAQP_Region__c
                FROM    AccountContactRelation
                WHERE   AccountId = :recruitClassId
                AND     IsActive  = true
                ORDER BY Contact.Name ASC
                LIMIT   500
            ]) {
                MemberRow row       = new MemberRow();
                row.memberId        = acr.Id;                         
                row.contactId       = acr.ContactId;                  
                row.personAccountId = acr.Contact?.Account?.Id;       
                row.contactName     = acr.Contact?.Name;
                row.tins            = acr.Contact?.Account?.TINS_NUMBER__c;
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
                SELECT Id, Name, TINS_NUMBER__c, PersonContactId
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
                    row.contactName     = emp.Name;
                    row.tins            = emp.TINS_NUMBER__c;
                    row.division        = null;
                    row.region          = null;
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

        List<Id> allContactIds = new List<Id>();
        for (MemberPayload mp : payloadList) {
            if (String.isNotBlank(mp.contactId)) allContactIds.add(mp.contactId);
        }

        Map<Id, Contact> contactMap = allContactIds.isEmpty()
            ? new Map<Id, Contact>()
            : new Map<Id, Contact>([
                SELECT Id, Name FROM Contact WHERE Id IN :allContactIds
              ]);

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
                ContactName__c       = mp.contactId,
                Qual_Roster_Label__c = String.isNotBlank(rosterLabel) ? rosterLabel.trim() : null
            );
            if (instructorId != null) fir.Firearms_Instrutor__c = instructorId;
            firForms.add(fir);
        }
        insert firForms;

        List<FIR_Weapon_Qualification_Detail__c> weapons =
            new List<FIR_Weapon_Qualification_Detail__c>();

        for (Integer i = 0; i < aligned.size(); i++) {
            Id            fir = firForms[i].Id;
            MemberPayload mp  = aligned[i];

            if (mp.pistol == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir, Weapon_Type__c = 'Pistol'));
            }
            if (mp.shotgun == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir, Weapon_Type__c = 'Shot Gun'));
            }
            if (mp.rifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir, Weapon_Type__c = 'Riffle'));
            }
            if (mp.autoWeapon == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir, Weapon_Type__c = 'Automatic Weapon'));
            }
            if (mp.precisionRifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir, Weapon_Type__c = 'Precision Riffle'));
            }
        }
        if (!weapons.isEmpty()) insert weapons;

        return aligned.size();
    }

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

    public class MemberPayload {
        public String memberId;
        public String contactId;        
        public String contactName;
        public String pistol;
        public String shotgun;
        public String rifle;
        public String autoWeapon;
        public String precisionRifle;
        public String lightningCondition;
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