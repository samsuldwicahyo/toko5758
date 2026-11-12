# Toko5758

Aplikasi kasir/POS untuk UMKM berbasis Flutter. Aplikasi menyediakan pencatatan transaksi dan stok lokal, pengelolaan kasbon, laporan, serta pencetakan struk Bluetooth.

## Fitur

- Login/registrasi lokal, dashboard, produk, supplier, dan kasir.
- Pemindaian barcode, pembayaran, struk, serta pengurangan stok.
- Kasbon pelanggan, riwayat dan audit aktivitas, serta laporan.
- Ekspor/impor data dan pengaturan toko.
- Integrasi printer thermal Bluetooth melalui plugin lokal di `packages/bluetooth_thermal_printer/`.

## Teknologi dan prasyarat

Flutter/Dart (Dart >=3.5), SQLite/sqflite, mobile_scanner, shared_preferences, fl_chart, serta paket PDF/Excel. Android adalah target utama; Android SDK 36, NDK 27.0.12077973, dan JDK 17 mengikuti konfigurasi build saat ini.

## Menjalankan

```powershell
flutter pub get
flutter run --dart-define=TOKO5758_DEMO_PASSWORD=demo-local-only
```

Akun contoh menggunakan email `demo@example.invalid` dan password sesuai `TOKO5758_DEMO_PASSWORD`. Nilai ini hanya untuk demonstrasi dan seed database baru. Anda juga dapat membuat akun lokal dari layar registrasi. Konfigurasi build tidak mengganti password yang sudah tersimpan pada database lama.

## Pemeriksaan dan build

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Printer harus dipasangkan melalui pengaturan Bluetooth perangkat. Uji barcode, izin kontak/Bluetooth, dan cetak struk pada perangkat Android.

## Sinkronisasi opsional

Sinkronisasi server tidak aktif secara default. Untuk pengembangan, tentukan endpoint milik sendiri melalui `--dart-define=TOKO5758_SYNC_ENDPOINT=https://server-anda.example/sync`. Backend belum disertakan. Respons harus berisi `success: true` dan daftar `synced_ids` agar transaksi ditandai tersimpan. Jangan gunakan endpoint echo publik untuk data transaksi.

## Batas saat ini

Fitur utama memakai penyimpanan lokal. Hash password lokal dan validasi sesi masih berupa implementasi demonstrasi, sehingga perlu ditinjau sebelum penggunaan produksi. Folder platform selain Android masih perlu validasi. Build rilis menggunakan debug signing bila `android/key.properties` tidak tersedia; siapkan keystore sendiri untuk distribusi resmi. Kunci signing, konfigurasi lokal, database pengguna, dan hasil build tidak disertakan.
