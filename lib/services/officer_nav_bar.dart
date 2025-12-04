import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:loan2/pages/bank_dashboard_page.dart';
import 'package:loan2/pages/history_page.dart';
import 'package:loan2/pages/reports_page.dart';
import 'package:loan2/pages/help_support_page.dart';

class OfficerNavBar extends StatelessWidget {
  /// OLD indices still used across app:
  /// 0 Home, 1 New Beneficiary (removed), 2 History, 3 Reports, 4 Profile (removed), 5 Help
  final int currentIndex;
  final String officerId;

  const OfficerNavBar({
    super.key,
    required this.currentIndex,
    required this.officerId,
  });

  static const blue = Color(0xFF1E5AA8);

  // Map OLD indices (0..5) -> NEW visible indices (0..3)
  int _mapOldToNew(int old) {
    switch (old) {
      case 0:
        return 0;
      case 2:
        return 1;
      case 3:
        return 2;
      case 5:
        return 3;
      default:
        return 0;
    }
  }

  // Map NEW visible indices (0..3) -> OLD indices (0..5)
  int _mapNewToOld(int idx) {
    switch (idx) {
      case 0:
        return 0;
      case 1:
        return 2;
      case 2:
        return 3;
      case 3:
        return 5;
      default:
        return 0;
    }
  }

