import 'package:flutter/material.dart';
import '../services/encryption_service.dart';
import 'vault_lock_screen.dart';
import 'vault_dashboard_screen.dart';

class VaultTabWrapper extends StatefulWidget {
  const VaultTabWrapper({super.key});

  @override
  State<VaultTabWrapper> createState() => _VaultTabWrapperState();
}

class _VaultTabWrapperState extends State<VaultTabWrapper> {
  @override
  Widget build(BuildContext context) {
    if (EncryptionService().hasKey) {
      return const VaultDashboardScreen();
    } else {
      return VaultLockScreen(
        onAuthenticated: () {
          if (mounted) {
            setState(() {}); // Rebuild and swap to VaultDashboardScreen
          }
        },
      );
    }
  }
}
