import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import 'cas_utils.dart';

/// Resultado de importar CAS desde un archivo.
class ImportResult {
  final List<String> cas;
  final String fileName;
  const ImportResult({required this.cas, required this.fileName});
}

/// Importa números CAS desde un archivo CSV/TXT o Excel (.xlsx/.xls).
class CasImporter {
  /// Abre el selector de archivos y extrae todos los CAS encontrados.
  /// Devuelve null si el usuario cancela.
  static Future<ImportResult?> pickAndExtract() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx', 'xls'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.single;
    final name = file.name;
    final ext = name.split('.').last.toLowerCase();

    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) {
      return ImportResult(cas: const [], fileName: name);
    }

    final text = switch (ext) {
      'xlsx' || 'xls' => _excelToText(bytes),
      _ => _decodeText(bytes), // csv, txt y cualquier otro: tratar como texto
    };

    return ImportResult(cas: CasUtils.extractAll(text), fileName: name);
  }

  /// Decodifica bytes a texto tolerando UTF-8 inválido (cae a latin1).
  static String _decodeText(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Vuelca todas las celdas de todas las hojas a texto plano,
  /// para luego extraer los CAS con la misma regex.
  static String _excelToText(List<int> bytes) {
    final buffer = StringBuffer();
    final book = Excel.decodeBytes(bytes);
    for (final table in book.tables.values) {
      for (final row in table.rows) {
        for (final cell in row) {
          final v = cell?.value;
          if (v != null) {
            buffer.write(v.toString());
            buffer.write(' ');
          }
        }
        buffer.write('\n');
      }
    }
    return buffer.toString();
  }
}
