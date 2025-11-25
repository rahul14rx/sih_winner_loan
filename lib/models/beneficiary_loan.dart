class BeneficiaryLoan {
  final String userId;
  final String loanId;
  final List<ProcessStep> processes;

  // New fields for dynamic display
  final String applicantName;
  final double amount;
  final String loanType;
  final String scheme;
  final String dateApplied;
  final String status;

  BeneficiaryLoan({
    required this.userId,
    required this.loanId,
    required this.processes,
    this.applicantName = '',
    this.amount = 0.0,
    this.loanType = '',
    this.scheme = '',
    this.dateApplied = '',
    this.status = '',
  });

  factory BeneficiaryLoan.fromJson(Map<String, dynamic> json) {
    var list = json['process'] as List? ?? [];
    List<ProcessStep> processList = list.map((i) => ProcessStep.fromJson(i)).toList();

    return BeneficiaryLoan(
      // Support both naming conventions if backend varies
      userId: json['user_id']?.toString() ?? json['userid']?.toString() ?? '',
      loanId: json['loan_id']?.toString() ?? '',
      processes: processList,
      
      applicantName: json['applicant_name']?.toString() ?? 'Unknown',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      loanType: json['loan_type']?.toString() ?? 'Loan',
      scheme: json['scheme']?.toString() ?? 'General',
      dateApplied: json['date_applied']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Pending',
    );
  }
}

class ProcessStep {
  final String id; // "P1"
  final int processId; // 1
  final String whatToDo;
  final String dataType; // "image" or "video"
  final String status; // "not verified", "verified"

  ProcessStep({
    required this.id,
    required this.processId,
    required this.whatToDo,
    required this.dataType,
    required this.status,
  });

  factory ProcessStep.fromJson(Map<String, dynamic> json) {
    // Handle 'processid' vs 'process_id'
    var pId = json['processid'] ?? json['process_id'];
    int parsedId = 0;
    if (pId is int) {
      parsedId = pId;
    } else if (pId != null) {
      parsedId = int.tryParse(pId.toString()) ?? 0;
    }

    return ProcessStep(
      id: json['id']?.toString() ?? '',
      processId: parsedId,
      whatToDo: json['what_to_do'] ?? '',
      dataType: json['data_type'] ?? 'image',
      // Handle 'process_status' vs 'status'
      status: json['process_status'] ?? json['status'] ?? 'not verified',
    );
  }
}
