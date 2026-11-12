import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _namaTokoController = TextEditingController();
  final _nomorHpController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  final _dbHelper = DbHelper();

  @override
  void dispose() {
    _namaTokoController.dispose();
    _nomorHpController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final nama = _namaTokoController.text.trim();
    final phone = _nomorHpController.text.trim();
    final pass = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (nama.isEmpty || phone.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua field wajib diisi')),
      );
      return;
    }
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password minimal 6 karakter')),
      );
      return;
    }
    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konfirmasi password tidak cocok')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Use phone as primary login key, create a pseudo email for compatibility with login
      final email = '${phone.replaceAll(RegExp(r'[^0-9]'), '')}@toko.local';
      final id = await _dbHelper.insertUser({
        'email': email,
        'phone': phone,
        'password': pass,
        'nama_toko': nama,
      });

      if (id > 0 && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registrasi berhasil! Silakan login dengan nomor HP atau email yang dibuat.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal daftar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Toko'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppColors.spacing16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buat Akun Toko5758',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: AppColors.spacing8),
              Text(
                'Isi data di bawah untuk membuat akun baru',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppColors.spacing32),
              // Brutalist register form
              Container(
                padding: const EdgeInsets.all(AppColors.spacing16),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: AppColors.primary, width: 2.5),
                  boxShadow: const [AppColors.brutalOffsetShadow],
                ),
                child: Column(
                  children: [
                    // Nama Toko
                    TextField(
                controller: _namaTokoController,
                decoration: const InputDecoration(
                  labelText: 'Nama Toko',
                  hintText: 'Contoh: Toko Kami',
                  prefixIcon: Icon(Icons.store),
                ),
              ),
              const SizedBox(height: AppColors.spacing16),
              // Nomor HP
              TextField(
                controller: _nomorHpController,
                decoration: const InputDecoration(
                  labelText: 'Nomor HP',
                  hintText: '0812 3456 7890',
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppColors.spacing16),
              // Password
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppColors.spacing16),
              // Confirm Password
              TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Konfirmasi Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirm = !_obscureConfirm;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppColors.spacing24),
              // Register button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text(
                          'Daftar',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(height: AppColors.spacing16),
                  ],
                ),
              ),
              // Back to login
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Kembali ke login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
