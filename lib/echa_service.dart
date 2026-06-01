import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

void _log(String msg) => dev.log(msg, name: 'ECHA');

/// Las tres fuentes que se consultan por cada CAS.
enum EchaSource {
  /// Candidate List (SVHC) — portal legado, portlet Liferay.
  candidate,

  /// Authorisation List (REACH Annex XIV) — API JSON de ECHA CHEM (nuevo).
  authNew,

  /// Authorisation List (REACH Annex XIV) — portal legado, portlet Liferay.
  authLegacy,
}

extension EchaSourceInfo on EchaSource {
  String get label => switch (this) {
        EchaSource.candidate => 'Candidate List (SVHC)',
        EchaSource.authNew => 'Annex XIV (ECHA CHEM)',
        EchaSource.authLegacy => 'Annex XIV (legado)',
      };

  String get shortLabel => switch (this) {
        EchaSource.candidate => 'Candidate',
        EchaSource.authNew => 'Annex XIV (nuevo)',
        EchaSource.authLegacy => 'Annex XIV (legado)',
      };
}

enum EchaStatus { listed, notListed, error }

/// Resultado de una consulta a UNA fuente para un CAS.
class EchaResult {
  final EchaSource source;
  final String cas;
  final EchaStatus status;

  // Identidad / detalles (los que aplican según la fuente).
  final String? name;
  final String? ecNumber;

  // Candidate List:
  final String? inclusionDate;
  final String? reason;
  final String? decisionNumber;

  // Authorisation List (Annex XIV):
  final String? entryNumber;
  final String? latestApplicationDate;
  final String? sunsetDate;

  final String? error;

  const EchaResult({
    required this.source,
    required this.cas,
    required this.status,
    this.name,
    this.ecNumber,
    this.inclusionDate,
    this.reason,
    this.decisionNumber,
    this.entryNumber,
    this.latestApplicationDate,
    this.sunsetDate,
    this.error,
  });

  EchaResult._status(this.source, this.cas, this.status, {this.error})
      : name = null,
        ecNumber = null,
        inclusionDate = null,
        reason = null,
        decisionNumber = null,
        entryNumber = null,
        latestApplicationDate = null,
        sunsetDate = null;
}

/// Reporte de un CAS contra las tres fuentes.
class CasReport {
  final String cas;
  final Map<EchaSource, EchaResult> bySource;
  const CasReport(this.cas, this.bySource);

  EchaResult? operator [](EchaSource s) => bySource[s];
}

/// Filtros opcionales (solo aplican a la Candidate List, como en la web).
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

/// Opciones del filtro "Reason for inclusion" (Candidate List).
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

/// Cliente que consulta un CAS contra las tres fuentes de ECHA:
///
/// 1. **Candidate List (SVHC)** y 3. **Annex XIV legado**: portal Liferay.
///    El portlet NO filtra por la acción POST (devuelve siempre las 50 más
///    recientes); el filtrado real es un **render GET** (`p_p_lifecycle=0`)
///    con criterios *namespaced* + `_doSearch=true`. La verdad está en el
///    campo oculto `_total` (0 = no listado). Solo requiere cookies.
/// 2. **Annex XIV nuevo (ECHA CHEM)**: API JSON
///    `api-obligation-list/v1/authorisationList?searchText=<cas>` (sin sesión).
class EchaService {
  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36';

  static const _portlet = '_disslists_WAR_disslistsportlet';
  static const _candidateBase =
      'https://www.echa.europa.eu/web/guest/candidate-list-table';
  static const _authLegacyBase =
      'https://www.echa.europa.eu/web/guest/authorisation-list';
  static const _authApi =
      'https://chem.echa.europa.eu/api-obligation-list/v1/authorisationList';

