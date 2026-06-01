import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

void _log(String msg) => dev.log(msg, name: 'ECHA');

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

/// Filtros opcionales del buscador (equivalen a los de la página de ECHA).
class EchaQuery {
  /// Motivo de inclusión (Art. 57). null/'' = "- All -".
  final String? reason;

  /// Rango de fecha de inclusión en formato yyyy-MM-dd. null = sin límite.
  final String? inclusionFrom;
  final String? inclusionTo;

  const EchaQuery({this.reason, this.inclusionFrom, this.inclusionTo});

  bool get isEmpty =>
      (reason == null || reason!.isEmpty) &&
      (inclusionFrom == null || inclusionFrom!.isEmpty) &&
      (inclusionTo == null || inclusionTo!.isEmpty);

  static const empty = EchaQuery();
}

/// Opciones del filtro "Reason for inclusion" (extraídas del formulario real).
/// La cadena vacía representa "- All -".
const echaReasons = <String>[
  '', // - All -
  'Carcinogenic (Article 57a)',
  'Mutagenic (Article 57b)',
  'Toxic for reproduction (Article 57c)',
  'PBT (Article 57d)',
  'vPvB (Article 57e)',
  'Endocrine disrupting properties (Article 57(f) - environment)',
  'Endocrine disrupting properties (Article 57(f) - human health)',
  'Equivalent level of concern having probable serious effects to human health (Article 57(f) - human health)',
  'Equivalent level of concern having probable serious effects to the environment (Article 57(f) - environment)',
  'Respiratory sensitising properties (Article 57(f) - human health)',
  'Specific target organ toxicity after repeated exposure (Article 57(f) - human health)',
];

