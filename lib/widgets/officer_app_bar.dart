import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_profile_menu.dart';

class OfficerAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String officerId;
  final Color bgColor;          // kept for back-compat; used for dark gradient
  final bool useGradient;       // still supported; we apply it only in dark mode
  final bool showBack;

  const OfficerAppBar({
    super.key,
    required this.title,
    required this.officerId,
    this.bgColor = const Color(0xFF1E5AA8),
    this.useGradient = true,
    this.showBack = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    const radius = 25.0;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Colors switch with theme
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A); // slate-900
    final iconColor  = isDark ? Colors.white : const Color(0xFF0F172A);

    // Status bar icons stay readable
    final overlay = isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: AppBar(
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: showBack,
        surfaceTintColor: Colors.transparent, // no M3 tint
        iconTheme: IconThemeData(color: iconColor),
        backgroundColor:
        // Light mode: plain surface (white)
        isDark ? null : theme.colorScheme.surface,
        title: Text(
          title,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: titleColor,
          ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
        ),
        clipBehavior: Clip.antiAlias,
        // Dark mode only: blue gradient
        flexibleSpace: isDark && useGradient
            ? Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF2A6CCF), bgColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        )
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: AppProfileMenu(officerId: officerId),
          ),
        ],
      ),
    );
  }
}
