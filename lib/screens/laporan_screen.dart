import 'dart:io';

import 'package:excel/excel.dart' hide Border;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../constants/colors.dart';
import '../data/db_helper.dart';

class LaporanScreen extends StatefulWidget {
  const LaporanScreen({super.key});

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  int _selectedTab = 0; // 0: Ringkasan, 1: Transaksi
  String _selectedPeriod = 'Mingguan'; // Harian, Mingguan, Bulanan, Tahunan
  final DbHelper _dbHelper = DbHelper();

  bool _isLoading = true;
  List<Map<String, dynamic>> _chartData = [];
  Map<String, dynamic> _stats = {
    'total_sales': 0,
    'tx_count': 0,
    'items_sold': 0,
  };
  String _lastUpdated = '';
  String? _reportNotice;
  List<Map<String, dynamic>> _filteredTx = [];
  Map<int, List<Map<String, dynamic>>> _transactionItemsById = {};
  List<Map<String, dynamic>> _productBreakdown = [];

  @override
  void initState() {
    super.initState();
    _loadRealData();
  }

  DateTime _startOfSelectedPeriod(DateTime now) {
    switch (_selectedPeriod) {
      case 'Mingguan':
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
      case 'Bulanan':
        return DateTime(now.year, now.month, 1);
      case 'Tahunan':
        return DateTime(now.year, 1, 1);
      case 'Harian':
      default:
        return DateTime(now.year, now.month, now.day);
    }
  }

  String _selectedPeriodLabel() {
    switch (_selectedPeriod) {
      case 'Harian':
        return 'hari ini';
      case 'Mingguan':
        return '7 hari terakhir';
      case 'Bulanan':
        return 'bulan ini';
      case 'Tahunan':
        return 'tahun ini';
      default:
        return _selectedPeriod.toLowerCase();
    }
  }

  String _formatRupiah(int amount) {
    final fmt = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return fmt.format(amount);
  }

