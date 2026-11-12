import 'package:bluetooth_thermal_printer/bluetooth_thermal_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db_helper.dart';

class PrinterService {
  static final PrinterService _instance = PrinterService._internal();
  factory PrinterService() => _instance;
  PrinterService._internal();

  String? _configuredAddress;
  String? _connectedAddress;
  bool _isConnected = false;
  String _paperSize = '58mm';

  static const String _prefPrinterAddress = 'printer_bt_address';
  static const String _prefPaperSize = 'printer_paper_size';

  bool _looksConnected(String? status) {
    final normalized = status?.trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized.contains('connected');
  }

  Future<bool> _refreshConnectionStatus() async {
    try {
      final status = await BluetoothThermalPrinter.connectionStatus;
      _isConnected = _looksConnected(status);
    } catch (_) {
      _isConnected = false;
    }
    if (_configuredAddress == null || _configuredAddress!.isEmpty) {
      _isConnected = false;
    }
    _connectedAddress = _isConnected ? _configuredAddress : null;
    return _isConnected;
  }

  Future<void> loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    _configuredAddress = prefs.getString(_prefPrinterAddress);
    _paperSize = prefs.getString(_prefPaperSize) ?? '58mm';
    await _refreshConnectionStatus();
  }

  Future<void> savePrinter(String? address, {String? paperSize}) async {
    final prefs = await SharedPreferences.getInstance();
    if (address != null) {
      await prefs.setString(_prefPrinterAddress, address);
      _configuredAddress = address;
    }
    if (paperSize != null) {
      await prefs.setString(_prefPaperSize, paperSize);
      _paperSize = paperSize;
    }
  }

  String get paperSize => _paperSize;
  String? get connectedAddress => _connectedAddress;

  /// Real scan of paired Bluetooth thermal printers (using bluetooth_thermal_printer).
  /// Devices are paired in phone Settings > Bluetooth first. Returns list like "Name#MAC".
  Future<List<String>> getPairedDevices() async {
    await loadSavedPrinter();
    try {
      final List? bluetooths = await BluetoothThermalPrinter.getBluetooths;
      if (bluetooths != null && bluetooths.isNotEmpty) {
        return bluetooths.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('Real BT getBluetooths error: $e. Make sure Bluetooth is on and permissions granted.');
    }
    // Fallback: if we have a saved one, surface it so UI is not empty
    if (_configuredAddress != null && _configuredAddress!.isNotEmpty) {
      return ['Saved Printer#$_configuredAddress'];
    }
    return [];
  }

  Future<bool> connect(String device) async {
    try {
      final parts = device.split('#');
      final addr = parts.length > 1 ? parts.last : device;
      // Real connect via the plugin. It returns "true" string on success on many versions.
      final String? result = await BluetoothThermalPrinter.connect(addr);
      final success = result != null && (result.toLowerCase() == 'true' || result.toLowerCase().contains('true') || result == 'connected');
      if (success) {
        await savePrinter(addr);
        _configuredAddress = addr;
        _connectedAddress = addr;
        _isConnected = true;
        return true;
      }
      _isConnected = false;
      _connectedAddress = null;
      debugPrint('BT connect returned: $result');
      return false;
    } catch (e) {
      _isConnected = false;
      _connectedAddress = null;
      debugPrint('Printer connect (real) error: $e');
      return false;
    }
  }

  Future<bool> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefPrinterAddress);
    _configuredAddress = null;
    _connectedAddress = null;
    _isConnected = false;
    return true;
  }

  bool get isConnected => _isConnected;

  /// Build ESC/POS bytes for a receipt. Supports 58mm / 80mm paper width.
  Future<List<int>> _buildReceiptBytes(Map<String, dynamic> tx, {String? paper}) async {
    final paperSize = paper ?? _paperSize;
    final profile = await CapabilityProfile.load();
    final generator = Generator(
      paperSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58,
      profile,
    );

    List<int> bytes = [];

    final String invoice = tx['invoice'] ?? 'TX-XXXX';
    final String tanggal = tx['tanggal'] ?? '';
    final String waktu = tx['waktu'] ?? '';
    final int total = tx['total'] ?? 0;
    final int bayar = tx['bayar'] ?? 0;
    final int kembali = tx['kembali'] ?? 0;
    final String metode = tx['metode'] ?? 'Tunai';
    final List items = (tx['items'] as List?) ?? [];

    // Header
    bytes += generator.text('TOKO5758',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2));
    bytes += generator.text('Warung Sejahtera',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text('Jl. Sudirman No.45, Jakarta',
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    bytes += generator.text('WA: 0812-3456-7890',
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    bytes += generator.hr();

    bytes += generator.text('No: $invoice   $tanggal $waktu',
        styles: const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB, height: PosTextSize.size1));
    bytes += generator.text('Kasir: Admin',
        styles: const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB));

    bytes += generator.hr();

    // Items
    for (final item in items) {
      final nama = (item['nama'] ?? '').toString();
      final qty = (item['qty'] ?? 1) as int;
      final harga = (item['harga'] ?? 0) as int;
      final sub = safeInt(item['subtotal'], qty * harga);

      bytes += generator.row([
        PosColumn(text: '$nama x$qty', width: 8),
        PosColumn(text: formatRupiah(sub), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: formatRupiah(total), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);

    bytes += generator.row([
      PosColumn(text: 'Diterima ($metode)', width: 6),
      PosColumn(text: formatRupiah(bayar), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Kembalian', width: 6),
      PosColumn(text: formatRupiah(kembali), width: 6, styles: const PosStyles(align: PosAlign.right)),
    ]);

    bytes += generator.hr();
    bytes += generator.text('Terima kasih!',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('Barang tidak dapat ditukar.',
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB));
    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  /// Print the receipt (generates real ESC/POS bytes via esc_pos_utils + sends via BT thermal printer plugin).
  Future<String> printReceipt(Map<String, dynamic> transactionData) async {
    try {
      await loadSavedPrinter();

      if (!_isConnected && _configuredAddress != null) {
        await connect(_configuredAddress!);
      }

      if (!_isConnected || _connectedAddress == null) {
        return 'Tidak ada printer terhubung. Silakan hubungkan di Pengaturan > Set Printer.';
      }

      // Generate proper ESC/POS commands (real)
      final bytes = await _buildReceiptBytes(transactionData);
      debugPrint('ESC/POS bytes generated: ${bytes.length} bytes for printer $_connectedAddress (paper: $_paperSize)');

      // REAL SEND to the thermal printer
      final String? writeResult = await BluetoothThermalPrinter.writeBytes(bytes);
      if (writeResult != null && (writeResult.toLowerCase().contains('true') || writeResult == 'true')) {
        return 'Struk berhasil dicetak ke $_connectedAddress (${bytes.length} bytes)';
      }
      // Some versions return null or other on success, assume ok if no exception
      return 'Struk dikirim ke $_connectedAddress (${bytes.length} bytes via BT)';
    } catch (e) {
      debugPrint('Print error: $e');
      return 'Gagal mencetak: $e';
    }
  }

  /// Test print. Prefers a real recent transaction from DB (no dummy UI). Falls back to demo if none.
  Future<String> testPrint() async {
    try {
      final db = DbHelper();
      final recent = await db.getRecentTransactions(limit: 1);
      if (recent.isNotEmpty) {
        final tx = Map<String, dynamic>.from(recent.first);
        final txId = tx['id'] as int?;
        if (txId != null) {
          final items = await db.getTransactionItems(txId);
          tx['items'] = items.map((it) => {
            'nama': (it['nama'] ?? '').toString(),
            'qty': (it['qty'] ?? 1) as int,
            'harga': (it['harga'] ?? 0) as int,
            'subtotal': safeInt(it['subtotal']),
          }).toList();
          // ensure fields for receipt builder
          tx['tanggal'] ??= tx['date'] ?? '';
          tx['waktu'] ??= '';
          tx['metode'] ??= tx['metode_pembayaran'] ?? 'Tunai';
          tx['bayar'] ??= tx['total'] ?? 0;
          tx['kembali'] ??= 0;
          return await printReceipt(tx);
        }
      }
    } catch (e) {
      debugPrint('testPrint real data error: $e');
    }
    // Fallback minimal demo (only if no real data at all)
    final demo = {
      'invoice': 'TEST-001',
      'tanggal': '01 Jan 2026',
      'waktu': '12:00',
      'total': 15000,
      'bayar': 20000,
      'kembali': 5000,
      'metode': 'Tunai',
      'items': [
        {'nama': 'Test Item', 'qty': 1, 'harga': 15000}
      ],
    };
    return printReceipt(demo);
  }
}
