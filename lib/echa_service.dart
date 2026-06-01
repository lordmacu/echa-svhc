import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

void _log(String msg) => dev.log(msg, name: 'ECHA');

/// Las tres fuentes que se consultan por cada CAS.
enum EchaSource {
  /// Candidate List (SVHC) — portal legado, portlet Liferay.
  candidate,

  /// Authorisation List (REACH Annex XIV) — API JSON de ECHA CHEM (nuevo).
  authNew,

  /// Authorisation List (REACH Annex XIV) — portal legado, portlet Liferay.
  authLegacy,

  /// Restriction List (REACH Annex XVII) — portal legado, portlet Liferay.
  restriction,

  /// California Proposition 65 List — vía ChemRadar (es_query).
  prop65,

  /// US TSCA Chemical Substance Inventory — vía ChemRadar (es_query).
  tsca,

  /// US EPA Hazardous Air Pollutants (Clean Air Act) — vía ChemRadar.
  epaHap,

  /// TSCA Significant New Use Rule (SNUR) — vía EPA ChemView.
  tscaSnur,

  /// TSCA § 5(e) Consent Order — vía EPA ChemView.
  tscaConsentOrder,

  /// Japan PDSCL — Poisonous substances (毒物) — NIHS, lista estática.
  japanPoison,

  /// Japan PDSCL — Deleterious substances (劇物) — NIHS, lista estática.
  japanDeleterious,

  /// Canada — Domestic Substances List (DSL) — Excel local.
  canadaDsl,

  /// Canada — Non-domestic Substances List (NDSL) — Excel local.
  canadaNdsl,

  /// China — Inventory of Existing Chemical Substances (IECSC) — ChemRadar.
  chinaIecsc,

  /// Korea — Existing Chemicals List (KECL) — ChemRadar.
  koreaKecl,

  /// EU — REACH Registered Substances — ChemRadar.
  euReachRegistered,

  /// Turkey — KKDIK Harmonized Classification List — ChemRadar.
  turkeyKkdik,

  /// Japan — Existing and New Chemical Substances Inventory (ENCS) — ChemRadar.
  japanEncs,

  /// Philippines — Inventory of Chemicals and Chemical Substances (PICCS).
  philippinesPiccs,

  /// Taiwan — Chemical Substance Inventory (TCSI) — ChemRadar.
  taiwanTcsi,

  /// Australia — Inventory of Industrial Chemicals (AIIC) — ChemRadar.
  australiaAiic,

  /// New Zealand — Inventory of Chemicals (NZIoC) — ChemRadar.
  newZealandNzioc,
}

extension EchaSourceInfo on EchaSource {
  String get label => switch (this) {
        EchaSource.candidate => 'Candidate List (SVHC)',
        EchaSource.authNew => 'Annex XIV (ECHA CHEM)',
        EchaSource.authLegacy => 'Annex XIV (legado)',
        EchaSource.restriction => 'Annex XVII (Restriction)',
        EchaSource.prop65 => 'California Proposition 65',
        EchaSource.tsca => 'US TSCA Inventory',
        EchaSource.epaHap => 'US EPA Hazardous Air Pollutants',
        EchaSource.tscaSnur => 'TSCA Significant New Use Rule (SNUR)',
        EchaSource.tscaConsentOrder => 'TSCA § 5(e) Consent Order',
        EchaSource.japanPoison => 'Japan PDSCL — Poison',
        EchaSource.japanDeleterious => 'Japan PDSCL — Deleterious',
        EchaSource.canadaDsl => 'Canada — Domestic Substances List (DSL)',
        EchaSource.canadaNdsl =>
          'Canada — Non-domestic Substances List (NDSL)',
        EchaSource.chinaIecsc => 'China — Existing Chemical Substances (IECSC)',
        EchaSource.koreaKecl => 'Korea — Existing Chemicals List (KECL)',
        EchaSource.euReachRegistered => 'EU — REACH Registered Substances',
        EchaSource.turkeyKkdik => 'Turkey — KKDIK Classification List',
        EchaSource.japanEncs =>
          'Japan — Existing & New Chemical Substances (ENCS)',
        EchaSource.philippinesPiccs =>
          'Philippines — Inventory of Chemicals (PICCS)',
        EchaSource.taiwanTcsi =>
          'Taiwan — Chemical Substance Inventory (TCSI)',
        EchaSource.australiaAiic =>
          'Australia — Inventory of Industrial Chemicals (AIIC)',
        EchaSource.newZealandNzioc =>
          'New Zealand — Inventory of Chemicals (NZIoC)',
      };

