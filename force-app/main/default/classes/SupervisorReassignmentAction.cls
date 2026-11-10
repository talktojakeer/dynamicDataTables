/**
 * Invocable entry point for the "Reassign Supervisor" screen flow.
 * Thin wrapper - all logic lives in SupervisorReassignmentService.
 */
public with sharing class SupervisorReassignmentAction {

    public class Request {
        @InvocableVariable(label='Primary Supervisor Id' required=true)
        public Id primarySupervisorId;
        @InvocableVariable(label='Temporary Supervisor Id' required=true)
        public Id temporarySupervisorId;
        @InvocableVariable(label='Reason for Reassignment' required=true)
        public String reason;
        @InvocableVariable(label='Start Date' required=true)
        public Date startDate;
        @InvocableVariable(label='End Date' required=true)
        public Date endDate;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Employee Count')
        public Integer employeeCount;
    }

    @InvocableMethod(
        label='Reassign Supervisor'
        description='Moves every employee reporting to the Primary Supervisor to the Temporary Supervisor for the given date window.'
        category='MSA Drug Test'
    )
    public static List<Result> reassign(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) {
            SupervisorReassignmentService.ReassignRequest sr = new SupervisorReassignmentService.ReassignRequest();
            sr.primarySupervisorId    = r.primarySupervisorId;
            sr.temporarySupervisorId  = r.temporarySupervisorId;
            sr.reason                 = r.reason;
            sr.startDate              = r.startDate;
            sr.endDate                = r.endDate;

            SupervisorReassignmentService.ReassignResult out = SupervisorReassignmentService.reassign(sr);

            Result res = new Result();
            res.success       = out.success;
            res.message       = out.message;
            res.employeeCount = out.employeeCount;
            results.add(res);
        }
        return results;
    }
}