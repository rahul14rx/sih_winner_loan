import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/services/bank_service.dart';
import 'package:loan2/pages/help_support_page.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';

class ProfileSettingsPage extends StatefulWidget {
  final String officerId;
  const ProfileSettingsPage({super.key, required this.officerId});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  static const blue = Color(0xFF1E5AA8);
  static const double headerRadius = 25;

  final BankService _bankService = BankService();
  late Future<Map<String, dynamic>> _f;

  bool _notifs = true;
  bool _dark = false;
  String _lang = "English";

  @override
  void initState() {
    super.initState();
    _f = _bankService.fetchOfficerProfile(widget.officerId);
  }

  Future<void> _retry() async {
    setState(() => _f = _bankService.fetchOfficerProfile(widget.officerId));
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s), behavior: SnackBarBehavior.floating),
    );
  }

  Map<String, dynamic> _unwrap(Map<String, dynamic> m) {
    final d = m['data'];
    if (d is Map) return Map<String, dynamic>.from(d as Map);
    return m;
  }

  String _pick(Map<String, dynamic> m, List<String> keys, String fallback) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return fallback;
  }

  Future<void> _copy(String label, String value) async {
    if (value.trim().isEmpty || value.trim() == "—") return;
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (!mounted) return;
    _toast("$label copied");
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text("Logout?", style: GoogleFonts.poppins(fontWeight: FontWeight.w900)),
        content: Text(
          "Are you sure you want to logout from this officer account?",
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel", style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text("Logout", style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _dark;

    final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF6F7FB);
    final card = isDark ? const Color(0xFF0F1B2D) : Colors.white;
    final border = isDark ? const Color(0xFF1F2A44) : const Color(0xFFF1F5F9);
    final titleC = isDark ? Colors.white : const Color(0xFF111827);
    final subC = isDark ? Colors.white70 : Colors.grey.shade700;
    final soft = isDark ? const Color(0xFF12233D) : const Color(0xFFF8FAFC);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: blue,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          "My Profile",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  title: Text("About", style: GoogleFonts.poppins(fontWeight: FontWeight.w900)),
                  content: Text(
                    "Nyay Sahayak\nOfficer dashboard profile & settings.",
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("Close", style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
                    )
                  ],
                ),
              );
            },
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
          ),
          const SizedBox(width: 6),
        ],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(headerRadius)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final pad = w >= 600 ? 20.0 : 16.0;

            return Padding(
              padding: EdgeInsets.fromLTRB(pad, 14, pad, 14),
              child: Column(
                children: [
                  Expanded(
                    flex: 44,
                    child: FutureBuilder<Map<String, dynamic>>(
                      future: _f,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return _profileLoadingCard(card, border);
                        }
                        if (snap.hasError) {
                          return _profileErrorCard(card, border, titleC, subC);
                        }

                        final raw = snap.data ?? {};
                        final m = _unwrap(raw);

                        final name = _pick(m, ["name", "officer_name", "full_name"], "Bank Officer");
                        final oid = _pick(m, ["officerId", "officer_id", "loan_officer_id", "id"], widget.officerId);
                        final branch = _pick(m, ["branch", "branch_name"], "Branch");
                        final bank = _pick(m, ["bank", "bank_name"], "Bank");
                        final city = _pick(m, ["city", "location"], "");
                        final email = _pick(m, ["email", "mail"], "");
                        final phone = _pick(m, ["phone", "mobile"], "");

                        final contact = email.isNotEmpty ? email : (phone.isNotEmpty ? phone : "—");
                        final place = city.isNotEmpty ? city : "$bank • $branch";

                        return _profileCard(
                          card: card,
                          border: border,
                          titleC: titleC,
                          subC: subC,
                          soft: soft,
                          name: name,
                          officerId: oid,
                          place: place,
                          contact: contact,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    flex: 56,
                    child: _settingsCard(card, border, titleC, subC, soft),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: OfficerNavBar(currentIndex: 4, officerId: widget.officerId),
    );
  }

  Widget _profileLoadingCard(Color card, Color border) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  children: [
                    Container(height: 14, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(99))),
                    const SizedBox(height: 10),
                    Container(height: 12, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(99))),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(child: Container(height: 44, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(14)))),
              const SizedBox(width: 12),
              Expanded(child: Container(height: 44, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(14)))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileErrorCard(Color card, Color border, Color titleC, Color subC) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 34),
          const SizedBox(height: 10),
          Text(
            "Couldn’t load profile",
            style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 16, color: titleC),
          ),
          const SizedBox(height: 6),
          Text(
            "Check your server/API and try again.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: subC),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _retry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: blue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text("Retry", style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: blue)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard({
    required Color card,
    required Color border,
    required Color titleC,
    required Color subC,
    required Color soft,
    required String name,
    required String officerId,
    required String place,
    required String contact,
  }) {
    final initials = officerId.isNotEmpty
        ? officerId.substring(0, officerId.length >= 2 ? 2 : 1).toUpperCase()
        : "OF";

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    initials,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w900, color: blue, fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 16, color: titleC),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: subC, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: blue.withOpacity(0.18)),
                ),
                child: Text(
                  "Officer",
                  style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _miniInfoCard(
                  soft: soft,
                  border: border,
                  titleC: titleC,
                  subC: subC,
                  title: "Officer ID",
                  value: officerId,
                  icon: Icons.badge_rounded,
                  onTap: () => _copy("Officer ID", officerId),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _miniInfoCard(
                  soft: soft,
                  border: border,
                  titleC: titleC,
                  subC: subC,
                  title: "Contact",
                  value: contact,
                  icon: Icons.call_rounded,
                  onTap: () => _copy("Contact", contact),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniInfoCard({
    required Color soft,
    required Color border,
    required Color titleC,
    required Color subC,
    required String title,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: blue.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: blue, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: subC)),
                  const SizedBox(height: 2),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w900, color: titleC)),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.copy_rounded, size: 16, color: subC),
          ],
        ),
      ),
    );
  }

  Widget _settingsCard(Color card, Color border, Color titleC, Color subC, Color soft) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        children: [
          Row(
            children: [
              Text("Settings", style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 14, color: titleC)),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openLanguageSheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: blue.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text("Language: $_lang", style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              )
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, g) {
                final tileH = (g.maxHeight - 12) / 2;
                return GridView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    mainAxisExtent: tileH,
                  ),
                  children: [
                    _toggleTile(
                      soft: soft,
                      border: border,
                      titleC: titleC,
                      subC: subC,
                      title: "Notifications",
                      subtitle: "Alerts & updates",
                      icon: Icons.notifications_active_rounded,
                      value: _notifs,
                      onChanged: (v) {
                        setState(() => _notifs = v);
                        _toast(v ? "Notifications enabled" : "Notifications disabled");
                      },
                    ),
                    _toggleTile(
                      soft: soft,
                      border: border,
                      titleC: titleC,
                      subC: subC,
                      title: "Dark Mode",
                      subtitle: "UI appearance",
                      icon: Icons.dark_mode_rounded,
                      value: _dark,
                      onChanged: (v) {
                        setState(() => _dark = v);
                        _toast(v ? "Dark mode ON (profile only)" : "Dark mode OFF");
                      },
                    ),
                    _actionTile(
                      soft: soft,
                      border: border,
                      titleC: titleC,
                      subC: subC,
                      title: "Help & Support",
                      subtitle: "FAQs and contact",
                      icon: Icons.help_outline_rounded,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => HelpSupportPage(officerId: widget.officerId)),
                        );
                      },
                    ),
                    _actionTile(
                      soft: soft,
                      border: border,
                      titleC: titleC,
                      subC: subC,
                      title: "Logout",
                      subtitle: "Exit officer account",
                      icon: Icons.logout_rounded,
                      danger: true,
                      onTap: _confirmLogout,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openLanguageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(99))),
              const SizedBox(height: 12),
              Text("Language", style: GoogleFonts.poppins(fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              _langTile("English"),
              _langTile("Hindi"),
              _langTile("Tamil"),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _langTile(String label) {
    final active = _lang == label;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        setState(() => _lang = label);
        Navigator.pop(context);
        _toast("Language set to $label");
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: active ? blue.withOpacity(0.10) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? blue.withOpacity(0.25) : const Color(0xFFEFF2F7)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: const Color(0xFF111827)))),
            Icon(active ? Icons.check_circle_rounded : Icons.circle_outlined, color: active ? blue : Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _toggleTile({
    required Color soft,
    required Color border,
    required Color titleC,
    required Color subC,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: blue.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: blue, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                        color: titleC,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: subC,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeColor: blue,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }


  Widget _actionTile({
    required Color soft,
    required Color border,
    required Color titleC,
    required Color subC,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final iconBg = danger ? const Color(0xFFFFEBEE) : blue.withOpacity(0.12);
    final iconColor = danger ? const Color(0xFFDC2626) : blue;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: soft,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontWeight: FontWeight.w900, fontSize: 12.5, color: titleC)),
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11, color: subC)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class ProfileSettingsPageState {
  static const blue = Color(0xFF1E5AA8);
}