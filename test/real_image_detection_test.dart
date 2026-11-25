// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qc_solder/services/ai/solder_localizer_service.dart';

void main() {
  test('REAL IMAGE TEST: Detect Solder Joints on Actual PCB Fixture', () async {
    final file = File('test/fixtures/sample_tht_pcb_pass.jpg');
    expect(file.existsSync(), isTrue, reason: 'Sample PCB fixture must exist');

    final bytes = file.readAsBytesSync();
    final decoded = img.decodeImage(bytes);
    expect(decoded, isNotNull);

    print('Loaded PCB Fixture: ${decoded!.width}x${decoded.height}');

    final detectedBoxes = SolderLocalizerService.detectSolderJoints(decoded);
    print('Auto-Detected Solder Joints on Real PCB Fixture: ${detectedBoxes.length} pads');

    expect(detectedBoxes.length, greaterThanOrEqualTo(5));

    for (int i = 0; i < detectedBoxes.length; i++) {
      final b = detectedBoxes[i];
      expect(b.x, inInclusiveRange(0.0, 1.0));
      expect(b.y, inInclusiveRange(0.0, 1.0));
      print(
        ' - Pad #${i + 1}: x=${b.x.toStringAsFixed(3)}, y=${b.y.toStringAsFixed(3)}, '
        'w=${b.width.toStringAsFixed(3)}, h=${b.height.toStringAsFixed(3)}',
      );
    }
  });
}
