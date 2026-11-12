import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../data/db_helper.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final DbHelper _db = DbHelper();

  // Sinkronisasi hanya aktif jika endpoint milik sendiri dikonfigurasi saat build.
  static const String _syncEndpoint =
      String.fromEnvironment('TOKO5758_SYNC_ENDPOINT');

  List<int> _extractAckedIds(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return const [];
    if (decoded['success'] != true) return const [];
    final ids = decoded['synced_ids'];
    if (ids is! List) return const [];
    return ids.map((e) => safeInt(e, -1)).where((id) => id > 0).toList();
  }

  /// Sync all unsynced local transactions to cloud.
  /// Returns summary string for UI.
  Future<String> syncNow() async {
    if (_syncEndpoint.isEmpty) {
      return 'Sinkronisasi belum dikonfigurasi. Data tetap tersimpan di perangkat.';
    }
    try {
      final unsynced = await _db.getUnsyncedTransactions();
      if (unsynced.isEmpty) {
        return 'Tidak ada data baru untuk disinkronkan.';
      }

      final List<Map<String, dynamic>> payload = [];

      for (final tx in unsynced) {
        final txId = tx['id'] as int;
        final items = await _db.getTransactionItems(txId);
        payload.add({
          'local_id': txId,
          'invoice': tx['invoice'],
          'total': tx['total'],
          'waktu': tx['waktu'],
          'tanggal': tx['tanggal'],
          'metode': tx['metode'],
          'bayar': tx['bayar'],
          'kembali': tx['kembali'],
          'items': items,
          'synced_at': DateTime.now().toIso8601String(),
        });
      }

      final body = jsonEncode({
        'store_id': '5758-001',
        'device': 'android',
        'transactions': payload,
      });

      final resp = await http
          .post(
            Uri.parse(_syncEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        dynamic decoded;
        try {
          decoded = jsonDecode(resp.body);
        } catch (_) {}

        final ackedIds = _extractAckedIds(decoded);
        for (final id in ackedIds) {
          await _db.markTransactionSynced(id);
        }

        if (ackedIds.isEmpty) {
          return 'Server merespons, tetapi belum memberi konfirmasi transaksi yang benar-benar tersimpan. Data tetap diantrikan di lokal.';
        }

        return 'Berhasil sinkronisasi ${ackedIds.length} transaksi ke cloud.';
      } else {
        return 'Server merespons ${resp.statusCode}. Data diantrikan untuk sync berikutnya.';
      }
    } catch (e) {
      debugPrint('Sync error: $e');
      return 'Gagal sinkron (offline atau server error). Data tetap aman di lokal.';
    }
  }

  Future<String> getLastSyncInfo() async {
    // Could be enhanced with a sync_logs table. For now simple.
    final unsynced = await _db.getUnsyncedTransactions();
    if (unsynced.isEmpty) {
      return 'Semua data tersinkron';
    }
    return '${unsynced.length} transaksi menunggu sinkronisasi';
  }
}
