import '../constants/demo_config.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart'
    show Database, openDatabase, getDatabasesPath;

// === Format helpers for Rupiah (auto titik) and WhatsApp phone normalization ===
String formatRupiah(num amount) {
  final f =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  return f.format(amount);
}

String formatAngka(num amount) {
  return NumberFormat('#,##0', 'id_ID').format(amount);
}

int parseRupiah(String? input) {
  if (input == null || input.trim().isEmpty) return 0;
  final cleaned = input.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(cleaned) ?? 0;
}

String normalizePhoneWA(String input) {
  String p = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (p.isEmpty) return '';
  if (p.startsWith('0')) {
    p = '62${p.substring(1)}';
  } else if (!p.startsWith('62') && p.length >= 9) {
    p = '62$p';
  }
  return p;
}

String formatPhoneDisplay(String input) {
  String p = normalizePhoneWA(input);
  if (p.startsWith('62') && p.length > 2) {
    p = '0${p.substring(2)}';
  }
  if (p.length <= 4) return p;
  final buffer = StringBuffer();
  for (int i = 0; i < p.length; i++) {
    if (i > 0 && i % 4 == 0) {
      buffer.write('-');
    }
    buffer.write(p[i]);
  }
  return buffer.toString();
}

// Safe helpers to avoid runtime CastError on 'as int' when data may be null/string (from web seeds or old data)
int safeInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

double safeDouble(dynamic value, [double fallback = 0.0]) {
  if (value == null) return fallback;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? fallback;
}

const String _passwordSalt = 'toko5758-pos-v1';

class StockException implements Exception {
  final String message;

  StockException(this.message);

  @override
  String toString() => message;
}

String hashPassword(String password) {
  final digest = sha256.convert(utf8.encode('$_passwordSalt::$password'));
  return 'sha256:$digest';
}

bool _isHashedPassword(String stored) => stored.startsWith('sha256:');

bool verifyPassword(String password, String stored) {
  if (_isHashedPassword(stored)) {
    return hashPassword(password) == stored;
  }
  return password == stored;
}

String stockStatusFor(int stock) {
  if (stock <= 0) return 'danger';
  if (stock <= 5) return 'warning';
  return 'normal';
}

DateTime? parseLegacyTransactionDate(dynamic tanggal, dynamic waktu) {
  final tanggalStr = tanggal?.toString().trim() ?? '';
  if (tanggalStr.isEmpty) return null;

  final parts = tanggalStr.split(' ');
  if (parts.length < 3) return null;

  const monthMap = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'Mei': 5,
    'Jun': 6,
    'Jul': 7,
    'Agt': 8,
    'Sep': 9,
    'Okt': 10,
    'Nov': 11,
    'Des': 12,
  };

  final day = int.tryParse(parts[0]);
  final month = monthMap[parts[1]];
  final year = int.tryParse(parts[2]);
  if (day == null || month == null || year == null) return null;

  int hour = 0;
  int minute = 0;
  final timeStr = waktu?.toString().trim() ?? '';
  if (timeStr.isNotEmpty && timeStr.contains(':')) {
    final timeParts = timeStr.split(':');
    hour = int.tryParse(timeParts.first) ?? 0;
    if (timeParts.length > 1) {
      minute = int.tryParse(timeParts[1]) ?? 0;
    }
  }

  return DateTime(year, month, day, hour, minute);
}

