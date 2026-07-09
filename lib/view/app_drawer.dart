import 'package:drone_checklist/view/form_view.dart';
import 'package:drone_checklist/view/template_view.dart';
import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  final String? username;
  final String? email;
  final VoidCallback onLogout;

  const AppDrawer({super.key, required this.username, this.email, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0097da),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.account_circle, size: 60, color: Colors.white),
                      const SizedBox(height: 10),
                      Text(
                        username ?? 'User',
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      if (email != null)
                        Text(
                          email!,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('Checklist Form'),
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const FormView()),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.search),
                  title: const Text('CheckList Template'),
                  onTap: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const TemplateView()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Logout'),
                  onTap: onLogout,
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Developed By BINUS University",
              style: TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
