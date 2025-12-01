// ===============================
// ALERTS / NOTIFICATIONS PAGE
// Premium UI – Integrated with backend
// ===============================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class AlertsPage extends StatefulWidget {
  final String userId;
  const AlertsPage({super.key, required this.userId});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  List<Map<String, dynamic>> _alerts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    try {
      setState(() => _loading = true);

      // TODO: Replace with your backend API call
      await Future.delayed(const Duration(milliseconds: 500));

      // Example backend-style data
      _alerts = [
        {
          "title": "Loan Approved",
          "message": "Your loan #1821 has been approved by NBCFDC.",
          "time": DateTime.now().subtract(const Duration(minutes: 10)),
          "type": "success",
          "read": false
        },
        {
          "title": "Document Verified",
          "message": "Asset front-view image successfully verified.",
          "time": DateTime.now().subtract(const Duration(hours: 2)),
          "type": "verify",
          "read": true
        },
        {
          "title": "New Step Pending",
          "message": "A new verification step has been added to your request.",
          "time": DateTime.now().subtract(const Duration(days: 1)),
          "type": "pending",
          "read": true
        },
      ];

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // -----------------------------------------
  // Icon by notification type
  // -----------------------------------------
  IconData _iconForType(String type) {
    switch (type) {
      case "success":
        return Icons.check_circle;
      case "verify":
        return Icons.verified_user;
      case "pending":
        return Icons.pending_actions;
      case "error":
        return Icons.error_outline;
      default:
        return Icons.notifications_none;
    }
  }

  // -----------------------------------------
  // Color badge by type
  // -----------------------------------------
  Color _colorForType(String type) {
    switch (type) {
      case "success":
        return Colors.green;
      case "verify":
        return Colors.blue;
      case "pending":
        return Colors.orange;
      case "error":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // -----------------------------------------
  // Build Single Notification Card
  // -----------------------------------------
  Widget _alertCard(Map<String, dynamic> a) {
    final icon = _iconForType(a["type"]);
    final col = _colorForType(a["type"]);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: a["read"] ? Colors.white : const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(
          color: a["read"] ? Colors.grey.shade200 : col.withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: col.withOpacity(0.12),
            child: Icon(icon, color: col),
          ),
          const SizedBox(width: 14),

          // TEXT SECTION
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a["title"],
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  a["message"],
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  DateFormat("dd MMM yyyy • hh:mm a").format(a["time"]),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),

          // READ DOT
          if (!a["read"])
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: col,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }

  // -----------------------------------------
  // MAIN BUILD
  // -----------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      appBar: AppBar(
        title: Text("Alerts", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0.4,
      ),

      body: RefreshIndicator(
        onRefresh: _loadAlerts,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _alerts.isEmpty
            ? Center(
          child: Text(
            "No alerts available",
            style: GoogleFonts.inter(fontSize: 15),
          ),
        )
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _alerts.length,
          itemBuilder: (context, i) => _alertCard(_alerts[i]),
        ),
      ),
    );
  }
}
