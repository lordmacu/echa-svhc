// ignore_for_file: avoid_print
// Prueba de humo: llama al servicio real contra ECHA.
// uso: dart run tool/smoke.dart
import 'package:echa_svhc/echa_service.dart';

Future<void> _run(String title, List<String> cas, EchaQuery q) async {
  print('\n=== $title ===');
  final svc = EchaService();
  await svc.searchMany(cas, query: q, onResult: (i, r) {
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

Future<void> main() async {
  // Regresión del bug del top-50: CAS listados que NO son los más recientes
  // (antes daban falso "NO"); y no-listados que deben dar NO.
  await _run('listados (no recientes) + no listados', [
    '110-54-3', // n-hexano (listado, reciente)
    '117-81-7', // DEHP (listado, antiguo)
    '7440-43-9', // cadmio (listado, antiguo)
    '50-00-0', // formaldehído (NO listado)
    '64-17-5', // etanol (NO listado)
    '99999-99-5', // inexistente
  ], EchaQuery.empty);
  // Filtro reason que SÍ aplica a n-hexano (STOT 57f).
  await _run('reason=STOT(57f)', ['110-54-3'],
      const EchaQuery(reason:
          'Specific target organ toxicity after repeated exposure (Article 57(f) - human health)'));
  // Filtro reason que NO aplica a n-hexano -> debe quedar NO.
  await _run('reason=Carcinogenic (no aplica a n-hexano)', ['110-54-3'],
      const EchaQuery(reason: 'Carcinogenic (Article 57a)'));
  // Rango de fecha que excluye (inclusión 04-Feb-2026, from posterior) -> NO.
  await _run('from=2026-03-01 (posterior) -> excluye', ['110-54-3'],
      const EchaQuery(inclusionFrom: '2026-03-01'));
  // Rango de fecha que incluye -> EN LISTA.
  await _run('from=2026-01-01 to=2026-12-31 -> incluye', ['110-54-3'],
      const EchaQuery(inclusionFrom: '2026-01-01', inclusionTo: '2026-12-31'));
}
