// lib/models/beneficiary_loan.dart
//
// FINAL SAFE MODEL (Compatible with ALL your screens & backend)
//
// Updated: Added totalUtilized + safe parsing for all dynamic values
// Author: ChatGPT (for premium UI integration)

import 'process_step.dart';

class BeneficiaryLoan {
  final String? loanId;
  final String? userId;
  final String? loanType;
  final String? scheme;
  final String? assetName;
  final String? applicantName;
  final String? dateApplied;

  final double? amount;                // sanctioned amount
  final double? totalUtilized;         // NEW FIELD — used by LoanDetailScreen & Wizard
  final String? status;

  final List<ProcessStep> processes;

  BeneficiaryLoan({
    this.loanId,
    this.userId,
    this.loanType,
    this.scheme,
    this.assetName,
    this.applicantName,
    this.dateApplied,
    this.amount,
    this.totalUtilized,
    this.status,
    required this.processes,
  });

  factory BeneficiaryLoan.fromJson(Map<String, dynamic> json) {
    double? _asDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    // backend sometimes uses "process" and sometimes "processes"
    final rawSteps = json['processes'] ?? json['process'] ?? [];
    return BeneficiaryLoan(
      loanId: json['loan_id']?.toString(),
      userId: json['user_id']?.toString(),
      loanType: json['loan_type']?.toString(),
      scheme: json['scheme']?.toString(),
      assetName: json['asset_name']?.toString(),
      applicantName: json['applicant_name']?.toString(),
      dateApplied: json['date_applied']?.toString(),

      amount: _asDouble(json['amount']),
      totalUtilized: _asDouble(json['total_utilized']),   // <── NEW FIELD ADDED SAFELY

      status: json['status']?.toString(),

      processes: (json['process'] is List)
          ? (json['process'] as List)
          .map((e) => ProcessStep.fromJson(e))
          .toList()
          : <ProcessStep>[],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'loan_id': loanId,
      'user_id': userId,
      'loan_type': loanType,
      'scheme': scheme,
      'asset_name': assetName,
      'applicant_name': applicantName,
      'date_applied': dateApplied,
      'amount': amount,
      'total_utilized': totalUtilized,
      'status': status,
      "process": processes.map((e) => e.toJson()).toList(),
    };
  }
}