  List<Map<String, dynamic>> _fallbackItemsFromSummary(
    Map<String, dynamic> tx,
  ) {
    final summary = (tx['items_summary'] ?? '').toString().trim();
    if (summary.isEmpty) return const [];

    return summary
        .split(',')
        .map((rawPart) {
          final part = rawPart.trim();
          if (part.isEmpty) return null;

          final match = RegExp(r'^(.*?)\s*x\s*(\d+)$', caseSensitive: false)
              .firstMatch(part);
          final qty = match != null ? safeInt(match.group(2), 1) : 1;
          final name = match != null
              ? (match.group(1) ?? '').trim()
              : part.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (name.isEmpty) return null;

          return <String, dynamic>{
            'nama': name,
            'qty': qty,
            'harga': 0,
            'subtotal': 0,
            'fallback': true,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _resolveTransactionItems(
    Map<String, dynamic> tx,
  ) {
    final txId = safeInt(tx['id']);
    final cached = _transactionItemsById[txId];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    return _fallbackItemsFromSummary(tx);
  }

  String _buildItemsPreview(Map<String, dynamic> tx) {
    final items = _resolveTransactionItems(tx);
    if (items.isEmpty) {
      final summary = (tx['items_summary'] ?? '').toString().trim();
      return summary.isEmpty ? 'Detail item belum tersedia.' : summary;
    }

    final preview = items.take(2).map((item) {
      final qty = safeInt(item['qty'], 1);
      final name = (item['nama'] ?? '-').toString();
      return '$name x$qty';
    }).join(', ');

    final remaining = items.length - 2;
    return remaining > 0 ? '$preview, +$remaining item lain' : preview;
  }

  int _countItems(Map<String, dynamic> tx) {
    final items = _resolveTransactionItems(tx);
    return items.fold<int>(0, (sum, item) => sum + safeInt(item['qty'], 1));
  }

  List<Map<String, dynamic>> _buildChartSeries(
    List<Map<String, dynamic>> transactions,
    DateTime start,
    DateTime end,
  ) {
    switch (_selectedPeriod) {
      case 'Harian':
        final totals = List<int>.filled(24, 0);
        for (final tx in transactions) {
          final dt = extractTransactionDate(tx);
          if (dt == null) continue;
          totals[dt.hour] += safeInt(tx['total']);
        }
        return List.generate(24, (hour) {
          final short = hour.toString().padLeft(2, '0');
          return {
            'label': '$short:00',
            'short_label': short,
            'total': totals[hour],
          };
        });
      case 'Tahunan':
        final totals = List<int>.filled(12, 0);
        for (final tx in transactions) {
          final dt = extractTransactionDate(tx);
          if (dt == null) continue;
          totals[dt.month - 1] += safeInt(tx['total']);
        }
        return List.generate(12, (index) {
          final month = DateTime(end.year, index + 1, 1);
          return {
            'label': DateFormat('MMMM yyyy', 'id_ID').format(month),
            'short_label': DateFormat('MMM', 'id_ID').format(month),
            'total': totals[index],
          };
        });
      case 'Bulanan':
      case 'Mingguan':
      default:
        final bucketCount = end.difference(start).inDays + 1;
        final totals = <String, int>{};
        final labels = <String, Map<String, String>>{};

        for (int i = 0; i < bucketCount; i++) {
          final day = start.add(Duration(days: i));
          final key = DateFormat('yyyy-MM-dd').format(day);
          totals[key] = 0;
          labels[key] = {
            'label': DateFormat('dd MMM yyyy', 'id_ID').format(day),
            'short_label': _selectedPeriod == 'Mingguan'
                ? DateFormat('E', 'id_ID').format(day)
                : DateFormat('d', 'id_ID').format(day),
          };
        }

        for (final tx in transactions) {
          final dt = extractTransactionDate(tx);
          if (dt == null) continue;
          final key = DateFormat('yyyy-MM-dd').format(dt);
          if (!totals.containsKey(key)) continue;
          totals[key] = (totals[key] ?? 0) + safeInt(tx['total']);
        }

        return totals.entries.map((entry) {
          final labelMeta = labels[entry.key]!;
          return {
            'label': labelMeta['label'],
            'short_label': labelMeta['short_label'],
            'total': entry.value,
          };
        }).toList();
    }
  }

  Future<void> _loadRealData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final start = _startOfSelectedPeriod(now);
      final filtered = await _dbHelper.getTransactionsInPeriod(start, now);
      var effectiveTransactions = filtered;
      var chartData = _buildChartSeries(filtered, start, now);
      String? notice;

      if (filtered.isEmpty) {
        final recent = await _dbHelper.getRecentTransactions(limit: 30);
        if (recent.isNotEmpty) {
          effectiveTransactions = recent;
          final fallbackSummary = await _dbHelper.getDailySalesSummary(days: 7);
          chartData = fallbackSummary.map((item) {
            final rawDate = item['date']?.toString() ?? '';
            final short = rawDate.length >= 5
                ? rawDate.substring(rawDate.length - 5)
                : rawDate;
            return {
              'label': rawDate,
              'short_label': short,
              'total': safeInt(item['total']),
            };
          }).toList();
          notice =
              'Tidak ada transaksi pada periode ${_selectedPeriodLabel()}. Menampilkan data transaksi terbaru.';
        }
      }

      int totalSales = 0;
      int itemsSold = 0;
      final transactionItemsById = <int, List<Map<String, dynamic>>>{};
      final productBreakdownMap = <String, Map<String, dynamic>>{};
      for (final tx in effectiveTransactions) {
        totalSales += safeInt(tx['total']);
      }

      final transactionsWithIds = effectiveTransactions
          .where((tx) => safeInt(tx['id']) > 0)
          .toList();
      final txIds = transactionsWithIds.map((tx) => safeInt(tx['id'])).toList();

      if (txIds.isNotEmpty) {
        try {
          final itemLists = await Future.wait(
            txIds.map((id) => _dbHelper.getTransactionItems(id)),
          );
          for (int index = 0; index < itemLists.length; index++) {
            final tx = transactionsWithIds[index];
            final txId = txIds[index];
            final dbItems = itemLists[index]
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            final resolvedItems = dbItems.isNotEmpty
                ? dbItems
                : _fallbackItemsFromSummary(tx);

            if (resolvedItems.isNotEmpty) {
              transactionItemsById[txId] = resolvedItems;
            }

            for (final item in resolvedItems) {
              final qty = safeInt(item['qty'], 1);
              final subtotal = safeInt(item['subtotal']);
              final productId = safeInt(item['product_id']);
              final productName = (item['nama'] ?? '-').toString();
              final key = productId > 0
                  ? 'id:$productId'
                  : 'name:${productName.toLowerCase()}';
              final current = productBreakdownMap.putIfAbsent(key, () {
                return {
                  'nama': productName,
                  'qty': 0,
                  'subtotal': 0,
                };
              });
              current['qty'] = safeInt(current['qty']) + qty;
              current['subtotal'] = safeInt(current['subtotal']) + subtotal;
              itemsSold += qty;
            }
          }
        } catch (_) {}
      }

      if (transactionItemsById.isEmpty) {
        for (final tx in effectiveTransactions) {
          final fallbackItems = _fallbackItemsFromSummary(tx);
          final txId = safeInt(tx['id']);
          if (txId > 0 && fallbackItems.isNotEmpty) {
            transactionItemsById[txId] = fallbackItems;
          }
          for (final item in fallbackItems) {
            final qty = safeInt(item['qty'], 1);
            final name = (item['nama'] ?? '-').toString();
            final current = productBreakdownMap.putIfAbsent(
              'name:${name.toLowerCase()}',
              () => {
                'nama': name,
                'qty': 0,
                'subtotal': 0,
              },
            );
            current['qty'] = safeInt(current['qty']) + qty;
            itemsSold += qty;
          }
        }
      }

      final productBreakdown = productBreakdownMap.values.toList()
        ..sort((a, b) {
          final qtyCompare = safeInt(b['qty']).compareTo(safeInt(a['qty']));
          if (qtyCompare != 0) return qtyCompare;
          return safeInt(b['subtotal']).compareTo(safeInt(a['subtotal']));
        });

      final fmt = DateFormat('dd MMM yyyy HH:mm', 'id_ID');

      if (!mounted) return;
      setState(() {
        _filteredTx = effectiveTransactions;
        _chartData = chartData;
        _stats = {
          'total_sales': totalSales,
          'tx_count': effectiveTransactions.length,
          'items_sold': itemsSold,
        };
        _lastUpdated = fmt.format(now);
        _reportNotice = notice;
        _transactionItemsById = transactionItemsById;
        _productBreakdown = productBreakdown;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Gagal memuat laporan: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showTransactionDetail(Map<String, dynamic> tx) async {
    final txId = safeInt(tx['id']);
    var items = _resolveTransactionItems(tx);
    if (items.isEmpty && txId > 0) {
      final dbItems = await _dbHelper.getTransactionItems(txId);
      items = dbItems.map((item) => Map<String, dynamic>.from(item)).toList();
    }
    if (items.isEmpty) {
      items = _fallbackItemsFromSummary(tx);
    }
    if (txId > 0 && items.isNotEmpty) {
      _transactionItemsById[txId] = items;
    }
    final totalItemQty = items.fold<int>(
      0,
      (sum, item) => sum + safeInt(item['qty'], 1),
    );
    final fallbackOnly = items.isNotEmpty &&
        items.every((item) => item['fallback'] == true);
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.76;
        return AlertDialog(
          title: Text('Detail ${tx['invoice']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppColors.spacing12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.primary, width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Waktu: ${tx['tanggal']} ${tx['waktu']}'),
                        const SizedBox(height: 4),
                        Text(
                          'Metode: ${tx['metode_pembayaran'] ?? tx['metode'] ?? '-'}',
                        ),
                        const SizedBox(height: 4),
                        Text('Total item: $totalItemQty'),
                        const SizedBox(height: 4),
                        Text('Total: ${_formatRupiah(safeInt(tx['total']))}'),
                        Text('Bayar: ${_formatRupiah(safeInt(tx['bayar']))}'),
                        Text(
                          'Kembalian: ${_formatRupiah(safeInt(tx['kembali']))}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if ((tx['items_summary'] ?? '').toString().trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Ringkasan: ${(tx['items_summary'] ?? '').toString()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  if (fallbackOnly)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(AppColors.spacing8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.12),
                        border: Border.all(color: AppColors.warning),
                      ),
                      child: const Text(
                        'Detail harga per item belum tersedia untuk transaksi lama. Menampilkan ringkasan item yang tersimpan.',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  const Text(
                    'Item Pesanan',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text(
                              'Item transaksi tidak ditemukan.',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          )
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final qty = safeInt(item['qty'], 1);
                              final harga = safeInt(item['harga']);
                              final subtotal =
                                  safeInt(item['subtotal'], qty * harga);
                              final hasPrice = harga > 0 || subtotal > 0;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding:
                                    const EdgeInsets.all(AppColors.spacing8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  border: Border.all(
                                  color:
                                        AppColors.primary.withOpacity(0.25),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['nama']?.toString() ?? '-',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            hasPrice
                                                ? '$qty x ${_formatRupiah(harga)}'
                                                : 'Qty: $qty',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color:
                                                  AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      hasPrice
                                          ? _formatRupiah(subtotal)
                                          : 'x$qty',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan Penjualan'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang data',
            icon: const Icon(Icons.refresh),
            onPressed: _loadRealData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppColors.spacing8),
                  color: AppColors.surface,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['Harian', 'Mingguan', 'Bulanan', 'Tahunan']
                          .map((period) {
                        final isActive = _selectedPeriod == period;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedPeriod = period);
                              _loadRealData();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    isActive ? AppColors.primary : AppColors.white,
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.zero,
                              ),
                              child: Text(
                                period.toUpperCase(),
                                style: TextStyle(
                                  color: isActive
                                      ? AppColors.white
                                      : AppColors.primary,
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
                ),
                Container(
                  padding: const EdgeInsets.all(AppColors.spacing12),
                  color: AppColors.surface,
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabButton(
                          label: 'Ringkasan',
                          isActive: _selectedTab == 0,
                          onTap: () => setState(() => _selectedTab = 0),
                        ),
                      ),
                      const SizedBox(width: AppColors.spacing12),
                      Expanded(
                        child: _TabButton(
                          label: 'Transaksi',
                          isActive: _selectedTab == 1,
                          onTap: () => setState(() => _selectedTab = 1),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadRealData,
                    child: _selectedTab == 0
                        ? _buildHarianReport(context)
                        : _buildBulananReport(context),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHarianReport(BuildContext context) {
    final totalSales = safeInt(_stats['total_sales']);
    final txCount = safeInt(_stats['tx_count']);
    final itemsSold = safeInt(_stats['items_sold']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppColors.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diperbarui: $_lastUpdated',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          if (_reportNotice != null) ...[
            const SizedBox(height: AppColors.spacing8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppColors.spacing12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                border: Border.all(color: AppColors.warning, width: 1.5),
              ),
              child: Text(
                _reportNotice!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppColors.spacing8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.primary, width: 2.5),
              boxShadow: const [AppColors.brutalOffsetShadow],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppColors.spacing16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GRAFIK TREN PENJUALAN',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Periode: ${_selectedPeriodLabel()}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: _buildBarChart(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppColors.spacing16),
          _StatCard(
            label: 'Total Penjualan',
            value: _formatRupiah(totalSales),
            color: AppColors.primary,
          ),
          const SizedBox(height: AppColors.spacing12),
          _StatCard(
            label: 'Jumlah Transaksi',
            value: txCount.toString(),
            color: AppColors.success,
          ),
          const SizedBox(height: AppColors.spacing12),
          _StatCard(
            label: 'Item Terjual',
            value: itemsSold.toString(),
            color: AppColors.warning,
          ),
          const SizedBox(height: AppColors.spacing16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            padding: const EdgeInsets.all(AppColors.spacing12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'BREAKDOWN METODE PEMBAYARAN',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (_) {
                    final metodeMap = <String, int>{};
                    for (final tx in _filteredTx) {
                      final metode =
                          (tx['metode_pembayaran'] ?? tx['metode'] ?? 'Tunai')
                              .toString();
                      metodeMap[metode] =
                          (metodeMap[metode] ?? 0) + safeInt(tx['total']);
                    }
                    if (metodeMap.isEmpty) {
                      return const Text(
                        'Belum ada transaksi di periode ini.',
                        style: TextStyle(fontSize: 12),
                      );
                    }
                    return Column(
                      children: metodeMap.entries.map((entry) {
                        final pct = totalSales > 0
                            ? ((entry.value / totalSales) * 100).round()
                            : 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: totalSales > 0
                                      ? entry.value / totalSales
                                      : 0,
                                  minHeight: 8,
                                  color: AppColors.accentYellow,
                                  backgroundColor: AppColors.surface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_formatRupiah(entry.value)} ($pct%)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppColors.spacing16),
          _buildProductBreakdownSection(),
          const SizedBox(height: AppColors.spacing16),
          _buildTransactionSection(
            title: 'TRANSAKSI TERBARU',
            limit: 10,
          ),
          const SizedBox(height: AppColors.spacing16),
          Text(
            'Catatan: ringkasan dan detail item transaksi ditarik dari database lokal sesuai periode ${_selectedPeriodLabel()}.',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppColors.spacing16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportReport(isPdf: true),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppColors.spacing8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportReport(isPdf: false),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Export Excel'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductBreakdownSection({int limit = 6}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      padding: const EdgeInsets.all(AppColors.spacing12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'RINGKASAN PRODUK TERJUAL',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 8),
          if (_productBreakdown.isEmpty)
            const Text(
              'Belum ada data item pada periode ini.',
              style: TextStyle(fontSize: 12),
            )
          else
            Column(
              children: _productBreakdown.take(limit).map((product) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          (product['nama'] ?? '-').toString(),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${safeInt(product['qty'])} item',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        safeInt(product['subtotal']) > 0
                            ? _formatRupiah(safeInt(product['subtotal']))
                            : '-',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          if (_productBreakdown.length > limit) ...[
            const SizedBox(height: 6),
            Text(
              'Menampilkan $limit dari ${_productBreakdown.length} produk.',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransactionSection({
    required String title,
    int? limit,
  }) {
    final visibleTransactions = limit == null
        ? _filteredTx
        : _filteredTx.take(limit).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      padding: const EdgeInsets.all(AppColors.spacing8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${_filteredTx.length} data)',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          if (_filteredTx.isEmpty)
            const Text(
              'Tidak ada transaksi pada periode ini.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleTransactions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final tx = visibleTransactions[index];
                final total = safeInt(tx['total']);
                final metode =
                    (tx['metode_pembayaran'] ?? tx['metode'] ?? '-').toString();
                final itemCount = _countItems(tx);
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 0,
                  ),
                  title: Text(
                    '${tx['invoice'] ?? ''} - ${tx['tanggal'] ?? ''} ${tx['waktu'] ?? ''}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Metode: $metode',
                        style: const TextStyle(fontSize: 10),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _buildItemsPreview(tx),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total item: $itemCount',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  trailing: Text(
                    _formatRupiah(total),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onTap: () => _showTransactionDetail(tx),
                );
              },
            ),
          if (limit != null && _filteredTx.length > limit)
            const Text(
              'Buka tab Transaksi untuk melihat seluruh data.',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBulananReport(BuildContext context) {
    final totalSales = safeInt(_stats['total_sales']);
    final txCount = safeInt(_stats['tx_count']);
    final itemsSold = safeInt(_stats['items_sold']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppColors.spacing16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Diperbarui: $_lastUpdated',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          if (_reportNotice != null) ...[
            const SizedBox(height: AppColors.spacing8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppColors.spacing12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                border: Border.all(color: AppColors.warning, width: 1.5),
              ),
              child: Text(
                _reportNotice!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMain,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppColors.spacing8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppColors.primary, width: 2.5),
              boxShadow: const [AppColors.brutalOffsetShadow],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppColors.spacing16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DETAIL TRANSAKSI PER PERIODE',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Periode: ${_selectedPeriodLabel()}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Menampilkan ${_filteredTx.length} transaksi dengan total ${_formatRupiah(totalSales)} dan $itemsSold item terjual.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppColors.spacing16),
          _StatCard(
            label: 'Total Omzet',
            value: _formatRupiah(totalSales),
            color: AppColors.primary,
          ),
          const SizedBox(height: AppColors.spacing12),
          _StatCard(
            label: 'Jumlah Transaksi',
            value: txCount.toString(),
            color: AppColors.success,
          ),
          const SizedBox(height: AppColors.spacing12),
          _StatCard(
            label: 'Item Terjual',
            value: itemsSold.toString(),
            color: AppColors.warning,
          ),
          const SizedBox(height: AppColors.spacing16),
          _buildProductBreakdownSection(limit: 12),
          const SizedBox(height: AppColors.spacing16),
          _buildTransactionSection(
            title: 'SEMUA TRANSAKSI & DETAIL ITEM',
          ),
          const SizedBox(height: AppColors.spacing16),
          Text(
            'Tap transaksi untuk membuka detail item lengkap. Jika transaksi lama belum punya harga per item, aplikasi menampilkan ringkasan item yang tersimpan.',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppColors.spacing16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportReport(isPdf: true),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppColors.spacing8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportReport(isPdf: false),
                  icon: const Icon(Icons.table_chart),
                  label: const Text('Export Excel'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 2,
                    ),
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart({bool isMonthlyView = false}) {
    if (_chartData.isEmpty) {
      return const Center(child: Text('Belum ada data penjualan.'));
    }

    final bars = <BarChartGroupData>[];
    double maxY = 0;

    for (int i = 0; i < _chartData.length; i++) {
      final total = safeDouble(_chartData[i]['total']);
      if (total > maxY) maxY = total;
      bars.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: total,
              color: AppColors.accentYellow,
              width: isMonthlyView ? 14 : 16,
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY * 1.2,
        barGroups: bars,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= _chartData.length) {
                  return const SizedBox.shrink();
                }
                final short =
                    (_chartData[idx]['short_label'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    short,
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
      ),
    );
  }

  Future<void> _exportReport({required bool isPdf}) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getTemporaryDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'Laporan_Toko5758_${_selectedPeriod}_$timestamp';
      final filePath = '${dir.path}/$fileName.${isPdf ? 'pdf' : 'xlsx'}';

      if (isPdf) {
        final pdf = pw.Document();
        pdf.addPage(
          pw.MultiPage(
            build: (pw.Context context) => [
              pw.Header(
                child: pw.Text(
                  'LAPORAN PENJUALAN TOKO5758 - $_selectedPeriod',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text('Tanggal Export: $_lastUpdated'),
              pw.SizedBox(height: 12),
              pw.Text(
                'RINGKASAN',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'Total Omzet: ${formatRupiah(safeInt(_stats['total_sales']))}',
              ),
              pw.Text('Jumlah Transaksi: ${_stats['tx_count']}'),
              pw.SizedBox(height: 12),
              pw.Text(
                'DETAIL TRANSAKSI',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Table.fromTextArray(
                headers: ['Tanggal', 'Invoice', 'Item', 'Total', 'Metode', 'Laba'],
                data: _filteredTx.take(50).map((tx) {
                  return [
                    '${tx['tanggal']} ${tx['waktu']}',
                    tx['invoice'] ?? '',
                    _buildItemsPreview(tx),
                    formatRupiah(safeInt(tx['total'])),
                    (tx['metode_pembayaran'] ?? tx['metode'] ?? '').toString(),
                    formatRupiah(safeInt(tx['total_laba'])),
                  ];
                }).toList(),
              ),
              if (_filteredTx.length > 50)
                pw.Text('... dan ${_filteredTx.length - 50} transaksi lainnya'),
            ],
          ),
        );
        final bytes = await pdf.save();
        final file = File(filePath);
        await file.writeAsBytes(bytes);
      } else {
        final excel = Excel.createExcel();
        final sheet = excel['Laporan'];
        sheet.appendRow([
          TextCellValue('Tanggal'),
          TextCellValue('Invoice'),
          TextCellValue('Item'),
          TextCellValue('Total'),
          TextCellValue('Metode'),
          TextCellValue('Laba'),
        ]);
        for (final tx in _filteredTx) {
          sheet.appendRow([
            TextCellValue(tx['tanggal']?.toString() ?? ''),
            TextCellValue(tx['invoice']?.toString() ?? ''),
            TextCellValue(_buildItemsPreview(tx)),
            IntCellValue(safeInt(tx['total'])),
            TextCellValue(
              (tx['metode_pembayaran'] ?? tx['metode'] ?? '').toString(),
            ),
            IntCellValue(safeInt(tx['total_laba'])),
          ]);
        }
        final bytes = excel.encode();
        if (bytes != null) {
          final file = File(filePath);
          await file.writeAsBytes(bytes);
        }
      }

      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'Laporan Toko5758 $_selectedPeriod',
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Laporan berhasil di-export & dibagikan!')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Gagal export: $e')),
      );
    }
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppColors.spacing12,
          vertical: AppColors.spacing8,
        ),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppColors.radius8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? AppColors.white : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.primary, width: 2.5),
        boxShadow: const [AppColors.brutalOffsetShadow],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppColors.spacing16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: Icon(Icons.trending_up, color: color),
            ),
            const SizedBox(width: AppColors.spacing16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