  String get shortLabel => switch (this) {
        EchaSource.candidate => 'Candidate',
        EchaSource.authNew => 'Annex XIV (nuevo)',
        EchaSource.authLegacy => 'Annex XIV (legado)',
        EchaSource.restriction => 'Annex XVII',
        EchaSource.prop65 => 'Prop 65',
        EchaSource.tsca => 'TSCA',
        EchaSource.epaHap => 'EPA HAP',
        EchaSource.tscaSnur => 'SNUR',
        EchaSource.tscaConsentOrder => '§5(e) Order',
        EchaSource.japanPoison => 'Japan Poison',
        EchaSource.japanDeleterious => 'Japan Deleterious',
        EchaSource.canadaDsl => 'Canada DSL',
        EchaSource.canadaNdsl => 'Canada NDSL',
        EchaSource.chinaIecsc => 'China IECSC',
        EchaSource.koreaKecl => 'Korea KECL',
        EchaSource.euReachRegistered => 'EU REACH Reg.',
        EchaSource.turkeyKkdik => 'Turkey KKDIK',
        EchaSource.japanEncs => 'Japan ENCS',
        EchaSource.philippinesPiccs => 'PICCS',
        EchaSource.taiwanTcsi => 'Taiwan TCSI',
        EchaSource.australiaAiic => 'Australia AIIC',
        EchaSource.newZealandNzioc => 'NZ NZIoC',
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
  static const _restrictionBase =
      'https://www.echa.europa.eu/web/guest/substances-restricted-under-reach';

  // ChemRadar: buscador público es_query (sin login) + IDs de inventario.
  static const _chemRadarApi = 'https://www.chemradar.com/api/gcis/es_query';
  static const _chemRadarInvId = {
    EchaSource.prop65: '64924a20e7fff39f787f1b0d',
    EchaSource.tsca: '649249f5e7fff39f787f1b0c',
    EchaSource.epaHap: '64924a49e7fff39f787f1b0e',
    EchaSource.chinaIecsc: '64896375bc1d7cdaf02f0ab5',
    EchaSource.koreaKecl: '6491044fe7fff39f787bb767',
    EchaSource.euReachRegistered: '6800b784bcddf0c66f3a78cb',
    EchaSource.turkeyKkdik: '66bc721115260fd97a652f96',
    EchaSource.japanEncs: '648fb470e7fff39f78795ebc',
    EchaSource.philippinesPiccs: '649a337f7ba20a1a4f5fd7b7',
    EchaSource.taiwanTcsi: '648fac15551b8802d693c9f1',
    EchaSource.australiaAiic: '649a350c7ba20a1a4f5fd7ba',
    EchaSource.newZealandNzioc: '649a33207ba20a1a4f5fd7b6',
  };

  // EPA ChemView: público, sin login. Flujo search -> id -> datatable.
  static const _chemViewBase = 'https://chemview.epa.gov/chemview';

  // Japan PDSCL (NIHS): listas estáticas Shift_JIS (Excel->HTML), sin login.
  // Se descargan una vez por sesión y se cachea el set de CAS.
  static const _japanUrl = {
    EchaSource.japanPoison:
        'http://www.nihs.go.jp/law/dokugeki/doku.files/sheet001.html',
    EchaSource.japanDeleterious:
        'http://www.nihs.go.jp/law/dokugeki/geki.files/sheet001.html',
  };
  // Cache en memoria: fuente -> conjunto de CAS de esa lista.
  final Map<EchaSource, Set<String>> _japanCache = {};

  final HttpClient _client = HttpClient()
    ..userAgent = _ua
    ..connectionTimeout = const Duration(seconds: 30);

  /// Pausa entre llamadas al mismo host de ChemRadar (anti rate-limiting).
  /// Subir si te bloquean; bajar si quieres más velocidad.
  final Duration chemRadarPause;

  /// Pausa entre cada CAS del lote.
  final Duration perCasPause;

  EchaService({
    this.chemRadarPause = const Duration(milliseconds: 700),
    this.perCasPause = const Duration(milliseconds: 400),
  });

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
    // La Restriction List ordena por nº de entry (prc_entry_no), no por fecha.
    final isRestriction = source == EchaSource.restriction;
    final orderByCol = isRestriction ? 'prc_entry_no' : 'dte_inclusion';
    final orderByType = isRestriction ? 'asc' : 'desc';
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
      '${_portlet}_orderByCol': orderByCol,
      '${_portlet}_orderByType': orderByType,
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

    // Campo oculto _total, anclado al id/name EXACTO del portlet (no por sufijo,
    // para no capturar otro campo que termine en "_total").
    final totalMatch = RegExp(
            '(?:name|id)="${RegExp.escape(_portlet)}_total"[^>]*value="(\\d+)"')
        .firstMatch(html);
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
      // NO filtrar celdas vacías: los índices deben reflejar las columnas
      // reales de ECHA (una celda vacía al inicio desplazaría todo).
      final cells = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true)
          .allMatches(row.group(1)!)
          .map((c) => _clean(c.group(1)!))
          .toList();

