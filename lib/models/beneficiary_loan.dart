class BeneficiaryLoan {
  final String loanId;
  final String userId;
  final String applicantName;
  final double amount;
  final String loanType;
  final String scheme;
  final String dateApplied;
  final String status;

  final int? shopFloors;
  final int? stages;
  final Map<int, double> stageUtilization;

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
    this.shopFloors,
    this.stages,
    this.stageUtilization = const {},
  });

  factory BeneficiaryLoan.fromJson(Map<String, dynamic> json) {
    final rawList = (json['process'] ?? json['processes']) as List? ?? [];
    final processes = rawList.map((e) => ProcessStep.fromJson(Map<String, dynamic>.from(e))).toList();

    final uid = (json['user_id'] ?? json['userid'] ?? '')?.toString() ?? '';
    final sid = (json['loan_id'] ?? '')?.toString() ?? '';

    final su = <int, double>{};
    final rawSu = json['stage_utilization'];
    if (rawSu is Map) {
      for (final entry in rawSu.entries) {
        final k = int.tryParse(entry.key.toString());
        final v = (entry.value is num) ? (entry.value as num).toDouble() : double.tryParse(entry.value.toString());
        if (k != null && v != null) su[k] = v;
      }
    }

    int? _toInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

    return BeneficiaryLoan(
      loanId: sid,
      userId: uid,
      applicantName: (json['applicant_name'] ?? 'Unknown Beneficiary')?.toString() ?? 'Unknown Beneficiary',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      loanType: (json['loan_type'] ?? 'General')?.toString() ?? 'General',
      scheme: (json['scheme'] ?? 'Standard')?.toString() ?? 'Standard',
      dateApplied: (json['date_applied'] ?? '')?.toString() ?? '',
      status: (json['status'] ?? 'not verified')?.toString() ?? 'not verified',
      processes: processes,
      shopFloors: _toInt(json['shop_floors']),
      stages: _toInt(json['stages']),
      stageUtilization: su,
    );
  }
}

class ProcessStep {
  final String id;
  final int processId;
  final String whatToDo;
  final String dataType;
  final String status;

  final bool isRequired;
  final String? fileId;
  final String? mediaUrl;
  final String? uploadedAt;
  final double? utilizationAmount;

  ProcessStep({
    required this.id,
    required this.processId,
    required this.whatToDo,
    required this.dataType,
    required this.status,
    this.isRequired = true,
    this.fileId,
    this.mediaUrl,
    this.uploadedAt,
    this.utilizationAmount,
  });

  factory ProcessStep.fromJson(Map<String, dynamic> json) {
    dynamic pid = json['process_id'] ?? json['processid'] ?? json['processId'];
    int p = 0;
    if (pid is int) {
      p = pid;
    } else {
      p = int.tryParse(pid?.toString() ?? '') ?? 0;
    }

    final st = (json['status'] ?? json['process_status'] ?? 'not verified')?.toString() ?? 'not verified';
    final dt = (json['data_type'] ?? json['dataType'] ?? 'image')?.toString() ?? 'image';

    bool req = true;
    final rr = json['is_required'] ?? json['required'] ?? json['isRequired'];
    if (rr is bool) req = rr;
    if (rr is String) req = rr.toLowerCase() != 'false';

    double? util;
    final u = json['utilization_amount'];
    if (u is num) util = u.toDouble();
    if (u is String) util = double.tryParse(u);

    return ProcessStep(
      id: (json['id'] ?? '')?.toString() ?? '',
      processId: p,
      whatToDo: (json['what_to_do'] ?? '')?.toString() ?? '',
      dataType: dt,
      status: st,
      isRequired: req,
      fileId: json['file_id']?.toString(),
      mediaUrl: json['media_url']?.toString(),
      uploadedAt: json['uploaded_at']?.toString(),
      utilizationAmount: util,
    );
  }
}
