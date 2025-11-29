import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';

class HelpSupportPage extends StatelessWidget {
  final String officerId;
  const HelpSupportPage({super.key, required this.officerId});

  static const _accent = Color(0xFF1E5AA8);
  static const double _headerRadius = 25;

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  Future<void> _sendEmail(String email) async {
    final Uri launchUri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=Officer Support Request&body=Officer ID: OFF1001\n\nDescribe your issue:',
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(
          'Help & Support',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(_headerRadius)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      bottomNavigationBar: OfficerNavBar(
        officerId: officerId,
        currentIndex: 5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Officer Support',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF000080),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Column(
                children: [
                  _buildContactTile(
                    icon: Icons.phone_in_talk_rounded,
                    title: 'Technical Helpline',
                    subtitle: '1800-11-0099 (Internal)',
                    color: Colors.green,
                    onTap: () => _makePhoneCall('1800110099'),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildContactTile(
                    icon: Icons.email_rounded,
                    title: 'IT Support Email',
                    subtitle: 'tech-support@nyaysahayak.gov.in',
                    color: Colors.blue,
                    onTap: () => _sendEmail('tech-support@nyaysahayak.gov.in'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text(
              'Officer FAQs',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF000080),
              ),
            ),
            const SizedBox(height: 12),
            _buildExpansionTile(
              'How do I approve a loan verification?',
              'Open the loan detail page, review the uploaded photos/videos, and click "Approve" if they match the requirements.',
            ),
            _buildExpansionTile(
              'What if the beneficiary uploaded wrong photos?',
              'Click "Reject" on the specific proof item. The beneficiary will be notified to re-upload correct evidence.',
            ),
            _buildExpansionTile(
              'Can I verify beneficiaries offline?',
              'Currently, the officer dashboard requires an internet connection to fetch and verify live data from the server.',
            ),
            _buildExpansionTile(
              'How do I add a new beneficiary manually?',
              'Go to the Dashboard and click the "New Beneficiary" button. Fill in the details and a login SMS will be sent to them.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 24),
      ),
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600])),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
      onTap: onTap,
    );
  }

  Widget _buildExpansionTile(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              content,
              style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}