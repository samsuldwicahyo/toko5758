import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';

class KasbonScreen extends StatefulWidget {
  const KasbonScreen({super.key});

  @override
  State<KasbonScreen> createState() => _KasbonScreenState();
}

class _KasbonScreenState extends State<KasbonScreen> {
  final DbHelper _dbHelper = DbHelper();
  List<Map<String, dynamic>> _kasbons = [];
  List<Map<String, dynamic>> _filteredKasbons = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Controllers for adding new Kasbon
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _descController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadKasbons();
    _amountController.addListener(() => _formatPriceInput(_amountController));
  }

  void _formatPriceInput(TextEditingController controller) {
    final text = controller.text;
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      if (text.isNotEmpty) controller.clear();
      return;
    }
    final number = int.tryParse(digitsOnly) ?? 0;
    final formatted = formatAngka(number);
    if (formatted != text) {
      controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickFromContacts() async {
    Future<void> applyPhone(String raw) async {
      final formatted = formatPhoneDisplay(raw);
      _phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    try {
      try {
        final picked = await FlutterContacts.openExternalPick();
        if (picked != null && picked.phones.isNotEmpty) {
          await applyPhone(picked.phones.first.number);
          return;
        }
      } catch (_) {}

      var status = await Permission.contacts.status;
      var granted = status.isGranted || status.isLimited;

      if (!granted) {
        status = await Permission.contacts.request();
        granted = status.isGranted || status.isLimited;
      }

      if (!granted) {
        try {
          granted = await FlutterContacts.requestPermission();
        } catch (_) {}
      }

      if (!granted) {
        try {
          final picked = await FlutterContacts.openExternalPick();
          if (picked != null && picked.phones.isNotEmpty) {
            await applyPhone(picked.phones.first.number);
            return;
          }
        } catch (_) {}

        if (!mounted) return;
        final goToSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Kontak Ditolak'),
            content: const Text(
              'Aplikasi belum bisa membaca kontak walaupun izin belum terbaca sebagai aktif. '
              'Pastikan izin Kontak untuk aplikasi ini aktif di Pengaturan, lalu coba lagi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Tutup'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan Aplikasi'),
              ),
            ],
          ),
        );

        if (goToSettings == true) {
          await openAppSettings();
        }
        return;
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        withPhoto: false,
      );
      final selectable = contacts
          .where((contact) => contact.phones.isNotEmpty)
          .toList()
        ..sort(
          (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
        );

      if (selectable.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada kontak yang memiliki nomor telepon.')),
        );
        return;
      }

      if (!mounted) return;
      final selected = await _showContactPickerDialog(selectable);
      if (selected != null && selected.phones.isNotEmpty) {
        await applyPhone(selected.phones.first.number);
      }
    } catch (e) {
      try {
        final picked = await FlutterContacts.openExternalPick();
        if (picked != null && picked.phones.isNotEmpty) {
          await applyPhone(picked.phones.first.number);
          return;
        }
      } catch (_) {}

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal akses kontak: $e')),
      );
    }
  }

  Future<Contact?> _showContactPickerDialog(List<Contact> contacts) async {
    final searchController = TextEditingController();
    List<Contact> filtered = List<Contact>.from(contacts);

    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.white,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void filterContacts(String query) {
              final normalized = query.trim().toLowerCase();
              setDialogState(() {
                if (normalized.isEmpty) {
                  filtered = List<Contact>.from(contacts);
                  return;
                }
                filtered = contacts.where((contact) {
                  final name = contact.displayName.toLowerCase();
                  final phones = contact.phones.map((phone) => phone.number.toLowerCase()).join(' ');
                  return name.contains(normalized) || phones.contains(normalized);
                }).toList();
              });
            }

            final maxHeight = MediaQuery.of(sheetContext).size.height * 0.78;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: AppColors.spacing16,
                  right: AppColors.spacing16,
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                      AppColors.spacing16,
                ),
                child: SizedBox(
                  height: maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pilih Kontak',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppColors.spacing12),
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          labelText: 'Cari kontak',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: filterContacts,
                      ),
                      const SizedBox(height: AppColors.spacing12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text(
                                  'Kontak tidak ditemukan',
                                  style: TextStyle(color: AppColors.textSecondary),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final contact = filtered[index];
                                  final phone = contact.phones.first.number;
                                  final displayName =
                                      contact.displayName.trim().isEmpty
                                          ? 'Tanpa Nama'
                                          : contact.displayName.trim();
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const CircleAvatar(
                                      backgroundColor: AppColors.primaryLight,
                                      child: Icon(
                                        Icons.person,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    title: Text(displayName),
                                    subtitle: Text(formatPhoneDisplay(phone)),
                                    onTap: () => Navigator.of(sheetContext)
                                        .pop(contact),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: AppColors.spacing8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: const Text('Batal'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    return selected;
  }

  Future<void> _hubungiWA(String phone) async {
    final waNum = normalizePhoneWA(phone);
    if (waNum.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor WA tidak valid')),
      );
      return;
    }
    final url = Uri.parse('https://wa.me/$waNum');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka WhatsApp')),
      );
    }
  }

  Future<void> _loadKasbons() async {
    setState(() => _isLoading = true);
    try {
      final data = await _dbHelper.getKasbons();
      if (!mounted) return;
      setState(() {
        _kasbons = data;
        _filteredKasbons = _buildFilteredKasbons(data);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat data kasbon: $e')),
      );
    }
  }

  List<Map<String, dynamic>> _buildFilteredKasbons(List<Map<String, dynamic>> source) {
    if (_searchQuery.isEmpty) {
      return List<Map<String, dynamic>>.from(source);
    }
    return source
        .where((k) =>
            k['customer_name']
                .toString()
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()) ||
            k['phone']
                .toString()
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
        .toList();
  }

  void _filterKasbons() {
    setState(() {
      _filteredKasbons = _buildFilteredKasbons(_kasbons);
    });
  }

  int get _totalOutstanding {
    return _kasbons.fold<int>(
      0,
      (sum, item) => sum + safeInt(item['remaining_amount']),
    );
  }

  int get _debtorCount {
    return _kasbons.where((k) => safeInt(k['remaining_amount']) > 0).length;
  }

  void _showAddKasbonDialog() {
    _nameController.clear();
    _phoneController.clear();
    _amountController.clear();
    _descController.clear();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius8),
          ),
          title: const Text(
            'Catat Kasbon Baru',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Pelanggan',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: AppColors.spacing12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'Nomor HP/WA',
                      prefixIcon: const Icon(Icons.phone_outlined),
                      hintText: '0812...',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.contacts),
                        tooltip: 'Pilih dari kontak',
                        onPressed: _pickFromContacts,
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nomor HP wajib diisi' : null,
                  ),
                  const SizedBox(height: AppColors.spacing12),
                  TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Jumlah Kasbon (Rp)',
                      prefixIcon: Icon(Icons.payments_outlined),
                      hintText: '0',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Jumlah wajib diisi';
                      }
                      final val = parseRupiah(v);
                      if (val <= 0) {
                        return 'Jumlah harus lebih besar dari 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppColors.spacing12),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan (Opsional)',
                      prefixIcon: Icon(Icons.description_outlined),
                      hintText: 'Contoh: Belanja bulanan...',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final name = _nameController.text.trim();
                  final phone = normalizePhoneWA(_phoneController.text.trim());
                  final amount = parseRupiah(_amountController.text);
                  final desc = _descController.text.trim();

                  final now = DateTime.now();
                  final months = [
                    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
                    'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'
                  ];
                  final dateStr = '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';

                  final nav = Navigator.of(dialogContext);
                  final messenger = ScaffoldMessenger.of(dialogContext);

                  await _dbHelper.insertKasbon({
                    'customer_name': name,
                    'phone': phone,
                    'amount': amount,
                    'remaining_amount': amount,
                    'date': dateStr,
                    'status': 'Belum Lunas',
                    'description': desc,
                  });

                  await _dbHelper.insertAuditLog({
                    'user': 'Admin',
                    'action': 'KASBON_CREATE',
                    'entity_type': 'kasbon',
                    'description': 'Kasbon baru untuk $name: ${formatRupiah(amount)}',
                    'details': 'Phone: $phone, Desc: $desc',
                  });

                  if (!mounted) return;
                  nav.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Kasbon berhasil dicatat!')),
                  );
                  _loadKasbons();
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showPayKasbonDialog(Map<String, dynamic> kasbon) {
    final payController = TextEditingController();
    payController.addListener(() {
      final text = payController.text;
      final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isEmpty) {
        if (text.isNotEmpty) payController.clear();
        return;
      }
      final number = int.tryParse(digitsOnly) ?? 0;
      final formatted = formatAngka(number);
      if (formatted != text) {
        payController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    });
    final payFormKey = GlobalKey<FormState>();
    final int maxPay = kasbon['remaining_amount'] as int;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius8),
          ),
          title: Text('Bayar Kasbon - ${kasbon['customer_name']}'),
          content: Form(
            key: payFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total tagihan: ${formatRupiah(safeInt(kasbon['remaining_amount']))}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppColors.spacing12),
                TextFormField(
                  controller: payController,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah Bayar (Rp)',
                    prefixIcon: Icon(Icons.payments_outlined),
                    hintText: '0',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Jumlah bayar wajib diisi';
                    }
                    final val = parseRupiah(v);
                    if (val <= 0) {
                      return 'Jumlah harus lebih besar dari 0';
                    }
                    if (val > maxPay) {
                      return 'Jumlah melebihi total kasbon (max ${formatRupiah(maxPay)})';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (payFormKey.currentState!.validate()) {
                  final amount = parseRupiah(payController.text);

                  // Capture refs before async gap
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  await _dbHelper.payKasbon(kasbon['id'], amount);

                  await _dbHelper.insertAuditLog({
                    'user': 'Admin',
                    'action': 'KASBON_PAY',
                    'entity_type': 'kasbon',
                    'entity_id': kasbon['id'],
                    'description': 'Bayar kasbon ${kasbon['customer_name']}: ${formatRupiah(amount)}',
                    'details': 'Sisa sebelum: ${kasbon['remaining_amount']}',
                  });

                  if (mounted) {
                    nav.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Pembayaran kasbon berhasil dicatat!')),
                    );
                    _loadKasbons();
                  }
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showDetailDialog(Map<String, dynamic> kasbon) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius8),
          ),
          title: const Text('Detail Kasbon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Pelanggan', kasbon['customer_name']),
              _buildDetailRow('Nomor HP', formatPhoneDisplay(kasbon['phone'].toString())),
              _buildDetailRow('Tanggal Transaksi', kasbon['date']),
              _buildDetailRow('Jumlah Awal', formatRupiah(safeInt(kasbon['amount']))),
              _buildDetailRow('Sisa Kasbon', formatRupiah(safeInt(kasbon['remaining_amount'])), isBold: true, color: AppColors.danger),
              _buildDetailRow('Status', kasbon['status'], color: kasbon['status'] == 'Lunas' ? AppColors.success : AppColors.warning),
              if (kasbon['description'] != null && kasbon['description'].toString().isNotEmpty)
                _buildDetailRow('Keterangan', kasbon['description']),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppColors.textMain,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Kasbon'),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Catat Kasbon Baru',
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        onPressed: _showAddKasbonDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Summary Banner
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(AppColors.spacing16),
                  padding: const EdgeInsets.all(AppColors.spacing16),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(AppColors.radius8),
                    boxShadow: const [AppColors.cardShadow],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL OUTSTANDING KASBON',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: AppColors.spacing4),
                      Text(
                        formatRupiah(_totalOutstanding),
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: AppColors.primary,
                              fontSize: 28,
                            ),
                      ),
                      const SizedBox(height: AppColors.spacing8),
                      Row(
                        children: [
                          const Icon(Icons.people_outline,
                              size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '$_debtorCount Pelanggan Menunggak',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Search Input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppColors.spacing16),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cari nama atau nomor telepon...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _filterKasbons();
                      });
                    },
                  ),
                ),
                const SizedBox(height: AppColors.spacing16),
                // List of Kasbons
                Expanded(
                  child: _filteredKasbons.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.handshake_outlined,
                                size: 64,
                                color: AppColors.textSecondary.withOpacity(0.5),
                              ),
                              const SizedBox(height: AppColors.spacing16),
                              const Text(
                                'Tidak ada data kasbon',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppColors.spacing16),
                          itemCount: _filteredKasbons.length,
                          itemBuilder: (context, index) {
                            final item = _filteredKasbons[index];
                            final int remaining = item['remaining_amount'] as int;
                            final bool isLunas = remaining == 0;

                            return Card(
                              margin: const EdgeInsets.only(bottom: AppColors.spacing12),
                              child: Padding(
                                padding: const EdgeInsets.all(AppColors.spacing12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isLunas
                                            ? AppColors.primaryLight
                                            : AppColors.surface,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        color: isLunas
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(width: AppColors.spacing12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['customer_name'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              const Icon(Icons.phone,
                                                  size: 12,
                                                  color: AppColors.textSecondary),
                                              const SizedBox(width: 4),
                                              Text(
                                                formatPhoneDisplay(item['phone'].toString()),
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              InkWell(
                                                onTap: () => _hubungiWA(item['phone']),
                                                child: const Icon(Icons.message, size: 16, color: AppColors.accentBlue),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Terakhir: ${item['date']}',
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          formatRupiah(remaining),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: isLunas
                                                ? AppColors.success
                                                : AppColors.danger,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            SizedBox(
                                              height: 32,
                                              child: OutlinedButton(
                                                onPressed: () => _showDetailDialog(item),
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                                ),
                                                child: const Text('Detail'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (!isLunas)
                                              SizedBox(
                                                height: 32,
                                                child: ElevatedButton(
                                                  onPressed: () => _showPayKasbonDialog(item),
                                                  style: ElevatedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 12),
                                                  ),
                                                  child: const Text('Bayar'),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
