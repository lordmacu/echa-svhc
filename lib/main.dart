import 'package:flutter/material.dart';

import 'cas_importer.dart';
import 'cas_utils.dart';
import 'echa_service.dart';
import 'excel_export.dart';

void main() {
  runApp(const EchaApp());
}

class EchaApp extends StatelessWidget {
  const EchaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ECHA SVHC',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _service = EchaService();

  /// CAS agregados como chips (orden preservado).
  final List<String> _casList = [];

  /// Reportes por CAS (mismo orden que _casList).
  final Map<String, CasReport> _results = {};

  bool _running = false;
  int _currentIndex = -1;

  // Filtros (como en la página de ECHA). Defaults: reason = All, fechas vacías.
  String _reason = ''; // '' = - All -
  DateTime? _from;
  DateTime? _to;

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _service.close();
    super.dispose();
  }

  /// Detecta los CAS dentro del texto (que puede ser prosa con CAS embebidos),
  /// los convierte en chips sin duplicar, y los elimina del campo dejando el
  /// resto del texto. Así pegar un párrafo extrae los CAS automáticamente.
  void _onChanged(String text) {
    final found = CasUtils.extractAll(text);
    if (found.isEmpty) return;

    final added = _addCas(found);

    // Quita los CAS ya detectados del campo y colapsa espacios sobrantes.
    final stripped = text
        .replaceAll(CasUtils.pattern, ' ')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    _controller.value = TextEditingValue(
      text: stripped,
      selection: TextSelection.collapsed(offset: stripped.length),
    );
    if (added > 0) setState(() {});
  }

  void _addFromField() {
    final added = _addCas(CasUtils.extractAll(_controller.text));
    _controller.clear();
    if (added > 0) setState(() {});
  }

  /// Agrega CAS evitando duplicados. Devuelve cuántos se agregaron.
  int _addCas(Iterable<String> cas) {
    var added = 0;
    for (final c in cas) {
      if (!_casList.contains(c)) {
        _casList.add(c);
        added++;
      }
    }
    return added;
  }

  Future<void> _importFile() async {
    try {
      final result = await CasImporter.pickAndExtract();
      if (result == null) return; // cancelado
      final added = _addCas(result.cas);
      setState(() {});
      if (!mounted) return;
      final msg = result.cas.isEmpty
          ? 'No se encontraron CAS en "${result.fileName}".'
          : '${result.fileName}: ${result.cas.length} CAS detectados, '
              '$added nuevos agregados.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al importar: $e')),
      );
    }
  }

  void _removeChip(String cas) {
    setState(() {
      _casList.remove(cas);
      _results.remove(cas);
    });
  }

  void _clearAll() {
    setState(() {
      _casList.clear();
      _results.clear();
      _currentIndex = -1;
    });
  }

  Future<void> _exportExcel() async {
    try {
      final path = await ExcelExport.export(_casList, _results);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(path == null
            ? 'Exportación cancelada.'
            : 'Guardado en: $path'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
    }
  }

  Future<void> _run() async {
    _addFromField(); // por si quedó algo escrito sin separador
    if (_casList.isEmpty || _running) return;

    setState(() {
      _running = true;
      _results.clear();
      _currentIndex = -1;
    });

    await _service.searchAll(
      List<String>.from(_casList),
      query: EchaQuery(
        reason: _reason,
        inclusionFrom: _from == null ? null : _fmt(_from!),
        inclusionTo: _to == null ? null : _fmt(_to!),
      ),
      onResult: (index, report) {
        setState(() {
          _currentIndex = index;
          _results[report.cas] = report;
        });
      },
    );

    // Una vez procesados, se limpia el campo de texto.
    _controller.clear();
    setState(() {
      _running = false;
      _currentIndex = -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _results.length;
    final total = _casList.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ECHA — SVHC + Annex XIV + XVII por CAS'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pega uno o varios números CAS (se detectan automáticamente). '
              'Se consultan 7 fuentes: ECHA (Candidate List, Annex XIV '
              'nuevo/legado, Annex XVII) y US (California Prop 65, TSCA, '
              'EPA HAP). Ej: 110-54-3',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _buildInput(theme),
            const SizedBox(height: 12),
            _buildFilters(theme),
            _buildFilterNote(theme),
            const SizedBox(height: 12),
            if (_casList.isNotEmpty) _buildChips(theme),
            const SizedBox(height: 12),
            _buildActions(theme, done, total),
            const SizedBox(height: 8),
            if (_running) LinearProgressIndicator(
              value: total == 0 ? null : done / total,
            ),
            const SizedBox(height: 12),
            const Divider(),
            Expanded(child: _buildResults(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            maxLines: 3,
            minLines: 1,
            enabled: !_running,
            onChanged: _onChanged,
            onSubmitted: (_) => _addFromField(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '110-54-3, 50-00-0 …',
              labelText: 'Números CAS',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            FilledButton.tonal(
              onPressed: _running ? null : _addFromField,
              child: const Text('Agregar'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _running ? null : _importFile,
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('Importar CSV/Excel'),
            ),
          ],
        ),
      ],
    );
  }

  /// Filtros opcionales: Reason for inclusion (default "- All -") y rango de
  /// fecha de inclusión (from/to, vacíos por defecto). Igual que la página ECHA.
  Widget _buildFilters(ThemeData theme) {
    String reasonLabel(String r) => r.isEmpty ? '- All -' : r;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: _reason,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Reason for inclusion',
              isDense: true,
            ),
            items: [
              for (final r in echaReasons)
                DropdownMenuItem(
                  value: r,
                  child: Text(
                    reasonLabel(r),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _running
                ? null
                : (v) => setState(() => _reason = v ?? ''),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DateField(
            label: 'Inclusion from',
            value: _from,
            enabled: !_running,
            onPick: (d) => setState(() => _from = d),
            fmt: _fmt,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DateField(
            label: 'Inclusion to',
            value: _to,
            enabled: !_running,
            onPick: (d) => setState(() => _to = d),
            fmt: _fmt,
          ),
        ),
      ],
    );
  }

  /// Nota: los filtros solo afectan a la Candidate List (como en la web).
  Widget _buildFilterNote(ThemeData theme) {
    if (_reason.isEmpty && _from == null && _to == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        'Los filtros Reason/Date solo aplican a la Candidate List.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      ),
    );
  }

  Widget _buildChips(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _casList.map((cas) {
        final report = _results[cas];
        final valid = CasUtils.isValidChecksum(cas);
        return InputChip(
          avatar: _chipAvatar(report),
          label: Text(cas),
          backgroundColor: valid ? null : theme.colorScheme.errorContainer,
          onDeleted: _running ? null : () => _removeChip(cas),
          tooltip: valid ? null : 'Dígito de control no válido (¿errata?)',
        );
      }).toList(),
    );
  }

  /// Avatar del chip: ✓ si aparece en alguna fuente, ✗ si en ninguna,
  /// ⚠ si hubo algún error.
  Widget? _chipAvatar(CasReport? r) {
    if (r == null) return null;
    final results = r.bySource.values;
    if (results.any((x) => x.status == EchaStatus.listed)) {
      return const Icon(Icons.check_circle, color: Colors.green, size: 18);
    }
    if (results.any((x) => x.status == EchaStatus.error)) {
      return const Icon(Icons.error, color: Colors.orange, size: 18);
    }
    return const Icon(Icons.cancel, color: Colors.grey, size: 18);
  }

  Widget _buildActions(ThemeData theme, int done, int total) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: (_running || _casList.isEmpty) ? null : _run,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(_running ? 'Consultando $done/$total…' : 'Consultar'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: (_running || _casList.isEmpty) ? null : _clearAll,
          icon: const Icon(Icons.clear_all),
          label: const Text('Limpiar'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed:
              (_running || _results.isEmpty) ? null : _exportExcel,
          icon: const Icon(Icons.file_download),
          label: const Text('Exportar a Excel'),
        ),
        const Spacer(),
        if (total > 0)
          Text('${_casList.length} CAS', style: theme.textTheme.labelLarge),
      ],
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_casList.isEmpty) {
      return Center(
        child: Text(
          'Agrega CAS y pulsa Consultar.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.disabledColor),
        ),
      );
    }
    // Tabla ancha (7 fuentes): scroll horizontal con ancho fijo.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: _kTableWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _ResultHeader(),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: _casList.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final cas = _casList[i];
                  final report = _results[cas];
                  final isCurrent = _running && i == _currentIndex;
                  return _ResultRow(
                    cas: cas,
                    report: report,
                    isCurrent: isCurrent,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Anchos de columna compartidos entre el header y cada fila.
const double _kCasWidth = 96;
const double _kSourceWidth = 78;
const double _kNameWidth = 220;
// Ancho total de la tabla (CAS + N fuentes + nombre + padding horizontal 4+4).
double get _kTableWidth =>
    _kCasWidth + EchaSource.values.length * _kSourceWidth + _kNameWidth + 8;

class _ResultHeader extends StatelessWidget {
  const _ResultHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(fontWeight: FontWeight.bold);
    Widget cell(String t, double w) =>
        SizedBox(width: w, child: Text(t, style: style, textAlign: TextAlign.center));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          SizedBox(width: _kCasWidth, child: Text('CAS', style: style)),
          for (final s in EchaSource.values) cell(s.shortLabel, _kSourceWidth),
          SizedBox(width: _kNameWidth, child: Text('Nombre', style: style)),
        ],
      ),
    );
  }
}

