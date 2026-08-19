/**
 * TestDataFactory
 * ---------------------------------------------------------------------------
 * Central builder for test data across the FAQP project. Keeps @testSetup in
 * every test class small and consistent, and isolates schema assumptions
 * (Person Accounts, record types, required fields) to ONE place so a schema
 * change only needs fixing here.
 */
@isTest
public class TestDataFactory {

    // ---- Record type resolution ------------------------------------------
    public static Id personAccountRtId() {
        return resolveAccountRt(new List<String>{ 'PersonAccount' }, true);
    }
    public static Id businessAccountRtId() {
        return resolveAccountRt(new List<String>{ 'FAQP_Account' }, false);
    }

    private static Id resolveAccountRt(List<String> devNames, Boolean wantPerson) {
        Map<String, Schema.RecordTypeInfo> byDev =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
        for (String dn : devNames) {
            if (byDev.containsKey(dn) && byDev.get(dn).isActive()) {
                return byDev.get(dn).getRecordTypeId();
            }
        }
        // Fallback: first active, available record type matching person-ness.
        for (Schema.RecordTypeInfo rti : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (rti.isActive() && rti.isAvailable() && !rti.isMaster()) {
                return rti.getRecordTypeId();
            }
        }
        return null; // org may not use record types
    }

    // ---- Person Accounts (employees / instructors / retired officers) -----
    public static Account buildPersonAccount(String firstName, String lastName, Decimal tins) {
        Account a = new Account(
            FirstName        = firstName,
            LastName         = lastName,
            TINS_NUMBER__c   = tins
            // ORG-SPECIFIC: add required __pc fields here if any
        );
        Id rt = personAccountRtId();
        if (rt != null) a.RecordTypeId = rt;
        return a;
    }

    public static List<Account> createPersonAccounts(Integer count, Boolean instructor) {
        List<Account> accts = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            Account a = buildPersonAccount('Test', 'Person' + i, 7000000000L + i);
            accts.add(a);
        }
        insert accts;
        // Set the person-level instructor flag after insert (field lives on Account)
        if (instructor) {
            for (Account a : accts) {
                try { a.put('Is_Firearms_Instructor__pc', true); } catch (Exception e) {}
            }
            update accts;
        }
        return accts;
    }

    public static Account createPersonAccount(String firstName, String lastName, Decimal tins) {
        Account a = buildPersonAccount(firstName, lastName, tins);
        insert a;
        return a;
    }

    // Requery to obtain PersonContactId (populated after insert)
    public static Id personContactId(Id accountId) {
        return [SELECT PersonContactId FROM Account WHERE Id = :accountId LIMIT 1].PersonContactId;
    }

    // ---- Business Account (Recruit Class / FTU Group) ---------------------
    public static Account createRecruitClass(String name) {
        Account a = new Account(Name = name);
        Id rt = businessAccountRtId();
        if (rt != null) a.RecordTypeId = rt;
        insert a;
        return a;
    }

    // ---- FIR Qualification Forms -----------------------------------------
    public static FIR_Qualification_Form__c buildForm(String rosterLabel, Id contactId, Id instructorUserId) {
        return new FIR_Qualification_Form__c(
            Name                  = 'Test Form',
            Qual_Roster_Label__c  = rosterLabel,
            ContactName__c        = contactId,
            Firearms_Instrutor__c = instructorUserId,
            Test_Date__c          = Date.today(),
            Location__c           = 'Test Location',
            Light_Condition__c    = 'DayTime / Normal Lighting'
            // ORG-SPECIFIC: add required fields / valid picklist values here
        );
    }

    public static List<FIR_Qualification_Form__c> createForms(
        String rosterLabel, List<Id> contactIds, Id instructorUserId
    ) {
        List<FIR_Qualification_Form__c> forms = new List<FIR_Qualification_Form__c>();
        for (Id cId : contactIds) {
            forms.add(buildForm(rosterLabel, cId, instructorUserId));
        }
        insert forms;
        return forms;
    }

    // ---- Weapon Qualification Details ------------------------------------
    public static FIR_Weapon_Qualification_Detail__c buildDetail(Id formId, String weaponType) {
        return new FIR_Weapon_Qualification_Detail__c(
            FIR_Qualification_Form__c = formId,
            Weapon_Type__c            = weaponType,
            Manufacturer__c           = 'Sig Sauer',
            Model__c                  = 'P365',
            Sight_Type__c             = 'Optic'
        );
    }

    public static List<FIR_Weapon_Qualification_Detail__c> createDetails(
        List<Id> formIds, String weaponType
    ) {
        List<FIR_Weapon_Qualification_Detail__c> dets = new List<FIR_Weapon_Qualification_Detail__c>();
        for (Id fId : formIds) {
            dets.add(buildDetail(fId, weaponType));
        }
        insert dets;
        return dets;
    }

    // ---- AccountContactRelation (junction) -------------------------------
    public static AccountContactRelation linkContactToAccount(Id accountId, Id contactId) {
        // Person accounts auto-create a direct ACR; for indirect links insert one.
        List<AccountContactRelation> existing = [
            SELECT Id FROM AccountContactRelation
            WHERE AccountId = :accountId AND ContactId = :contactId LIMIT 1
        ];
        if (!existing.isEmpty()) return existing[0];
        AccountContactRelation acr = new AccountContactRelation(
            AccountId = accountId,
            ContactId = contactId
        );
        insert acr;
        return acr;
    }

    // ---- Running user (for Firearms_Instrutor__c = User lookup) ----------
    public static Id currentUserId() {
        return UserInfo.getUserId();
    }
}