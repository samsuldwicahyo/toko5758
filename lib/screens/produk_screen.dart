import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as ex;
import '../constants/colors.dart';
import '../data/db_helper.dart';
import 'barcode_scanner_screen.dart';

class ProdukScreen extends StatefulWidget {
  const ProdukScreen({super.key});

  @override
  State<ProdukScreen> createState() => _ProdukScreenState();
}

class _ProdukScreenState extends State<ProdukScreen> {
  final DbHelper _dbHelper = DbHelper();
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _filteredProducts = [];
  bool _isLoading = true;
  String _searchQuery = '';

  // Controllers for add/edit forms
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _beliController = TextEditingController(); // HPP / harga modal (Bagian 1)
  final _stockController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Image picker
  final ImagePicker _imagePicker = ImagePicker();
  String? _selectedImagePath;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _priceController.addListener(() => _formatPriceInput(_priceController));
    _beliController.addListener(() => _formatPriceInput(_beliController));
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
    _priceController.dispose();
    _beliController.dispose();
    _stockController.dispose();
    _barcodeController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final data = await _dbHelper.getProducts();
      setState(() {
        _products = data;
        _filterProducts();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat produk: $e')),
        );
      }
    }
  }

  void _filterProducts() {
    setState(() {
      if (_searchQuery.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products
            .where((p) {
              final nama = p['nama'].toString().toLowerCase();
              final barcode = (p['barcode'] ?? '').toString().toLowerCase();
              final q = _searchQuery.toLowerCase();
              return nama.contains(q) || barcode.contains(q);
            })
            .toList();
      }
    });
  }

  Future<String?> _saveImageToAppDir(String sourcePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/product_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final fileName = 'product_${DateTime.now().millisecondsSinceEpoch}${p.extension(sourcePath)}';
      final destPath = '${imagesDir.path}/$fileName';

      await File(sourcePath).copy(destPath);
      return destPath;
    } catch (e) {
      debugPrint('Error saving image: $e');
      return null;
    }
  }

  Future<void> _pickImage(StateSetter setDialogState) async {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppColors.spacing16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppColors.spacing16),
                const Text(
                  'Pilih Sumber Foto',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: AppColors.spacing16),
                ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppColors.radius8),
                    ),
                    child: const Icon(Icons.camera_alt, color: AppColors.primary),
                  ),
                  title: const Text('Ambil Foto'),
                  subtitle: const Text('Gunakan kamera untuk foto produk'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final XFile? photo = await _imagePicker.pickImage(
                      source: ImageSource.camera,
                      maxWidth: 800,
                      maxHeight: 800,
                      imageQuality: 85,
                    );
                    if (photo != null) {
                      setDialogState(() {
                        _selectedImagePath = photo.path;
                      });
                    }
                  },
                ),
                ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(AppColors.radius8),
                    ),
                    child: const Icon(Icons.photo_library, color: Colors.blue),
                  ),
                  title: const Text('Pilih dari Galeri'),
                  subtitle: const Text('Pilih foto yang sudah ada'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final XFile? photo = await _imagePicker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 800,
                      maxHeight: 800,
                      imageQuality: 85,
                    );
                    if (photo != null) {
                      setDialogState(() {
                        _selectedImagePath = photo.path;
                      });
                    }
                  },
                ),
                if (_selectedImagePath != null && _selectedImagePath!.isNotEmpty)
                  ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppColors.radius8),
                      ),
                      child: const Icon(Icons.delete_outline, color: AppColors.danger),
                    ),
                    title: const Text('Hapus Foto'),
                    subtitle: const Text('Hapus foto produk saat ini'),
                    onTap: () {
                      Navigator.pop(ctx);
                      setDialogState(() {
                        _selectedImagePath = '';
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _scanBarcodeForForm(StateSetter setDialogState) async {
    final String? scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );

    if (scannedCode != null) {
      setDialogState(() {
        _barcodeController.text = scannedCode;
      });
    }
  }

  Widget _buildImagePreview(StateSetter setDialogState) {
    Widget imageWidget;

    if (_selectedImagePath != null && _selectedImagePath!.isNotEmpty) {
      final file = File(_selectedImagePath!);
      if (file.existsSync()) {
        imageWidget = ClipRRect(
          borderRadius: BorderRadius.circular(AppColors.radius8),
          child: Image.file(
            file,
            width: double.infinity,
            height: 160,
            fit: BoxFit.cover,
          ),
        );
      } else {
        imageWidget = _buildImagePlaceholder();
      }
    } else {
      imageWidget = _buildImagePlaceholder();
    }

    return GestureDetector(
      onTap: () => _pickImage(setDialogState),
      child: Container(
        width: double.infinity,
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.radius8),
          border: Border.all(
            color: Colors.grey.shade300,
            style: BorderStyle.solid,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            imageWidget,
            // Edit overlay
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppColors.spacing8,
                  vertical: AppColors.spacing4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text(
                      'Ubah Foto',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 160,
      color: AppColors.surface,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 40,
            color: AppColors.textSecondary.withOpacity(0.5),
          ),
          const SizedBox(height: AppColors.spacing8),
          Text(
            'Tap untuk menambah foto',
            style: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductFormContent(StateSetter setDialogState) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image preview
            _buildImagePreview(setDialogState),
            const SizedBox(height: AppColors.spacing16),

            // Product name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama Produk',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
            ),
            const SizedBox(height: AppColors.spacing12),

            // Barcode field with scan button
            TextFormField(
              controller: _barcodeController,
              decoration: InputDecoration(
                labelText: 'Barcode (Opsional)',
                prefixIcon: const Icon(Icons.qr_code),
                suffixIcon: IconButton(
                  tooltip: 'Scan Barcode',
                  icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
                  onPressed: () => _scanBarcodeForForm(setDialogState),
                ),
              ),
            ),
            const SizedBox(height: AppColors.spacing12),

            // Price
            TextFormField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Harga Jual (Rp)',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Harga wajib diisi';
                final price = parseRupiah(v);
                if (price < 0) return 'Harga harus valid';
                return null;
              },
            ),
            const SizedBox(height: AppColors.spacing12),

            // Harga Beli / Modal (HPP) - Bagian 1 requirement
            TextFormField(
              controller: _beliController,
              decoration: const InputDecoration(
                labelText: 'Harga Beli / Modal (Rp)',
                prefixIcon: Icon(Icons.shopping_cart_checkout),
                helperText: 'Digunakan untuk hitung Laba',
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Harga beli wajib';
                final beli = parseRupiah(v);
                if (beli < 0) return 'Harga beli harus valid';
                return null;
              },
            ),
            const SizedBox(height: AppColors.spacing12),

            // Stock
            TextFormField(
              controller: _stockController,
              decoration: const InputDecoration(
                labelText: 'Stok Awal',
                prefixIcon: Icon(Icons.archive_outlined),
              ),
              keyboardType: TextInputType.number,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Stok wajib diisi';
                final stock = int.tryParse(v);
                if (stock == null || stock < 0) return 'Stok harus valid';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  // Import Excel/CSV for bulk products (Bagian 3)
  Future<void> _importFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final path = file.path;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal membaca file')));
        return;
      }

      final bytes = await File(path).readAsBytes();
      final excel = ex.Excel.decodeBytes(bytes);

      int imported = 0;
      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table]!;
        for (var row in sheet.rows.skip(1)) { // skip header
          if (row.isEmpty || row[0]?.value == null) continue;
          final nama = row[0]?.value.toString() ?? '';
          final harga = parseRupiah(row[1]?.value?.toString());
          final hargaBeli = row.length > 2 ? parseRupiah(row[2]?.value?.toString()) : (harga * 0.6).round();
          final stok = row.length > 3 ? int.tryParse(row[3]?.value?.toString() ?? '0') ?? 10 : 10;
          final barcode = row.length > 4 ? row[4]?.value?.toString() ?? '' : '';

          if (nama.isNotEmpty && harga > 0) {
            final status = stok == 0 ? 'danger' : stok <= 5 ? 'warning' : 'normal';
            await _dbHelper.insertProduct({
              'nama': nama,
              'harga': harga,
              'harga_beli': hargaBeli,
              'stok': stok,
              'status': status,
              'barcode': barcode,
              'gambar': '',
            });
            imported++;
          }
        }
      }
      _loadProducts();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Berhasil import $imported produk')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal import: $e')));
    }
  }

  void _showAddProductDialog() {
    _nameController.clear();
    _priceController.clear();
    _beliController.clear();
    _stockController.clear();
    _barcodeController.clear();
    _selectedImagePath = null;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radius8),
              ),
              title: const Row(
                children: [
                  Icon(Icons.add_circle, color: AppColors.primary, size: 24),
                  SizedBox(width: 8),
                  Text('Tambah Produk Baru'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: _buildProductFormContent(setDialogState),
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
                      final price = parseRupiah(_priceController.text);
                      final stock = int.parse(_stockController.text.trim());
                      final barcode = _barcodeController.text.trim();
                      final status = stock == 0
                          ? 'danger'
                          : stock <= 5
                              ? 'warning'
                              : 'normal';

                      // Capture refs before async gap
                      final nav = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      // Save image to app dir
                      String gambarPath = '';
                      if (_selectedImagePath != null && _selectedImagePath!.isNotEmpty) {
                        final saved = await _saveImageToAppDir(_selectedImagePath!);
                        if (saved != null) gambarPath = saved;
                      }

                      final beli = parseRupiah(_beliController.text);

                      final newId = await _dbHelper.insertProduct({
                        'nama': name,
                        'harga': price,
                        'harga_beli': beli,
                        'stok': stock,
                        'status': status,
                        'barcode': barcode,
                        'gambar': gambarPath,
                      });

                      await _dbHelper.insertAuditLog({
                        'user': 'Admin',
                        'action': 'PRODUCT_CREATE',
                        'entity_type': 'product',
                        'entity_id': newId,
                        'description': 'Produk baru ditambahkan: $name',
                        'details': 'Harga: $price, HPP: $beli, Stok: $stock',
                      });

                      if (mounted) {
                        nav.pop();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Produk berhasil ditambahkan!')),
                        );
                        _loadProducts();
                      }
                    }
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

  void _showEditProductDialog(Map<String, dynamic> product) {
    _nameController.text = product['nama'];
    _priceController.text = formatAngka(safeInt(product['harga']));
    _beliController.text = formatAngka(safeInt(product['harga_beli']));
    _stockController.text = product['stok'].toString();
    _barcodeController.text = (product['barcode'] ?? '').toString();
    _selectedImagePath = (product['gambar'] ?? '').toString();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radius8),
              ),
              title: const Row(
                children: [
                  Icon(Icons.edit, color: AppColors.primary, size: 24),
                  SizedBox(width: 8),
                  Text('Ubah Produk'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: _buildProductFormContent(setDialogState),
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
                      final price = parseRupiah(_priceController.text);
                      final stock = int.parse(_stockController.text.trim());
                      final barcode = _barcodeController.text.trim();
                      final status = stock == 0
                          ? 'danger'
                          : stock <= 5
                              ? 'warning'
                              : 'normal';

                      // Capture refs before async gap
                      final nav = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);

                      // Save image to app dir if changed
                      String gambarPath = _selectedImagePath ?? '';
                      if (_selectedImagePath != null &&
                          _selectedImagePath!.isNotEmpty &&
                          _selectedImagePath != (product['gambar'] ?? '')) {
                        final saved = await _saveImageToAppDir(_selectedImagePath!);
                        if (saved != null) gambarPath = saved;
                      }

                      final beli = parseRupiah(_beliController.text);

                      await _dbHelper.updateProduct({
                        'id': product['id'],
                        'nama': name,
                        'harga': price,
                        'harga_beli': beli,
                        'stok': stock,
                        'status': status,
                        'barcode': barcode,
                        'gambar': gambarPath,
                      });

                      await _dbHelper.insertAuditLog({
                        'user': 'Admin',
                        'action': 'PRODUCT_UPDATE',
                        'entity_type': 'product',
                        'entity_id': product['id'],
                        'description': 'Produk diedit: $name',
                        'details': 'Harga: $price, HPP: $beli, Stok: $stock',
                      });

                      if (mounted) {
                        nav.pop();
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Produk berhasil diperbarui!')),
                        );
                        _loadProducts();
                      }
                    }
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

  void _showDeleteConfirmDialog(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Produk'),
          content: Text('Apakah Anda yakin ingin menghapus "${product['nama']}"?'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () async {
                // Capture refs before async gap
                final nav = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);

                await _dbHelper.deleteProduct(product['id']);
                if (mounted) {
                  nav.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Produk berhasil dihapus')),
                  );
                  _loadProducts();
                }
              },
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProductThumbnail(Map<String, dynamic> product) {
    final gambar = (product['gambar'] ?? '').toString();

    if (gambar.isNotEmpty) {
      final file = File(gambar);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppColors.radius8),
          child: Image.file(
            file,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        );
      }
    }

    // Fallback icon
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppColors.radius8),
      ),
      child: const Icon(
        Icons.inventory_2_outlined,
        color: AppColors.primary,
        size: 28,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Katalog Produk'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _importFromExcel,
            tooltip: 'Import dari Excel/CSV (Bagian 3)',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Tambah Produk',
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        onPressed: _showAddProductDialog,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(AppColors.spacing12),
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Cari produk atau barcode...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                        _filterProducts();
                      });
                    },
                  ),
                ),
                // Products list
                Expanded(
                  child: _filteredProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: AppColors.textSecondary.withOpacity(0.5),
                              ),
                              const SizedBox(height: AppColors.spacing16),
                              const Text(
                                'Tidak ada produk ditemukan',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(AppColors.spacing12),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            final status = product['status'] ?? 'normal';
                            final int stock = product['stok'] ?? 0;
                            final barcode = (product['barcode'] ?? '').toString();

                            final statusColor = status == 'danger'
                                ? AppColors.danger
                                : status == 'warning'
                                    ? AppColors.warning
                                    : AppColors.success;

                            return Container(
                              margin: const EdgeInsets.only(bottom: AppColors.spacing12),
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius: BorderRadius.zero,
                                border: Border.all(color: AppColors.primary, width: 2.5),
                                boxShadow: const [AppColors.brutalOffsetShadow],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(AppColors.spacing12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Product thumbnail
                                        _buildProductThumbnail(product),
                                        const SizedBox(width: AppColors.spacing12),

                                        // Product info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      product['nama'],
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                  ),
                                                  PopupMenuButton<String>(
                                                    tooltip: 'Aksi Produk',
                                                    onSelected: (value) {
                                                      if (value == 'edit') {
                                                        _showEditProductDialog(product);
                                                      } else if (value == 'supply') {
                                                        _showReceiveSupplyDialog(product);
                                                      } else if (value == 'delete') {
                                                        _showDeleteConfirmDialog(product);
                                                      }
                                                    },
                                                    itemBuilder: (context) => [
                                                      const PopupMenuItem(
                                                        value: 'edit',
                                                        child: Text('Edit'),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'supply',
                                                        child: Text('Terima Supply'),
                                                      ),
                                                      const PopupMenuItem(
                                                        value: 'delete',
                                                        child: Text('Hapus'),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              if (barcode.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.qr_code,
                                                      size: 12,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      barcode,
                                                      style: const TextStyle(
                                                        color: AppColors.textSecondary,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: AppColors.spacing8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          formatRupiah(safeInt(product['harga'])),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                            fontSize: 15,
                                          ),
                                        ),
                                        Text(
                                          'HPP: ${formatRupiah(safeInt(product['harga_beli']))}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppColors.spacing8,
                                            vertical: AppColors.spacing4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Stok: $stock',
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Stock alert
                                    if (status != 'normal') ...[
                                      const SizedBox(height: AppColors.spacing8),
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => _showReceiveSupplyDialog(product),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(AppColors.spacing8),
                                            decoration: BoxDecoration(
                                              color: statusColor.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(
                                                color: statusColor.withOpacity(0.4),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  status == 'danger'
                                                      ? Icons.warning_amber_rounded
                                                      : Icons.info_outline,
                                                  color: statusColor,
                                                  size: 16,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        status == 'danger'
                                                            ? 'Stok habis! Pesan sekarang ke Supplier'
                                                            : 'Stok hampir habis',
                                                        style: TextStyle(
                                                          color: statusColor,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        'Tap untuk restock produk ini.',
                                                        style: TextStyle(
                                                          color: statusColor,
                                                          fontSize: 10,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  Icons.add_business_outlined,
                                                  color: statusColor,
                                                  size: 18,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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

  // Dialog untuk terima supply bulk dari supplier (solusi agar kasir tidak ribet)
  // Contoh: Beli 1 slop rokok @100.000 (isi 10 bungkus) → otomatis +10 stok, HPP per bungkus = 10.000
  void _showReceiveSupplyDialog(Map<String, dynamic> product) {
    final kemasanCtrl = TextEditingController(text: '1');
    final hargaCtrl = TextEditingController();
    final isiCtrl = TextEditingController(text: '10'); // default untuk slop rokok biasanya 10

    hargaCtrl.addListener(() {
      final text = hargaCtrl.text;
      final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
      if (digitsOnly.isEmpty) {
        if (text.isNotEmpty) hargaCtrl.clear();
        return;
      }
      final number = int.tryParse(digitsOnly) ?? 0;
      final formatted = formatAngka(number);
      if (formatted != text) {
        hargaCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    });

    int previewUnit = 0;
    int previewHpp = 0;
    int previewTotal = 0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Hitung preview real-time
            final int jml = int.tryParse(kemasanCtrl.text) ?? 0;
            final int hrg = parseRupiah(hargaCtrl.text);
            final int isi = int.tryParse(isiCtrl.text) ?? 1;

            previewUnit = jml * isi;
            previewHpp = isi > 0 ? (hrg / isi).round() : 0;
            previewTotal = jml * hrg;

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppColors.radius8),
              ),
              title: Text('Terima Supply ${product['nama']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contoh: 1 slop @ Rp 100.000 (isi 10 bungkus) → HPP Rp 10.000/bungkus'),
                    const SizedBox(height: AppColors.spacing12),

                    TextFormField(
                      controller: kemasanCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah Kemasan (slop / box)',
                        prefixIcon: Icon(Icons.inventory_2),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: AppColors.spacing8),

                    TextFormField(
                      controller: hargaCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Harga per Kemasan (Rp)',
                        prefixIcon: Icon(Icons.payments),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: AppColors.spacing8),

                    TextFormField(
                      controller: isiCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Isi per Kemasan (berapa bungkus/pcs)',
                        prefixIcon: Icon(Icons.numbers),
                        helperText: '1 slop = 10 bungkus biasanya',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: AppColors.spacing16),

                    Container(
                      padding: const EdgeInsets.all(AppColors.spacing12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.primary, width: 1.5),
                        borderRadius: BorderRadius.zero,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PREVIEW UPDATE:'),
                          Text('Unit tambah ke stok: $previewUnit'),
                          Text('HPP baru per unit jual: ${formatRupiah(previewHpp)}'),
                          Text('Total belanja: ${formatRupiah(previewTotal)}'),
                          const SizedBox(height: 4),
                          const Text(
                            'Sistem akan hitung rata-rata HPP (weighted average) agar laba akurat.',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
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
                    if (previewUnit <= 0 || previewHpp <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Isi jumlah & harga dengan benar')),
                      );
                      return;
                    }

                    final int currentStok = product['stok'] ?? 0;
                    final int currentHpp = product['harga_beli'] ?? 0;

                    // Weighted average HPP
                    final double totalModalLama = currentHpp * currentStok.toDouble();
                    final double totalModalTambah = previewHpp * previewUnit.toDouble();
                    final double newHppDouble = (totalModalLama + totalModalTambah) / (currentStok + previewUnit);
                    final int newHpp = newHppDouble.round();
                    final int newStok = currentStok + previewUnit;

                    // Update product
                    await _dbHelper.updateProduct({
                      'id': product['id'],
                      'nama': product['nama'],
                      'harga': product['harga'],
                      'harga_beli': newHpp,
                      'stok': newStok,
                      'status': newStok == 0
                          ? 'danger'
                          : newStok <= 5
                              ? 'warning'
                              : 'normal',
                      'barcode': product['barcode'] ?? '',
                      'gambar': product['gambar'] ?? '',
                    });

                    await _dbHelper.insertAuditLog({
                      'user': 'Admin',
                      'action': 'SUPPLY_RECEIVE',
                      'entity_type': 'product',
                      'entity_id': product['id'],
                      'description': 'Supply diterima untuk ${product['nama']}: +$previewUnit unit dari $jml kemasan',
                      'details': 'HPP per unit: ${formatRupiah(previewHpp)}, Total beli: ${formatRupiah(previewTotal)}, New HPP rata: ${formatRupiah(newHpp)}, New stok: $newStok',
                    });

                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Supply diterima! +$previewUnit unit. HPP rata-rata: ${formatRupiah(newHpp)}')),
                      );
                      _loadProducts();
                    }
                  },
                  child: const Text('Terima Supply & Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
