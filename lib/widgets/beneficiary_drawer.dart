import 'package:flutter/material.dart';

class BeneficiaryDrawer extends StatelessWidget {
  final String userName;
  final String userId;

  const BeneficiaryDrawer({
    super.key,
    this.userName = "Beneficiary", // Default fallback
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // 1. Premium Header with Gradient
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF9933), Color(0xFFFFFFFE)], // Saffron to Green
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: Text(
              userName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            accountEmail: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "ID: $userId",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : "B",
                style: const TextStyle(
                  fontSize: 28,
                  color: Color(0xFFFF9933), // Saffron text
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // 2. Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildDrawerItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  title: "My Dashboard",
                  onTap: () {
                    Navigator.pop(context); // Close drawer
                    // We are already on dashboard, so no push needed
                  },
                  isSelected: true,
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.person_outline,
                  title: "My Profile",
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navigate to Profile Page
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.history,
                  title: "Application History",
                  onTap: () {
                    Navigator.pop(context);
                    // TODO: Navigate to History
                  },
                ),
                const Divider(indent: 16, endIndent: 16),
                _buildDrawerItem(
                  context,
                  icon: Icons.notifications_outlined,
                  title: "Notifications",
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.help_outline,
                  title: "Help & Support",
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),

          // 3. Bottom Logout
          const Divider(height: 1),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.logout, color: Colors.red, size: 20),
            ),
            title: const Text(
              "Logout",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            onTap: () {
              // Clear session/tokens here if needed
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
          ),
          const SizedBox(height: 20), // Bottom padding
        ],
      ),
    );
  }

  Widget _buildDrawerItem(
      BuildContext context, {
        required IconData icon,
        required String title,
        required VoidCallback onTap,
        bool isSelected = false,
      }) {
    final color = isSelected ? const Color(0xFFFF9933) : Colors.grey[700];
    final bgColor = isSelected ? const Color(0xFFFF9933).withOpacity(0.1) : Colors.transparent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 26),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFF9933) : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 15,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}