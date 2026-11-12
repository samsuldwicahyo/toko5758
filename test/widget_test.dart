import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:toko5758/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('menampilkan layar login saat aplikasi dibuka', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Toko5758'), findsOneWidget);
    expect(find.text('Sistem POS untuk UMKM Indonesia'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
  });
}
