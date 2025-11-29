import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:loan2/pages/bank_dashboard_page.dart';
import 'package:loan2/pages/create_beneficiary_page.dart';
import 'package:loan2/pages/history_page.dart';
import 'package:loan2/pages/reports_page.dart';
import 'package:loan2/pages/profile_settings_page.dart';
import 'package:loan2/pages/help_support_page.dart';

class OfficerNavBar extends StatelessWidget {
  final int currentIndex;
  final String officerId;
  const OfficerNavBar({super.key, required this.currentIndex, required this.officerId});

  static const blue = Color(0xFF1E5AA8);

  void _go(BuildContext context, int i) {
    if (i == currentIndex) return;

    Widget page;
    if (i == 0) {
      page = BankDashboardPage(officerId: officerId);
    } else if (i == 1) {
      page = CreateBeneficiaryPage(officerId: officerId);
    } else if (i == 2) {
      page = HistoryPage(officerId: officerId);
    } else if (i == 3) {
      page = ReportsPage(officerId: officerId);
    } else if (i == 4) {
      page = ProfileSettingsPage(officerId: officerId);
    } else {
      page = HelpSupportPage(officerId: officerId);
    }

    // Always make Dashboard the root
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => BankDashboardPage(officerId: officerId)),
          (_) => false,
    );

    // If user tapped a tab other than Home, push it on top of Dashboard
    if (i != 0) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
    }
  }


  Widget _item(BuildContext context, int i, IconData icon, String label) {
    final active = i == currentIndex;
    final c = active ? blue : Colors.grey[500];

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _go(context, i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, active ? -6 : 0),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: active ? blue.withOpacity(0.12) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: c, size: 24),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: c,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: [
            _item(context, 0, Icons.home_rounded, "Home"),
            _item(context, 1, Icons.person_add_alt_1_rounded, "New Beneficiary"),
            _item(context, 2, Icons.history_rounded, "History"),
            _item(context, 3, Icons.analytics_rounded, "Reports"),
            _item(context, 4, Icons.person_outline_rounded, "Profile"),
            _item(context, 5, Icons.help_outline_rounded, "Help"),
          ],
        ),
      ),
    );
  }
}