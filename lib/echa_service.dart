import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

void _log(String msg) => debugPrint('[ECHA] $msg');

/// Resultado de una consulta a la Candidate List (SVHC) de ECHA.
class EchaResult {
  final String cas;
  final EchaStatus status;

  /// Datos de la fila si fue encontrada en la Candidate List.
  final String? name;
  final String? ecNumber;
  final String? inclusionDate;
  final String? reason;
  final String? decisionNumber;

  /// Mensaje de error (cuando status == error).
  final String? error;

  const EchaResult({
    required this.cas,
    required this.status,
    this.name,
    this.ecNumber,
    this.inclusionDate,
    this.reason,
    this.decisionNumber,
    this.error,
  });
}

enum EchaStatus { listed, notListed, error }

/// Cliente que replica el flujo verificado en test.md:
///   GET página base -> extraer p_auth + formDate + cookies -> POST a la acción.
/// El POST puede devolver HTTP 403 "falso": se parsea el cuerpo igual.
/// No se siguen redirects (equivalente a no usar `curl -L`).
class EchaService {
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  static const _portlet = '_disslists_WAR_disslistsportlet';
  static const _base =
      'https://www.echa.europa.eu/web/guest/candidate-list-table';

  final HttpClient _client = HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 30);

  void close() => _client.close(force: true);

  /// Sesión obtenida de la página base: token CSRF, formDate y cookies.
  /// p_auth y formDate caducan, así que se refresca antes de cada lote.
  Future<_Session> _openSession() async {
    _log('openSession: GET $_base');
    final req = await _client.getUrl(Uri.parse(_base));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    _log('openSession: status=${res.statusCode} bodyLen=${body.length} '
        'setCookies=${res.cookies.length}');

    final cookies = res.cookies;

    final pAuth = RegExp(r'p_auth=([A-Za-z0-9]+)').firstMatch(body)?.group(1);
    // formDate: número de 10+ dígitos asociado a la palabra formDate.
    final formDate =
        RegExp(r'formDate[^0-9]*([0-9]{10,})').firstMatch(body)?.group(1);
    _log('openSession: pAuth=$pAuth formDate=$formDate '
        'cookies=[${cookies.map((c) => c.name).join(",")}]');

    if (pAuth == null || pAuth.isEmpty) {
      _log('openSession: SIN p_auth. body contiene "WAF"=${body.contains("WAF")}');
      throw Exception(
          'No se pudo obtener p_auth de la página base (¿bloqueo/WAF o cambio de portal?).');
    }
    return _Session(pAuth: pAuth, formDate: formDate ?? '', cookies: cookies);
  }

  /// Consulta un único CAS reusando una sesión ya abierta.
  Future<EchaResult> _searchWith(_Session s, String cas) async {
    final actionUri = Uri.parse(
      '$_base?p_p_id=$_portlet&p_p_lifecycle=1&p_p_state=normal'
      '&p_p_mode=view&${_portlet}_javax.portlet.action=searchDissLists'
      '&p_auth=${s.pAuth}',
    );

    final form = <String, String>{
      '${_portlet}_formDate': s.formDate,
      '${_portlet}_substance_identifier_field_key': cas,
      '${_portlet}_deltaParamValue': '50',
      'doSearch': 'true',
    };
    final encoded = form.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final req = await _client.postUrl(actionUri);
    req.followRedirects = false; // no -L: el redirect final cae en 403 real.
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    req.headers.set('Referer', _base);
    req.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.cookies.addAll(s.cookies);
    req.write(encoded);

    _log('search "$cas": POST acción');
    final res = await req.close();
    // El status 403 es engañoso: se parsea el cuerpo de todos modos.
    final body = await res.transform(utf8.decoder).join();
    final hits = RegExp(RegExp.escape(cas)).allMatches(body).length;
    final waf = body.contains('Azure WAF') ||
        body.contains('Web Application Firewall');
    _log('search "$cas": status=${res.statusCode} bodyLen=${body.length} '
        'ocurrenciasCAS=$hits tieneWAF=$waf');

    final result = _parse(cas, body);
    _log('search "$cas": -> ${result.status} name=${result.name}');
    return result;
  }

  /// Parsea el HTML de resultados y busca la fila que contenga el CAS.
  EchaResult _parse(String cas, String html) {
    // Detección de WAF real (no el 403 falso).
    if (html.contains('Azure WAF') || html.contains('Web Application Firewall')) {
      return EchaResult(
        cas: cas,
        status: EchaStatus.error,
        error: 'Bloqueado por WAF (sesión inválida o caducada).',
      );
    }

    final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html);
    for (final row in rows) {
      final cells = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true)
          .allMatches(row.group(1)!)
          .map((c) => _clean(c.group(1)!))
          .where((c) => c.isNotEmpty)
          .toList();

      if (cells.any((c) => c.contains(cas))) {
        // Columnas esperadas (test.md):
        // nombre | EC number | CAS | fecha inclusión | motivo | nº decisión | detalle
        String? at(int i) => i < cells.length ? cells[i] : null;
        return EchaResult(
          cas: cas,
          status: EchaStatus.listed,
          name: at(0),
          ecNumber: at(1),
          inclusionDate: at(3),
          reason: at(4),
          decisionNumber: at(5),
        );
      }
    }

    return EchaResult(cas: cas, status: EchaStatus.notListed);
  }

  /// Quita etiquetas HTML, decodifica entidades y colapsa espacios.
  String _clean(String s) {
    var t = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    t = _unescape(t);
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');

  /// Consulta una lista de CAS uno por uno, reportando progreso.
  /// Abre una sesión nueva al inicio (tokens frescos) y la reusa para el lote.
  /// Si una consulta falla por token caducado, reabre sesión y reintenta una vez.
  Future<void> searchMany(
    List<String> casList, {
    required void Function(int index, EchaResult result) onResult,
  }) async {
    _Session? session;
    for (var i = 0; i < casList.length; i++) {
      final cas = casList[i];
      try {
        session ??= await _openSession();
        var result = await _searchWith(session, cas);

        // Reintento único si el WAF tumbó la sesión.
        if (result.status == EchaStatus.error) {
          session = await _openSession();
          result = await _searchWith(session, cas);
        }
        onResult(i, result);
      } catch (e) {
        // Si falló abriendo sesión, invalidarla para reintentar en el siguiente.
        session = null;
        onResult(
          i,
          EchaResult(cas: cas, status: EchaStatus.error, error: e.toString()),
        );
      }
    }
  }
}

class _Session {
  final String pAuth;
  final String formDate;
  final List<Cookie> cookies;
  _Session({required this.pAuth, required this.formDate, required this.cookies});
}
