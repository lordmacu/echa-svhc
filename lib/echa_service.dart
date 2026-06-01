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
  Future<EchaResult> _searchWith(_Session s, String cas, EchaQuery q) async {
    final actionUri = Uri.parse(
      '$_base?p_p_id=$_portlet&p_p_lifecycle=1&p_p_state=normal'
      '&p_p_mode=view&${_portlet}_javax.portlet.action=searchDissLists'
      '&p_auth=${s.pAuth}',
    );

    final form = <String, String>{
      '${_portlet}_formDate': s.formDate,
      '${_portlet}_substance_identifier_field_key': cas,
      // Filtros opcionales (vacío = sin filtro, como en la página real).
      '${_portlet}_haz_detailed_concern': q.reason ?? '',
      '${_portlet}_dte_inclusionFrom': q.inclusionFrom ?? '',
      '${_portlet}_dte_inclusionTo': q.inclusionTo ?? '',
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

    final result = _parse(cas, body, res.statusCode, q);
    _log('search "$cas": -> ${result.status} name=${result.name}');
    return result;
  }

  /// Parsea el HTML de resultados y busca la fila que contenga el CAS.
  /// El servidor ignora los filtros cuando se busca por CAS, así que se
  /// aplican aquí del lado del cliente sobre la fila encontrada.
  EchaResult _parse(String cas, String html, int statusCode, EchaQuery q) {
    // Detección de WAF real (no el 403 falso).
    if (html.contains('Azure WAF') || html.contains('Web Application Firewall')) {
      return EchaResult(
        cas: cas,
        status: EchaStatus.error,
        error: 'Bloqueado por WAF (sesión inválida o caducada).',
      );
    }

    // Respuesta inválida (502/503 gateway, página de error, body truncado…):
    // NO debe reportarse como "no está en la lista" (sería un falso negativo).
    // Una página de resultados legítima siempre incluye el formulario del portlet.
    final isResultsPage =
        html.contains('substance_identifier_field_key') && html.length > 50000;
    if (statusCode >= 500 || !isResultsPage) {
      return EchaResult(
        cas: cas,
        status: EchaStatus.error,
        error: 'Respuesta inválida del servidor (HTTP $statusCode, '
            '${html.length} bytes). Reintentar.',
      );
    }

    final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html);
    for (final row in rows) {
      final cells = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true)
          .allMatches(row.group(1)!)
          .map((c) => _clean(c.group(1)!))
          .where((c) => c.isNotEmpty)
          .toList();

      if (cells.any((c) => _cellHasCas(c, cas))) {
        // Columnas esperadas (test.md):
        // nombre | EC number | CAS | fecha inclusión | motivo | nº decisión | detalle
        String? at(int i) => i < cells.length ? cells[i] : null;
        final result = EchaResult(
          cas: cas,
          status: EchaStatus.listed,
          name: at(0),
          ecNumber: at(1),
          inclusionDate: at(3),
          reason: at(4),
          decisionNumber: at(5),
        );

        // Filtrado del lado del cliente (el servidor lo ignora por CAS).
        if (!_passesFilter(result, q)) {
          _log('search "$cas": fila encontrada pero excluida por filtros');
          return EchaResult(cas: cas, status: EchaStatus.notListed);
        }
        return result;
      }
    }

    return EchaResult(cas: cas, status: EchaStatus.notListed);
  }

  /// Comprueba si la fila encontrada cumple los filtros de reason y fecha.
  bool _passesFilter(EchaResult r, EchaQuery q) {
    if (q.isEmpty) return true;

    // Reason: comparación por contención (la celda puede traer texto extra).
    if (q.reason != null && q.reason!.isNotEmpty) {
      final rowReason = r.reason ?? '';
      if (!rowReason.contains(q.reason!)) return false;
    }

    // Fecha de inclusión: parsear "dd-MMM-yyyy" y comparar con el rango.
    final date = _parseInclusionDate(r.inclusionDate);
    if (q.inclusionFrom != null && q.inclusionFrom!.isNotEmpty) {
      final from = DateTime.tryParse(q.inclusionFrom!);
      if (from != null && (date == null || date.isBefore(from))) return false;
    }
    if (q.inclusionTo != null && q.inclusionTo!.isNotEmpty) {
      final to = DateTime.tryParse(q.inclusionTo!);
      if (to != null && (date == null || date.isAfter(to))) return false;
    }
    return true;
  }

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  /// Convierte "04-Feb-2026" a DateTime. null si no parsea.
  DateTime? _parseInclusionDate(String? s) {
    if (s == null) return null;
    final m = RegExp(r'(\d{1,2})-([A-Za-z]{3})-(\d{4})').firstMatch(s);
    if (m == null) return null;
    final day = int.tryParse(m.group(1)!);
    final month = _months[m.group(2)!.toLowerCase()];
    final year = int.tryParse(m.group(3)!);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
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
  /// Abre una sesión nueva al inicio (tokens frescos) y la reusa para el lote.
  /// Si una consulta falla por token caducado, reabre sesión y reintenta una vez.
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
  final String pAuth;
  final String formDate;
  final List<Cookie> cookies;
  _Session({required this.pAuth, required this.formDate, required this.cookies});
}