/// Cliente del buscador de la Candidate List (SVHC) de ECHA.
///
/// Método (ver test.md): el portlet Liferay NO filtra por la acción POST
/// (`p_p_lifecycle=1`, que devuelve siempre las 50 más recientes), sino por
/// un **render GET** (`p_p_lifecycle=0`) con los criterios como parámetros
/// *namespaced* + `_doSearch=true`. El número de coincidencias se lee del
/// campo oculto `_total`. Solo se necesitan las cookies de sesión (no p_auth).
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

  /// Sesión: solo cookies de la página base (el render GET no usa p_auth).
  Future<_Session> _openSession() async {
    _log('openSession: GET $_base');
    final req = await _client.getUrl(Uri.parse(_base));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    _log('openSession: status=${res.statusCode} bodyLen=${body.length} '
        'setCookies=${res.cookies.length}');

    if (body.contains('Azure WAF') ||
        body.contains('Web Application Firewall')) {
      throw Exception('Bloqueado por WAF al abrir sesión.');
    }
    if (res.cookies.isEmpty && body.length < 50000) {
      throw Exception('No se pudo abrir sesión con ECHA (respuesta inválida).');
    }
    return _Session(cookies: res.cookies);
  }

  /// Consulta un único CAS vía render GET (filtra server-side de verdad).
  Future<EchaResult> _searchWith(_Session s, String cas, EchaQuery q) async {
    // Parámetros namespaced del render (p_p_lifecycle=0) + _doSearch=true.
    final params = <String, String>{
      'p_p_id': 'disslists_WAR_disslistsportlet',
      'p_p_lifecycle': '0',
      'p_p_state': 'normal',
      'p_p_mode': 'view',
      '${_portlet}_substance_identifier_field_key': cas,
      '${_portlet}_haz_detailed_concern': q.reason ?? '',
      '${_portlet}_dte_inclusionFrom': _toEchaDate(q.inclusionFrom),
      '${_portlet}_dte_inclusionTo': _toEchaDate(q.inclusionTo),
      '${_portlet}_orderByCol': 'dte_inclusion',
      '${_portlet}_orderByType': 'desc',
      '${_portlet}_doSearch': 'true',
      '${_portlet}_deltaParamValue': '50',
      '${_portlet}_resetCur': 'false',
      '${_portlet}_delta': '50',
      '${_portlet}_cur': '1',
    };
    final uri = Uri.parse(_base).replace(queryParameters: params);

    final req = await _client.getUrl(uri);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    req.headers.set('Referer', _base);
    req.cookies.addAll(s.cookies);

    _log('search "$cas": render GET (reason=${q.reason}, '
        'from=${q.inclusionFrom}, to=${q.inclusionTo})');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    _log('search "$cas": status=${res.statusCode} bodyLen=${body.length}');

    final result = _parse(cas, body, res.statusCode);
    _log('search "$cas": -> ${result.status} name=${result.name}');
    return result;
  }

  /// Parsea la página de resultados. El número de coincidencias está en el
  /// campo oculto `_total`; la(s) fila(s) traen los detalles.
  EchaResult _parse(String cas, String html, int statusCode) {
    if (html.contains('Azure WAF') ||
        html.contains('Web Application Firewall')) {
      return EchaResult(
        cas: cas,
        status: EchaStatus.error,
        error: 'Bloqueado por WAF (sesión inválida o caducada).',
      );
    }

    // Respuesta inválida (502/503, body truncado, sin el campo _total):
    // no reportar como "no está" (sería un falso negativo).
    final totalMatch =
        RegExp('${_portlet}_total"[^>]*value="(\\d+)"').firstMatch(html);
    if (statusCode >= 500 || totalMatch == null) {
      return EchaResult(
        cas: cas,
        status: EchaStatus.error,
        error: 'Respuesta inválida del servidor (HTTP $statusCode, '
            '${html.length} bytes). Reintentar.',
      );
    }

    final total = int.parse(totalMatch.group(1)!);
    if (total == 0) {
      return EchaResult(cas: cas, status: EchaStatus.notListed);
    }

    // Hay coincidencias: buscar la fila de datos que contenga el CAS exacto.
    final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html);
    for (final row in rows) {
      if (!row.group(1)!.contains('View Details')) continue;
      final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
          .allMatches(row.group(1)!)
          .map((c) => _clean(c.group(1)!))
          .where((c) => c.isNotEmpty)
          .toList();

      if (cells.any((c) => _cellHasCas(c, cas))) {
        // nombre | EC number | CAS | fecha inclusión | motivo | nº decisión | …
        String? at(int i) => i < cells.length ? cells[i] : null;
        return EchaResult(
          cas: cas,
          status: EchaStatus.listed,
          name: _cleanName(at(0)),
          ecNumber: at(1),
          inclusionDate: at(3),
          reason: at(4),
          decisionNumber: at(5),
        );
      }
    }

    // total>0 pero el CAS exacto no aparece en una fila: probablemente una
    // coincidencia difusa (p. ej. CAS inválido). Tratar como no listado.
    return EchaResult(cas: cas, status: EchaStatus.notListed);
  }

  /// Convierte "yyyy-MM-dd" (o null) al formato "dd-MMM-yyyy" que usa ECHA.
  String _toEchaDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd-${names[d.month - 1]}-${d.year}';
  }

  /// Limpia el nombre quitando los sufijos "EC number: …"/"CAS number: …"
  /// que el layout responsive de ECHA inyecta dentro de la primera celda.
  String? _cleanName(String? raw) {
    if (raw == null) return null;
    var n = raw;
    final cut = RegExp(r'\s*(EC number|CAS number)\s*:', caseSensitive: false)
        .firstMatch(n);
    if (cut != null) n = n.substring(0, cut.start);
    return n.trim();
  }

  /// True si la celda contiene el CAS como número completo (no como subcadena
  /// de otro CAS). Ej: "7440-43-9" no debe coincidir dentro de "17440-43-9".
  bool _cellHasCas(String cell, String cas) {
    final re = RegExp(r'(?<![\d-])' + RegExp.escape(cas) + r'(?![\d-])');
    return re.hasMatch(cell);
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
  /// Abre una sesión (cookies) al inicio y la reusa para el lote.
  /// Si una consulta falla, reabre sesión y reintenta una vez.
  Future<void> searchMany(
    List<String> casList, {
    EchaQuery query = EchaQuery.empty,
    required void Function(int index, EchaResult result) onResult,
  }) async {
    _Session? session;
    for (var i = 0; i < casList.length; i++) {
      final cas = casList[i];
      try {
        session ??= await _openSession();
        var result = await _searchWith(session, cas, query);

        // Reintento con sesión fresca si hubo WAF o respuesta inválida
        // (502/503, body truncado): así un fallo transitorio no se reporta
        // como "no está en la lista".
        if (result.status == EchaStatus.error) {
          session = await _openSession();
          result = await _searchWith(session, cas, query);
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

      // Pausa de cortesía entre consultas para no disparar el WAF/throttling.
      if (i < casList.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }
}

class _Session {
  final List<Cookie> cookies;
  _Session({required this.cookies});
}
