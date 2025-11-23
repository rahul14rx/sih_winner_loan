class LoanApplication {
  final String loanId;
  final String applicantName;
  final String loanType;
  final double amount;
  final String status; // 'pending', 'verified', 'rejected', 'not verified'
  final String dateApplied;
  final String userId; // Helpful for linking back to user specific data

  LoanApplication({
    required this.loanId,
    required this.applicantName,
    required this.loanType,
    required this.amount,
    required this.status,
    required this.dateApplied,
    required this.userId,
  });

  // Factory constructor to create a LoanApplication from a JSON map
  factory LoanApplication.fromJson(Map<String, dynamic> json) {
    return LoanApplication(
      loanId: json['loan_id']?.toString() ?? '',
      applicantName: json['applicant_name'] ?? 'Unknown Beneficiary',
      loanType: json['loan_type'] ?? 'General Loan',
      // Safely handle int or double for amount
      amount: (json['amount'] is int)
          ? (json['amount'] as int).toDouble()
          : (json['amount'] as double? ?? 0.0),
      status: json['status'] ?? 'pending',
      dateApplied: json['date_applied'] ?? 'N/A',
      userId: json['user_id']?.toString() ?? '',
    );
  }

  // Method to convert LoanApplication instance back to JSON map (if needed)
  Map<String, dynamic> toJson() {
    return {
      'loan_id': loanId,
      'applicant_name': applicantName,
      'loan_type': loanType,
      'amount': amount,
      'status': status,
      'date_applied': dateApplied,
      'user_id': userId,
    };
  }
}