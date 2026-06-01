import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import 'echa_service.dart';

/// Exporta los reportes a un archivo .xlsx con Sí/No por fuente + detalles.
class ExcelExport {
  /// Genera el Excel y abre un diálogo para guardarlo.
  /// Devuelve la ruta guardada, o null si el usuario cancela.
  static Future<String?> export(
    List<String> casList,
    Map<String, CasReport> reports,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel.getDefaultSheet()!;

    // --- Encabezado ---
    final header = <String>['CAS', 'Name'];
    for (final s in EchaSource.values) {
      header.add(s.shortLabel);
    }
    // Columnas de detalle (Annex XIV / XVII / Candidate).
    header.addAll([
      'Candidate — inclusion date',
      'Candidate — reason',
      'Annex XIV — entry / sunset',
      'Annex XVII — entry / conditions',
    ]);
    excel.appendRow(sheet, header.map((h) => TextCellValue(h)).toList());

    String yn(EchaResult? r) => switch (r?.status) {
          EchaStatus.listed => 'Yes',
          EchaStatus.notListed => 'No',
          EchaStatus.error => 'Error',
          null => '',
        };

    // --- Filas ---
    for (final cas in casList) {
      final rep = reports[cas];
      final row = <String>[cas];

      // Nombre: el primero disponible entre las fuentes con nombre.
      final name = rep?[EchaSource.candidate]?.name ??
          rep?[EchaSource.tsca]?.name ??
          rep?[EchaSource.prop65]?.name ??
          rep?[EchaSource.epaHap]?.name ??
          '';
      row.add(name);

      for (final s in EchaSource.values) {
        row.add(yn(rep?[s]));
      }

      // Detalles.
      final cand = rep?[EchaSource.candidate];
      final xiv = rep?[EchaSource.authLegacy] ?? rep?[EchaSource.authNew];
      final xvii = rep?[EchaSource.restriction];
      row.add(cand?.inclusionDate ?? '');
      row.add(cand?.reason ?? '');
      row.add([
        if (xiv?.entryNumber != null) 'Entry ${xiv!.entryNumber}',
        if (xiv?.sunsetDate != null) 'Sunset ${xiv!.sunsetDate}',
        if (xiv?.latestApplicationDate != null)
          'Latest app ${xiv!.latestApplicationDate}',
      ].join(' · '));
      row.add([
        if (xvii?.entryNumber != null) 'Entry ${xvii!.entryNumber}',
        if (xvii?.reason != null) xvii!.reason!,
      ].join(' · '));

      excel.appendRow(sheet, row.map((c) => TextCellValue(c)).toList());
    }

    final bytes = excel.save();
    if (bytes == null) return null;

    // Diálogo de guardado.
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save results as Excel',
      fileName: 'cas_results.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      bytes: Uint8List.fromList(bytes),
    );
    if (path == null) return null;

    // En desktop, saveFile devuelve la ruta pero no siempre escribe los bytes;
    // garantizamos la escritura.
    final file = File(path);
    if (!await file.exists() || (await file.length()) == 0) {
      await file.writeAsBytes(bytes);
    }
    return path;
  }
}
