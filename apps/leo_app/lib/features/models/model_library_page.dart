import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/resources/model_resource_policy.dart';
import '../../core/diagnostics/runtime_benchmark_store.dart';
import '../../src/rust/api/simple.dart' as rust_api;
import '../../src/rust/rust_bridge_initializer.dart';

class ModelLibraryPage extends StatefulWidget {
  const ModelLibraryPage({super.key});

  @override
  State<ModelLibraryPage> createState() => _ModelLibraryPageState();
}

class _ModelLibraryPageState extends State<ModelLibraryPage> {
  List<rust_api.ModelSummaryDto> _models = const [];
  rust_api.RuntimeDiagnosticsDto? _diagnostics;
  String? _activeModelId;
  String? _error;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<String> _modelRoot() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(path.join(support.path, 'leo', 'model-library'));
    await root.create(recursive: true);
    return root.path;
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await RustBridgeInitializer.ensureInitialized();
      final root = await _modelRoot();
      final models = await rust_api.listModels(modelRoot: root);
      final diagnostics = await rust_api.runtimeDiagnostics();
      if (!mounted) return;
      setState(() {
        _models = models;
        _diagnostics = diagnostics;
        _loading = false;
        if (!diagnostics.modelLoaded) _activeModelId = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر قراءة مكتبة النماذج: $error';
      });
    }
  }

  Future<void> _importModel() async {
    if (_working) return;
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
    );
    if (selected == null) return;
    final sourcePath = selected.path;
    if (sourcePath == null || sourcePath.isEmpty) {
      _showMessage('لم يتمكن منتقي الملفات من توفير مسار محلي للملف.');
      return;
    }

    final displayName = path.basenameWithoutExtension(sourcePath).trim();
    final slug = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^[-_]+|[-_]+$'), '');
    final modelId =
        '${slug.isEmpty ? 'local-model' : slug}-${DateTime.now().millisecondsSinceEpoch}';

    await _runOperation(() async {
      final root = await _modelRoot();
      final imported = await rust_api.importGgufModel(
        sourcePath: sourcePath,
        modelRoot: root,
        modelId: modelId,
        displayName: displayName.isEmpty ? 'نموذج محلي' : displayName,
        contextLengthOverride: null,
        // GGUF weights are portable; platform compatibility is decided by
        // the native runtime available on the current device, not by import OS.
        supportedPlatforms: const <String>[],
        importedAtUtc: DateTime.now().toUtc().toIso8601String(),
      );
      _showMessage(
        'تم استيراد ${imported.displayName} والتحقق من سلامة الملف.',
      );
      await _refresh();
    });
  }

  Future<void> _loadModel(rust_api.ModelSummaryDto model) async {
    if (_working) return;
    if (_diagnostics?.generationActive ?? false) {
      _showMessage('انتظر انتهاء التوليد الحالي قبل تحميل نموذج آخر.');
      return;
    }
    final contextChoices = ModelResourcePolicy.supportedContextChoices(
      model.contextLength,
    );
    if (contextChoices.isEmpty) {
      _showMessage(
        'السياق الذي يعلنه ملف GGUF أقل من الحد الأدنى المدعوم في Leo (512 رمزاً).',
      );
      return;
    }

    final recommendedThreads = ModelResourcePolicy.recommendedModelThreads(
      Platform.numberOfProcessors,
    );
    final configuration = await showDialog<ModelLoadConfiguration>(
      context: context,
      builder: (_) => _ModelLoadDialog(
        model: model,
        contextChoices: contextChoices,
        recommendedThreads: recommendedThreads,
      ),
    );
    if (configuration == null || !mounted) return;

    await _runOperation(() async {
      final root = await _modelRoot();
      final result = await rust_api.loadModel(
        modelRoot: root,
        modelId: model.id,
        contextTokens: configuration.contextTokens,
        threads: configuration.threads,
      );
      if (!result.success || !result.modelLoaded) {
        throw StateError(result.message);
      }
      if (mounted) setState(() => _activeModelId = model.id);
      _showMessage('تم تحميل النموذج. يمكنك بدء المحادثة المحلية الآن.');
      await _refresh();
    });
  }

  Future<void> _unloadModel() async {
    if (_working) return;
    if (_diagnostics?.generationActive ?? false) {
      _showMessage('لا يمكن تفريغ النموذج أثناء التوليد.');
      return;
    }
    await _runOperation(() async {
      final result = await rust_api.unloadModel();
      if (!result.success || result.modelLoaded) {
        throw StateError(result.message);
      }
      if (mounted) setState(() => _activeModelId = null);
      _showMessage('تم تفريغ النموذج من الذاكرة.');
      await _refresh();
    });
  }

  Future<void> _removeModel(rust_api.ModelSummaryDto model) async {
    if (_working) return;
    if (_diagnostics?.generationActive ?? false) {
      _showMessage('لا يمكن حذف نموذج أثناء التوليد.');
      return;
    }
    if (_activeModelId == model.id || (_diagnostics?.modelLoaded ?? false)) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('تفريغ النموذج أولاً؟'),
          content: const Text(
            'هناك نموذج محمّل في الذاكرة. سيُطلب تفريغه قبل حذف الملف المحلي.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      if (choice != true) return;
    }

    await _runOperation(() async {
      if (_diagnostics?.modelLoaded ?? false) {
        final unloaded = await rust_api.unloadModel();
        if (!unloaded.success) throw StateError(unloaded.message);
      }
      final root = await _modelRoot();
      final removed = await rust_api.removeModel(
        modelRoot: root,
        modelId: model.id,
      );
      if (!removed) throw StateError('لم يتم العثور على سجل النموذج.');
      if (mounted) setState(() => _activeModelId = null);
      _showMessage('تم حذف النموذج وملفه المحلي.');
      await _refresh();
    });
  }

  Future<void> _clearContext() async {
    if (_working) return;
    if (_diagnostics?.generationActive ?? false) {
      _showMessage('لا يمكن تفريغ سياق النموذج أثناء التوليد.');
      return;
    }
    await _runOperation(() async {
      final result = await rust_api.clearContextMemory();
      if (!result.success) throw StateError(result.message);
      _showMessage(result.message);
      await _refresh();
    });
  }

  Future<void> _runOperation(Future<void> Function() operation) async {
    if (mounted) {
      setState(() {
        _working = true;
        _error = null;
      });
    }
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatBytes(int bytes) => _formatByteCount(bytes);

  @override
  Widget build(BuildContext context) {
    final diagnostics = _diagnostics;
    return Scaffold(
      appBar: AppBar(
        title: const Text('النماذج المحلية'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _working ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : _importModel,
        icon: const Icon(Icons.add_rounded),
        label: const Text('استيراد GGUF'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _RuntimeCard(
                  diagnostics: diagnostics,
                  busy: _working,
                  onUnload: _unloadModel,
                  onClearContext: _clearContext,
                ),
                const SizedBox(height: 12),
                const _RuntimeBenchmarkCard(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorPanel(message: _error!),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'مكتبة النماذج',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${_models.length}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_models.isEmpty)
                  const _EmptyModels()
                else
                  ..._models.map(
                    (model) => _ModelCard(
                      model: model,
                      isActive: _activeModelId == model.id,
                      busy: _working,
                      canLoad:
                          (diagnostics?.nativeEngineAvailable ?? false) &&
                          !(diagnostics?.generationActive ?? false),
                      sizeLabel: _formatBytes(model.fileSizeBytes),
                      onLoad: () => _loadModel(model),
                      onRemove: () => _removeModel(model),
                    ),
                  ),
                const SizedBox(height: 14),
                const Text(
                  'تُحفظ النماذج داخل مساحة Leo الخاصة على الجهاز. لا يجري تنزيلها أو رفعها إلى خادم.',
                  style: TextStyle(
                    color: Colors.white54,
                    height: 1.5,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
    );
  }
}

class _RuntimeCard extends StatelessWidget {
  const _RuntimeCard({
    required this.diagnostics,
    required this.busy,
    required this.onUnload,
    required this.onClearContext,
  });

  final rust_api.RuntimeDiagnosticsDto? diagnostics;
  final bool busy;
  final VoidCallback onUnload;
  final VoidCallback onClearContext;

  @override
  Widget build(BuildContext context) {
    final state = diagnostics;
    return Card(
      color: const Color(0xFF141F31),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory_rounded, color: Color(0xFF9BB0FF)),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'محرك Leo المحلي',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusBadge(available: state?.nativeEngineAvailable ?? false),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              state?.message ?? 'لم تصل بيانات المحرك بعد.',
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            if (state != null && state.nativeEngineVersion != null)
              Text(
                'llama.cpp ${state.nativeEngineVersion}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            if (state != null &&
                (state.residentBytes > 0 || state.peakResidentBytes > 0)) ...[
              const SizedBox(height: 8),
              Text(
                'ذاكرة عملية Leo: ${_formatByteCount(state.residentBytes)} حالياً • '
                'الذروة ${_formatByteCount(state.peakResidentBytes)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Text(
                'القياس يشمل التطبيق كاملاً، وليس أوزان النموذج وحدها.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ],
            if (state?.modelLoaded ?? false) ...[
              const SizedBox(height: 12),
              const Text(
                'يوجد نموذج محمّل في الذاكرة.',
                style: TextStyle(color: Color(0xFF9DE6B4)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy || (state?.generationActive ?? false)
                        ? null
                        : onClearContext,
                    icon: const Icon(Icons.cleaning_services_outlined),
                    label: const Text('تفريغ سياق المحادثة'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || (state?.generationActive ?? false)
                        ? null
                        : onUnload,
                    icon: const Icon(Icons.eject_rounded),
                    label: const Text('تفريغ النموذج'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RuntimeBenchmarkCard extends StatefulWidget {
  const _RuntimeBenchmarkCard();

  @override
  State<_RuntimeBenchmarkCard> createState() => _RuntimeBenchmarkCardState();
}

class _RuntimeBenchmarkCardState extends State<_RuntimeBenchmarkCard> {
  final RuntimeBenchmarkStore _store = RuntimeBenchmarkStore();
  bool _enabled = false;
  bool _loading = true;
  RuntimeBenchmarkSummary _summary = const RuntimeBenchmarkSummary.empty();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final enabled = await _store.isEnabled;
      final summary = await _store.summary();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _summary = summary;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool value) async {
    try {
      await _store.setEnabled(value);
      if (mounted) setState(() => _enabled = value);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث إعداد القياس: $error')),
        );
      }
    }
  }

  Future<void> _clear() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('مسح قياسات الأداء؟'),
            content: const Text(
              'سيحذف Leo سجلات الأداء المحلية المحفوظة على هذا الجهاز.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('مسح'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await _store.clear();
    if (!mounted) return;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Card(
      color: const Color(0xFF141F31),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed_rounded, color: Color(0xFF9BB0FF)),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'قياسات أداء المحرك',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث القياسات',
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: _loading ? null : _setEnabled,
              title: const Text('تفعيل جمع القياسات محلياً'),
              subtitle: const Text(
                'معطّل افتراضياً؛ لا يحفظ المطالبات أو الإجابات أو أسماء النماذج.',
              ),
            ),
            if (_loading)
              const LinearProgressIndicator()
            else if (summary.sampleCount == 0)
              const Text(
                'لا توجد عينات مسجلة بعد.',
                style: TextStyle(color: Colors.white60),
              )
            else ...[
              const Divider(color: Colors.white12),
              _MetricLine(
                label: 'عدد العينات',
                value: '${summary.sampleCount}',
              ),
              _MetricLine(
                label: 'وسيط زمن المحاولة',
                value: '${summary.medianLatencyMilliseconds} ms',
              ),
              _MetricLine(
                label: 'P95 لزمن المحاولة',
                value: '${summary.p95LatencyMilliseconds} ms',
              ),
              _MetricLine(
                label: 'متوسط سرعة الإخراج',
                value:
                    '${summary.averageOutputCharactersPerSecond.toStringAsFixed(1)} حرف/ث',
              ),
              _MetricLine(
                label: 'أعلى ذروة لذاكرة العملية',
                value: _formatByteCount(summary.maximumPeakResidentBytes),
              ),
              _MetricLine(
                label: 'معدل اكتمال التوليد',
                value: '${summary.successRatePercent.toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 4),
              const Text(
                'سرعة الإخراج محسوبة بالأحرف لا بالرموز (Tokens). قياس الذاكرة يشمل عملية Leo كاملة، وليس أوزان النموذج وحدها.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: _clear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('مسح القياسات'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ],
    ),
  );
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.isActive,
    required this.busy,
    required this.canLoad,
    required this.sizeLabel,
    required this.onLoad,
    required this.onRemove,
  });

  final rust_api.ModelSummaryDto model;
  final bool isActive;
  final bool busy;
  final bool canLoad;
  final String sizeLabel;
  final VoidCallback onLoad;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF111B2A),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.model_training_rounded,
                  color: Color(0xFF9BB0FF),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    model.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (isActive)
                  const _StatusBadge(available: true, label: 'محمّل'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$sizeLabel • سياق معلن ${model.contextLength} Token',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (model.architecture != null)
              Text(
                'Architecture: ${model.architecture}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            if (model.sha256 != null)
              Text(
                'SHA-256: ${model.sha256}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy || isActive || !canLoad ? null : onLoad,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('تحميل'),
                ),
                IconButton.outlined(
                  tooltip: 'حذف النموذج',
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.available, this.label});

  final bool available;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = available ? const Color(0xFF8FE0AA) : const Color(0xFFFFBC80);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(
        label ?? (available ? 'متاح' : 'غير متاح'),
        style: TextStyle(color: color, fontSize: 11),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF3A2025),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF7C3A45)),
    ),
    child: Text(message, style: const TextStyle(color: Color(0xFFFFC3C8))),
  );
}

class _EmptyModels extends StatelessWidget {
  const _EmptyModels();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
    decoration: BoxDecoration(
      color: const Color(0xFF101A29),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF27364D)),
    ),
    child: const Column(
      children: [
        Icon(Icons.folder_open_rounded, size: 36, color: Colors.white38),
        SizedBox(height: 10),
        Text('لم تضف نموذجاً محلياً بعد.'),
        SizedBox(height: 5),
        Text(
          'استورد ملف GGUF من جهازك للبدء.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    ),
  );
}

class _ModelLoadDialog extends StatefulWidget {
  const _ModelLoadDialog({
    required this.model,
    required this.contextChoices,
    required this.recommendedThreads,
  });

  final rust_api.ModelSummaryDto model;
  final List<int> contextChoices;
  final int recommendedThreads;

  @override
  State<_ModelLoadDialog> createState() => _ModelLoadDialogState();
}

class _ModelLoadDialogState extends State<_ModelLoadDialog> {
  late int _contextTokens;
  late int _threads;

  @override
  void initState() {
    super.initState();
    _contextTokens = ModelResourcePolicy.defaultContextTokens(
      widget.model.contextLength,
    );
    _threads = widget.recommendedThreads;
  }

  @override
  Widget build(BuildContext context) {
    final requiredMemory = ModelResourcePolicy.estimateRequiredAvailableMemory(
      modelFileSizeBytes: BigInt.from(widget.model.fileSizeBytes),
      contextTokens: _contextTokens,
    );
    final threadChoices = List<int>.generate(
      widget.recommendedThreads,
      (index) => index + 1,
    );

    return AlertDialog(
      title: const Text('تهيئة موارد النموذج'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.model.displayName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            const Text('حجم سياق المحادثة'),
            const SizedBox(height: 4),
            DropdownButton<int>(
              isExpanded: true,
              value: _contextTokens,
              items: widget.contextChoices
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text('$value Token'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _contextTokens = value);
              },
            ),
            const SizedBox(height: 10),
            const Text('خيوط المعالجة CPU'),
            const SizedBox(height: 4),
            DropdownButton<int>(
              isExpanded: true,
              value: _threads,
              items: threadChoices
                  .map(
                    (value) => DropdownMenuItem<int>(
                      value: value,
                      child: Text(
                        value == widget.recommendedThreads
                            ? '$value (موصى به)'
                            : '$value',
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) setState(() => _threads = value);
              },
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF18263A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تقدير الذاكرة المطلوبة',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatBigByteCount(requiredMemory),
                    style: const TextStyle(
                      color: Color(0xFF9DE6B4),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'يشمل حجم ملف GGUF وهامش 12.5% واحتياطياً أساسياً 384 MiB و128 MiB لكل 2048 رمزاً من السياق.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'هذا تقدير أولي وليس قراءة للذاكرة المتاحة حالياً. سيعيد المحرك فحص الذاكرة الفعلية قبل التحميل، وقد يرفض العملية إذا لم تكن كافية.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ModelLoadConfiguration(
              contextTokens: _contextTokens,
              threads: _threads,
            ),
          ),
          child: const Text('تحميل النموذج'),
        ),
      ],
    );
  }
}

String _formatByteCount(int bytes) => _formatByteValue(bytes, bytes.toString());

String _formatBigByteCount(BigInt bytes) =>
    _formatByteValue(bytes.toDouble(), bytes.toString());

String _formatByteValue(num bytes, String exactValue) {
  const mebibyte = 1024 * 1024;
  final value = bytes.toDouble();
  if (value >= mebibyte * 1024) {
    return '${(value / (mebibyte * 1024)).toStringAsFixed(2)} GiB';
  }
  if (value >= mebibyte) return '${(value / mebibyte).toStringAsFixed(1)} MiB';
  return '$exactValue bytes';
}
