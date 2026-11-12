import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';
import '../services/printer_service.dart';

class StrukScreen extends StatelessWidget {
  final Map<String, dynamic> transactionData;

  const StrukScreen({
    super.key,
    required this.transactionData,
  });

  @override
  Widget build(BuildContext context) {
    // Extract transaction metadata
    final String invoice = transactionData['invoice'] ?? '#5758-XXXXXX';
    final String dateStr = transactionData['tanggal'] ?? 'Hari ini';
    final String timeStr = transactionData['waktu'] ?? '--:--';
    final int total = transactionData['total'] ?? 0;
    final int bayar = transactionData['bayar'] ?? 0;
    final int kembali = transactionData['kembali'] ?? 0;
    final String metode = transactionData['metode'] ?? 'Tunai';
    final List<Map<String, dynamic>> items = List<Map<String, dynamic>>.from(transactionData['items'] ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Struk Digital'),
        leading: IconButton(
          tooltip: 'Kembali ke POS',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Pop back to the MainApp
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppColors.spacing16),
              child: Column(
                children: [
                  const SizedBox(height: AppColors.spacing12),
                  // Success Header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: AppColors.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                            size: 48,
                          ),
                        ),
                        const SizedBox(height: AppColors.spacing12),
                        const Text(
                          'Pembayaran Berhasil',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Transaksi Anda telah selesai diproses',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppColors.spacing24),

                  // Struk Card with Custom Jagged Border Painter
                  CustomPaint(
                    painter: JaggedEdgesPainter(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppColors.spacing24,
                        vertical: AppColors.spacing32,
                      ),
                      color: AppColors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Shop details
                          const Center(
                            child: Column(
                              children: [
                                Text(
                                  'Warung Sejahtera',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Jl. Sudirman No. 45, Jakarta Selatan',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'WA: 0812-3456-7890',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const _DashedDivider(),
                          const SizedBox(height: 12),

                          // Transaction Meta
                          _buildMetaRow('No. Transaksi', invoice, isBold: true),
                          _buildMetaRow('Waktu', '$dateStr, $timeStr'),
                          _buildMetaRow('Kasir', 'Budi Santoso'),
                          const SizedBox(height: 12),
                          const _DashedDivider(),
                          const SizedBox(height: 12),

                          // Item list header
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Item',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary),
                              ),
                              Text(
                                'Total',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // List items
                          ...items.map((item) => Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['nama'],
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            '${item['qty']} x ${formatRupiah(safeInt(item['harga']))}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      formatRupiah(
                                        safeInt(
                                          item['subtotal'],
                                          safeInt(item['qty']) * safeInt(item['harga']),
                                        ),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                          const SizedBox(height: 12),
                          const _DashedDivider(),
                          const SizedBox(height: 12),

                          // Subtotals / Totals
                          _buildMetaRow('Subtotal', formatRupiah(total)),
                          _buildMetaRow('Diskon', 'Rp 0', color: AppColors.danger),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                formatRupiah(total),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const _DashedDivider(),
                          const SizedBox(height: 12),

                          // Payment Details
                          Container(
                            padding: const EdgeInsets.all(AppColors.spacing8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Column(
                              children: [
                                _buildMetaRow('Metode Pembayaran', metode.toUpperCase(), isBold: true),
                                _buildMetaRow('Diterima', formatRupiah(bayar)),
                                _buildMetaRow('Kembalian', formatRupiah(kembali)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Footer note
                          const Center(
                            child: Column(
                              children: [
                                Text(
                                  'Terima kasih telah berbelanja!',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Barang yang sudah dibeli tidak dapat ditukar.',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          // Action Buttons at the bottom
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
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.textSecondary),
                      foregroundColor: AppColors.textMain,
                    ),
                    onPressed: () => _printStruk(context),
                    icon: const Icon(Icons.print),
                    label: const Text('Cetak Struk'),
                  ),
                ),
                const SizedBox(width: AppColors.spacing12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _shareToWhatsApp(context),
                    icon: const Icon(Icons.share),
                    label: const Text('Bagikan Struk'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printStruk(BuildContext context) async {
    final printer = PrinterService();
    await printer.loadSavedPrinter();

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Menghubungkan & mencetak ke printer thermal...')));

    final result = await printer.printReceipt(transactionData);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(result)));
  }

  Future<void> _shareToWhatsApp(BuildContext context) async {
    final invoice = transactionData['invoice'] ?? 'TX-XXXX';
    final total = transactionData['total'] ?? 0;
    final dateStr = transactionData['tanggal'] ?? '';
    final timeStr = transactionData['waktu'] ?? '';
    final items = (transactionData['items'] as List?) ?? [];

    final buffer = StringBuffer();
    buffer.writeln('*Struk Toko5758*');
    buffer.writeln('No: $invoice');
    buffer.writeln('Waktu: $dateStr $timeStr');
    buffer.writeln('');
    for (final it in items) {
      final n = it['nama'];
      final q = it['qty'];
      final h = it['harga'];
      final subtotal = safeInt(it['subtotal'], safeInt(q) * safeInt(h));
      buffer.writeln('- $n x$q = ${formatRupiah(subtotal)}');
    }
    buffer.writeln('');
    buffer.writeln('*Total: ${formatRupiah(total)}*');
    buffer.writeln('Terima kasih telah berbelanja di Toko5758!');

    final text = Uri.encodeComponent(buffer.toString());
    final url = Uri.parse('https://wa.me/?text=$text');

    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak dapat membuka WhatsApp. Pastikan aplikasi terinstall.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membagikan: $e')));
    }
  }

  Widget _buildMetaRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? AppColors.textMain,
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 5.0;
        const dashHeight = 1.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          direction: Axis.horizontal,
          children: List.generate(dashCount, (_) {
            return const SizedBox(
              width: dashWidth,
              height: dashHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(color: AppColors.textSecondary),
              ),
            );
          }),
        );
      },
    );
  }
}

// Custom Painter to draw jagged receipt border style
class JaggedEdgesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    const toothWidth = 12.0;
    const toothHeight = 6.0;

    // Start top left (under the jagged edge)
    path.moveTo(0, toothHeight);

    // Draw top jagged line
    double x = 0;
    bool up = true;
    while (x < size.width) {
      x += toothWidth / 2;
      path.lineTo(x, up ? 0 : toothHeight);
      up = !up;
    }

    // Line to bottom right
    path.lineTo(size.width, size.height - toothHeight);

    // Draw bottom jagged line (going backwards)
    x = size.width;
    up = true;
    while (x > 0) {
      x -= toothWidth / 2;
      path.lineTo(x, up ? size.height : size.height - toothHeight);
      up = !up;
    }

    path.lineTo(0, toothHeight);
    path.close();

    // Shadow
    canvas.drawShadow(path, Colors.black.withOpacity(0.4), 3, true);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