      String? at(int i) =>
          (i < cells.length && cells[i].isNotEmpty) ? cells[i] : null;
      final casCol = at(2) ?? '';
      final nameCol = at(0) ?? '';

      if (source == EchaSource.restriction) {
        // Restricciones por grupo: la columna CAS suele venir "-" y los CAS
        // miembros van listados en el nombre bajo "CAS Number:". Restringido si:
        //  (a) el CAS está en la columna CAS exacta, o
        //  (b) el CAS está en el nombre Y el nombre tiene un label "CAS Number/No"
        //      (marca de lista de miembros) — esto excluye CAS sueltos en texto
        //      como "Reaction mass of 100-41-4 and …" (falso positivo).
        final inCasCol = _cellHasCas(casCol, cas);
        final hasCasLabel =
            RegExp(r'CAS\s*(?:Number|No)', caseSensitive: false)
                .hasMatch(nameCol);
        final inMemberList = hasCasLabel && _cellHasCas(nameCol, cas);
        if (!inCasCol && !inMemberList) continue;
        // name | EC | CAS | Entry no. | Conditions | Appendices | …
        return EchaResult(
          source: source,
          cas: cas,
          status: EchaStatus.listed,
          name: _cleanName(nameCol),
          ecNumber: at(1),
          entryNumber: at(3),
          reason: at(4), // Conditions
        );
      }

      if (!cells.any((c) => _cellHasCas(c, cas))) continue;
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

