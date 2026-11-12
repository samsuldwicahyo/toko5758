import 'dart:math';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';
import 'struk_screen.dart';
import 'barcode_scanner_screen.dart';

class KasirScreen extends StatefulWidget {
  const KasirScreen({super.key});

  @override
  State<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends State<KasirScreen> {
  final DbHelper _dbHelper = DbHelper();
  final List<Map<String, dynamic>> _cart = [];
  List<Map<String, dynamic>> _allProducts = [];
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _displayProducts = [];
  final _searchController = TextEditingController();
  bool _showSuggestions = false;

  final List<String> _categories = ['Semua', 'Makanan', 'Minuman', 'Sembako', 'Lainnya'];
  String _selectedCategory = 'Semua';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    try {
      final data = await _dbHelper.getPopularProducts(limit: 30); // bestsellers first
      setState(() {
        _allProducts = data;
        _filterDisplayProducts();
      });
    } catch (_) {}
  }

  void _filterDisplayProducts() {
    List<Map<String, dynamic>> filtered = List.from(_allProducts);

    if (_selectedCategory != 'Semua') {
      final cat = _selectedCategory.toLowerCase();
      filtered = filtered.where((p) {
        final nama = p['nama'].toString().toLowerCase();
        if (cat == 'makanan') return nama.contains('roti') || nama.contains('mie') || nama.contains('telur') || nama.contains('sosis');
        if (cat == 'minuman') return nama.contains('air') || nama.contains('minum') || nama.contains('kopi');
        if (cat == 'sembako') return nama.contains('beras') || nama.contains('gula') || nama.contains('minyak');
        return true;
      }).toList();
    }

    setState(() {
      _displayProducts = filtered;
    });
  }

  void _selectCategory(String cat) {
    setState(() {
      _selectedCategory = cat;
    });
    _filterDisplayProducts();
  }

