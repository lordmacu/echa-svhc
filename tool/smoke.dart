// Prueba de humo: llama al servicio real contra ECHA.
// uso: dart run tool/smoke.dart
// ignore_for_file: avoid_print
import 'package:echa_svhc/echa_service.dart';

Future<void> main() async {
  final svc = EchaService();
  final cas = ['110-54-3', '50-00-0', '99999-99-5'];
  await svc.searchMany(cas, onResult: (i, r) {
    final tag = switch (r.status) {
      EchaStatus.listed => 'EN LISTA',
      EchaStatus.notListed => 'NO',
      EchaStatus.error => 'ERROR',
    };
    print('[$tag] ${r.cas}'
        '${r.name != null ? " | ${r.name}" : ""}'
        '${r.inclusionDate != null ? " | ${r.inclusionDate}" : ""}'
        '${r.reason != null ? " | ${r.reason}" : ""}'
        '${r.error != null ? " | ${r.error}" : ""}');
  });
  svc.close();
}
