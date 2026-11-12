import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';
import '../data/db_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  final _dbHelper = DbHelper();

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt('last_active') ?? 0;
    final currentUserId = prefs.getInt('current_user_id') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (currentUserId > 0 && last > 0 && now - last < 10 * 60 * 1000) {
      // 10 minutes
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/dashboard');
      }
      return;
    }
    if (currentUserId <= 0 && last > 0) {
      await prefs.remove('last_active');
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final identifier = _emailController.text.trim();
    final password = _passwordController.text;

    if (identifier.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email/No. HP dan password wajib diisi')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = await _dbHelper.login(identifier, password);
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(
            'last_active', DateTime.now().millisecondsSinceEpoch);
        await prefs.setInt('current_user_id', safeInt(user['id']));
        await _dbHelper.insertAuditLog({
          'user': identifier,
          'action': 'LOGIN',
          'description': 'User login berhasil: $identifier',
        });
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/dashboard');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Login gagal. Periksa Email/No.HP/Username dan password.\nAkun demo dapat dikonfigurasi saat build; lihat README.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppColors.spacing16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: AppColors.spacing32),
              // Logo/Title - brutalist
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  border: Border.all(color: AppColors.primary, width: 3),
                  borderRadius: BorderRadius.zero,
                  boxShadow: const [AppColors.brutalOffsetShadow],
                ),
                child: const Icon(
                  Icons.store,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppColors.spacing24),
              Text(
                'Toko5758',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: AppColors.spacing8),
              Text(
                'Sistem POS untuk UMKM Indonesia',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppColors.spacing32),
              // Brutalist login form container
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
                    // Email field
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email / No. HP / Username',
                        hintText: 'admin@5758.local atau 081234567890',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: AppColors.spacing16),
                    // Password field
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing8),
                    // Forgot password link
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Demo: gunakan password "123456" untuk akun admin@5758.local')),
                          );
                        },
                        child: const Text('Lupa password?'),
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing24),
                    // Login button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text(
                                'Masuk',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                      ),
                    ),
                    const SizedBox(height: AppColors.spacing16),
                  ],
                ),
              ),
              // Register link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Belum punya akun? '),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushNamed('/register');
                    },
                    child: const Text(
                      'Daftar di sini',
                      style: TextStyle(
                        color: AppColors.accentBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
