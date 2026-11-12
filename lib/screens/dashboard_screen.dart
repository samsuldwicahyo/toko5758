import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onNavigateToKasir;
  final VoidCallback onNavigateToProduk;

  const DashboardScreen({
    super.key,
    required this.onNavigateToKasir,
    required this.onNavigateToProduk,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DbHelper _dbHelper = DbHelper();
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _todayTransactions = [];
  List<Map<String, dynamic>> _dailySales = [];
  List<Map<String, dynamic>> _lowStock = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  // Reload data when widget dependencies change or tab is visible
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final txData = await _dbHelper.getRecentTransactions(limit: 30);
      final todayData = await _dbHelper.getTransactionsInPeriod(startOfDay, now);
      final daily = await _dbHelper.getDailySalesSummary(days: 7);
      final low = await _dbHelper.getLowStockProducts();
      if (mounted) {
        setState(() {
          _transactions = txData;
          _todayTransactions = todayData;
          _dailySales = daily;
          _lowStock = low;
          _isLoading = false;
        });
        // Keep session alive
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_active', DateTime.now().millisecondsSinceEpoch);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Calculate metrics for today (02 Jun 2026 - simulated)
  int get _todaySalesTotal {
    return _todayTransactions.fold<int>(0, (sum, tx) => sum + safeInt(tx['total']));
  }

  int get _todayTxCount {
    return _todayTransactions.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sinkronisasi ke Cloud',
            icon: const Icon(Icons.sync),
            onPressed: () async {
              setState(() => _isLoading = true);
              final messenger = ScaffoldMessenger.of(context);
              final syncResult = await SyncService().syncNow();
              await _loadDashboardData();
              if (mounted) {
                messenger.showSnackBar(SnackBar(content: Text(syncResult)));
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppColors.spacing16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary card - Brutalist Neo-Brutalist style
                    Container(
                      padding: const EdgeInsets.all(AppColors.spacing16),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.zero,
                        border: Border.all(color: AppColors.primary, width: 2.5),
                        boxShadow: const [AppColors.brutalOffsetShadow],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PENJUALAN HARI INI',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: AppColors.spacing8),
                          Text(
                            formatRupiah(_todaySalesTotal),
                            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: AppColors.spacing8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _InfoChip('Transaksi: $_todayTxCount'),
                              const _InfoChip('Status: Offline-OK'),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing24),

                    // Grafik Penjualan (real data from DB) - matching reference dashboard with grafik
                    const Text(
                      'GRAFIK PENJUALAN 7 HARI TERAKHIR',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing8),
                    Container(
                      height: 200,
                      padding: const EdgeInsets.all(AppColors.spacing12),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.zero,
                        border: Border.all(color: AppColors.primary, width: 2.5),
                        boxShadow: const [AppColors.brutalOffsetShadow],
                      ),
                      child: _buildSalesChart(),
                    ),
                    const SizedBox(height: AppColors.spacing24),

                    // Notifikasi Stok Menipis (Bagian 3)
                    if (_lowStock.isNotEmpty)
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: widget.onNavigateToProduk,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: AppColors.spacing16),
                            padding: const EdgeInsets.all(AppColors.spacing12),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.1),
                              border: Border.all(color: AppColors.danger, width: 2.5),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning, color: AppColors.danger),
                                const SizedBox(width: AppColors.spacing8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_lowStock.length} produk stok menipis (<5). Segera restock!',
                                        style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'Tap untuk buka daftar produk bermasalah.',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppColors.spacing8),
                                const Icon(
                                  Icons.arrow_forward_ios,
                                  color: AppColors.danger,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Quick action button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: widget.onNavigateToKasir,
                        icon: const Icon(Icons.add),
                        label: const Text(
                          'Transaksi Baru',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing24),

                    // Recent transactions heading
                    const Text(
                      'Riwayat Transaksi Terakhir',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing12),

                    // Transactions list - clickable for detail
                    if (_transactions.isEmpty)
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.zero,
                          border: Border.all(color: AppColors.primary, width: 2.5),
                          boxShadow: const [AppColors.brutalOffsetShadow],
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(AppColors.spacing16),
                          child: Center(
                            child: Text(
                              'Belum ada transaksi hari ini',
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      )
                    else
                      for (var tx in _transactions.take(5))
                        GestureDetector(
                          onTap: () => _showTxDetail(tx),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: AppColors.spacing12),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.zero,
                              border: Border.all(color: AppColors.primary, width: 2.5),
                              boxShadow: const [AppColors.brutalOffsetShadow],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppColors.spacing12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tx['items_summary'] ?? 'Transaksi POS',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${tx['waktu']} - ${tx['invoice']}',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppColors.spacing8),
                                  Text(
                                    formatRupiah(safeInt(tx['total'])),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: AppColors.accentYellow,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSalesChart() {
    if (_dailySales.isEmpty) {
      return const Center(
        child: Text('Belum ada data penjualan', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    final barGroups = <BarChartGroupData>[];
    double maxY = 0;

    for (int i = 0; i < _dailySales.length; i++) {
      final total = safeDouble(_dailySales[i]['total']);
      if (total > maxY) maxY = total;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: total,
              color: AppColors.accentYellow,
              width: 18,
              borderRadius: BorderRadius.zero,
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        maxY: maxY * 1.15,
        barGroups: barGroups,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= _dailySales.length) return const SizedBox.shrink();
                final dateStr = _dailySales[idx]['date'].toString();
                final short = dateStr.length >= 5 ? dateStr.substring(dateStr.length - 5) : dateStr;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(short, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: AppColors.primary, width: 1.5),
        ),
        gridData: const FlGridData(show: false),
        alignment: BarChartAlignment.spaceAround,
      ),
    );
  }

  Future<void> _showTxDetail(Map<String, dynamic> tx) async {
    final items = await _dbHelper.getTransactionItems(safeInt(tx['id']));
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Detail ${tx['invoice']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Waktu: ${tx['tanggal']} ${tx['waktu']}'),
              Text('Metode: ${tx['metode_pembayaran'] ?? tx['metode'] ?? '-'}'),
              Text('Total: ${formatRupiah(safeInt(tx['total']))}'),
              Text('Bayar: ${formatRupiah(safeInt(tx['bayar']))} | Kembali: ${formatRupiah(safeInt(tx['kembali']))}'),
              if (tx['total_laba'] != null) Text('Laba: ${formatRupiah(safeInt(tx['total_laba']))}'),
              const SizedBox(height: 8),
              const Text('Item:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...items.map((i) {
                final qty = safeInt(i['qty']);
                final harga = safeInt(i['harga']);
                final subtotal = safeInt(i['subtotal']);
                return Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          i['nama'],
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      Text(
                        '$qty x ${formatRupiah(harga)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRupiah(subtotal),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;

  const _InfoChip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppColors.spacing8,
        vertical: AppColors.spacing4,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