DateTime? extractTransactionDate(Map<String, dynamic> tx) {
  final createdAt = tx['created_at']?.toString() ?? '';
  if (createdAt.isNotEmpty) {
    try {
      return DateTime.parse(createdAt);
    } catch (_) {}
  }
  return parseLegacyTransactionDate(tx['tanggal'], tx['waktu']);
}

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  Database? _db;

  // In-memory lists for Web fallback
  static final List<Map<String, dynamic>> _webProducts = [
    {
      'id': 1,
      'nama': 'Roti Tawar',
      'harga': 25000,
      'harga_beli': 15000,
      'stok': 45,
      'status': 'normal',
      'barcode': '8992761136000',
      'gambar': '',
    },
    {
      'id': 2,
      'nama': 'Mie Instan',
      'harga': 3500,
      'harga_beli': 2200,
      'stok': 5,
      'status': 'warning',
      'barcode': '8996001600146',
      'gambar': '',
    },
    {
      'id': 3,
      'nama': 'Air Mineral 1.5L',
      'harga': 5000,
      'harga_beli': 2800,
      'stok': 0,
      'status': 'danger',
      'barcode': '8992222052017',
      'gambar': '',
    },
    {
      'id': 4,
      'nama': 'Telur Ayam (1kg)',
      'harga': 28000,
      'harga_beli': 18000,
      'stok': 120,
      'status': 'normal',
      'barcode': '',
      'gambar': '',
    },
  ];

  static final List<Map<String, dynamic>> _webSuppliers = [
    {
      'id': 1,
      'nama': 'Sembako Berkah',
      'whatsapp': '+62 812 3456 7890',
      'alamat': 'Jl. Raya Industri No. 45, Cikarang, Bekasi',
      'hutang': 4500000,
      'status': 'Aktif',
    },
    {
      'id': 2,
      'nama': 'Toko Jaya Abadi',
      'whatsapp': '+62 857 1122 3344',
      'alamat': 'Kawasan MM2100, Blok B2, Cibitung',
      'hutang': 0,
      'status': 'Proses',
    },
    {
      'id': 3,
      'nama': 'Agen Minuman Segar',
      'whatsapp': '+62 899 7788 9900',
      'alamat': 'Pusat Grosir Senen Jaya, Lt. 2 Blok A',
      'hutang': 7950000,
      'status': 'Tempo',
    },
    {
      'id': 4,
      'nama': 'Surya Makmur Sosis',
      'whatsapp': '+62 813 1111 2222',
      'alamat': 'Komp. Gudang Peluru No. 12, Tebet',
      'hutang': 0,
      'status': 'Aktif',
    },
  ];

  static final List<Map<String, dynamic>> _webKasbons = [
    {
      'id': 1,
      'customer_name': 'Budi Santoso',
      'phone': '0812-3456-7890',
      'amount': 450000,
      'remaining_amount': 450000,
      'date': '12 Okt 2023',
      'status': 'Belum Lunas',
      'description': 'Belanja bulanan sembako',
    },
    {
      'id': 2,
      'customer_name': 'Siti Aminah',
      'phone': '0857-9988-1122',
      'amount': 1200000,
      'remaining_amount': 1200000,
      'date': '15 Okt 2023',
      'status': 'Belum Lunas',
      'description': 'Belanja sembako warung',
    },
    {
      'id': 3,
      'customer_name': 'Andi Wijaya',
      'phone': '0822-4455-6677',
      'amount': 85500,
      'remaining_amount': 85500,
      'date': '02 Okt 2023',
      'status': 'Belum Lunas',
      'description': 'Kebutuhan kopi & rokok',
    },
  ];

  static final List<Map<String, dynamic>> _webTransactions = [
    {
      'id': 1,
      'invoice': 'TX-5758-001247',
      'total': 45000,
      'waktu': '14:30',
      'items_summary': 'Roti Tawar + Minum',
      'metode': 'Tunai',
      'metode_pembayaran': 'Tunai',
      'bayar': 50000,
      'kembali': 5000,
      'tanggal': '02 Jun 2026',
      'total_modal': 27000,
      'total_laba': 18000,
    },
    {
      'id': 2,
      'invoice': 'TX-5758-001248',
      'total': 85000,
      'waktu': '13:15',
      'items_summary': 'Beras 5kg',
      'metode': 'QRIS',
      'metode_pembayaran': 'QRIS',
      'bayar': 85000,
      'kembali': 0,
      'tanggal': '02 Jun 2026',
      'total_modal': 52000,
      'total_laba': 33000,
    },
    {
      'id': 3,
      'invoice': 'TX-5758-001249',
      'total': 68500,
      'waktu': '12:00',
      'items_summary': 'Rokok + Korek Api',
      'metode': 'Tunai',
      'metode_pembayaran': 'Tunai',
      'bayar': 70000,
      'kembali': 1500,
      'tanggal': '02 Jun 2026',
      'total_modal': 41000,
      'total_laba': 27500,
    },
  ];

  static final List<Map<String, dynamic>> _webTxItems = [];

  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError(
          'SQLite is not supported on web. Use web helper fallback.');
    }
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'toko5758.db');

    return await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db
          .execute("ALTER TABLE products ADD COLUMN barcode TEXT DEFAULT ''");
      await db
          .execute("ALTER TABLE products ADD COLUMN gambar TEXT DEFAULT ''");
    }
    if (oldVersion < 3) {
      // Add users table for auth
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT,
          phone TEXT NOT NULL,
          password TEXT NOT NULL,
          nama_toko TEXT,
          created_at TEXT
        )
      ''');

      // Enhance transactions for sync + proper timestamp
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN is_synced INTEGER DEFAULT 0");
      } catch (_) {}
      try {
        await db.execute("ALTER TABLE transactions ADD COLUMN created_at TEXT");
      } catch (_) {}

      // Akun contoh dikonfigurasi melalui DemoConfig.
      await db.insert('users', {
        'email': DemoConfig.email,
        'phone': normalizePhoneWA(DemoConfig.phone),
        'password': hashPassword(DemoConfig.password),
        'nama_toko': 'Warung Sejahtera',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    if (oldVersion < 4) {
      // BAGIAN 1: HPP (harga_beli) + metode pembayaran + laba per transaksi
      try {
        await db.execute(
            "ALTER TABLE products ADD COLUMN harga_beli INTEGER DEFAULT 0");
      } catch (_) {}

      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN metode_pembayaran TEXT DEFAULT 'Tunai'");
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN total_modal INTEGER DEFAULT 0");
      } catch (_) {}
      try {
        await db.execute(
            "ALTER TABLE transactions ADD COLUMN total_laba INTEGER DEFAULT 0");
      } catch (_) {}

      // Backfill realistic harga_beli for existing products (approx 60-65% of jual)
      await db.execute('''
        UPDATE products 
        SET harga_beli = CAST(harga * 0.62 AS INTEGER) 
        WHERE harga_beli = 0 OR harga_beli IS NULL
      ''');

      // Backfill metode_pembayaran for old transactions
      await db.execute('''
        UPDATE transactions 
        SET metode_pembayaran = COALESCE(metode, 'Tunai')
        WHERE metode_pembayaran IS NULL OR metode_pembayaran = ''
      ''');
    }
    if (oldVersion < 5) {
      // Audit Log table for business actions
      await db.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT NOT NULL,
          user TEXT,
          action TEXT NOT NULL,
          entity_type TEXT,
          entity_id INTEGER,
          description TEXT,
          details TEXT
        )
      ''');
    }

    if (oldVersion < 6) {
      // Performance indexes for growing data (transactions, kasbon, reports)
      // These dramatically speed up WHERE, ORDER BY, JOIN on large tables
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at)');
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_tanggal ON transactions(tanggal)');
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transactions_is_synced ON transactions(is_synced)');
      } catch (_) {}

      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transaction_items_tx_id ON transaction_items(transaction_id)');
      } catch (_) {}

      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_kasbons_phone ON kasbons(phone)');
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_kasbons_customer_name ON kasbons(customer_name)');
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_kasbons_status ON kasbons(status)');
      } catch (_) {}

      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)');
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_products_nama ON products(nama)');
      } catch (_) {}

      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp)');
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action)');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      try {
        await db.execute(
            "ALTER TABLE transaction_items ADD COLUMN product_id INTEGER");
      } catch (_) {}
      try {
        await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_transaction_items_product_id ON transaction_items(product_id)');
      } catch (_) {}

      final users = await db.query('users', columns: ['id', 'password']);
      for (final user in users) {
        final stored = user['password']?.toString() ?? '';
        if (stored.isNotEmpty && !_isHashedPassword(stored)) {
          await db.update(
            'users',
            {'password': hashPassword(stored)},
            where: 'id = ?',
            whereArgs: [user['id']],
          );
        }
      }

      try {
        await db.execute('''
          UPDATE transaction_items
          SET product_id = (
            SELECT p.id
            FROM products p
            WHERE p.nama = transaction_items.nama
            ORDER BY p.id ASC
            LIMIT 1
          )
          WHERE product_id IS NULL
        ''');
      } catch (_) {}

      final legacyTransactions = await db.query(
        'transactions',
        columns: ['id', 'tanggal', 'waktu', 'created_at'],
        where: 'created_at IS NULL OR created_at = ?',
        whereArgs: [''],
      );
      for (final tx in legacyTransactions) {
        final parsed = parseLegacyTransactionDate(tx['tanggal'], tx['waktu']);
        if (parsed != null) {
          await db.update(
            'transactions',
            {'created_at': parsed.toIso8601String()},
            where: 'id = ?',
            whereArgs: [tx['id']],
          );
        }
      }
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        harga INTEGER NOT NULL,
        harga_beli INTEGER DEFAULT 0,
        stok INTEGER NOT NULL,
        status TEXT NOT NULL,
        barcode TEXT DEFAULT '',
        gambar TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        whatsapp TEXT NOT NULL,
        alamat TEXT NOT NULL,
        hutang INTEGER NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE kasbons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_name TEXT NOT NULL,
        phone TEXT NOT NULL,
        amount INTEGER NOT NULL,
        remaining_amount INTEGER NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice TEXT NOT NULL,
        total INTEGER NOT NULL,
        waktu TEXT NOT NULL,
        items_summary TEXT NOT NULL,
        metode TEXT NOT NULL, -- legacy, kept for compatibility
        bayar INTEGER NOT NULL,
        kembali INTEGER NOT NULL,
        tanggal TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        created_at TEXT,
        metode_pembayaran TEXT DEFAULT 'Tunai',
        total_modal INTEGER DEFAULT 0,
        total_laba INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        product_id INTEGER,
        nama TEXT NOT NULL,
        qty INTEGER NOT NULL,
        harga INTEGER NOT NULL,
        subtotal INTEGER NOT NULL
      )
    ''');

    // Users for login/registration (local only)
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT,
        phone TEXT NOT NULL,
        password TEXT NOT NULL,
        nama_toko TEXT,
        created_at TEXT
      )
    ''');

    // Audit Log for business actions
    await db.execute('''
      CREATE TABLE audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        user TEXT,
        action TEXT NOT NULL,
        entity_type TEXT,
        entity_id INTEGER,
        description TEXT,
        details TEXT
      )
    ''');

    // === Performance Indexes (added in v6) ===
    // Critical for reports, kasbon search, sync, and large transaction history
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_tanggal ON transactions(tanggal)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_is_synced ON transactions(is_synced)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transaction_items_tx_id ON transaction_items(transaction_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transaction_items_product_id ON transaction_items(product_id)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_kasbons_phone ON kasbons(phone)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_kasbons_customer_name ON kasbons(customer_name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_kasbons_status ON kasbons(status)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_nama ON products(nama)');

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action)');

    // Populate Initial Dummy Data
    for (var p in _webProducts) {
      await db.insert('products', {
        'nama': p['nama'],
        'harga': p['harga'],
        'harga_beli': p['harga_beli'] ?? (safeInt(p['harga']) * 0.62).round(),
        'stok': p['stok'],
        'status': p['status'],
        'barcode': p['barcode'] ?? '',
        'gambar': p['gambar'] ?? '',
      });
    }

    for (var s in _webSuppliers) {
      await db.insert('suppliers', {
        'nama': s['nama'],
        'whatsapp': s['whatsapp'],
        'alamat': s['alamat'],
        'hutang': s['hutang'],
        'status': s['status'],
      });
    }

    for (var k in _webKasbons) {
      await db.insert('kasbons', {
        'customer_name': k['customer_name'],
        'phone': k['phone'],
        'amount': k['amount'],
        'remaining_amount': k['remaining_amount'],
        'date': k['date'],
        'status': k['status'],
        'description': k['description'],
      });
    }

    for (var t in _webTransactions) {
      final txWithSync = Map<String, dynamic>.from(t)
        ..['is_synced'] = 1
        ..['created_at'] =
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String()
        ..['metode_pembayaran'] =
            t['metode_pembayaran'] ?? t['metode'] ?? 'Tunai'
        ..['total_modal'] = (t['total_modal'] ?? 0)
        ..['total_laba'] = (t['total_laba'] ??
            ((t['total'] as int? ?? 0) * 0.35).round()); // rough for old dummy
      await db.insert('transactions', txWithSync);
    }

    // Akun contoh dikonfigurasi melalui DemoConfig.
    await db.insert('users', {
      'email': DemoConfig.email,
      'phone': normalizePhoneWA(DemoConfig.phone),
      'password': hashPassword(DemoConfig.password),
      'nama_toko': 'Warung Sejahtera',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  // --- PRODUCTS CRUD ---
  Future<List<Map<String, dynamic>>> getProducts() async {
    if (kIsWeb) {
      return List.from(_webProducts);
    }
    final db = await database;
    return await db.query('products');
  }

  Future<Map<String, dynamic>?> getProductByBarcode(String barcode) async {
    if (barcode.isEmpty) return null;

    if (kIsWeb) {
      try {
        return _webProducts.firstWhere(
          (p) => p['barcode'] == barcode,
        );
      } catch (_) {
        return null;
      }
    }

    final db = await database;
    final results = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<Map<String, dynamic>?> getProductById(int id) async {
    if (id <= 0) return null;

    if (kIsWeb) {
      try {
        return _webProducts.firstWhere((p) => safeInt(p['id']) == id);
      } catch (_) {
        return null;
      }
    }

    final db = await database;
    final results = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> insertProduct(Map<String, dynamic> product) async {
    if (kIsWeb) {
      final newId = _webProducts.isEmpty
          ? 1
          : (_webProducts
                  .map((e) => safeInt(e['id']))
                  .reduce((a, b) => a > b ? a : b) +
              1);
      final item = Map<String, dynamic>.from(product)..['id'] = newId;
      _webProducts.add(item);
      return newId;
    }
    final db = await database;
    return await db.insert('products', product);
  }

  Future<int> updateProduct(Map<String, dynamic> product) async {
    final int id = product['id'];
    if (kIsWeb) {
      final index = _webProducts.indexWhere((e) => e['id'] == id);
      if (index != -1) {
        _webProducts[index] = product;
        return 1;
      }
      return 0;
    }
    final db = await database;
    return await db
        .update('products', product, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteProduct(int id) async {
    if (kIsWeb) {
      final lenBefore = _webProducts.length;
      _webProducts.removeWhere((e) => e['id'] == id);
      return lenBefore - _webProducts.length;
    }
    final db = await database;
    return await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  // --- SUPPLIERS CRUD ---
  Future<List<Map<String, dynamic>>> getSuppliers() async {
    if (kIsWeb) {
      return List.from(_webSuppliers);
    }
    final db = await database;
    return await db.query('suppliers');
  }

  Future<int> insertSupplier(Map<String, dynamic> supplier) async {
    if (kIsWeb) {
      final newId = _webSuppliers.isEmpty
          ? 1
          : (_webSuppliers
                  .map((e) => safeInt(e['id']))
                  .reduce((a, b) => a > b ? a : b) +
              1);
      final item = Map<String, dynamic>.from(supplier)..['id'] = newId;
      _webSuppliers.add(item);
      return newId;
    }
    final db = await database;
    return await db.insert('suppliers', supplier);
  }

  // --- KASBONS (CUSTOMER DEBTS) CRUD ---
  Future<List<Map<String, dynamic>>> getKasbons() async {
    if (kIsWeb) {
      return List.from(_webKasbons);
    }
    final db = await database;
    return await db.query('kasbons');
  }

  Future<int> insertKasbon(Map<String, dynamic> kasbon) async {
    if (kIsWeb) {
      final newId = _webKasbons.isEmpty
          ? 1
          : (_webKasbons
                  .map((e) => safeInt(e['id']))
                  .reduce((a, b) => a > b ? a : b) +
              1);
      final item = Map<String, dynamic>.from(kasbon)..['id'] = newId;
      _webKasbons.add(item);
      return newId;
    }
    final db = await database;
    return await db.insert('kasbons', kasbon);
  }

  Future<int> payKasbon(int id, int payAmount) async {
    if (kIsWeb) {
      final index = _webKasbons.indexWhere((e) => e['id'] == id);
      if (index != -1) {
        final item = Map<String, dynamic>.from(_webKasbons[index]);
        final int remaining = item['remaining_amount'] as int;
        final int newRemaining = remaining - payAmount;
        item['remaining_amount'] = newRemaining < 0 ? 0 : newRemaining;
        item['status'] =
            item['remaining_amount'] == 0 ? 'Lunas' : 'Belum Lunas';
        _webKasbons[index] = item;
        return 1;
      }
      return 0;
    }
    final db = await database;
    final List<Map<String, dynamic>> res =
        await db.query('kasbons', where: 'id = ?', whereArgs: [id]);
    if (res.isNotEmpty) {
      final item = Map<String, dynamic>.from(res.first);
      final int remaining = item['remaining_amount'] as int;
      final int newRemaining = remaining - payAmount;
      final updatedRemaining = newRemaining < 0 ? 0 : newRemaining;
      final updatedStatus = updatedRemaining == 0 ? 'Lunas' : 'Belum Lunas';
      return await db.update(
          'kasbons',
          {
            'remaining_amount': updatedRemaining,
            'status': updatedStatus,
          },
          where: 'id = ?',
          whereArgs: [id]);
    }
    return 0;
  }

  // --- TRANSACTIONS CRUD ---
  Future<List<Map<String, dynamic>>> getTransactions() async {
    if (kIsWeb) {
      return List.from(_webTransactions);
    }
    final db = await database;
    return await db.query('transactions', orderBy: 'id DESC');
  }

  Future<int> insertTransaction(
      Map<String, dynamic> tx, List<Map<String, dynamic>> items) async {
    final nowIso = DateTime.now().toIso8601String();

    // Prepare base meta (will compute modal/laba inside txn for accuracy)
    final txWithMeta = Map<String, dynamic>.from(tx)
      ..['is_synced'] = 0
      ..['created_at'] = nowIso;

    if (kIsWeb) {
      final requestedQty = <String, int>{};
      final requestedProducts = <String, Map<String, dynamic>>{};

      for (final item in items) {
        final productId = safeInt(item['product_id'] ?? item['id']);
        final productName = item['nama']?.toString() ?? '';
        final key = productId > 0 ? 'id:$productId' : 'name:$productName';
        requestedQty[key] = (requestedQty[key] ?? 0) + safeInt(item['qty']);

        final indexProd = productId > 0
            ? _webProducts.indexWhere((p) => safeInt(p['id']) == productId)
            : _webProducts.indexWhere((p) => p['nama'] == productName);
        if (indexProd == -1) {
          throw StockException('Produk "$productName" tidak ditemukan.');
        }
        requestedProducts[key] =
            Map<String, dynamic>.from(_webProducts[indexProd]);
      }

      for (final entry in requestedProducts.entries) {
        final product = entry.value;
        final requiredQty = requestedQty[entry.key] ?? 0;
        final currentStock = safeInt(product['stok']);
        if (requiredQty > currentStock) {
          throw StockException(
              'Stok ${product['nama']} tidak mencukupi. Tersedia $currentStock, diminta $requiredQty.');
        }
      }

      int totalModal = 0;
      for (var item in items) {
        final productId = safeInt(item['product_id'] ?? item['id']);
        final indexProd = productId > 0
            ? _webProducts.indexWhere((p) => safeInt(p['id']) == productId)
            : _webProducts.indexWhere((p) => p['nama'] == item['nama']);
        if (indexProd != -1) {
          final hb = safeInt(_webProducts[indexProd]['harga_beli']);
          totalModal += safeInt(item['qty']) * hb;
        }
      }
      final total = (tx['total'] as int?) ?? 0;
      txWithMeta['metode_pembayaran'] =
          tx['metode_pembayaran'] ?? tx['metode'] ?? 'Tunai';
      txWithMeta['total_modal'] = totalModal;
      txWithMeta['total_laba'] = total - totalModal;

      final newTxId = _webTransactions.isEmpty
          ? 1
          : (_webTransactions
                  .map((e) => safeInt(e['id']))
                  .reduce((a, b) => a > b ? a : b) +
              1);
      final txItem = Map<String, dynamic>.from(txWithMeta)..['id'] = newTxId;
      _webTransactions.insert(0, txItem);

      for (var item in items) {
        final newId = _webTxItems.isEmpty
            ? 1
            : (_webTxItems
                    .map((e) => safeInt(e['id']))
                    .reduce((a, b) => a > b ? a : b) +
                1);
        final itemMap = Map<String, dynamic>.from(item)
          ..['id'] = newId
          ..['transaction_id'] = newTxId;
        _webTxItems.add(itemMap);

        // Adjust stocks in web fallback
        final productId = safeInt(item['product_id'] ?? item['id']);
        final indexProd = productId > 0
            ? _webProducts.indexWhere((p) => safeInt(p['id']) == productId)
            : _webProducts.indexWhere((p) => p['nama'] == item['nama']);
        if (indexProd != -1) {
          final p = Map<String, dynamic>.from(_webProducts[indexProd]);
          final int qty = safeInt(item['qty']);
          final int currentStok = safeInt(p['stok']);
          final int newStok = (currentStok - qty) < 0 ? 0 : (currentStok - qty);
          p['stok'] = newStok;
          p['status'] = stockStatusFor(newStok);
          _webProducts[indexProd] = p;
        }
      }
      return newTxId;
    }

    final db = await database;
    int txId = 0;
    await db.transaction((txn) async {
      final requestedQty = <String, int>{};
      final productCache = <String, Map<String, dynamic>>{};

      for (final item in items) {
        final productId = safeInt(item['product_id'] ?? item['id']);
        final productName = item['nama']?.toString() ?? '';
        final key = productId > 0 ? 'id:$productId' : 'name:$productName';
        requestedQty[key] = (requestedQty[key] ?? 0) + safeInt(item['qty']);

        final List<Map<String, dynamic>> products = productId > 0
            ? await txn.query('products',
                where: 'id = ?', whereArgs: [productId], limit: 1)
            : await txn.query('products',
                where: 'nama = ?', whereArgs: [productName], limit: 1);
        if (products.isEmpty) {
          throw StockException('Produk "$productName" tidak ditemukan.');
        }
        productCache[key] = Map<String, dynamic>.from(products.first);
      }

      for (final entry in productCache.entries) {
        final product = entry.value;
        final requiredQty = requestedQty[entry.key] ?? 0;
        final currentStock = safeInt(product['stok']);
        if (requiredQty > currentStock) {
          throw StockException(
              'Stok ${product['nama']} tidak mencukupi. Tersedia $currentStock, diminta $requiredQty.');
        }
      }

      // Compute total_modal & laba inside transaction for accuracy (lookup current harga_beli)
      int totalModal = 0;
      for (var item in items) {
        final productId = safeInt(item['product_id'] ?? item['id']);
        final key = productId > 0 ? 'id:$productId' : 'name:${item['nama']}';
        final product = productCache[key];
        if (product != null) {
          final hb = safeInt(product['harga_beli']);
          totalModal += safeInt(item['qty']) * hb;
        }
      }
      final total = (tx['total'] as int?) ?? 0;
      txWithMeta['metode_pembayaran'] =
          tx['metode_pembayaran'] ?? tx['metode'] ?? 'Tunai';
      txWithMeta['total_modal'] = totalModal;
      txWithMeta['total_laba'] = total - totalModal;

      txId = await txn.insert('transactions', txWithMeta);

      for (var item in items) {
        final productId = safeInt(item['product_id'] ?? item['id']);
        await txn.insert('transaction_items', {
          'transaction_id': txId,
          'product_id': productId > 0 ? productId : null,
          'nama': item['nama'],
          'qty': item['qty'],
          'harga': item['harga'],
          'subtotal': item['subtotal'],
        });
      }

      for (final entry in productCache.entries) {
        final product = entry.value;
        final requiredQty = requestedQty[entry.key] ?? 0;
        final int currentStock = safeInt(product['stok']);
        final int newStock = currentStock - requiredQty;
        await txn.update(
          'products',
          {
            'stok': newStock,
            'status': stockStatusFor(newStock),
          },
          where: 'id = ?',
          whereArgs: [product['id']],
        );
      }
    });
    return txId;
  }

  // --- AUTH (Login / Register) ---
  Future<Map<String, dynamic>?> login(
      String identifier, String password) async {
    if (kIsWeb) {
      // Demo: allow the seeded credentials on web too
      if ((identifier == DemoConfig.email || identifier == DemoConfig.phone) &&
          password == DemoConfig.password) {
        return {
          'id': 1,
          'email': DemoConfig.email,
          'phone': DemoConfig.phone,
          'nama_toko': 'Warung Sejahtera',
        };
      }
      return null;
    }
    final db = await database;
    final rawIdentifier = identifier.trim();
    final normalizedPhone = normalizePhoneWA(rawIdentifier);
    final displayPhone = formatPhoneDisplay(rawIdentifier);
    final res = await db.query(
      'users',
      where: 'email = ? OR phone = ? OR phone = ? OR phone = ?',
      whereArgs: [rawIdentifier, rawIdentifier, normalizedPhone, displayPhone],
      orderBy: 'id DESC',
    );
    for (final user in res) {
      final stored = user['password']?.toString() ?? '';
      if (verifyPassword(password, stored)) {
        if (!_isHashedPassword(stored)) {
          await db.update(
            'users',
            {'password': hashPassword(password)},
            where: 'id = ?',
            whereArgs: [user['id']],
          );
        }
        return user;
      }
    }
    return null;
  }

  Future<int> insertUser(Map<String, dynamic> user) async {
    if (kIsWeb) {
      // For web demo just pretend success
      return 1;
    }
    final db = await database;
    final rawPhone = user['phone']?.toString() ?? '';
    final normalizedPhone = normalizePhoneWA(rawPhone);
    return await db.insert('users', {
      ...user,
      'phone': normalizedPhone.isNotEmpty ? normalizedPhone : rawPhone,
      'password': hashPassword(user['password']?.toString() ?? ''),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<Map<String, dynamic>?> getUserById(int userId) async {
    if (userId <= 0 || kIsWeb) return null;
    final db = await database;
    final users = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    return users.isNotEmpty ? users.first : null;
  }

  Future<bool> verifyUserPassword(int userId, String password) async {
    final user = await getUserById(userId);
    if (user == null) return false;
    final stored = user['password']?.toString() ?? '';
    final matched = verifyPassword(password, stored);
    if (matched && !_isHashedPassword(stored) && !kIsWeb) {
      await updateUserPassword(userId, password);
    }
    return matched;
  }

  Future<int> updateUserPassword(int userId, String newPassword) async {
    if (userId <= 0 || kIsWeb) return 0;
    final db = await database;
    return await db.update(
      'users',
      {'password': hashPassword(newPassword)},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  // --- SYNC HELPERS (for cloud REST sync) ---
  Future<List<Map<String, dynamic>>> getUnsyncedTransactions() async {
    if (kIsWeb) {
      return []; // web demo no real sync
    }
    final db = await database;
    return await db.query('transactions',
        where: 'is_synced = ?', whereArgs: [0], orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getTransactionItems(int txId) async {
    if (kIsWeb) {
      return _webTxItems
          .where((item) => safeInt(item['transaction_id']) == txId)
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
        ..sort((a, b) => safeInt(a['id']).compareTo(safeInt(b['id'])));
    }
    final db = await database;
    return await db.query(
      'transaction_items',
      where: 'transaction_id = ?',
      whereArgs: [txId],
      orderBy: 'id ASC',
    );
  }

  Future<int> markTransactionSynced(int id) async {
    if (kIsWeb) return 1;
    final db = await database;
    return await db.update('transactions', {'is_synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  // --- REPORTS (real data for Laporan) ---
  Future<List<Map<String, dynamic>>> getRecentTransactions(
      {int limit = 30}) async {
    if (kIsWeb) {
      return List<Map<String, dynamic>>.from(_webTransactions)
          .take(limit)
          .toList();
    }
    final db = await database;
    return await db.query('transactions', orderBy: 'id DESC', limit: limit);
  }

  /// Returns list of daily sales for last N days, aggregated from DB
  Future<List<Map<String, dynamic>>> getDailySalesSummary(
      {int days = 7}) async {
    final txs = await getTransactions();
    final now = DateTime.now();
    final startDay = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final Map<String, int> daily = {};

    for (int i = 0; i < days; i++) {
      final day = startDay.add(Duration(days: i));
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      daily[key] = 0;
    }

    for (final tx in txs) {
      final dt = extractTransactionDate(tx);
      if (dt == null) continue;
      final txDay = DateTime(dt.year, dt.month, dt.day);
      if (txDay.isBefore(startDay)) continue;
      final key =
          '${txDay.year}-${txDay.month.toString().padLeft(2, '0')}-${txDay.day.toString().padLeft(2, '0')}';
      if (!daily.containsKey(key)) continue;
      daily[key] = (daily[key] ?? 0) + safeInt(tx['total']);
    }

    final entries = daily.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => {'date': e.key, 'total': e.value}).toList();
  }

  Future<Map<String, dynamic>> getSalesStats({bool monthly = false}) async {
    final txs = await getRecentTransactions(limit: 500);
    int total = 0;
    int count = txs.length;
    int itemsSold = 0; // rough, we can enhance later

    for (var t in txs) {
      total += (t['total'] as int? ?? 0);
    }

    // For items count we would join, but for demo approximate from summary or skip detailed
    // To keep simple we just use tx count * avg items or load items count
    if (!kIsWeb) {
      final db = await database;
      final itemRows = await db
          .rawQuery('SELECT SUM(qty) as sum_qty FROM transaction_items');
      if (itemRows.isNotEmpty && itemRows.first['sum_qty'] != null) {
        itemsSold = (itemRows.first['sum_qty'] as int?) ?? 0;
      }
    }

    return {
      'total_sales': total,
      'tx_count': count,
      'items_sold': itemsSold,
    };
  }

  // --- Low stock for notifications (Bagian 3)
  Future<List<Map<String, dynamic>>> getLowStockProducts(
      {int threshold = 5}) async {
    if (kIsWeb) {
      return _webProducts.where((p) => safeInt(p['stok']) < threshold).toList();
    }
    final db = await database;
    return await db.query('products',
        where: 'stok < ?', whereArgs: [threshold], orderBy: 'stok ASC');
  }

  // Filtered transactions for laporan periods (using created_at or tanggal)
  Future<List<Map<String, dynamic>>> getTransactionsInPeriod(
      DateTime start, DateTime end) async {
    final source = kIsWeb
        ? List<Map<String, dynamic>>.from(_webTransactions)
        : await getTransactions();
    final filtered = source.where((tx) {
      final txDate = extractTransactionDate(tx);
      if (txDate == null) return false;
      return !txDate.isBefore(start) && !txDate.isAfter(end);
    }).toList();
    filtered.sort((a, b) {
      final aDate = extractTransactionDate(a);
      final bDate = extractTransactionDate(b);
      if (aDate == null || bDate == null) {
        return safeInt(b['id']).compareTo(safeInt(a['id']));
      }
      final compare = bDate.compareTo(aDate);
      if (compare != 0) return compare;
      return safeInt(b['id']).compareTo(safeInt(a['id']));
    });
    return filtered;
  }

  Future<List<Map<String, dynamic>>> getPopularProducts(
      {int limit = 20}) async {
    if (kIsWeb) {
      return List.from(_webProducts)
        ..sort((a, b) => safeInt(b['id']).compareTo(safeInt(a['id'])));
    }
    final db = await database;
    final results = await db.rawQuery('''
      SELECT p.*, COALESCE(SUM(ti.qty), 0) as sold_qty 
      FROM products p 
      LEFT JOIN transaction_items ti
        ON ti.product_id = p.id
        OR (ti.product_id IS NULL AND p.nama = ti.nama)
      GROUP BY p.id 
      ORDER BY sold_qty DESC, p.id DESC 
      LIMIT ?
    ''', [limit]);
    return results;
  }

  // --- AUDIT LOG ---
  Future<int> insertAuditLog(Map<String, dynamic> log) async {
    if (kIsWeb) {
      // For web demo, just print
      print('AUDIT LOG (web): ${log['action']} - ${log['description']}');
      return 1;
    }
    final db = await database;
    return await db.insert('audit_logs', {
      ...log,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getAuditLogs({int limit = 100}) async {
    if (kIsWeb) return [];
    final db = await database;
    return await db.query('audit_logs', orderBy: 'id DESC', limit: limit);
  }

  // === Backup / Restore for cloud feature (full data export to JSON file) ===
  Future<Map<String, dynamic>> exportAllData() async {
    if (kIsWeb) {
      // embed items for tx in web
      final txsWithItems = <Map<String, dynamic>>[];
      for (final tx in _webTransactions) {
        final txId = tx['id'] as int;
        final items = _webTxItems
            .where((i) => safeInt(i['transaction_id']) == txId)
            .toList();
        final tcopy = Map<String, dynamic>.from(tx);
        tcopy['items'] = items;
        txsWithItems.add(tcopy);
      }
      return {
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'products': List.from(_webProducts),
        'suppliers': List.from(_webSuppliers),
        'kasbons': List.from(_webKasbons),
        'transactions': txsWithItems,
      };
    }

    final products = await getProducts();
    final suppliers = await getSuppliers();
    final kasbons = await getKasbons();
    final txs = await getTransactions();
    final txsWithItems = <Map<String, dynamic>>[];
    for (final tx in txs) {
      final txId = tx['id'] as int;
      final items = await getTransactionItems(txId);
      final tcopy = Map<String, dynamic>.from(tx);
      tcopy['items'] = items;
      txsWithItems.add(tcopy);
    }
    return {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'products': products,
      'suppliers': suppliers,
      'kasbons': kasbons,
      'transactions': txsWithItems,
    };
  }

  Future<String> createBackupFile() async {
    final data = await exportAllData();
    final jsonStr = jsonEncode(data);
    if (kIsWeb) {
      return 'WEB_JSON:$jsonStr';
    }
    final dir = await getApplicationDocumentsDirectory();
    final ts =
        DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final filePath = '${dir.path}/toko5758_backup_$ts.json';
    final file = File(filePath);
    await file.writeAsString(jsonStr);
    return filePath;
  }

  Future<bool> restoreFromBackup(String source) async {
    String jsonStr;
    if (source.startsWith('WEB_JSON:')) {
      jsonStr = source.substring(9);
    } else {
      final file = File(source);
      if (!await file.exists()) return false;
      jsonStr = await file.readAsString();
    }
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    await _importDataFromMap(data);
    return true;
  }

  Future<void> _importDataFromMap(Map<String, dynamic> data) async {
    if (kIsWeb) {
      _webProducts.clear();
      _webProducts.addAll((data['products'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)));
      _webSuppliers.clear();
      _webSuppliers.addAll((data['suppliers'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)));
      _webKasbons.clear();
      _webKasbons.addAll((data['kasbons'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)));
      _webTransactions.clear();
      _webTxItems.clear();
      final txList = (data['transactions'] as List? ?? <dynamic>[]);
      for (final t in txList) {
        final tmap = Map<String, dynamic>.from(t as Map);
        final items = (tmap.remove('items') as List? ?? <dynamic>[])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _webTransactions.add(tmap);
        _webTxItems.addAll(items);
      }
      return;
    }

    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('products');
      await txn.delete('suppliers');
      await txn.delete('kasbons');
      await txn.delete('transaction_items');
      await txn.delete('transactions');

      for (final p in (data['products'] as List? ?? <dynamic>[])) {
        await txn.insert('products', Map<String, dynamic>.from(p as Map));
      }
      for (final s in (data['suppliers'] as List? ?? <dynamic>[])) {
        await txn.insert('suppliers', Map<String, dynamic>.from(s as Map));
      }
      for (final k in (data['kasbons'] as List? ?? <dynamic>[])) {
        await txn.insert('kasbons', Map<String, dynamic>.from(k as Map));
      }
      for (final t in (data['transactions'] as List? ?? <dynamic>[])) {
        final tmap = Map<String, dynamic>.from(t as Map);
        final items = (tmap.remove('items') as List? ?? <dynamic>[])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        await txn.insert('transactions', tmap);
        for (final item in items) {
          await txn.insert('transaction_items', item);
        }
      }
    });
  }
}
