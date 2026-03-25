/**
 * QualRosterController.cls
 *
 * Methods:
 *  1. searchRecruitClassAndContacts  — live lookup: RC (Account/FAQP_Account) + Contacts
 *  2. searchUsers                    — live lookup: active Users by name
 *  3. getContactMembers              — FAQP_Members__c for selected RC
 *  4. addToRoster                    — creates FIR_Qualification_Form__c +
 *                                      FIR_Weapon_Qualification_Detail__c × 3 per member
 *
 * Key API names:
 *  Recruit Class  → Account (RecordType: FAQP_Account)
 *  Junction       → FAQP_Members__c  (Contact__c MD, Recruit_Class__c MD → Account)
 *  FIR Form       → FIR_Qualification_Form__c
 *  Weapon detail  → FIR_Weapon_Qualification_Detail__c  (Weapon_Type__c, Attempt_Date__c)
 *  Instructor     → FIR_Qualification_Form__c.Firearms_Instrutor__c (Lookup → User)
 *  Contact TINS   → TINS_NUMBER__c
 */
public with sharing class QualRosterController {

    // ─── 1. RC + Contact live lookup ──────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static SearchResultWrapper searchRecruitClassAndContacts(String searchKey) {
        SearchResultWrapper result = new SearchResultWrapper();
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) return result;

        String keyword = '%' + searchKey.trim() + '%';

        // Recruit Classes — Account with FAQP_Account record type
        result.recruitClasses = [
            SELECT Id, Name
            FROM Account
            WHERE Name LIKE :keyword
            AND RecordType.DeveloperName = 'FAQP_Account'
            ORDER BY Name ASC
            LIMIT 10
        ];

        // Contacts — search by Name or TINS, must be linked to an Account (RC)
        List<Contact> contacts = [
            SELECT Id, Name, TINS_NUMBER__c, AccountId, Account.Name
            FROM Contact
            WHERE (Name LIKE :keyword OR TINS_NUMBER__c LIKE :keyword)
            AND AccountId != null
            ORDER BY Name ASC
            LIMIT 10
        ];

        for (Contact c : contacts) {
            ContactSearchItem item = new ContactSearchItem();
            item.Id               = c.Id;
            item.Name             = c.Name;
            item.TINS             = c.TINS_NUMBER__c;
            item.RecruitClassId   = c.AccountId;
            item.RecruitClassName = c.Account != null ? c.Account.Name : '';
            result.contacts.add(item);
        }
        return result;
    }

    // ─── 2. User live lookup ───────────────────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<UserResult> searchUsers(String searchKey) {
        if (String.isBlank(searchKey) || searchKey.trim().length() < 1) {
            return new List<UserResult>();
        }
        String keyword = '%' + searchKey.trim() + '%';

        List<User> users = [
            SELECT Id, Name, Title
            FROM User
            WHERE Name LIKE :keyword
            AND IsActive = true
            ORDER BY Name ASC
            LIMIT 10
        ];

        List<UserResult> results = new List<UserResult>();
        for (User u : users) {
            UserResult ur = new UserResult();
            ur.Id    = u.Id;
            ur.Name  = u.Name;
            ur.Title = u.Title;
            results.add(ur);
        }
        return results;
    }

    // ─── 3. Contact Members ────────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<FAQP_Members__c> getContactMembers(Id recruitClassId) {
        if (recruitClassId == null) return new List<FAQP_Members__c>();

        return [
            SELECT
                Id, Name,
                Contact__c,
                Contact__r.Name,
                Contact__r.TINS_NUMBER__c,
                Contact__r.FAQP_Division__c,
                Contact__r.FAQP_Region__c,
                Recruit_Class__c
            FROM FAQP_Members__c
            WHERE Recruit_Class__c = :recruitClassId
            ORDER BY Contact__r.Name ASC
            LIMIT 500
        ];
    }

    // ─── 4. Add To Roster ──────────────────────────────────────────────────
    @AuraEnabled
    public static Integer addToRoster(
        String rosterPayload,
        Id     recruitClassId,
        Date   testDate,
        Id     instructorId,       // User Id passed directly from LWC
        String location
    ) {
        List<MemberPayload> payloadList =
            (List<MemberPayload>) JSON.deserialize(rosterPayload, List<MemberPayload>.class);

        if (payloadList == null || payloadList.isEmpty()) return 0;

        // Load FAQP_Members__c
        List<Id> memberIds = new List<Id>();
        for (MemberPayload mp : payloadList) memberIds.add(mp.memberId);

        Map<Id, FAQP_Members__c> memberMap = new Map<Id, FAQP_Members__c>([
            SELECT Id, Contact__c, Contact__r.Name
            FROM FAQP_Members__c
            WHERE Id IN :memberIds
        ]);

        // Build aligned lists
        List<MemberPayload>             aligned  = new List<MemberPayload>();
        List<FIR_Qualification_Form__c> firForms = new List<FIR_Qualification_Form__c>();

        for (MemberPayload mp : payloadList) {
            FAQP_Members__c m = memberMap.get(mp.memberId);
            if (m == null) continue;
            aligned.add(mp);

            FIR_Qualification_Form__c fir = new FIR_Qualification_Form__c(
                Name         = (m.Contact__r != null ? m.Contact__r.Name : 'Member') + ' – FIR',
                Test_Date__c = testDate,
                Location__c  = location
            );
            if (instructorId != null) fir.Firearms_Instrutor__c = instructorId;
            firForms.add(fir);
        }
        insert firForms;

        // Build FIR_Weapon_Qualification_Detail__c — only for selected (Yes) weapons
        List<FIR_Weapon_Qualification_Detail__c> weapons =
            new List<FIR_Weapon_Qualification_Detail__c>();

        for (Integer i = 0; i < aligned.size(); i++) {
            Id            fir = firForms[i].Id;
            MemberPayload mp  = aligned[i];

            if (mp.pistol == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Pistol',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.shotgun == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Shot Gun',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.rifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Riffle',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.autoWeapon == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Automatic Weapon',
                    Attempt_Date__c           = testDate
                ));
            }
            if (mp.precisionRifle == 'Yes') {
                weapons.add(new FIR_Weapon_Qualification_Detail__c(
                    FIR_Qualification_Form__c = fir,
                    Weapon_Type__c            = 'Precision Riffle',
                    Attempt_Date__c           = testDate
                ));
            }
        }
        if (!weapons.isEmpty()) {
            insert weapons;
        }

        return aligned.size();
    }

    // ─── Wrapper classes ───────────────────────────────────────────────────
    public class MemberPayload {
        public String memberId;
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
        @AuraEnabled public Id     RecruitClassId;
        @AuraEnabled public String RecruitClassName;
    }

    public class UserResult {
        @AuraEnabled public Id     Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String Title;
    }
}