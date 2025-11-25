import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

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
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFFFF9933),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Contact Support
            Text(
              'Officer Support',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF000080)),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
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

            // Section 2: Report Issue
            Text(
              'Report an Issue',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF000080)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Facing issues with verification sync or beneficiary data? Log a ticket directly.',
                    style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600], height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Redirecting to internal ticketing system...')),
                        );
                      },
                      icon: const Icon(Icons.bug_report_rounded, size: 20),
                      label: Text('Raise Ticket', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Section 3: FAQs
            Text(
              'Officer FAQs',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF000080)),
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
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
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