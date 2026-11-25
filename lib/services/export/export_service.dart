import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../data/models/inspection_model.dart';

/// Service Ekspor Data Riwayat Inspeksi (CSV & PDF)
class ExportService {
  /// Ekspor Riwayat Inspeksi ke Berkas CSV Terstruktur
  static Future<String> exportToCsv(List<InspectionModel> inspections) async {
    final List<List<dynamic>> rows = [
      [
        'Inspection Code',
        'Date Time',
        'Board Type',
        'Total Joints',
        'Pass Count',
        'Fail Count',
        'Uncertain Count',
        'Overall Result',
        'Yield Rate (%)',
        'Inference Time (ms)',
        'Joint Index',
        'Joint Result',
        'Defect Code',
        'Defect Name',
        'Confidence',
      ]
    ];

    for (final insp in inspections) {
      if (insp.joints.isEmpty) {
        rows.add([
          insp.inspectionCode,
          insp.inspectedAt,
          insp.boardType,
          insp.totalJoints,
          insp.passCount,
          insp.failCount,
          insp.uncertainCount,
          insp.overallResult,
          insp.passRate.toStringAsFixed(1),
          insp.totalInferenceTimeMs,
          '-',
          '-',
          '-',
          '-',
          '-',
        ]);
      } else {
        for (final joint in insp.joints) {
          rows.add([
            insp.inspectionCode,
            insp.inspectedAt,
            insp.boardType,
            insp.totalJoints,
            insp.passCount,
            insp.failCount,
            insp.uncertainCount,
            insp.overallResult,
            insp.passRate.toStringAsFixed(1),
            insp.totalInferenceTimeMs,
            joint.jointIndex,
            joint.result,
            joint.defectType?.defectCode ?? '-',
            joint.defectType?.defectName ?? '-',
            joint.confidence.toStringAsFixed(3),
          ]);
        }
      }
    }

    final csvBuffer = StringBuffer();
    for (final row in rows) {
      csvBuffer.writeln(row.map((val) => '"${val.toString().replaceAll('"', '""')}"').join(','));
    }
    final csvString = csvBuffer.toString();

    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${appDir.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final filePath = '${exportDir.path}/QC_Solder_Export_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file = File(filePath);
    await file.writeAsString(csvString);

    return filePath;
  }

  /// Ekspor Laporan Formal Sesi Inspeksi ke Format PDF
  static Future<String> exportInspectionToPdf(InspectionModel inspection) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header Laporan
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'LAPORAN HASIL INSPEKSI QC SOLDER',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        'Standar Mutu: Standar Inspeksi Visual Solder Elektronika',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                    pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: inspection.isPass
                          ? PdfColors.green100
                          : (inspection.isFail ? PdfColors.red100 : PdfColors.amber100),
                      border: pw.Border.all(
                        color: inspection.isPass
                            ? PdfColors.green800
                            : (inspection.isFail ? PdfColors.red800 : PdfColors.amber800),
                      ),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      inspection.isPass ? 'LULUS' : (inspection.isFail ? 'REWORK' : 'TINJAU'),
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        color: inspection.isPass
                            ? PdfColors.green900
                            : (inspection.isFail ? PdfColors.red900 : PdfColors.amber900),
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 12),

              // Metadata Grid
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.5),
                  1: const pw.FlexColumnWidth(2.5),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(2.5),
                },
                children: [
                  pw.TableRow(children: [
                    pw.Text('Kode Sesi:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(inspection.inspectionCode, style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Tipe Papan:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(inspection.boardName, style: const pw.TextStyle(fontSize: 10)),
                  ]),
                  pw.TableRow(children: [
                    pw.Text('Waktu Uji:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text(inspection.inspectedAt, style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Latensi AI:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('${inspection.totalInferenceTimeMs} ms', style: const pw.TextStyle(fontSize: 10)),
                  ]),
                  pw.TableRow(children: [
                    pw.Text('Total Titik:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('${inspection.totalJoints} Titik Solder', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Tingkat Kerapian:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                    pw.Text('${inspection.passRate.toStringAsFixed(1)}% Optimal', style: const pw.TextStyle(fontSize: 10)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 18),

              // Tabel Rincian Titik Solder (Joints)
              pw.Text(
                'RINCIAN SAMBUNGAN SOLDER PER TITIK',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),

              pw.TableHelper.fromTextArray(
                headers: ['Titik #', 'Hasil', 'Kode Cacat', 'Deskripsi Mutu', 'Confidence'],
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                data: inspection.joints.map((joint) {
                  final statusTxt = joint.isPass ? 'OPTIMAL' : (joint.isFail ? 'REWORK' : 'TINJAU');
                  return [
                    'Titik ${joint.jointIndex}',
                    statusTxt,
                    joint.defectType?.defectCode ?? (joint.isPass ? 'PASS_NORMAL' : '-'),
                    joint.defectType?.defectName ??
                        (joint.isPass ? 'Optimal (Meniskus Cekung)' : (joint.isFail ? 'Perlu Rework' : 'Perlu Tinjauan')),
                    '${(joint.confidence * 100).toStringAsFixed(1)}%',
                  ];
                }).toList(),
              ),

              pw.Spacer(),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Sistem Otomasi Inspeksi Mutu Solder - Standar Kerapian Industri', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('Verifikasi: Standar Inspeksi Visual Solder', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          );
        },
      ),
    );

    final appDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${appDir.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final filePath = '${exportDir.path}/Laporan_${inspection.inspectionCode}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());

    return filePath;
  }
}
