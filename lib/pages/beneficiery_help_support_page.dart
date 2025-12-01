import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatefulWidget {
  final String userId;
  const HelpSupportPage({super.key, required this.userId});

  @override
  State<HelpSupportPage> createState() => _HelpSupportPageState();
}

class _HelpSupportPageState extends State<HelpSupportPage> {
  // ----------------------------
  // Complaint Form State
  // ----------------------------
  bool showForm = false;
  String? selectedCategory;
  String? selectedSubCategory;
  final TextEditingController issueCtrl = TextEditingController();

  // Problem Categories
  final Map<String, List<String>> problems = {
    "Verification Issues": [
      "GPS accuracy issues",
      "Camera not opening",
      "Media upload failing",
      "Step not updating"
    ],
    "Login / OTP Issues": [
      "Not receiving OTP",
      "Invalid OTP",
      "Phone number mismatch"
    ],
    "Loan Related": [
      "Loan not visible",
      "Incorrect process steps",
      "Progress not updating",
    ],
    "App Issues": [
      "App crashing",
      "Slow performance",
      "UI not loading",
    ]
  };

  // FAQs
  final List<Map<String, String>> faqList = [
    {
      "q": "Why is my GPS location not accurate?",
      "a":
      "Ensure you are outdoors or near a window, and enable high-accuracy location mode."
    },
    {
      "q": "Why is my verification not moving to the next step?",
      "a": "Ensure you have uploaded a clear image and stable internet."
    },
    {
      "q": "How to fix OTP not receiving?",
      "a":
      "Check network signal, disable DND, or try again after 60 seconds."
    },
    {
      "q": "Why can't I see my loan details?",
      "a":
      "Your loan may be pending officer verification. Try refreshing after some time."
    },
  ];

  // -------------------------------------------------------
  // Launch functions
  // -------------------------------------------------------
  Future<void> _callSupport() async {
    await launchUrl(Uri.parse("tel:9150462438"));
  }

  Future<void> _emailSupport() async {
    final Uri email = Uri(
      scheme: "mailto",
      path: "support@nyaysahayak.gov.in",
      query: "subject=App Support Request&body=User ID: ${widget.userId}\n\nDescribe your issue:",
    );
    await launchUrl(email);
  }

  // -------------------------------------------------------
  // Submit Complaint
  // -------------------------------------------------------
  void _submitComplaint() {
    if (selectedCategory == null ||
        selectedSubCategory == null ||
        issueCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Please fill all fields before submitting")),
      );
      return;
    }

    setState(() {
      showForm = false;
      selectedCategory = null;
      selectedSubCategory = null;
      issueCtrl.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Complaint filed successfully!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  // -------------------------------------------------------
  // UI
  // -------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Help & Support"),
        backgroundColor: const Color(0xFF1F6FEB),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // -------------------------------------------------------
            // QUICK SUPPORT CARDS
            // -------------------------------------------------------
            Text("Quick Assistance",
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(child: _supportCard(
                  icon: Icons.call,
                  color: Colors.green,
                  title: "Call Support",
                  onTap: _callSupport,
                )),
                const SizedBox(width: 14),
                Expanded(child: _supportCard(
                  icon: Icons.email_outlined,
                  color: Colors.orange,
                  title: "Send Email",
                  onTap: _emailSupport,
                )),
              ],
            ),

            const SizedBox(height: 20),

            // -------------------------------------------------------
            // RAISE COMPLAINT
            // -------------------------------------------------------
            Text("Raise a Complaint",
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),

            InkWell(
              onTap: () => setState(() => showForm = !showForm),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.report_problem_outlined,
                        color: Colors.red.shade700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        showForm
                            ? "Hide Complaint Form"
                            : "Open Complaint Form",
                        style: GoogleFonts.inter(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(
                      showForm
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.grey[700],
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            if (showForm) _complaintForm(),

            const SizedBox(height: 28),

            // -------------------------------------------------------
            // FAQ SECTION
            // -------------------------------------------------------
            Text("Frequently Asked Questions",
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 14),

            ...faqList.map((faq) => _faqTile(faq["q"]!, faq["a"]!)).toList(),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // SUPPORT CARD
  // -------------------------------------------------------
  Widget _supportCard({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 5))
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 8),
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------
  // COMPLAINT FORM
  // -------------------------------------------------------
  Widget _complaintForm() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Select Problem Category",
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          DropdownButtonFormField<String>(
            value: selectedCategory,
            hint: const Text("Choose category"),
            decoration: _inputDecoration(),
            items: problems.keys
                .map((c) =>
                DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              setState(() {
                selectedCategory = v;
                selectedSubCategory = null;
              });
            },
          ),

          const SizedBox(height: 16),

          if (selectedCategory != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Select Sub Category",
                    style: GoogleFonts.inter(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),

                DropdownButtonFormField<String>(
                  value: selectedSubCategory,
                  hint: const Text("Choose sub-category"),
                  decoration: _inputDecoration(),
                  items: (problems[selectedCategory] ?? [])
                      .map((sc) =>
                      DropdownMenuItem(value: sc, child: Text(sc)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedSubCategory = v),
                ),
              ],
            ),

          const SizedBox(height: 20),

          Text("Describe Your Issue",
              style: GoogleFonts.inter(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          TextField(
            controller: issueCtrl,
            maxLines: 4,
            decoration: _inputDecoration().copyWith(
              hintText: "Enter issue details...",
            ),
          ),

          const SizedBox(height: 20),

          ElevatedButton.icon(
            onPressed: _submitComplaint,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1F6FEB),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.send),
            label: const Text("Submit Complaint"),
          )
        ],
      ),
    );
  }

  // -------------------------------------------------------
  // FAQ TILE
  // -------------------------------------------------------
  Widget _faqTile(String q, String a) {
    return ExpansionTile(
      title: Text(q,
          style:
          GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(a, style: GoogleFonts.inter(fontSize: 13)),
        )
      ],
    );
  }

  // Input style
  InputDecoration _inputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF6F8FF),
      border:
      OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderSide:
        const BorderSide(color: Color(0xFFD3DAE6), width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide:
        const BorderSide(color: Color(0xFF1F6FEB), width: 1.4),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }
}
