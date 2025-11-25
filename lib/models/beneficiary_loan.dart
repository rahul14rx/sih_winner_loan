class BeneficiaryLoan {
  final String loanId;
  final String userId;
  final String applicantName;
  final double amount;
  final String loanType;
  final String scheme;
  final String dateApplied;
  final String status;
  final List<ProcessStep> processes;

  BeneficiaryLoan({
    required this.loanId,
    required this.userId,
    required this.applicantName,
    required this.amount,
    required this.loanType,
    required this.scheme,
    required this.dateApplied,
    required this.status,
    required this.processes,
  });

  factory BeneficiaryLoan.fromJson(Map<String, dynamic> json) {
    var list = json['process'] as List? ?? [];
    List<ProcessStep> processList = list.map((i) => ProcessStep.fromJson(i)).toList();

    return BeneficiaryLoan(
      loanId: json['loan_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      applicantName: json['applicant_name']?.toString() ?? 'Unknown Beneficiary',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      loanType: json['loan_type']?.toString() ?? 'General',
      scheme: json['scheme']?.toString() ?? 'Standard',
      dateApplied: json['date_applied']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Pending',
      processes: processList,
    );
  }
}

class ProcessStep {
  final String id;
  final int processId;
  final String whatToDo;
  final String dataType;
  final String status;

  ProcessStep({
    required this.id,
    required this.processId,
    required this.whatToDo,
    required this.dataType,
    required this.status,
  });

  factory ProcessStep.fromJson(Map<String, dynamic> json) {
    return ProcessStep(
      id: json['id']?.toString() ?? '',
      processId: json['process_id'] as int? ?? 0,
      whatToDo: json['what_to_do']?.toString() ?? '',
      dataType: json['data_type']?.toString() ?? 'image',
      status: json['status']?.toString() ?? 'pending',
    );
  }
}