  void _searchProducts(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSuggestions = false;
      });
      return;
    }

    final results = _allProducts
        .where((p) {
          final nama = p['nama'].toString().toLowerCase();
          final barcode = (p['barcode'] ?? '').toString().toLowerCase();
          final q = query.toLowerCase();
          return nama.contains(q) || barcode.contains(q);
        })
        .toList();

    setState(() {
      _searchResults = results;
      _showSuggestions = results.isNotEmpty;
    });
  }

  Future<void> _openBarcodeScanner() async {
    final String? scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );

    if (scannedCode == null || !mounted) return;

    // Search by barcode in database
    final product = await _dbHelper.getProductByBarcode(scannedCode);

    if (product != null) {
      _addToCart(product);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${product['nama']} ditambahkan ke keranjang'),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Barcode "$scannedCode" tidak ditemukan'),
                ),
              ],
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  void _addToCart(Map<String, dynamic> product) {
    // Check stock
    final stock = safeInt(product['stok']);
    if (stock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stok ${product['nama']} habis!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final productId = safeInt(product['id']);
    final index = _cart.indexWhere((item) => safeInt(item['id']) == productId);
    setState(() {
      if (index != -1) {
        final currentQty = safeInt(_cart[index]['qty']);
        if (currentQty < stock) {
          _cart[index]['qty'] = currentQty + 1;
          _cart[index]['stok'] = stock;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Jumlah melebihi stok yang tersedia ($stock)'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      } else {
        _cart.add({
          'id': product['id'],
          'nama': product['nama'],
          'qty': 1,
          'harga': product['harga'],
          'stok': stock,
        });
      }
      _searchController.clear();
      _showSuggestions = false;
    });
  }

  void _updateQty(int index, int newQty) {
    final item = _cart[index];
    final stock = safeInt(item['stok']);

    if (newQty > stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stok tidak mencukupi (Max: $stock)'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() {
      if (newQty <= 0) {
        _cart.removeAt(index);
      } else {
        _cart[index]['qty'] = newQty;
      }
    });
  }

  int get _cartTotal {
    return _cart.fold<int>(
      0,
      (sum, item) => sum + safeInt(item['harga']) * safeInt(item['qty']),
    );
  }

  // Supported payment methods for real business logic (HPP + multi metode)
  static const String metodeTunai = 'Tunai';
  static const String metodeQris = 'QRIS';
  static const String metodeKasbon = 'Kasbon';

  Future<List<Map<String, dynamic>>> _loadExistingKasbonCustomers() async {
    final rawKasbons = await _dbHelper.getKasbons();
    final uniqueCustomers = <String, Map<String, dynamic>>{};

    for (final kasbon in rawKasbons) {
      final name = (kasbon['customer_name'] ?? '').toString().trim();
      final phone = normalizePhoneWA((kasbon['phone'] ?? '').toString());
      if (name.isEmpty && phone.isEmpty) continue;

      final key = phone.isNotEmpty ? 'phone:$phone' : 'name:${name.toLowerCase()}';
      final current = uniqueCustomers[key];
      if (current == null || safeInt(kasbon['id']) > safeInt(current['id'])) {
        uniqueCustomers[key] = {
          'customer_name': name,
          'phone': phone,
          'status': (kasbon['status'] ?? '').toString(),
          'remaining_amount': safeInt(kasbon['remaining_amount']),
        };
      }
    }

    final customers = uniqueCustomers.values.toList()
      ..sort((a, b) => (a['customer_name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['customer_name'] ?? '').toString().toLowerCase()));
    return customers;
  }

  Future<Map<String, dynamic>?> _pickExistingCustomer(
    List<Map<String, dynamic>> customers,
  ) async {
    if (customers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belum ada data pelanggan kasbon yang tersimpan.'),
          ),
        );
      }
      return null;
    }

    final searchController = TextEditingController();
    try {
      return await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.white,
        builder: (sheetContext) {
          var filtered = List<Map<String, dynamic>>.from(customers);

          return StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: AppColors.spacing16,
                    right: AppColors.spacing16,
                    top: AppColors.spacing16,
                    bottom:
                        MediaQuery.of(sheetContext).viewInsets.bottom +
                        AppColors.spacing16,
                  ),
                  child: SizedBox(
                    height: MediaQuery.of(sheetContext).size.height * 0.72,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PILIH PELANGGAN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: AppColors.spacing12),
                        TextField(
                          controller: searchController,
                          decoration: const InputDecoration(
                            hintText: 'Cari nama atau nomor HP...',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) {
                            final query = value.trim().toLowerCase();
                            setSheetState(() {
                              filtered = customers.where((customer) {
                                final name = (customer['customer_name'] ?? '')
                                    .toString()
                                    .toLowerCase();
                                final phone =
                                    (customer['phone'] ?? '').toString().toLowerCase();
                                return query.isEmpty ||
                                    name.contains(query) ||
                                    phone.contains(query);
                              }).toList();
                            });
                          },
                        ),
                        const SizedBox(height: AppColors.spacing12),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Pelanggan tidak ditemukan.',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final customer = filtered[index];
                                    final remaining = safeInt(
                                      customer['remaining_amount'],
                                    );
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        (customer['customer_name'] ?? '-')
                                            .toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${formatPhoneDisplay((customer['phone'] ?? '').toString())}${remaining > 0 ? ' • Sisa kasbon ${formatRupiah(remaining)}' : ''}',
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right,
                                      ),
                                      onTap: () =>
                                          Navigator.of(sheetContext).pop(customer),
                                    );
                                  },
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
    } finally {
      searchController.dispose();
    }
  }

  Future<void> _showPaymentBottomSheet() async {
    if (_cart.isEmpty) return;

    final int total = _cartTotal;
    final existingCustomers = await _loadExistingKasbonCustomers();
    if (!mounted) return;
    final payController = TextEditingController(text: formatAngka(total));
    final customerNameCtrl = TextEditingController();
    final customerPhoneCtrl = TextEditingController();
    final dpCtrl = TextEditingController(text: formatAngka(0));

    // Auto dot formatting for price inputs (pay & DP)
    void formatLocalPrice(TextEditingController c) {
      final text = c.text;
      final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isEmpty) {
        if (text.isNotEmpty) c.clear();
        return;
      }
      final number = int.tryParse(digitsOnly) ?? 0;
      final formatted = formatAngka(number);
      if (formatted != text) {
        c.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
    payController.addListener(() => formatLocalPrice(payController));
    dpCtrl.addListener(() => formatLocalPrice(dpCtrl));

    String selectedMetode = metodeTunai; // default
    final payFormKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero, // brutalist
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSheet) {
            final payValueStr = payController.text.trim();
            final int payValue = parseRupiah(payValueStr);
            final int changeValue = payValue - total;

            final bool isQris = selectedMetode == metodeQris;
            final bool isKasbon = selectedMetode == metodeKasbon;

            // Note: Forcing payController.text for QRIS is now handled only in onTap callbacks
            // to avoid setting controller during build (prevents potential re-entrancy / extra rebuilds).

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: AppColors.spacing16,
                right: AppColors.spacing16,
                top: AppColors.spacing16,
              ),
              child: Form(
                key: payFormKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brutalist header
                    const Text(
                      'PEMBAYARAN',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 8),

                    // Segmented / choice for 3 real methods
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _MetodeChip(
                            label: 'TUNAI',
                            selected: selectedMetode == metodeTunai,
                            onTap: () => setStateSheet(() {
                              selectedMetode = metodeTunai;
                              if (payController.text.isEmpty) payController.text = formatAngka(total);
                            }),
                          ),
                          const SizedBox(width: 8),
                          _MetodeChip(
                            label: 'QRIS',
                            selected: selectedMetode == metodeQris,
                            onTap: () => setStateSheet(() {
                              selectedMetode = metodeQris;
                              payController.text = formatAngka(total);
                            }),
                          ),
                          const SizedBox(width: 8),
                          _MetodeChip(
                            label: 'KASBON',
                            selected: selectedMetode == metodeKasbon,
                            onTap: () => setStateSheet(() {
                              selectedMetode = metodeKasbon;
                              // DP default 0 or half for demo
                              dpCtrl.text = formatAngka((total * 0.3).round());
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Belanja:', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                        Text(formatRupiah(total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      ],
                    ),
                    const SizedBox(height: AppColors.spacing12),

                    // Conditional fields
                    if (!isKasbon) ...[
                      TextFormField(
                        controller: payController,
                        autofocus: !isQris,
                        readOnly: isQris,
                        decoration: InputDecoration(
                          labelText: isQris ? 'Uang Diterima (QRIS - Uang Pas)' : 'Uang Diterima (Rp)',
                          prefixIcon: const Icon(Icons.payments_outlined),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setStateSheet(() {}),
                        validator: (v) {
                          if (isQris) return null;
                          if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                          final val = parseRupiah(v);
                          if (val < total) return 'Kurang dari total';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppColors.spacing12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Kembalian:', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                          Text(
                            formatRupiah(changeValue < 0 ? 0 : changeValue),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: changeValue < 0 ? AppColors.danger : AppColors.success,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // KASBON extra fields
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Pelanggan Kasbon',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (existingCustomers.isNotEmpty)
                            TextButton.icon(
                              onPressed: () async {
                                final picked = await _pickExistingCustomer(
                                  existingCustomers,
                                );
                                if (picked == null) return;
                                customerNameCtrl.text =
                                    (picked['customer_name'] ?? '').toString();
                                customerPhoneCtrl.text = formatPhoneDisplay(
                                  (picked['phone'] ?? '').toString(),
                                );
                                setStateSheet(() {});
                              },
                              icon: const Icon(Icons.people_alt_outlined),
                              label: const Text('Pilih Data Lama'),
                            ),
                        ],
                      ),
                      if (existingCustomers.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Gunakan data pelanggan yang pernah dicatat agar tidak input ulang.',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      TextFormField(
                        controller: customerNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama Pelanggan',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama pelanggan wajib' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: customerPhoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nomor HP Pelanggan',
                          prefixIcon: Icon(Icons.phone),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'No HP wajib' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: dpCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Uang Muka / DP (Rp)',
                          prefixIcon: Icon(Icons.payments),
                          helperText: 'Sisa akan dicatat sebagai kasbon/hutang',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final dp = parseRupiah(v);
                          if (dp < 0 || dp > total) return 'DP tidak valid';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sisa Kasbon: ${formatRupiah(total - parseRupiah(dpCtrl.text))}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.danger),
                      ),
                    ],

                    const SizedBox(height: AppColors.spacing24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: AppColors.spacing12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (payFormKey.currentState!.validate()) {
                                final invoice = 'TX-5758-${100000 + Random().nextInt(899999)}';
                                final now = DateTime.now();
                                final months = [
                                  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
                                  'Jul', 'Agt', 'Sep', 'Okt', 'Nov', 'Des'
                                ];
                                final dateStr = '${now.day.toString().padLeft(2, '0')} ${months[now.month - 1]} ${now.year}';
                                final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

                                final itemsSummary = _cart.map((e) => '${e['nama']} x${e['qty']}').join(', ');

                                final itemsList = _cart.map((e) => {
                                  'product_id': safeInt(e['id']),
                                  'nama': e['nama'],
                                  'qty': safeInt(e['qty']),
                                  'harga': safeInt(e['harga']),
                                  'subtotal': safeInt(e['qty']) * safeInt(e['harga']),
                                }).toList();

                                int finalBayar = payValue;
                                int finalKembali = changeValue;

                                // === REAL BUSINESS LOGIC PER METODE ===
                                String metodePembayaran = selectedMetode;
                                Map<String, dynamic>? kasbonData;

                                if (isQris) {
                                  finalBayar = total;
                                  finalKembali = 0;
                                } else if (isKasbon) {
                                  final dp = parseRupiah(dpCtrl.text);
                                  final sisa = total - dp;
                                  finalBayar = dp;
                                  finalKembali = 0;

                                  // Prepare kasbon to be created after successful tx
                                  // 'amount' = initial debt amount (the sisa after DP), not the full sale total.
                                  // Full sale is already recorded in the transaction itself.
                                  kasbonData = {
                                    'customer_name': customerNameCtrl.text.trim(),
                                    'phone': normalizePhoneWA(customerPhoneCtrl.text.trim()),
                                    'amount': sisa,
                                    'remaining_amount': sisa,
                                    'date': dateStr,
                                    'status': 'Belum Lunas',
                                    'description': 'Pembelian via Kasir - $itemsSummary',
                                  };
                                }

                                final transaction = {
                                  'invoice': invoice,
                                  'total': total,
                                  'waktu': timeStr,
                                  'items_summary': itemsSummary,
                                  'metode': metodePembayaran, // legacy
                                  'metode_pembayaran': metodePembayaran,
                                  'bayar': finalBayar,
                                  'kembali': finalKembali,
                                  'tanggal': dateStr,
                                };

                                // Capture refs
                                final nav = Navigator.of(context);
                                final outerNav = Navigator.of(this.context);
                                final messenger = ScaffoldMessenger.of(this.context);

                                try {
                                  // Write transaction (DB now auto-calcs total_modal + total_laba using harga_beli)
                                  final txId = await _dbHelper.insertTransaction(transaction, itemsList);

                                  // Audit log for sale
                                  await _dbHelper.insertAuditLog({
                                    'user': 'Kasir',
                                    'action': 'SALE',
                                    'entity_type': 'transaction',
                                    'entity_id': txId,
                                    'description': 'Penjualan $invoice total ${formatRupiah(total)} via $metodePembayaran',
                                    'details': 'Items: $itemsSummary',
                                  });

                                  // If Kasbon mode, record the debt
                                  if (kasbonData != null && txId > 0) {
                                    await _dbHelper.insertKasbon(kasbonData);
                                  }

                                  if (!mounted) return;

                                  nav.pop(); // close sheet

                                  final receiptData = Map<String, dynamic>.from(transaction)
                                    ..['items'] = itemsList;

                                  setState(() {
                                    _cart.clear();
                                  });
                                  await _loadProducts();

                                  if (!mounted) return;
                                  outerNav.push(
                                    MaterialPageRoute(
                                      builder: (context) => StrukScreen(transactionData: receiptData),
                                    ),
                                  );
                                } on StockException catch (e) {
                                  await _loadProducts();
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(e.message),
                                        backgroundColor: AppColors.warning,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text('Gagal menyimpan transaksi: $e'),
                                        backgroundColor: AppColors.danger,
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            child: Text('PROSES ${selectedMetode.toUpperCase()}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppColors.spacing16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir / POS'),
      ),
      body: Column(
        children: [
          // Search & Barcode scan input
          Padding(
            padding: const EdgeInsets.all(AppColors.spacing12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Cari produk atau barcode...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    _searchProducts('');
                                  },
                                )
                              : null,
                        ),
                        onChanged: _searchProducts,
                      ),
                    ),
                    const SizedBox(width: AppColors.spacing8),
                    // Barcode scan button
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(AppColors.radius8),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _openBarcodeScanner,
                          borderRadius: BorderRadius.circular(AppColors.radius8),
                          child: Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.qr_code_scanner,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Category filters for products (BAGIAN 3)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final isSel = _selectedCategory == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _selectCategory(cat),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSel ? AppColors.primary : AppColors.white,
                              border: Border.all(color: AppColors.primary, width: 2),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                color: isSel ? AppColors.white : AppColors.primary,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppColors.spacing8),
                // Product grid - bestsellers first, filter by category
                SizedBox(
                  height: 160,
                  child: _displayProducts.isEmpty
                      ? const Center(child: Text('Tidak ada produk'))
                      : GridView.builder(
                          scrollDirection: Axis.horizontal,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 1,
                            childAspectRatio: 0.85,
                          ),
                          itemCount: _displayProducts.length,
                          itemBuilder: (context, index) {
                            final p = _displayProducts[index];
                            final stock = safeInt(p['stok']);
                            final stockColor = stock <= 5
                                ? AppColors.danger
                                : stock <= 10
                                    ? AppColors.warning
                                    : AppColors.success;
                            return InkWell(
                              onTap: () => _addToCart(p),
                              child: Container(
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  border: Border.all(color: AppColors.primary, width: 2),
                                  borderRadius: BorderRadius.zero,
                                ),
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Placeholder for image / icon with accent bar
                                    Container(
                                      height: 48,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        border: Border.all(color: AppColors.primary, width: 1),
                                      ),
                                      child: const Center(
                                        child: Icon(Icons.inventory_2_outlined, size: 28, color: AppColors.primary),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      p['nama'],
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.1),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatRupiah(safeInt(p['harga'])),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.accentYellow,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    // Stock badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: stockColor.withOpacity(0.15),
                                        border: Border.all(color: stockColor, width: 1),
                                      ),
                                      child: Text(
                                        'Stok: $stock',
                                        style: TextStyle(fontSize: 10, color: stockColor, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: AppColors.spacing8),
                // Suggestions list overlaid or stacked
                if (_showSuggestions)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: const [AppColors.cardShadow],
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final product = _searchResults[index];
                          final int stock = product['stok'] as int;
                          final barcode = (product['barcode'] ?? '').toString();

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              title: Text(
                                product['nama'],
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              subtitle: Text(
                                '${formatRupiah(safeInt(product['harga']))} • Stok: $stock${barcode.isNotEmpty ? ' • $barcode' : ''}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: ElevatedButton(
                                onPressed: () => _addToCart(product),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  minimumSize: const Size(0, 28),
                                  textStyle: const TextStyle(fontSize: 11),
                                ),
                                child: const Text('Tambah'),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Shopping cart
          Expanded(
            child: _cart.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 64,
                          color: AppColors.textSecondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: AppColors.spacing16),
                        const Text(
                          'Keranjang belanja kosong',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Cari produk atau scan barcode untuk menambahkan',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: AppColors.spacing16),
                        OutlinedButton.icon(
                          onPressed: _openBarcodeScanner,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan Barcode'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppColors.spacing12,
                          vertical: AppColors.spacing4,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(AppColors.spacing12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['nama'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatRupiah(safeInt(item['harga'])),
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Kurangi',
                                    icon: const Icon(Icons.remove),
                                    onPressed: () => _updateQty(index, item['qty'] - 1),
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    child: Text(
                                      item['qty'].toString(),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Tambah',
                                    icon: const Icon(Icons.add),
                                    onPressed: () => _updateQty(index, item['qty'] + 1),
                                    constraints: const BoxConstraints(
                                      minWidth: 36,
                                      minHeight: 36,
                                    ),
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

          // Total & Checkout
          Container(
            padding: const EdgeInsets.all(AppColors.spacing16),
            decoration: BoxDecoration(
              color: AppColors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade200),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      formatRupiah(_cartTotal),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppColors.spacing16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.danger),
                          foregroundColor: AppColors.danger,
                        ),
                        onPressed: _cart.isEmpty
                            ? null
                            : () => setState(() => _cart.clear()),
                        child: const Text('Batalkan'),
                      ),
                    ),
                    const SizedBox(width: AppColors.spacing12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _cart.isEmpty ? null : _showPaymentBottomSheet,
                        child: const Text('Bayar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Brutalist segmented chip for payment method (no radius, thick border)
class _MetodeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MetodeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          border: Border.all(color: AppColors.primary, width: 2.5),
          borderRadius: BorderRadius.zero, // neo-brutalist
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: selected ? AppColors.white : AppColors.primary,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}
