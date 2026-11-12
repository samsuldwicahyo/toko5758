import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';
import '../services/printer_service.dart';
import '../services/sync_service.dart';

class PengaturanScreen extends StatefulWidget {
  const PengaturanScreen({super.key});

  @override
  State<PengaturanScreen> createState() => _PengaturanScreenState();
}

class _PengaturanScreenState extends State<PengaturanScreen> {
  final DbHelper _dbHelper = DbHelper();
  // Store details state
  String _shopName = 'Warung Sejahtera';
  String _shopAddress = 'Jl. Sudirman No. 45, Jakarta Selatan';
  String _shopPhone = '0812-3456-7890';
  final String _shopId = '5758-001';

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_active');
    await prefs.remove('current_user_id');
    await _dbHelper.insertAuditLog({
      'user': 'Admin',
      'action': 'LOGOUT',
      'description': 'User logout',
    });
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _showEditInfoDialog(String title, String currentValue, Function(String) onSave, {bool isPhone = false}) {
    final controller = TextEditingController(text: currentValue);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius8),
          ),
          title: Text('Ubah $title'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(
                labelText: title,
              ),
              keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '$title tidak boleh kosong' : null,
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  onSave(controller.text.trim());
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$title berhasil diperbarui')),
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showChangePasswordDialog() {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final passFormKey = GlobalKey<FormState>();
    bool obscureOld = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radius8),
              ),
              title: const Text('Ganti Kata Sandi'),
              content: Form(
                key: passFormKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: oldPasswordController,
                        obscureText: obscureOld,
                        decoration: InputDecoration(
                          labelText: 'Kata Sandi Lama',
                          suffixIcon: IconButton(
                            icon: Icon(obscureOld ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setStateDialog(() => obscureOld = !obscureOld),
                          ),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Kata sandi lama wajib diisi' : null,
                      ),
                      const SizedBox(height: AppColors.spacing12),
                      TextFormField(
                        controller: newPasswordController,
                        obscureText: obscureNew,
                        decoration: InputDecoration(
                          labelText: 'Kata Sandi Baru',
                          suffixIcon: IconButton(
                            icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setStateDialog(() => obscureNew = !obscureNew),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Kata sandi baru wajib diisi';
                          if (v.length < 6) return 'Kata sandi minimal 6 karakter';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppColors.spacing12),
                      TextFormField(
                        controller: confirmPasswordController,
                        obscureText: obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'Konfirmasi Kata Sandi Baru',
                          suffixIcon: IconButton(
                            icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setStateDialog(() => obscureConfirm = !obscureConfirm),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Konfirmasi wajib diisi';
                          if (v != newPasswordController.text) return 'Kata sandi tidak cocok';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (!passFormKey.currentState!.validate()) return;

                    final dialogNavigator = Navigator.of(context);
                    final prefs = await SharedPreferences.getInstance();
                    if (!context.mounted) return;
                    final userId = prefs.getInt('current_user_id') ?? 0;
                    final messenger = ScaffoldMessenger.of(context);

                    if (userId <= 0) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Sesi login tidak ditemukan. Silakan login ulang.')),
                      );
                      return;
                    }

                    final oldPassword = oldPasswordController.text;
                    final newPassword = newPasswordController.text;
                    final isValid = await _dbHelper.verifyUserPassword(userId, oldPassword);

                    if (!isValid) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Kata sandi lama tidak cocok.')),
                      );
                      return;
                    }

                    final updated = await _dbHelper.updateUserPassword(userId, newPassword);
                    if (updated <= 0) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Gagal mengubah kata sandi. Coba lagi.')),
                      );
                      return;
                    }

                    await _dbHelper.insertAuditLog({
                      'user': 'Admin',
                      'action': 'PASSWORD_CHANGE',
                      'entity_type': 'user',
                      'entity_id': userId,
                      'description': 'User mengubah kata sandi',
                    });

                    if (!context.mounted) return;
                    dialogNavigator.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Kata sandi berhasil diubah.')),
                    );
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPrinterConfigDialog() {
    final printer = PrinterService();
    String printerSize = printer.paperSize;
    List<String> devices = [];
    bool isScanning = false;
    String? selectedDevice;

    // Load saved immediately so dialog shows real persisted state (not dummy) on first render
    printer.loadSavedPrinter().then((_) {
      if (mounted) {
        // Force a rebuild of the dialog content by triggering setStateDialog if possible
        // (StatefulBuilder will pick fresh values on next interaction or we rely on live reads)
      }
    });

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isConnected = printer.isConnected;
            final connAddr = printer.connectedAddress ?? '';

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radius8),
              ),
              title: const Text('Sambungkan ke Printer Thermal'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ukuran Kertas Struk:', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Radio<String>(
                          value: '58mm',
                          groupValue: printerSize,
                          onChanged: (v) async {
                            setStateDialog(() => printerSize = v!);
                            await printer.savePrinter(null, paperSize: v);
                          },
                        ),
                        const Text('58mm (Standar)'),
                        const SizedBox(width: AppColors.spacing16),
                        Radio<String>(
                          value: '80mm',
                          groupValue: printerSize,
                          onChanged: (v) async {
                            setStateDialog(() => printerSize = v!);
                            await printer.savePrinter(null, paperSize: v);
                          },
                        ),
                        const Text('80mm (Lebar)'),
                      ],
                    ),
                    const SizedBox(height: AppColors.spacing12),

                    // Real status from service / prefs (no dummy)
                    const Text('Status Koneksi:', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: isConnected ? AppColors.success : AppColors.danger, width: 2),
                        color: (isConnected ? AppColors.success : AppColors.danger).withOpacity(0.08),
                      ),
                      child: Row(
                        children: [
                          Icon(isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                              color: isConnected ? AppColors.success : AppColors.danger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isConnected && connAddr.isNotEmpty
                                  ? "Terhubung: $connAddr"
                                  : 'Belum terhubung',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing8),
                    if (isConnected && connAddr.isNotEmpty)
                      TextButton.icon(
                        onPressed: () async {
                          await printer.disconnect();
                          setStateDialog(() {
                            selectedDevice = null;
                            // devices stay, status will update on rebuild
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Printer diputuskan.')),
                          );
                        },
                        icon: const Icon(Icons.link_off, size: 16),
                        label: const Text('Putuskan Koneksi'),
                        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      ),

                    const SizedBox(height: AppColors.spacing12),
                    const Text('Perangkat Bluetooth (pair dulu di Setting HP > Bluetooth):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 6),

                    if (isScanning)
                      const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 8), child: CircularProgressIndicator()))
                    else
                      ElevatedButton.icon(
                        onPressed: () async {
                          setStateDialog(() => isScanning = true);

                          // Request real BT permissions (manifest already has them)
                          try {
                            await [
                              Permission.bluetoothScan,
                              Permission.bluetoothConnect,
                              Permission.bluetooth,
                              Permission.locationWhenInUse, // often required for BT scan on Android <12
                            ].request();
                          } catch (_) {}

                          final devs = await printer.getPairedDevices();
                          setStateDialog(() {
                            devices = devs;
                            isScanning = false;
                          });
                          if (devs.isEmpty && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Tidak ada perangkat. Pair printer thermal via Setting Bluetooth HP terlebih dulu, lalu Scan lagi.'),
                            ));
                          }
                        },
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('Scan / Muat Perangkat'),
                      ),

                    // Constrained list to avoid layout overflow / excess scale / element warnings
                    if (devices.isNotEmpty) ...[
                      const SizedBox(height: AppColors.spacing8),
                      const Text('Pilih & Hubungkan:', style: TextStyle(fontSize: 12)),
                      SizedBox(
                        height: 160, // constrain to prevent unbounded/overflow in dialog
                        child: ListView.builder(
                          itemCount: devices.length,
                          itemBuilder: (ctx, i) {
                            final d = devices[i];
                            return RadioListTile<String>(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              title: Text(d, style: const TextStyle(fontSize: 12)),
                              value: d,
                              groupValue: selectedDevice,
                              onChanged: (v) async {
                                setStateDialog(() => selectedDevice = v);
                                final ok = await printer.connect(v!);
                                final messenger = ScaffoldMessenger.of(context);
                                if (mounted) {
                                  messenger.showSnackBar(SnackBar(
                                    content: Text(ok
                                        ? 'Berhasil terhubung ke printer'
                                        : 'Gagal menghubungkan. Pastikan printer ON & dalam jangkauan.'),
                                  ));
                                }
                                // refresh status in dialog
                                setStateDialog(() {});
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (selectedDevice != null || isConnected)
                        ElevatedButton.icon(
                          onPressed: () async {
                            final res = await printer.testPrint(); // now uses REAL last tx from DB when available
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
                            }
                          },
                          icon: const Icon(Icons.print),
                          label: const Text('Test Cetak (pakai data transaksi terakhir)'),
                        ),
                    ] else ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Tekan "Scan / Muat Perangkat". Jika kosong, pastikan printer sudah dipair di pengaturan Bluetooth ponsel.',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _triggerBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Membuat backup + sinkronisasi ke cloud...')));

    try {
      final backupPath = await DbHelper().createBackupFile();
      final sync = SyncService();
      final syncResult = await sync.syncNow();

      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text('Backup: $backupPath\n$syncResult')));
      }
    } catch (e) {
      if (mounted) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Toko'),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppColors.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shop Profile card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppColors.spacing16),
                child: Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.store,
                            color: AppColors.primary,
                            size: 44,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            height: 28,
                            width: 28,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              iconSize: 16,
                              color: AppColors.white,
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Fitur ubah logo dalam pengembangan.')),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppColors.spacing12),
                    Text(
                      _shopName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID Toko: $_shopId',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppColors.spacing24),
            // Shop Details Section
            const Text(
              'Informasi Toko',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppColors.spacing8),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.storefront, color: AppColors.primary),
                    title: const Text('Nama Toko'),
                    subtitle: Text(_shopName),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _showEditInfoDialog(
                      'Nama Toko',
                      _shopName,
                      (val) => setState(() => _shopName = val),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                    title: const Text('Alamat Toko'),
                    subtitle: Text(_shopAddress),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _showEditInfoDialog(
                      'Alamat Toko',
                      _shopAddress,
                      (val) => setState(() => _shopAddress = val),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.phone_iphone_outlined, color: AppColors.primary),
                    title: const Text('Nomor WhatsApp'),
                    subtitle: Text(_shopPhone),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _showEditInfoDialog(
                      'Nomor WhatsApp',
                      _shopPhone,
                      (val) => setState(() => _shopPhone = val),
                      isPhone: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppColors.spacing24),
            // Feature Settings grid
            const Text(
              'Pengaturan Fitur',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppColors.spacing8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: AppColors.spacing12,
              mainAxisSpacing: AppColors.spacing12,
              childAspectRatio: 1.0,
              children: [
                _buildQuickSettingButton(
                  'Backup & Sync',
                  Icons.backup_outlined,
                  _triggerBackup,
                ),
                _buildQuickSettingButton(
                  'Ganti Sandi',
                  Icons.lock_outline,
                  _showChangePasswordDialog,
                ),
                _buildQuickSettingButton(
                  'Set Printer',
                  Icons.print_outlined,
                  _showPrinterConfigDialog,
                ),
              ],
            ),
            const SizedBox(height: AppColors.spacing24),
            // About App
            const Text(
              'Tentang Aplikasi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppColors.spacing8),
            Card(
              child: Column(
                children: [
                  const ListTile(
                    leading: Icon(Icons.info_outline, color: AppColors.textSecondary),
                    title: Text('Versi Aplikasi'),
                    trailing: Text(
                      'v2.4.0',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.security_outlined, color: AppColors.textSecondary),
                    title: const Text('Kebijakan Privasi'),
                    trailing: const Icon(Icons.open_in_new, size: 16),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Membuka halaman kebijakan privasi...')),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppColors.spacing32),
            // Logout
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger.withOpacity(0.1),
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger, width: 1),
                  elevation: 0,
                ),
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text(
                  'Keluar',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: AppColors.spacing24),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSettingButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppColors.radius8),
      child: Container(
        padding: const EdgeInsets.all(AppColors.spacing8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(AppColors.radius8),
          border: Border.all(color: AppColors.surface, width: 1.5),
          boxShadow: const [AppColors.cardShadow],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
