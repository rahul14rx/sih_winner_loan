class BeneficiaryLoan {
  final String userId;
  final String loanId;
  final List<ProcessStep> processes;

  BeneficiaryLoan({
    required this.userId,
    required this.loanId,
    required this.processes,
  });

  factory BeneficiaryLoan.fromJson(Map<String, dynamic> json) {
    var list = json['process'] as List? ?? [];
    List<ProcessStep> processList = list.map((i) => ProcessStep.fromJson(i)).toList();

    return BeneficiaryLoan(
      userId: json['userid']?.toString() ?? '', // backend sends 'userid'
      loanId: json['loan_id']?.toString() ?? '',
      processes: processList,
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
    return ProcessStep(
      id: json['id']?.toString() ?? '',
      processId: json['process_id'] is int ? json['process_id'] : int.tryParse(json['process_id'].toString()) ?? 0,
      whatToDo: json['what_to_do'] ?? '',
      dataType: json['data_type'] ?? 'image',
      status: json['status'] ?? 'not verified',
    );
  }
}