  // ---------------------------------------------------------------------------
  // ChemRadar (Prop 65, TSCA, EPA HAP) — endpoint público es_query.
  // ---------------------------------------------------------------------------
  Future<EchaResult> _searchChemRadar(EchaSource source, String cas) async {
    final invId = _chemRadarInvId[source]!;
    final payload = jsonEncode({
      'PageNum': 1,
      'PageSize': 20,
      'Type': 1,
      'Keyword': cas,
      'InvId': invId,
      'Platforms': [2],
      'IsCollapse': true,
      'Size': 20,
    });
    try {
      final bytes = utf8.encode(payload);
      final req = await _client.postUrl(Uri.parse(_chemRadarApi));
      req.followRedirects = false;
      req.headers.set(HttpHeaders.userAgentHeader, _ua);
      req.headers.contentType = ContentType('application', 'json',
          charset: 'utf-8');
      req.headers.set('Accept', 'application/json');
      req.headers.set('Origin', 'https://www.chemradar.com');
      req.headers.set(
          'Referer', 'https://www.chemradar.com/en/tools/gcis/inv/list');
      req.contentLength = bytes.length; // evita "connection closed before header"
      req.add(bytes);

      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      _log('chemradar ${source.name} "$cas": status=${res.statusCode} '
          'bodyLen=${body.length}');

      if (res.statusCode != 200) {
        return EchaResult._status(source, cas, EchaStatus.error,
            error: 'ChemRadar HTTP ${res.statusCode}.');
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final list = (data['List'] as List?) ?? const [];

      for (final raw in list) {
        final item = raw as Map<String, dynamic>;
        final casList = (item['CAS'] as List?)?.cast<dynamic>() ?? [];
        if (!casList.any((c) => '$c' == cas)) continue;
        return EchaResult(
          source: source,
          cas: cas,
          status: EchaStatus.listed,
          name: _first(item['InvNameEn']) ?? _first(item['InvName']),
        );
      }
      return EchaResult._status(source, cas, EchaStatus.notListed);
    } catch (e) {
      return EchaResult._status(source, cas, EchaStatus.error,
          error: e.toString());
    }
  }

  /// ChemRadar con reintentos y backoff exponencial: si la llamada falla
  /// (bloqueo/red), espera cada vez más antes de reintentar. Así un bloqueo
  /// transitorio por rate-limiting no se reporta como error.
  Future<EchaResult> _searchChemRadarRetry(EchaSource source, String cas) async {
    var r = await _searchChemRadar(source, cas);
    var backoffMs = 1000;
    for (var attempt = 0; attempt < 2 && r.status == EchaStatus.error; attempt++) {
      _log('chemradar ${source.name} "$cas": reintento en ${backoffMs}ms');
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
      r = await _searchChemRadar(source, cas);
      backoffMs *= 2;
    }
    return r;
  }

  /// Pausa entre llamadas al mismo host (evita rate-limiting).
  Future<void> _pause() => Future<void>.delayed(chemRadarPause);

  // ---------------------------------------------------------------------------
  // EPA ChemView (TSCA SNUR + § 5(e) Consent Order) — público, sin login.
  // Flujo: search?name=<cas> -> id -> datatable?chemicalIds=<id> -> sources[].
  // Una sola consulta devuelve AMBOS resultados (SNUR y Consent Order).
  // ---------------------------------------------------------------------------
  Future<(EchaResult snur, EchaResult co)> _searchChemView(String cas) async {
    EchaResult snurErr(String e) =>
        EchaResult._status(EchaSource.tscaSnur, cas, EchaStatus.error, error: e);
    EchaResult coErr(String e) => EchaResult._status(
        EchaSource.tscaConsentOrder, cas, EchaStatus.error, error: e);

    try {
      // Paso 1: search -> id interno del químico.
      final searchUri = Uri.parse('$_chemViewBase/chemicals/search')
          .replace(queryParameters: {'matchMode': '0', 'name': cas});
      final id = await _chemViewGet(searchUri, (body) {
        final arr = jsonDecode(body) as List;
        if (arr.isEmpty) return null;
        return '${(arr.first as Map)['id']}';
      });

      if (id == null) {
        // No está en ChemView -> no sujeto a SNUR ni Consent Order.
        return (
          EchaResult._status(EchaSource.tscaSnur, cas, EchaStatus.notListed),
          EchaResult._status(
              EchaSource.tscaConsentOrder, cas, EchaStatus.notListed),
        );
      }

      // Paso 2: datatable?chemicalIds=<id> -> sources[].
      final dtUri = Uri.parse('$_chemViewBase/chemicals/datatable').replace(
        queryParameters: {
          'isTemplateFilter': 'false',
          'chemicalIds': id,
          'draw': '1',
          'columns[0][data]': '0',
          'columns[0][searchable]': 'true',
          'columns[0][orderable]': 'false',
          'columns[0][search][value]': '',
          'columns[0][search][regex]': 'false',
          'start': '0',
          'length': '25',
          'search[value]': '',
          'search[regex]': 'false',
        },
      );
      final sources = await _chemViewGet(dtUri, (body) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final cqr = (data['chemicalDataTables']
                as Map<String, dynamic>?)?['chemicalQueryResults'] as List?;
        if (cqr == null || cqr.isEmpty) return <String>[];
        final srcs = (cqr.first as Map<String, dynamic>)['sources'] as List?;
        return (srcs ?? [])
            .whereType<Map<String, dynamic>>()
            .map((s) => '${s['sourceName'] ?? s['name'] ?? s['sourceType'] ?? ''}')
            .toList();
      });

      final hasSnur = sources!.contains('SNUR');
      final hasCo = sources.contains('CO');
      return (
        EchaResult(
          source: EchaSource.tscaSnur,
          cas: cas,
          status: hasSnur ? EchaStatus.listed : EchaStatus.notListed,
        ),
        EchaResult(
          source: EchaSource.tscaConsentOrder,
          cas: cas,
          status: hasCo ? EchaStatus.listed : EchaStatus.notListed,
        ),
      );
    } catch (e) {
      return (snurErr(e.toString()), coErr(e.toString()));
    }
  }

