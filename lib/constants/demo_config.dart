/// Konfigurasi contoh publik; jangan gunakan untuk data usaha nyata.
class DemoConfig {
  static const email = 'demo@example.invalid';
  static const phone = '0000000000';
  static const password = String.fromEnvironment(
    'TOKO5758_DEMO_PASSWORD',
    defaultValue: 'demo-local-only',
  );
}
