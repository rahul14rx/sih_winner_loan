import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/services/app_theme.dart';

class AppProfileMenu extends StatelessWidget {
  final String officerId;
  const AppProfileMenu({super.key, required this.officerId});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<int>(
      offset: const Offset(0, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: Colors.white.withOpacity(0.25),
        child: Text(
          (officerId.isNotEmpty ? officerId[0] : 'O').toUpperCase(),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<int>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Text('Quick Settings',
              style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
        ),
        PopupMenuItem<int>(
          value: 1,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.nightlight_round, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Dark mode',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              ),
              Switch(
                value: isDark,
                onChanged: (v) {
                  Navigator.pop(ctx);
                  AppTheme.toggle(v); // global theme toggle you already use
                },
                activeColor: Colors.white,                 // thumb
                activeTrackColor: const Color(0xFF1E5AA8), // dark bluish track
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: Colors.black87,        // proper black track in light mode
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<int>(
          value: 2,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, size: 18),
              const SizedBox(width: 10),
              Text('Logout', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
      onSelected: (v) {
        if (v == 2) {
          Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
        }
      },
    );
  }
}