  /// GET a ChemView con headers de XHR; aplica [parse] al body si HTTP 200.
  Future<T?> _chemViewGet<T>(Uri uri, T Function(String body) parse) async {
    final req = await _client.getUrl(uri);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    req.headers.set('X-Requested-With', 'XMLHttpRequest');
    req.headers.set('Accept', 'application/json, text/javascript, */*');
    req.headers.set('Referer', '$_chemViewBase/');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    _log('chemview GET ${uri.path}: status=${res.statusCode} '
        'bodyLen=${body.length}');
    if (res.statusCode != 200) {
      throw Exception('ChemView HTTP ${res.statusCode}');
    }
    return parse(body);
  }

  /// ChemView con reintentos + backoff (mismo rate-limiting que ChemRadar).
  Future<(EchaResult, EchaResult)> _searchChemViewRetry(String cas) async {
    var r = await _searchChemView(cas);
    var backoffMs = 1000;
    for (var attempt = 0;
        attempt < 2 && r.$1.status == EchaStatus.error;
        attempt++) {
      _log('chemview "$cas": reintento en ${backoffMs}ms');
      await Future<void>.delayed(Duration(milliseconds: backoffMs));
      r = await _searchChemView(cas);
      backoffMs *= 2;
    }
    return r;
  }

  // ---------------------------------------------------------------------------
  // Japan PDSCL (毒物/劇物) — listas estáticas. Se descarga y cachea el set de
  // CAS una vez por sesión; las consultas siguientes son locales (instantáneas).
  // La página está en Shift_JIS, pero los CAS son ASCII -> se extraen de los
  // bytes crudos sin decodificar el japonés.
  // ---------------------------------------------------------------------------
  Future<Set<String>> _japanCasSet(EchaSource source) async {
    final cached = _japanCache[source];
    if (cached != null) return cached;

    final req = await _client.getUrl(Uri.parse(_japanUrl[source]!));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    final res = await req.close();
    // Leer como latin1 (1 byte = 1 char): preserva los CAS ASCII intactos.
    final body = await res.transform(latin1.decoder).join();
    _log('japan ${source.name}: status=${res.statusCode} bodyLen=${body.length}');
    if (res.statusCode != 200) {
      throw Exception('Japan PDSCL HTTP ${res.statusCode}');
    }
    final set = RegExp(r'(?<![\d-])\d{2,7}-\d{2}-\d(?![\d-])')
        .allMatches(body)
        .map((m) => m.group(0)!)
        .toSet();
    _japanCache[source] = set;
    return set;
  }