  final HttpClient _client = HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 30);

  void close() => _client.close(force: true);

  // ---------------------------------------------------------------------------
  // Sesión del portlet (cookies). Se reusa por base URL.
  // ---------------------------------------------------------------------------
  Future<List<Cookie>> _openSession(String baseUrl) async {
    _log('openSession: GET $baseUrl');
    final req = await _client.getUrl(Uri.parse(baseUrl));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    _log('openSession: status=${res.statusCode} bodyLen=${body.length} '
        'cookies=${res.cookies.length}');

    if (body.contains('Azure WAF') ||
        body.contains('Web Application Firewall')) {
      throw Exception('Bloqueado por WAF al abrir sesión.');
    }
    if (res.cookies.isEmpty && body.length < 50000) {
      throw Exception('No se pudo abrir sesión con ECHA (respuesta inválida).');
    }
    return res.cookies;
  }

  // ---------------------------------------------------------------------------
  // Portlet (Candidate List y Annex XIV legado) — render GET.
  // ---------------------------------------------------------------------------
  Future<EchaResult> _searchPortlet(
    List<Cookie> cookies,
    String baseUrl,
    EchaSource source,
    String cas,
    EchaQuery q,
  ) async {
    // Los filtros reason/fecha solo existen en la Candidate List.
    final isCandidate = source == EchaSource.candidate;
    final params = <String, String>{
      'p_p_id': 'disslists_WAR_disslistsportlet',
      'p_p_lifecycle': '0',
      'p_p_state': 'normal',
      'p_p_mode': 'view',
      '${_portlet}_substance_identifier_field_key': cas,
      if (isCandidate) ...{
        '${_portlet}_haz_detailed_concern': q.reason ?? '',
        '${_portlet}_dte_inclusionFrom': _toEchaDate(q.inclusionFrom),
        '${_portlet}_dte_inclusionTo': _toEchaDate(q.inclusionTo),
      },
      '${_portlet}_orderByCol': 'dte_inclusion',
      '${_portlet}_orderByType': 'desc',
      '${_portlet}_doSearch': 'true',
      '${_portlet}_deltaParamValue': '50',
      '${_portlet}_resetCur': 'false',
      '${_portlet}_delta': '50',
      '${_portlet}_cur': '1',
    };
    final uri = Uri.parse(baseUrl).replace(queryParameters: params);

    final req = await _client.getUrl(uri);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    req.headers.set('Referer', baseUrl);
    req.cookies.addAll(cookies);

    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    _log('portlet ${source.name} "$cas": status=${res.statusCode} '
        'bodyLen=${body.length}');

    return _parsePortlet(source, cas, body, res.statusCode);
  }

  EchaResult _parsePortlet(
      EchaSource source, String cas, String html, int statusCode) {
    if (html.contains('Azure WAF') ||
        html.contains('Web Application Firewall')) {
      return EchaResult._status(source, cas, EchaStatus.error,
          error: 'Bloqueado por WAF.');
    }

    final totalMatch =
        RegExp('${_portlet}_total"[^>]*value="(\\d+)"').firstMatch(html);
    if (statusCode >= 500 || totalMatch == null) {
      return EchaResult._status(source, cas, EchaStatus.error,
          error: 'Respuesta inválida (HTTP $statusCode, ${html.length} B).');
    }

    if (int.parse(totalMatch.group(1)!) == 0) {
      return EchaResult._status(source, cas, EchaStatus.notListed);
    }

    final rows = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html);
    for (final row in rows) {
      if (!row.group(1)!.contains('View Details')) continue;
      final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
          .allMatches(row.group(1)!)
          .map((c) => _clean(c.group(1)!))
          .where((c) => c.isNotEmpty)
          .toList();
      if (!cells.any((c) => _cellHasCas(c, cas))) continue;

      String? at(int i) => i < cells.length ? cells[i] : null;
      if (source == EchaSource.candidate) {
        // name | EC | CAS | inclusión | reason | decisión | …
        return EchaResult(
          source: source,
          cas: cas,
          status: EchaStatus.listed,
          name: _cleanName(at(0)),
          ecNumber: at(1),
          inclusionDate: at(3),
          reason: at(4),
          decisionNumber: at(5),
        );
      } else {
        // name | EC | CAS | Entry No | Latest application | Sunset | property
        return EchaResult(
          source: source,
          cas: cas,
          status: EchaStatus.listed,
          name: _cleanName(at(0)),
          ecNumber: at(1),
          entryNumber: at(3),
          latestApplicationDate: at(4),
          sunsetDate: at(5),
          reason: at(6),
        );
      }
    }
    // total>0 pero sin fila con el CAS exacto: coincidencia difusa => no listado.
    return EchaResult._status(source, cas, EchaStatus.notListed);
  }

  // ---------------------------------------------------------------------------
  // API JSON (Annex XIV nuevo, ECHA CHEM).
  // ---------------------------------------------------------------------------
  Future<EchaResult> _searchAuthApi(String cas) async {
    final uri = Uri.parse(_authApi).replace(queryParameters: {
      'searchText': cas,
      'pageIndex': '1',
      'pageSize': '20',
    });
    try {
      final req = await _client.getUrl(uri);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.set('Accept', 'application/json');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      _log('authApi "$cas": status=${res.statusCode} bodyLen=${body.length}');

      if (res.statusCode != 200) {
        return EchaResult._status(EchaSource.authNew, cas, EchaStatus.error,
            error: 'API HTTP ${res.statusCode}.');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? const [];

      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final casList = (item['casNumber'] as List?)?.cast<dynamic>() ?? [];
        if (!casList.any((c) => '$c' == cas)) continue;
        return EchaResult(
          source: EchaSource.authNew,
          cas: cas,
          status: EchaStatus.listed,
          name: _first(item['substanceName']),
          ecNumber: _first(item['ecNumber']),
          entryNumber: _first(item['entryNumber']) ?? '${item['entryNumber']}',
          latestApplicationDate: _first(item['latestApplicationDate']),
          sunsetDate: _first(item['sunsetDate']),
          reason: _first(item['reasonForInclusion']),
        );
      }
      return EchaResult._status(EchaSource.authNew, cas, EchaStatus.notListed);
    } catch (e) {
      return EchaResult._status(EchaSource.authNew, cas, EchaStatus.error,
          error: e.toString());
    }
  }

  /// Toma el primer valor útil de un campo que puede ser String o List.
  String? _first(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.isEmpty || v == '-' ? null : v;
    if (v is List) {
      for (final e in v) {
        final s = '$e';
        if (s.isNotEmpty && s != '-') return s;
      }
      return null;
    }
    final s = '$v';
    return s.isEmpty || s == '-' || s == 'null' ? null : s;
  }

  // ---------------------------------------------------------------------------
  // Orquestación: por cada CAS, consultar las tres fuentes.
  // ---------------------------------------------------------------------------
  Future<void> searchAll(
    List<String> casList, {
    EchaQuery query = EchaQuery.empty,
    required void Function(int index, CasReport report) onResult,
  }) async {
    List<Cookie>? candidateCookies;
    List<Cookie>? authLegacyCookies;

    for (var i = 0; i < casList.length; i++) {
      final cas = casList[i];

      // Candidate List (con reintento de sesión).
      EchaResult candidate;
      try {
        candidateCookies ??= await _openSession(_candidateBase);
        candidate = await _searchPortlet(
            candidateCookies, _candidateBase, EchaSource.candidate, cas, query);
        if (candidate.status == EchaStatus.error) {
          candidateCookies = await _openSession(_candidateBase);
          candidate = await _searchPortlet(candidateCookies, _candidateBase,
              EchaSource.candidate, cas, query);
        }
      } catch (e) {
        candidateCookies = null;
        candidate = EchaResult._status(
            EchaSource.candidate, cas, EchaStatus.error, error: e.toString());
      }

      // Annex XIV legado (con reintento de sesión).
      EchaResult authLegacy;
      try {
        authLegacyCookies ??= await _openSession(_authLegacyBase);
        authLegacy = await _searchPortlet(authLegacyCookies, _authLegacyBase,
            EchaSource.authLegacy, cas, query);
        if (authLegacy.status == EchaStatus.error) {
          authLegacyCookies = await _openSession(_authLegacyBase);
          authLegacy = await _searchPortlet(authLegacyCookies, _authLegacyBase,
              EchaSource.authLegacy, cas, query);
        }
      } catch (e) {
        authLegacyCookies = null;
        authLegacy = EchaResult._status(
            EchaSource.authLegacy, cas, EchaStatus.error, error: e.toString());
      }

      // Annex XIV nuevo (API JSON, sin sesión).
      final authNew = await _searchAuthApi(cas);

      onResult(
        i,
        CasReport(cas, {
          EchaSource.candidate: candidate,
          EchaSource.authNew: authNew,
          EchaSource.authLegacy: authLegacy,
        }),
      );

      if (i < casList.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers de parseo.
  // ---------------------------------------------------------------------------
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

  String? _cleanName(String? raw) {
    if (raw == null) return null;
    var n = raw;
    final cut = RegExp(r'\s*(EC number|CAS number)\s*:', caseSensitive: false)
        .firstMatch(n);
    if (cut != null) n = n.substring(0, cut.start);
    return n.trim();
  }

  bool _cellHasCas(String cell, String cas) {
    final re = RegExp(r'(?<![\d-])' + RegExp.escape(cas) + r'(?![\d-])');
    return re.hasMatch(cell);
  }

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
}
