import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final DbHelper _dbHelper = DbHelper();
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final data = await _dbHelper.getAuditLogs(limit: 200);
      setState(() {
        _logs = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredLogs {
    if (_searchQuery.isEmpty) return _logs;
    final q = _searchQuery.toLowerCase();
    return _logs.where((log) {
      final desc = (log['description'] ?? '').toString().toLowerCase();
      final action = (log['action'] ?? '').toString().toLowerCase();
      return desc.contains(q) || action.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Log Bisnis'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppColors.spacing12),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Cari action atau deskripsi...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.zero),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredLogs.isEmpty
                    ? const Center(child: Text('Tidak ada log'))
                    : ListView.builder(
                        itemCount: _filteredLogs.length,
                        itemBuilder: (context, index) {
                          final log = _filteredLogs[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: AppColors.spacing12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              border: Border.all(color: AppColors.primary, width: 1.5),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: ListTile(
                              title: Text(
                                log['action'] ?? 'ACTION',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(log['description'] ?? ''),
                                  Text(
                                    '${log['timestamp']} | User: ${log['user'] ?? '-'}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                              trailing: Icon(
                                _getActionIcon(log['action']),
                                color: AppColors.primary,
                              ),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: Text(log['action'] ?? ''),
                                    content: SingleChildScrollView(
                                      child: Text(
                                        'Waktu: ${log['timestamp']}\n'
                                        'User: ${log['user']}\n\n'
                                        'Deskripsi:\n${log['description']}\n\n'
                                        'Detail:\n${log['details'] ?? '-'}',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Tutup'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _getActionIcon(String? action) {
    if (action == null) return Icons.history;
    if (action.contains('SALE')) return Icons.shopping_cart;
    if (action.contains('PRODUCT')) return Icons.inventory;
    if (action.contains('SUPPLY')) return Icons.local_shipping;
    if (action.contains('KASBON')) return Icons.account_balance;
    return Icons.history;
  }
}
