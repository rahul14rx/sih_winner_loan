import 'package:flutter/material.dart';
import 'package:loan2/pages/beneficiary_dashboard.dart';

class Nav {
  /// Always land on BeneficiaryDashboard as the new root.
  static void toDashboard(BuildContext context, String userId) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/dashboard'),
        builder: (_) => BeneficiaryDashboard(userId: userId),
      ),
          (route) => false,
    );
  }

  /// Intercept back: if you want *always* Dashboard (not pop), call this.
  static Future<bool> backToDashboard(BuildContext context, String userId) async {
    toDashboard(context, userId);
    return false; // we handled it
  }
}
