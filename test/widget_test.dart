import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qc_solder/main.dart';

void main() {
  testWidgets('SolderLab App boots up to splash screen smoke test', (WidgetTester tester) async {
    // Build our app wrapped in ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: SolderLabApp(),
      ),
    );
    // Verifikasi tampilan awal splash screen SolderLab
    expect(find.text('SolderLab'), findsOneWidget);

    // Jalankan timer hingga inisialisasi selesai
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
  });
}
