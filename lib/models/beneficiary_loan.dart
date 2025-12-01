// lib/models/beneficiary_loan.dart
//
// Single source of truth for ProcessStep:
// - Imports ProcessStep from models/process_step.dart
// - Robust fromJson that accepts many backend shapes
// - No duplicate ProcessStep class here

import 'package:loan2/models/process_step.dart';

class BeneficiaryLoan {
  final String loanId;
  final String? userId;
  final String? applicantName;
  final String? loanType;
  final String? scheme;
  final String? status;
  final dynamic amount;      // keep dynamic because API can be num or String
  final String? dateApplied;

  final List<ProcessStep> processes;

  BeneficiaryLoan({
    required this.loanId,
    this.userId,
    this.applicantName,
    this.loanType,
    this.scheme,
    this.status,
    this.amount,
    this.dateApplied,
    required this.processes,
  });

  // Try many key aliases safely
  static T? _firstOf<T>(Map<String, dynamic> j, List<String> keys) {
    for (final k in keys) {
      if (j.containsKey(k) && j[k] != null) return j[k] as T?;
    }
    return null;
  }

  factory BeneficiaryLoan.fromJson(Map<String, dynamic> json) {
    // Some APIs wrap the object:
    final Map<String, dynamic> j = (() {
      if (json.containsKey('loan') && json['loan'] is Map<String, dynamic>) {
        return (json['loan'] as Map).cast<String, dynamic>();
      }
      if (json.containsKey('loan_details') && json['loan_details'] is Map<String, dynamic>) {
        return (json['loan_details'] as Map).cast<String, dynamic>();
      }
      if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
        return (json['data'] as Map).cast<String, dynamic>();
      }
      return json;
    })();

    final loanId = (_firstOf(j, ['loan_id', 'loanId', 'id']) ?? '').toString();

    // processes could live under various keys
    final dynamic rawSteps =
        j['processes'] ??
            j['steps'] ??
            j['verification_steps'] ??
            j['process'] ??
            j['loan_process'] ??
            [];

    final List<ProcessStep> processes = [];
    if (rawSteps is List) {
      for (final e in rawSteps) {
        if (e is ProcessStep) {
          processes.add(e);
        } else if (e is Map<String, dynamic>) {
          processes.add(ProcessStep.fromJson(e));
        } else if (e is Map) {
          processes.add(ProcessStep.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    return BeneficiaryLoan(
      loanId: loanId,
      userId: _firstOf(j, ['user_id', 'userId', 'beneficiary', 'beneficiary_id'])?.toString(),
      applicantName: _firstOf(j, ['applicant_name', 'applicantName', 'name'])?.toString(),
      loanType: _firstOf(j, ['loan_type', 'loanType'])?.toString(),
      scheme: _firstOf(j, ['scheme', 'scheme_name', 'schemeName'])?.toString(),
      status: _firstOf(j, ['status', 'loan_status'])?.toString(),
      amount: j.containsKey('amount') ? j['amount'] : (j['sanctioned_amount'] ?? j['sanctionedAmount']),
      dateApplied: _firstOf(j, ['date_applied', 'applied_on', 'created_at', 'createdAt'])?.toString(),
      processes: processes,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'loan_id': loanId,
      'user_id': userId,
      'applicant_name': applicantName,
      'loan_type': loanType,
      'scheme': scheme,
      'status': status,
      'amount': amount,
      'date_applied': dateApplied,
      'processes': processes.map((e) => e.toJson()).toList(),
    };
  }
}
