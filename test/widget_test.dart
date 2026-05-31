import 'package:flutter_test/flutter_test.dart';

import 'package:echa_svhc/cas_utils.dart';

void main() {
  test('extrae varios CAS de texto pegado', () {
    final cas = CasUtils.extractAll('110-54-3, 50-00-0\n7440-43-9 basura');
    expect(cas, ['110-54-3', '50-00-0', '7440-43-9']);
  });

  test('no duplica CAS repetidos', () {
    final cas = CasUtils.extractAll('110-54-3 110-54-3');
    expect(cas, ['110-54-3']);
  });

  test('valida dígito de control', () {
    expect(CasUtils.isValidChecksum('110-54-3'), isTrue);
    expect(CasUtils.isValidChecksum('110-54-9'), isFalse);
  });
}