/// Una fila de la tabla: CAS + indicadores por fuente + nombre.
/// Al tocarla se expande mostrando el detalle de cada fuente.
class _ResultRow extends StatefulWidget {
  final String cas;
  final CasReport? report;
  final bool isCurrent;

  const _ResultRow({
    required this.cas,
    required this.report,
    required this.isCurrent,
  });

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.report;

    Widget indicator(EchaSource s) {
      final r = report?[s];
      final Widget icon;
      if (report == null) {
        icon = widget.isCurrent
            ? const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.hourglass_empty, size: 18, color: theme.disabledColor);
      } else {
        icon = switch (r!.status) {
          EchaStatus.listed =>
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
          EchaStatus.notListed =>
            Icon(Icons.remove_circle_outline,
                color: theme.disabledColor, size: 20),
          EchaStatus.error =>
            const Icon(Icons.error_outline, color: Colors.orange, size: 20),
        };
      }
      return SizedBox(
        width: _kSourceWidth,
        child: Tooltip(
          message: r?.error ?? s.label,
          child: Center(child: icon),
        ),
      );
    }

    final canExpand = report != null;
    final summaryRow = InkWell(
      onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: _kCasWidth,
              child: Row(
                children: [
                  if (canExpand)
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: theme.hintColor,
                    ),
                  Expanded(
                    child: Text(widget.cas,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            for (final s in EchaSource.values) indicator(s),
            SizedBox(
              width: _kNameWidth,
              child: Text(
                _detailSummary(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );

    if (!canExpand || !_expanded) return summaryRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        summaryRow,
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in EchaSource.values)
                _SourceDetail(result: report[s]!),
            ],
          ),
        ),
      ],
    );
  }

  String _detailSummary() {
    final r = widget.report;
    if (r == null) return widget.isCurrent ? 'Consultando…' : 'En cola';
    final name = r[EchaSource.candidate]?.name ??
        r[EchaSource.authNew]?.name ??
        r[EchaSource.authLegacy]?.name ??
        r[EchaSource.tsca]?.name ??
        r[EchaSource.prop65]?.name;
    final inLists = EchaSource.values
        .where((s) => r[s]?.status == EchaStatus.listed)
        .map((s) => s.shortLabel)
        .toList();
    if (inLists.isEmpty) return name ?? 'No aparece en ninguna lista';
    return '${name ?? ''} — en: ${inLists.join(", ")}';
  }
}

