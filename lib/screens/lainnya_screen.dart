import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';

class LainnyaScreen extends StatelessWidget {
  const LainnyaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final menuItems = [
      {
        'icon': Icons.handshake,
        'label': 'Kasbon Pelanggan',
        'desc': 'Kelola hutang pelanggan',
        'route': '/kasbon',
      },
      {
        'icon': Icons.local_shipping,
        'label': 'Supplier',
        'desc': 'Direktori supplier & kontak',
        'route': '/supplier',
      },
      {
        'icon': Icons.settings,
        'label': 'Pengaturan Toko',
        'desc': 'Profil toko & konfigurasi',
        'route': '/pengaturan',
      },
      {
        'icon': Icons.history,
        'label': 'Audit Log',
        'desc': 'Riwayat aktivitas bisnis',
        'route': '/audit_log',
      },
      {
        'icon': Icons.backup,
        'label': 'Backup Data',
        'desc': 'Backup data ke file lokal + sync transaksi ke cloud (demo)',
        'action': (BuildContext ctx) async {
          final messenger = ScaffoldMessenger.of(ctx);
          try {
            messenger.showSnackBar(const SnackBar(content: Text('Membuat backup file...')));
            final path = await DbHelper().createBackupFile();
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(content: Text('Backup berhasil: $path')));
            // also do cloud tx sync
            final syncResult = await SyncService().syncNow();
            messenger.showSnackBar(SnackBar(content: Text(syncResult)));
          } catch (e) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(content: Text('Gagal backup: $e')));
          }
        },
      },
      {
        'icon': Icons.restore,
        'label': 'Restore Data',
        'desc': 'Pulihkan data dari file backup JSON',
        'action': (BuildContext ctx) async {
          final messenger = ScaffoldMessenger.of(ctx);
          try {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['json'],
            );
            if (result == null || result.files.isEmpty || result.files.single.path == null) {
              return;
            }
            final path = result.files.single.path!;
            messenger.showSnackBar(const SnackBar(content: Text('Memulihkan data...')));
            final ok = await DbHelper().restoreFromBackup(path);
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(content: Text(ok ? 'Data berhasil dipulihkan! Restart app jika perlu.' : 'Gagal restore.')));
          } catch (e) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(SnackBar(content: Text('Error restore: $e')));
          }
        },
      },
      {
        'icon': Icons.help_outline,
        'label': 'Bantuan',
        'desc': 'Panduan & FAQ',
        'action': (BuildContext ctx) {
          showDialog(
            context: ctx,
            builder: (context) => AlertDialog(
              title: const Text('Bantuan Toko5758'),
              content: const Text(
                'Hubungi support kami via WA 0812-3456-7890 untuk panduan penggunaan atau pertanyaan lebih lanjut.',
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          );
        },
      },
      {
        'icon': Icons.info_outline,
        'label': 'Tentang Aplikasi',
        'desc': 'Versi & informasi',
        'action': (BuildContext ctx) {
          showAboutDialog(
            context: ctx,
            applicationName: 'Toko5758 POS',
            applicationVersion: '2.4.0',
            applicationIcon: const Icon(Icons.store, color: AppColors.primary, size: 48),
            children: [
              const Text('Aplikasi Point of Sale (POS) terbaik untuk warung dan UMKM di Indonesia.'),
            ],
          );
        },
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu Lainnya'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppColors.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppColors.spacing16),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.store,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppColors.spacing16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Warung Sejahtera',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '0812 3456 7890',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppColors.spacing24),
            // Menu items
            const Text(
              'Menu Utama',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: AppColors.spacing12),
            ...menuItems.map((item) {
              return _MenuItem(
                icon: item['icon'] as IconData,
                label: item['label'] as String,
                description: item['desc'] as String,
                onTap: () {
                  if (item.containsKey('route')) {
                    Navigator.of(context).pushNamed(item['route'] as String);
                  } else if (item.containsKey('action')) {
                    final act = item['action'] as Function(BuildContext);
                    act(context);
                  }
                },
              );
            }),
            const SizedBox(height: AppColors.spacing24),
            // Logout button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('last_active');
                  await prefs.remove('current_user_id');
                  await DbHelper().insertAuditLog({
                    'user': 'Admin',
                    'action': 'LOGOUT',
                    'description': 'User logout dari menu lainnya',
                  });
                  if (!context.mounted) return;
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppColors.spacing12),
      child: ListTile(
        leading: Icon(
          icon,
          color: AppColors.primary,
          size: 28,
        ),
        title: Text(label),
        subtitle: Text(
          description,
          style: Theme.of(context).textTheme.labelSmall,
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        onTap: onTap,
        contentPadding: const EdgeInsets.all(AppColors.spacing12),
      ),
    );
  }
}