  Future<EchaResult> _searchJapan(EchaSource source, String cas) async {
    try {
      final set = await _japanCasSet(source);
      return EchaResult(
        source: source,
        cas: cas,
        status: set.contains(cas) ? EchaStatus.listed : EchaStatus.notListed,
      );
    } catch (e) {
      return EchaResult._status(source, cas, EchaStatus.error,
          error: e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // Canada DSL / NDSL — listas LOCALES (assets). Se cargan una vez y se cachea
  // el conjunto de CAS; lookup local instantáneo, sin red.
  // ---------------------------------------------------------------------------
  static const _canadaAsset = {
    EchaSource.canadaDsl: 'assets/canada_dsl_cas.txt',
    EchaSource.canadaNdsl: 'assets/canada_ndsl_cas.txt',
  };
  final Map<EchaSource, Set<String>> _canadaCache = {};

  Future<Set<String>> _canadaCasSet(EchaSource source) async {
    final cached = _canadaCache[source];
    if (cached != null) return cached;
    final text = await rootBundle.loadString(_canadaAsset[source]!);
    final set = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toSet();
    _log('canada ${source.name}: ${set.length} CAS (asset local)');
    _canadaCache[source] = set;
    return set;
  }

  Future<EchaResult> _searchCanadaLocal(EchaSource source, String cas) async {
    try {
      final set = await _canadaCasSet(source);
      return EchaResult(
        source: source,
        cas: cas,
        status: set.contains(cas) ? EchaStatus.listed : EchaStatus.notListed,
      );
    } catch (e) {
      return EchaResult._status(source, cas, EchaStatus.error,
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
    // Fuentes basadas en el portlet Liferay: (fuente -> base URL).
    const portletSources = {
      EchaSource.candidate: _candidateBase,
      EchaSource.authLegacy: _authLegacyBase,
      EchaSource.restriction: _restrictionBase,
    };
    // Cookies por base URL (se reusan entre CAS).
    final cookies = <String, List<Cookie>>{};

    Future<EchaResult> runPortlet(EchaSource source, String cas) async {
      final base = portletSources[source]!;
      try {
        cookies[base] ??= await _openSession(base);
        var r = await _searchPortlet(cookies[base]!, base, source, cas, query);
        if (r.status == EchaStatus.error) {
          cookies[base] = await _openSession(base); // sesión fresca y reintento
          r = await _searchPortlet(cookies[base]!, base, source, cas, query);
        }
        return r;
      } catch (e) {
        cookies.remove(base);
        return EchaResult._status(source, cas, EchaStatus.error,
            error: e.toString());
      }
    }

    for (var i = 0; i < casList.length; i++) {
      final cas = casList[i];

      // Las distintas fuentes se agrupan por HOST y los grupos corren en
      // PARALELO. Dentro de cada host las llamadas van secuenciales con pausa
      // (mismo servidor -> evitar rate-limiting). Acumulamos en un mapa.
      final results = <EchaSource, EchaResult>{};

      // Grupo 1 — ECHA (www.echa.europa.eu): 3 portlets secuenciales + 1 API.
      Future<void> echaGroup() async {
        results[EchaSource.candidate] =
            await runPortlet(EchaSource.candidate, cas);
        results[EchaSource.authLegacy] =
            await runPortlet(EchaSource.authLegacy, cas);
        results[EchaSource.restriction] =
            await runPortlet(EchaSource.restriction, cas);
      }

      // Grupo 2 — ECHA CHEM (API JSON, otro host).
      Future<void> echaChemGroup() async {
        results[EchaSource.authNew] = await _searchAuthApi(cas);
      }

      // Grupo 3 — ChemRadar (mismo host): 8 inventarios secuenciales + pausa.
      Future<void> chemRadarGroup() async {
        const order = [
          EchaSource.prop65,
          EchaSource.tsca,
          EchaSource.epaHap,
          EchaSource.chinaIecsc,
          EchaSource.koreaKecl,
          EchaSource.euReachRegistered,
          EchaSource.turkeyKkdik,
          EchaSource.japanEncs,
          EchaSource.philippinesPiccs,
          EchaSource.taiwanTcsi,
          EchaSource.australiaAiic,
          EchaSource.newZealandNzioc,
        ];
        for (var k = 0; k < order.length; k++) {
          results[order[k]] = await _searchChemRadarRetry(order[k], cas);
          if (k < order.length - 1) await _pause();
        }
      }

      // Grupo 4 — EPA ChemView (SNUR + §5e).
      Future<void> chemViewGroup() async {
        final (snur, co) = await _searchChemViewRetry(cas);
        results[EchaSource.tscaSnur] = snur;
        results[EchaSource.tscaConsentOrder] = co;
      }

      // Grupo 5 — locales (Japón estático + Canadá assets): instantáneos.
      Future<void> localGroup() async {
        results[EchaSource.japanPoison] =
            await _searchJapan(EchaSource.japanPoison, cas);
        results[EchaSource.japanDeleterious] =
            await _searchJapan(EchaSource.japanDeleterious, cas);
        results[EchaSource.canadaDsl] =
            await _searchCanadaLocal(EchaSource.canadaDsl, cas);
        results[EchaSource.canadaNdsl] =
            await _searchCanadaLocal(EchaSource.canadaNdsl, cas);
      }

      // Correr los 5 grupos en paralelo.
      await Future.wait([
        echaGroup(),
        echaChemGroup(),
        chemRadarGroup(),
        chemViewGroup(),
        localGroup(),
      ]);

      onResult(i, CasReport(cas, results));

      if (i < casList.length - 1) {
        await Future<void>.delayed(perCasPause);
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
