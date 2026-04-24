public with sharing class QualRosterController {

    @AuraEnabled(cacheable=true)
    public static SearchResultWrapper searchRecruitClassAndContacts(String searchKey) {
        SearchResultWrapper result = new SearchResultWrapper();
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) return result;

        String keyword = '%' + searchKey.trim() + '%';

        result.recruitClasses = [
            SELECT Id, Name
            FROM   Account
            WHERE  Name LIKE :keyword
            AND    RecordType.DeveloperName = 'FAQP_Account'
            ORDER BY Name ASC
            LIMIT 10
        ];

        List<Contact> rawContacts = [
            SELECT Id, Name, TINS_NUMBER__c
            FROM   Contact
            WHERE  (Name LIKE :keyword OR TINS_NUMBER__c LIKE :keyword)
            AND    TINS_NUMBER__c != null
            ORDER BY Name ASC
            LIMIT 10
        ];

        if (rawContacts.isEmpty()) {
            rawContacts = [
                SELECT Id, Name, TINS_NUMBER__c
                FROM   Contact
                WHERE  (Name LIKE :keyword OR TINS_NUMBER__c LIKE :keyword)
                ORDER BY TINS_NUMBER__c NULLS LAST, Name ASC
                LIMIT 10
            ];
        }

        Map<String, Contact> uniqueByName = new Map<String, Contact>();
        for (Contact c : rawContacts) {
            String key = c.Name.toLowerCase().trim();
            if (!uniqueByName.containsKey(key)) uniqueByName.put(key, c);
        }

        for (Contact c : uniqueByName.values()) {
            ContactSearchItem item = new ContactSearchItem();
            item.Id   = c.Id;
            item.Name = c.Name;
            item.TINS = c.TINS_NUMBER__c;
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
        System.debug('getContactMembers → recruitClassId=' + recruitClassId + ' | contactId=' + contactId);
        List<MemberRow> rows = new List<MemberRow>();

        if (recruitClassId != null) {
            for (FAQP_Members__c m : [
                SELECT  Id,
                        Contact__c,
                        Contact__r.Name,
                        Contact__r.TINS_NUMBER__c,
                        Contact__r.FAQP_Division__c,
                        Contact__r.FAQP_Region__c,
                        Recruit_Class__c
                FROM    FAQP_Members__c
                WHERE   Recruit_Class__c = :recruitClassId
                ORDER BY Contact__r.Name ASC
                LIMIT   500
            ]) {
                MemberRow row      = new MemberRow();
                row.memberId       = m.Id;
                row.contactId      = m.Contact__c;
                row.contactName    = m.Contact__r.Name;
                row.tins           = m.Contact__r.TINS_NUMBER__c;
                row.division       = m.Contact__r.FAQP_Division__c;
                row.region         = m.Contact__r.FAQP_Region__c != null
                                     ? String.valueOf(m.Contact__r.FAQP_Region__c) : null;
                row.recruitClassId = m.Recruit_Class__c;
                rows.add(row);
            }
            System.debug('Mode A rows: ' + rows.size());
            return rows;
        }

        if (contactId != null) {
            for (Contact c : [
                SELECT  Id, Name,
                        TINS_NUMBER__c,
                        FAQP_Division__c,
                        FAQP_Region__c
                FROM    Contact
                WHERE   Id = :contactId
                LIMIT   1
            ]) {
                MemberRow row      = new MemberRow();
                row.memberId       = null;
                row.contactId      = c.Id;
                row.contactName    = c.Name;
                row.tins           = c.TINS_NUMBER__c;
                row.division       = c.FAQP_Division__c;
                row.region         = c.FAQP_Region__c != null
                                     ? String.valueOf(c.FAQP_Region__c) : null;
                row.recruitClassId = null;
                rows.add(row);
            }
            System.debug('Mode B rows: ' + rows.size());
            return rows;
        }

        System.debug('getContactMembers: both params null');
        return rows;
    }

    @AuraEnabled(cacheable=false)
    public static Boolean checkRosterLabelExists(String rosterLabel) {
        if (String.isBlank(rosterLabel)) return false;
        String trimmed = rosterLabel.trim();
        // Use LOWER() on both sides for case-insensitive duplicate detection
        String lowerLabel = trimmed.toLowerCase();
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

        List<Id> memberIds = new List<Id>();
        for (MemberPayload mp : payloadList) {
            if (String.isNotBlank(mp.memberId)) memberIds.add(mp.memberId);
        }

        Map<Id, FAQP_Members__c> memberMap = memberIds.isEmpty()
            ? new Map<Id, FAQP_Members__c>()
            : new Map<Id, FAQP_Members__c>([
                SELECT Id, Contact__c, Contact__r.Name
                FROM   FAQP_Members__c
                WHERE  Id IN :memberIds
              ]);

        List<Id> contactIds = new List<Id>();
        for (MemberPayload mp : payloadList) {
            if (String.isBlank(mp.memberId) && String.isNotBlank(mp.contactId)) {
                contactIds.add(mp.contactId);
            }
        }

        Map<Id, Contact> contactMap = contactIds.isEmpty()
            ? new Map<Id, Contact>()
            : new Map<Id, Contact>([
                SELECT Id, Name FROM Contact WHERE Id IN :contactIds
              ]);

        List<MemberPayload>             aligned  = new List<MemberPayload>();
        List<FIR_Qualification_Form__c> firForms = new List<FIR_Qualification_Form__c>();

        for (MemberPayload mp : payloadList) {
            String displayName     = null;
            Id     resolvedContact = null;

            if (String.isNotBlank(mp.memberId)) {
                FAQP_Members__c m = memberMap.get(mp.memberId);
                if (m == null) continue;
                resolvedContact = m.Contact__c;
                displayName     = m.Contact__r != null ? m.Contact__r.Name : 'Member';
            } else if (String.isNotBlank(mp.contactId)) {
                Contact c       = contactMap.get(mp.contactId);
                resolvedContact = mp.contactId;
                displayName     = (c != null ? c.Name : mp.contactName);
            }

            if (String.isBlank(displayName)) continue;

            aligned.add(mp);

            FIR_Qualification_Form__c fir = new FIR_Qualification_Form__c(
                Name                  = displayName + ' - FIR',
                Test_Date__c          = testDate,
                Location__c           = location,
                ContactName__c        = resolvedContact,
                Qual_Roster_Label__c  = String.isNotBlank(rosterLabel) ? rosterLabel.trim() : null  // ← store label
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
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Pistol'
                ));
            }
            if (mp.shotgun == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Shot Gun'
                ));
            }
            if (mp.rifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Riffle'
                ));
            }
            if (mp.autoWeapon == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Automatic Weapon'
                ));
            }
            if (mp.precisionRifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Precision Riffle'
                ));
            }
        }
        if (!weapons.isEmpty()) insert weapons;

        return aligned.size();
    }

    public class MemberRow {
        @AuraEnabled public String memberId;
        @AuraEnabled public String contactId;
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
    }

    public class UserResult {
        @AuraEnabled public Id     Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Title;
    }
}