/// Detalle de una fuente dentro de la fila expandida.
class _SourceDetail extends StatelessWidget {
  final EchaResult result;
  const _SourceDetail({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;

    final (IconData ico, Color col, String estado) = switch (r.status) {
      EchaStatus.listed => (Icons.check_circle, Colors.green, 'EN LA LISTA'),
      EchaStatus.notListed =>
        (Icons.remove_circle_outline, theme.disabledColor, 'No está'),
      EchaStatus.error => (Icons.error_outline, Colors.orange, 'Error'),
    };

    final lines = <String>[
      if (r.name != null) 'Nombre: ${r.name}',
      if (r.ecNumber != null) 'EC: ${r.ecNumber}',
      // Candidate List:
      if (r.inclusionDate != null) 'Inclusión: ${r.inclusionDate}',
      if (r.decisionNumber != null) 'Decisión: ${r.decisionNumber}',
      // Annex XIV:
      if (r.entryNumber != null) 'Entry: ${r.entryNumber}',
      if (r.latestApplicationDate != null)
        'Latest application: ${r.latestApplicationDate}',
      if (r.sunsetDate != null) 'Sunset date: ${r.sunsetDate}',
      if (r.reason != null) 'Motivo/propiedad: ${r.reason}',
      if (r.status == EchaStatus.error && r.error != null) r.error!,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ico, color: col, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r.source.label} — $estado',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: r.status == EchaStatus.listed
                            ? Colors.green.shade800
                            : null)),
                for (final l in lines)
                  Text(l, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Campo de fecha de solo lectura que abre un date picker al pulsarlo.
/// Muestra un botón para limpiar la fecha (volver a "vacío").
class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final bool enabled;
  final ValueChanged<DateTime?> onPick;
  final String Function(DateTime) fmt;

  const _DateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2008),
                lastDate: DateTime(2100),
              );
              if (picked != null) onPick(picked);
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          labelText: label,
          isDense: true,
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today, size: 18)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: enabled ? () => onPick(null) : null,
                  tooltip: 'Limpiar',
                ),
        ),
        child: Text(
          value == null ? '—' : fmt(value!),
          style: TextStyle(
            color: value == null
                ? Theme.of(context).hintColor
                : Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ),
    );
  }
}
