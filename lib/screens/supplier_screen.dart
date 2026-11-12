import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  final DbHelper _dbHelper = DbHelper();
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _filteredSuppliers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Form controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _debtController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _debtController.addListener(() => _formatDebtInput(_debtController));
  }

  void _formatDebtInput(TextEditingController controller) {
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
    _addressController.dispose();
    _debtController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    try {
      final data = await _dbHelper.getSuppliers();
      setState(() {
        _suppliers = data;
        _filterSuppliers();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat data supplier: $e')),
        );
      }
    }
  }

  void _filterSuppliers() {
    setState(() {
      if (_searchQuery.isEmpty) {
        _filteredSuppliers = _suppliers;
      } else {
        _filteredSuppliers = _suppliers
            .where((s) => s['nama']
                .toString()
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
            .toList();
      }
    });
  }

  int get _totalDebt {
    return _suppliers.fold<int>(
      0,
      (sum, item) => sum + safeInt(item['hutang']),
    );
  }

  void _showAddSupplierDialog() {
    _nameController.clear();
    _phoneController.clear();
    _addressController.clear();
    _debtController.clear();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius8),
          ),
          title: const Text(
            'Tambah Supplier Baru',
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
                      labelText: 'Nama Supplier',
                      prefixIcon: Icon(Icons.business_outlined),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: AppColors.spacing12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: 'Nomor WhatsApp',
                      prefixIcon: Icon(Icons.phone_outlined),
                      hintText: '+62...',
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Nomor WhatsApp wajib diisi' : null,
                  ),
                  const SizedBox(height: AppColors.spacing12),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Alamat',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      hintText: 'Nama jalan, kota...',
                    ),
                    maxLines: 2,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Alamat wajib diisi' : null,
                  ),
                  const SizedBox(height: AppColors.spacing12),
                  TextFormField(
                    controller: _debtController,
                    decoration: const InputDecoration(
                      labelText: 'Hutang ke Supplier (Rp)',
                      prefixIcon: Icon(Icons.payments_outlined),
                      hintText: '0',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      if (v != null && v.isNotEmpty) {
                        final val = parseRupiah(v);
                        if (val < 0) {
                          return 'Hutang harus bernilai 0 atau positif';
                        }
                      }
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
                if (_formKey.currentState!.validate()) {
                  final name = _nameController.text.trim();
                  final phone = _phoneController.text.trim();
                  final address = _addressController.text.trim();
                  final debt = parseRupiah(_debtController.text);

                  // Capture refs before async gap
                  final nav = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);

                  await _dbHelper.insertSupplier({
                    'nama': name,
                    'whatsapp': phone,
                    'alamat': address,
                    'hutang': debt,
                    'status': 'Aktif',
                  });

                  if (mounted) {
                    nav.pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Supplier berhasil ditambahkan!')),
                    );
                    _loadSuppliers();
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

  String _getInitials(String name) {
    if (name.isEmpty) return 'SP';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'aktif':
        return AppColors.success;
      case 'proses':
        return Colors.blue;
      case 'tempo':
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mitra Supplier'),
        leading: IconButton(
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Tambah Supplier Baru',
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        onPressed: _showAddSupplierDialog,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Supplier'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats Banner Row
                Padding(
                  padding: const EdgeInsets.all(AppColors.spacing16),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: AppColors.spacing8,
                    childAspectRatio: 1.0,
                    children: [
                      _buildStatBox(
                        'Total Supplier',
                        '${_suppliers.length} Mitra',
                        Icons.group_outlined,
                        AppColors.primary,
                      ),
                      _buildStatBox(
                        'Total Hutang',
                        formatRupiah(_totalDebt),
                        Icons.account_balance_wallet_outlined,
                        AppColors.danger,
                      ),
                      _buildStatBox(
                        'Pengiriman',
                        '3 Pesanan',
                        Icons.local_shipping_outlined,
                        Colors.blue,
                      ),
                    ],
                  ),
                ),
                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppColors.spacing16),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cari nama supplier...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _filterSuppliers();
                      });
                    },
                  ),
                ),
                const SizedBox(height: AppColors.spacing16),
                // List
                Expanded(
                  child: _filteredSuppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.business_outlined,
                                size: 64,
                                color: AppColors.textSecondary.withOpacity(0.5),
                              ),
                              const SizedBox(height: AppColors.spacing16),
                              const Text(
                                'Tidak ada data supplier',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppColors.spacing16),
                          itemCount: _filteredSuppliers.length,
                          itemBuilder: (context, index) {
                            final item = _filteredSuppliers[index];
                            final status = item['status'] ?? 'Aktif';
                            final statusColor = _getStatusColor(status);
                            final int hutang = item['hutang'] as int;

                            return Card(
                              margin: const EdgeInsets.only(bottom: AppColors.spacing12),
                              child: Padding(
                                padding: const EdgeInsets.all(AppColors.spacing12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryLight,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Center(
                                            child: Text(
                                              _getInitials(item['nama']),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            status,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: statusColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppColors.spacing12),
                                    Text(
                                      item['nama'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.phone,
                                            size: 14,
                                            color: AppColors.textSecondary),
                                        const SizedBox(width: 6),
                                        Text(
                                          item['whatsapp'],
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.location_on,
                                            size: 14,
                                            color: AppColors.textSecondary),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            item['alamat'],
                                            style: const TextStyle(
                                              color: AppColors.textSecondary,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppColors.spacing12),
                                    Container(
                                      padding: const EdgeInsets.only(top: 8),
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          top: BorderSide(
                                            color: AppColors.surface,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Total Hutang',
                                                style: TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontSize: 11,
                                                ),
                                              ),
                                              Text(
                                                formatRupiah(hutang),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: hutang > 0
                                                      ? AppColors.danger
                                                      : AppColors.textMain,
                                                ),
                                              ),
                                            ],
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.chevron_right,
                                              color: AppColors.primary,
                                            ),
                                            onPressed: () {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                      'Detail ${item['nama']} - Simulasikan pengiriman & riwayat'),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 80), // Offset for floating button overlapping
              ],
            ),
    );
  }

  Widget _buildStatBox(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(AppColors.spacing8),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.surface, width: 1.5),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color == AppColors.danger ? AppColors.danger : AppColors.textMain,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
