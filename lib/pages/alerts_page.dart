// ===============================
// ALERTS / NOTIFICATIONS PAGE
// Dynamic from backend (/user?id=)
// ===============================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:loan2/pages/beneficiary_dashboard.dart';


class AlertsPage extends StatefulWidget {
  final String userId;
  const AlertsPage({super.key, required this.userId});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _alerts = [];

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => BeneficiaryDashboard(userId: widget.userId),
      ),
          (route) => false,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  // =====================================
  // LOAD FROM BACKEND
  // GET /user?id=<id>
  // =====================================
  Future<void> _loadAlerts() async {
    try {
      setState(() => _loading = true);

      final url = Uri.parse("http://172.20.10.11:5000/user?id=${widget.userId}");
      final res = await http.get(url);

      if (res.statusCode != 200) {
        setState(() => _loading = false);
        return;
      }

      final parsed = json.decode(res.body);
      final List loans = parsed["data"] ?? [];

      List<Map<String, dynamic>> out = [];

      for (var loan in loans) {
        final loanId = loan["loan_id"];

        // Loan-level status
        String loanStatus = (loan["status"] ?? "").toLowerCase();
        if (loanStatus == "verified") {
          out.add(_makeAlert(
            title: "Loan Verified",
            msg: "Your loan #$loanId was successfully verified.",
            type: "success",
            time: DateTime.now(),
          ));
        } else if (loanStatus == "rejected") {
          out.add(_makeAlert(
            title: "Loan Rejected",
            msg: "Your loan #$loanId has been rejected.",
            type: "error",
            time: DateTime.now(),
          ));
        }

        // Process-level status
        for (var p in (loan["process"] ?? [])) {
          final status = (p["status"] ?? "").toLowerCase();
          final updatedAt = p["uploaded_at"];
          DateTime t = DateTime.now();
          if (updatedAt != null) {
            try {
              t = DateTime.parse(updatedAt);
            } catch (_) {}
          }

          if (p["file_id"] != null) {
            out.add(_makeAlert(
              title: "Media Uploaded",
              msg: "Uploaded: ${p["what_to_do"]}",
              type: "pending",
              time: t,
            ));
          }

          if (status == "verified") {
            out.add(_makeAlert(
              title: "Document Verified",
              msg: "${p["what_to_do"]} is verified.",
              type: "verify",
              time: t,
            ));
          }

          if (status == "rejected") {
            out.add(_makeAlert(
              title: "Document Rejected",
              msg: "${p["what_to_do"]} was rejected by officer.",
              type: "error",
              time: t,
            ));
          }

          if (status == "pending_review") {
            out.add(_makeAlert(
              title: "Pending Review",
              msg: "${p["what_to_do"]} is waiting for officer review.",
              type: "pending",
              time: t,
            ));
          }
        }
      }

      // Sort by latest first
      out.sort((a, b) => b["time"].compareTo(a["time"]));

      if (mounted) {
        setState(() {
          _alerts = out;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  // BUILD NOTIFICATION OBJECT
  Map<String, dynamic> _makeAlert({
    required String title,
    required String msg,
    required String type,
    required DateTime time,
  }) {
    return {
      "title": title,
      "message": msg,
      "type": type,
      "time": time,
      "read": false,
    };
  }

  // -----------------------------------------
  // ICON FOR TYPE
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

  // COLOR FOR TYPE
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
  // ALERT CARD UI
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
        border: Border.all(
          color: col.withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: col.withOpacity(0.15),
            child: Icon(icon, color: col),
          ),
          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a["title"],
                    style: GoogleFonts.inter(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(a["message"],
                    style: GoogleFonts.inter(
                        fontSize: 13, color: Colors.black87)),
                const SizedBox(height: 10),
                Text(
                  DateFormat("dd MMM yyyy • hh:mm a").format(a["time"]),
                  style: GoogleFonts.inter(
                      fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),

          if (!a["read"])
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: col, shape: BoxShape.circle),
            )
        ],
      ),
    );
  }

  // -----------------------------------------
  // MAIN BUILD
  // -----------------------------------------
  @override
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _goHome();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 18),
          child: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _goHome,
            ),
            title: Text(
              "Alerts",
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
            centerTitle: true,
            backgroundColor: const Color(0xFF1F6FEB),
            foregroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(25),
              ),
            ),
            bottom: const PreferredSize(
              preferredSize: Size.fromHeight(18),
              child: SizedBox(height: 18),
            ),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadAlerts,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _alerts.isEmpty
              ? Center(
            child: Text(
              "No alerts yet",
              style: GoogleFonts.inter(fontSize: 15),
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _alerts.length,
            itemBuilder: (_, i) => _alertCard(_alerts[i]),
          ),
        ),
      ),
    );
  }

}