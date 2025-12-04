import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';

class HelpSupportPage extends StatelessWidget {
  final String officerId;
  const HelpSupportPage({super.key, required this.officerId});

  // Keep the blue accent; let the rest follow theme.
  static const _accent = Color(0xFF1E5AA8);
  static const double _headerRadius = 25;

  Future<void> _makePhoneCall(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendEmail(String email) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': 'Officer Support Request',
        'body': 'Officer ID: $officerId\n\nDescribe your issue:',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bg = theme.scaffoldBackgroundColor;
    final card = theme.cardColor;
    final onSurface = theme.colorScheme.onSurface;
    final divider = theme.dividerColor.withOpacity(isDark ? 0.15 : 0.35);
    final border = isDark ? const Color(0xFF1F2A44) : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Help & Support',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(_headerRadius)),
        ),
        clipBehavior: Clip.antiAlias,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2A6CCF), _accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      bottomNavigationBar: OfficerNavBar(officerId: officerId, currentIndex: 5),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('Officer Support', onSurface),
            const SizedBox(height: 12),
            _cardBox(
              color: card,
              border: border,
              child: Column(
                children: [
                  _contactTile(
                    icon: Icons.phone_in_talk_rounded,
                    title: 'Technical Helpline',
                    subtitle: '1800-11-0099 (Internal)',
                    badgeColor: const Color(0xFF22C55E),
                    onTap: () => _makePhoneCall('1800110099'),
                    onSurface: onSurface,
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: divider, indent: 16, endIndent: 16),
                  _contactTile(
                    icon: Icons.email_rounded,
                    title: 'IT Support Email',
                    subtitle: 'tech-support@nyaysahayak.gov.in',
                    badgeColor: const Color(0xFF38BDF8),
                    onTap: () => _sendEmail('tech-support@nyaysahayak.gov.in'),
                    onSurface: onSurface,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle('Officer FAQs', onSurface),
            const SizedBox(height: 12),
            _faqTile(
              title: 'How do I approve a loan verification?',
              content:
              'Open the loan detail page, review the uploaded photos/videos, and tap “Approve” if they meet the requirements.',
              card: card,
              border: border,
              onSurface: onSurface,
              divider: divider,
            ),
            _faqTile(
              title: 'What if the beneficiary uploaded wrong photos?',
              content:
              'Tap “Reject” on that proof. The beneficiary will be notified to re-upload the correct evidence.',
              card: card,
              border: border,
              onSurface: onSurface,
              divider: divider,
            ),
            _faqTile(
              title: 'Can I verify beneficiaries offline?',
              content:
              'The officer dashboard needs internet to fetch and update verification data in real time.',
              card: card,
              border: border,
              onSurface: onSurface,
              divider: divider,
            ),
            _faqTile(
              title: 'How do I add a new beneficiary manually?',
              content:
              'From Dashboard, tap “New Beneficiary”, fill the details, and a login SMS will be sent to them.',
              card: card,
              border: border,
              onSurface: onSurface,
              divider: divider,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- widgets ----------

  Widget _sectionTitle(String t, Color onSurface) => Text(
    t,
    style: GoogleFonts.poppins(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: onSurface,
    ),
  );

  Widget _cardBox({required Widget child, required Color color, required Color border}) => Container(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );

  Widget _contactTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color badgeColor,
    required VoidCallback onTap,
    required Color onSurface,
    required bool isDark,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: badgeColor.withOpacity(isDark ? 0.18 : 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isDark ? Colors.white : badgeColor, size: 22),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15, color: onSurface),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.inter(fontSize: 13, color: onSurface.withOpacity(0.7)),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: onSurface.withOpacity(0.6)),
    );
  }

  Widget _faqTile({
    required String title,
    required String content,
    required Color card,
    required Color border,
    required Color onSurface,
    required Color divider,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Theme(
        data: ThemeData().copyWith(dividerColor: divider),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          collapsedIconColor: onSurface.withOpacity(0.7),
          iconColor: onSurface,
          title: Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: onSurface),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                content,
                style: GoogleFonts.inter(fontSize: 13, color: onSurface.withOpacity(0.7), height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
