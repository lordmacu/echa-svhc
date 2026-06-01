// ignore_for_file: avoid_print
// Prueba de humo: consulta las 3 fuentes contra ECHA real.
// uso: dart run tool/smoke.dart
import 'package:echa_svhc/echa_service.dart';

String _tag(EchaResult? r) => switch (r?.status) {
      EchaStatus.listed => 'SI ',
      EchaStatus.notListed => 'no ',
      EchaStatus.error => 'ERR',
      null => ' ? ',
    };

Future<void> main() async {
  final svc = EchaService();
  const cas = [
    '110-54-3', // n-hexano: Candidate sí, Annex XIV no
    '117-81-7', // DEHP: las tres sí
    '7440-43-9', // cadmio: Candidate sí (Annex XIV no)
    '64-17-5', // etanol: ninguna
    '99999-99-5', // inexistente
  ];
  print('CAS         | Cand | XIVnew | XIVleg | detalle');
  await svc.searchAll(cas, onResult: (i, rep) {
    final c = rep[EchaSource.candidate];
    final n = rep[EchaSource.authNew];
    final l = rep[EchaSource.authLegacy];
    final name = c?.name ?? n?.name ?? l?.name ?? '';
    print('${rep.cas.padRight(11)} | ${_tag(c)}  | ${_tag(n)}    '
        '| ${_tag(l)}    | $name');
  });
  svc.close();
}
