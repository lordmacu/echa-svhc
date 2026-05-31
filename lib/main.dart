import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cas_utils.dart';
import 'echa_service.dart';

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

  /// Resultados por CAS (mismo orden que _casList).
  final Map<String, EchaResult> _results = {};

  bool _running = false;
  int _currentIndex = -1;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _service.close();
    super.dispose();
  }

  /// Extrae CAS completos del texto y los convierte en chips, dejando en el
  /// campo cualquier fragmento aún incompleto que el usuario siga escribiendo.
  void _onChanged(String text) {
    final matches = CasUtils.pattern.allMatches(text).toList();
    if (matches.isEmpty) return;

    var added = false;
    for (final m in matches) {
      final cas = m.group(0)!;
      if (!_casList.contains(cas)) {
        _casList.add(cas);
        added = true;
      }
    }

    final remainder = text.substring(matches.last.end);
    _controller.value = TextEditingValue(
      text: remainder,
      selection: TextSelection.collapsed(offset: remainder.length),
    );
    if (added) setState(() {});
  }

  void _addFromField() {
    final cas = CasUtils.extractAll(_controller.text);
    var added = false;
    for (final c in cas) {
      if (!_casList.contains(c)) {
        _casList.add(c);
        added = true;
      }
    }
    _controller.clear();
    if (added) setState(() {});
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

  Future<void> _run() async {
    _addFromField(); // por si quedó algo escrito sin separador
    if (_casList.isEmpty || _running) return;

    setState(() {
      _running = true;
      _results.clear();
      _currentIndex = -1;
    });

    await _service.searchMany(
      List<String>.from(_casList),
      onResult: (index, result) {
        setState(() {
          _currentIndex = index;
          _results[result.cas] = result;
        });
      },
    );

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
        title: const Text('ECHA — Candidate List (SVHC) por CAS'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pega uno o varios números CAS (se detectan automáticamente). '
              'Ej: 110-54-3',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            _buildInput(theme),
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
            inputFormatters: [
              // permite dígitos, guiones y separadores; bloquea letras.
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s,;\-\n\t]')),
            ],
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '110-54-3, 50-00-0 …',
              labelText: 'Números CAS',
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: _running ? null : _addFromField,
          child: const Text('Agregar'),
        ),
      ],
    );
  }

  Widget _buildChips(ThemeData theme) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _casList.map((cas) {
        final result = _results[cas];
        final valid = CasUtils.isValidChecksum(cas);
        return InputChip(
          avatar: _statusAvatar(result),
          label: Text(cas),
          backgroundColor: valid ? null : theme.colorScheme.errorContainer,
          onDeleted: _running ? null : () => _removeChip(cas),
          tooltip: valid ? null : 'Dígito de control no válido (¿errata?)',
        );
      }).toList(),
    );
  }

  Widget? _statusAvatar(EchaResult? r) {
    if (r == null) return null;
    switch (r.status) {
      case EchaStatus.listed:
        return const Icon(Icons.check_circle, color: Colors.green, size: 18);
      case EchaStatus.notListed:
        return const Icon(Icons.cancel, color: Colors.grey, size: 18);
      case EchaStatus.error:
        return const Icon(Icons.error, color: Colors.orange, size: 18);
    }
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
    return ListView.separated(
      itemCount: _casList.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final cas = _casList[i];
        final r = _results[cas];
        final isCurrent = _running && i == _currentIndex;
        return _ResultTile(cas: cas, result: r, isCurrent: isCurrent);
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String cas;
  final EchaResult? result;
  final bool isCurrent;

  const _ResultTile({
    required this.cas,
    required this.result,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = result;

    Widget leading;
    String title;
    Widget? subtitle;
    Color? color;

    if (r == null) {
      leading = isCurrent
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.hourglass_empty, color: theme.disabledColor);
      title = cas;
      subtitle = Text(isCurrent ? 'Consultando…' : 'En cola');
    } else {
      switch (r.status) {
        case EchaStatus.listed:
          leading = const Icon(Icons.check_circle, color: Colors.green);
          title = '$cas — EN LA LISTA';
          color = Colors.green.shade800;
          subtitle = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.name != null) Text('Nombre: ${r.name}'),
              if (r.ecNumber != null) Text('EC: ${r.ecNumber}'),
              if (r.inclusionDate != null)
                Text('Inclusión: ${r.inclusionDate}'),
              if (r.reason != null) Text('Motivo: ${r.reason}'),
              if (r.decisionNumber != null)
                Text('Decisión: ${r.decisionNumber}'),
            ],
          );
          break;
        case EchaStatus.notListed:
          leading = const Icon(Icons.cancel, color: Colors.grey);
          title = '$cas — NO está en la lista';
          subtitle = const Text('No aparece en la Candidate List (SVHC).');
          break;
        case EchaStatus.error:
          leading = const Icon(Icons.error, color: Colors.orange);
          title = '$cas — Error';
          color = Colors.orange.shade900;
          subtitle = Text(r.error ?? 'Error desconocido');
          break;
      }
    }

    return ListTile(
      leading: leading,
      title: Text(title,
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      subtitle: subtitle,
      isThreeLine: r?.status == EchaStatus.listed,
    );
  }
}
