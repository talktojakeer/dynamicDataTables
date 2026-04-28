public class recruitClassController {
    @AuraEnabled(cacheable=true)
    public static List<Account> searchContacts(String searchKey, Boolean selectedModel) {
        list<Account> searchcontacts = new list<Account>();
        system.debug('Search Accounts '+searchKey+' >> '+selectedModel);
        try{
            if(selectedModel){
                String key = searchKey + '%';        
                searchcontacts = [SELECT Id, firstName, LastName,TINS_NUMBER__c FROM Account 
                                  WHERE ispersonAccount = true and  firstName LIKE :key
                                  ORDER BY Name LIMIT 50];
            }else{        
                searchcontacts = [SELECT Id, firstName, LastName,TINS_NUMBER__c FROM Account where  ispersonAccount = true ORDER BY Name LIMIT 50];
            }
            system.debug('searchcontacts '+searchcontacts);
        }catch(exception ex){
            
        }
        return searchcontacts;
    }
    
    @AuraEnabled
    public static void updateContactsWithRecruitClass(Id recruitClassId, List<Id> contactIds){
        try {
            List<Account> searchcontacts = [SELECT Id,LastName,firstName,PersonContactId FROM Account WHERE ispersonAccount = true and Id IN :contactIds];
            List<AccountContactRelation> insertContactMembers = new List<AccountContactRelation>();
            for(Account c : searchcontacts){
                AccountContactRelation cm = new AccountContactRelation();
                cm.contactId = c.PersonContactId;
                cm.AccountId = recruitClassId;
                insertContactMembers.add(cm);
            }
            insert insertContactMembers;
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<Account> findContacts( List<Map<String, String>> contactsData ) {
        if (contactsData == null || contactsData.isEmpty()) {
            throw new AuraHandledException('No data received');
        }
        
        List<Account> contactsList = new List<Account>();
        set<string> tins = new Set<string>();
        for (Map<String, String> row : contactsData) {
            string tinsNumber = row.get('tins');
            tins.add(tinsNumber);
        }
        system.debug('tinsnumber '+tins);
        if(!tins.isempty()){
            for(Account con: [select Id, firstName, LastName,TINS_NUMBER__c from Account where ispersonAccount = true and TINS_NUMBER__c IN: tins]){
                contactsList.add(con);
            }
        }
        
        system.debug('contactsList '+contactsList.size());
        return contactsList;
    }
    @AuraEnabled(cacheable=true)
    public static List<Account> getRecruitClasses() {
        return [
            SELECT Id, Name, FAQP_Recruit_model__c
            FROM Account where RecordType.Name ='FAQP_Account'
            ORDER BY CreatedDate DESC
        ];
    }
    
    @AuraEnabled
    public static Boolean recruitClassDupblicateCheck(string accName){
        try {
            List<Account> accList = [SELECT Id FROM Account WHERE Name = :accName AND RecordType.Name = 'FAQP_Account' LIMIT 1 ];
            return !accList.isEmpty();
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}