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
          // 1. Premium Header
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF9933), Color(0xFFFF6600)], // Saffron Gradient
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: Text(
              userName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Text(
              "ID: $userId",
              style: const TextStyle(color: Colors.white70),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                userName.isNotEmpty ? userName[0].toUpperCase() : "B",
                style: const TextStyle(
                  fontSize: 24,
                  color: Color(0xFFFF9933),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // 2. Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
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
                const Divider(),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Logout",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
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

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFFFF9933) : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFFFF9933).withOpacity(0.1),
      onTap: onTap,
    );
  }
}