  void _go(BuildContext context, int newIndex) {
    final oldIndex = _mapNewToOld(newIndex);
    if (oldIndex == currentIndex) return;

    Widget page;
    if (oldIndex == 0) {
      page = BankDashboardPage(officerId: officerId);
    } else if (oldIndex == 2) {
      page = HistoryPage(officerId: officerId);
    } else if (oldIndex == 3) {
      page = ReportsPage(officerId: officerId);
    } else {
      page = HelpSupportPage(officerId: officerId);
    }

    // KEEP your existing nav behavior
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => BankDashboardPage(officerId: officerId)),
          (_) => false,
    );

    if (oldIndex != 0) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _mapOldToNew(currentIndex);

    // ✅ lock text scale so this looks identical across pages (prevents overflow too)
    final mq = MediaQuery.of(context);
    final fixedMq = mq.copyWith(textScaleFactor: 1.0);
    final safeBottom = mq.padding.bottom;

    const items = <_NavItem>[
      _NavItem(icon: Icons.home_rounded, label: "Home"),
      _NavItem(icon: Icons.history_rounded, label: "History"),
      _NavItem(icon: Icons.analytics_rounded, label: "Reports"),
      _NavItem(icon: Icons.help_outline_rounded, label: "Help"),
    ];

    return MediaQuery(
      data: fixedMq,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;

          // ---------- TUNING (matches goal image) ----------
          const double barH = 68.0; // slightly taller to avoid any label overflow
          const double cornerRadius = 26.0;
          const double innerHPad = 18.0;

          final innerW = (w - innerHPad * 2).clamp(200.0, w);
          final itemW = innerW / items.length;

          // Active tab X in BAR coords
          final centerX = innerHPad + itemW * (selectedIndex + 0.5);

          // Bubble size (FAB)
          final bubbleSize = (itemW * 0.70).clamp(42.0, 52.0);
          final bubbleR = bubbleSize / 2;

          // Notch radius slightly bigger than bubble => “engraved seat”
          final notchR = (bubbleR + 10.0).clamp(bubbleR + 8.0, bubbleR + 12.0);

          // Push bubble DOWN into the notch (this is the “seated” effect)
          final embed = (bubbleR * 0.95).clamp(15.0, 30.0);

          // Bubble position: bottom lower than bar top => pushed down into bar
          final bubbleBottom = safeBottom + barH - embed;

          // Extra top to avoid clipping
          final extraTop = (bubbleR + 16.0).clamp(32.0, 48.0);
          final totalH = safeBottom + barH + extraTop;

          return SizedBox(
            height: totalH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // BAR with TRUE circular concave notch (FAB-style)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: PhysicalShape(
                    color: blue,
                    elevation: 0,
                    clipper: _FabNotchClipper(
                      notchCenterX: centerX,
                      notchRadius: notchR,
                      cornerRadius: cornerRadius,
                    ),
                    child: SizedBox(
                      height: safeBottom + barH,
                      child: Stack(
                        children: [
                          // ✅ Engraved rim + inner shadow INSIDE the notch
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _NotchEngravePainter(
                                notchCenterX: centerX,
                                notchRadius: notchR,
                              ),
                            ),
                          ),

                          // Tabs
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              innerHPad,
                              8,          // ✅ less top padding
                              innerHPad,
                              6 + safeBottom,
                            ),

                            child: Row(
                              children: List.generate(items.length, (i) {
                                final active = i == selectedIndex;
                                final it = items[i];

                                return Expanded(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(18),
                                    onTap: () => _go(context, i),
                                    child: SizedBox(
                                      height: barH,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          // Keep space stable: hide active icon here, bubble shows it
                                          Opacity(
                                            opacity: active ? 0.0 : 1.0,
                                            child: Icon(
                                              it.icon,
                                              size: 22,
                                              color: Colors.white.withOpacity(0.72),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              it.label,
                                              style: GoogleFonts.inter(
                                                fontSize: 10.5,
                                                height: 1.0,
                                                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                                                color: Colors.white.withOpacity(active ? 1.0 : 0.70),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Active FAB bubble (sits in the notch and is pushed down a bit)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  left: centerX - bubbleR,
                  bottom: bubbleBottom,
                  child: Container(
                    width: bubbleSize,
                    height: bubbleSize,
                    decoration: BoxDecoration(
                      color: Color.lerp(blue, Colors.white, 0.06),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.30), width: 2),
                    ),
                    child: Center(
                      child: Icon(
                        items[selectedIndex].icon,
                        color: Colors.white,
                        size: (bubbleSize * 0.52).clamp(20.0, 26.0),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

/// True FAB-style concave notch (perfect circular cut-out).
class _FabNotchClipper extends CustomClipper<Path> {
  final double notchCenterX;
  final double notchRadius;
  final double cornerRadius;

  const _FabNotchClipper({
    required this.notchCenterX,
    required this.notchRadius,
    required this.cornerRadius,
  });

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;

    final r = cornerRadius.clamp(0.0, 32.0);
    final nr = notchRadius.clamp(18.0, 40.0);

    final startX = (notchCenterX - nr).clamp(r, w - r);
    final endX = (notchCenterX + nr).clamp(r, w - r);

    final p = Path();

    // Top-left rounded
    p.moveTo(0, r);
    p.quadraticBezierTo(0, 0, r, 0);

    // Go to notch start
    p.lineTo(startX, 0);

    // Concave notch: bottom half of a circle centered on the top edge (y=0)
    // Start angle PI (left) sweep -PI => goes downward through PI/2 (y+)
    p.arcTo(
      Rect.fromCircle(center: Offset(notchCenterX, 0), radius: nr),
      math.pi,
      -math.pi,
      false,
    );

    // Continue to top-right rounded
    p.lineTo(w - r, 0);
    p.quadraticBezierTo(w, 0, w, r);

    // Down to bottom (flat)
    p.lineTo(w, h);
    p.lineTo(0, h);
    p.close();

    return p;
  }

  @override
  bool shouldReclip(covariant _FabNotchClipper oldClipper) {
    return oldClipper.notchCenterX != notchCenterX ||
        oldClipper.notchRadius != notchRadius ||
        oldClipper.cornerRadius != cornerRadius;
  }
}

/// Paints the engraved “valley” effect inside the notch:
/// - inner shadow (depth)
/// - rim highlight (engraved edge)
class _NotchEngravePainter extends CustomPainter {
  final double notchCenterX;
  final double notchRadius;

  const _NotchEngravePainter({
    required this.notchCenterX,
    required this.notchRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final nr = notchRadius;
    final rect = Rect.fromCircle(center: Offset(notchCenterX, 0), radius: nr);

    // Soft fill shadow inside notch (makes it feel carved)
    final shadeRect = Rect.fromLTWH(
      notchCenterX - nr,
      0,
      nr * 2,
      nr * 1.6,
    );

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00000000),
          Color(0x22000000),
          Color(0x35000000),
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(shadeRect);

    final fillPath = Path()
      ..addArc(rect, math.pi, -math.pi)
      ..lineTo(notchCenterX + nr, nr * 1.6)
      ..lineTo(notchCenterX - nr, nr * 1.6)
      ..close();

    canvas.drawPath(fillPath, fillPaint);

    // Rim highlight (upper edge)
    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = Colors.white.withOpacity(0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2);

    canvas.drawArc(rect, math.pi, -math.pi, false, highlight);

    // Inner dark rim slightly “inside” the notch
    final shadowRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..color = Colors.black.withOpacity(0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

    canvas.save();
    canvas.translate(0, math.min(2.6, nr * 0.16));
    canvas.drawArc(rect, math.pi, -math.pi, false, shadowRim);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NotchEngravePainter oldDelegate) {
    return oldDelegate.notchCenterX != notchCenterX ||
        oldDelegate.notchRadius != notchRadius;
  }
}
