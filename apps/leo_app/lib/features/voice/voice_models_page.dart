import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/capabilities/capability_hub_service.dart';
import '../../core/voice/voice_diagnostics.dart';
import '../../core/voice/voice_pack_store.dart';

class VoiceModelsPage extends StatefulWidget {
  const VoiceModelsPage({super.key, this.store});

  final VoicePackStore? store;

  @override
  State<VoiceModelsPage> createState() => _VoiceModelsPageState();
}

class _VoiceModelsPageState extends State<VoiceModelsPage> {
  late final VoicePackStore _store;
  late final CapabilityHubService _capabilityHub;
  final VoiceDiagnosticsStore _diagnostics = VoiceDiagnosticsStore();
  VoicePackStatus? _status;
  VoiceRunMetrics? _asrMetrics;
  VoiceRunMetrics? _ttsMetrics;
  VoiceRuntimePreflightResult? _runtimeResult;
  bool _loading = true;
  bool _importing = false;
  bool _checkingRuntime = false;
  bool _metricsEnabled = false;
  bool _vadAutoStopEnabled = false;
  VoicePackKind? _verifyingKind;
  String? _error;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? VoicePackStore();
    _capabilityHub = CapabilityHubService();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await _store.inspect();
      final metricsEnabled = await _diagnostics.metricsEnabled;
      final vadEnabled = await _diagnostics.vadAutoStopEnabled;
      final asrMetrics = await _diagnostics.readLatest('asr');
      final ttsMetrics = await _diagnostics.readLatest('tts');
      if (!mounted) return;
      setState(() {
        _status = status;
        _metricsEnabled = metricsEnabled;
        _vadAutoStopEnabled = vadEnabled;
        _asrMetrics = asrMetrics;
        _ttsMetrics = ttsMetrics;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر فحص حزم الصوت: $error';
        _loading = false;
      });
    }
  }

  Future<void> _setVadEnabled(bool enabled) async {
    final ready = _status?.voiceActivityDetectionReady ?? false;
    if (enabled && !ready) {
      _message('ثبّت نموذج Silero VAD واجتز فحص سلامته قبل تفعيل الإيقاف التلقائي.');
      return;
    }
    await _diagnostics.setVadAutoStopEnabled(enabled);
    if (mounted) setState(() => _vadAutoStopEnabled = enabled);
  }

  Future<void> _setMetricsEnabled(bool enabled) async {
    await _diagnostics.setMetricsEnabled(enabled);
    if (!enabled) await _diagnostics.clearMetrics();
    if (!mounted) return;
    setState(() {
      _metricsEnabled = enabled;
      if (!enabled) {
        _asrMetrics = null;
        _ttsMetrics = null;
      }
    });
  }

  Future<void> _runRuntimeCheck() async {
    if (_checkingRuntime) return;
    setState(() => _checkingRuntime = true);
    final result = await VoiceRuntimeDiagnostics.checkNativeRuntime();
    if (!mounted) return;
    setState(() {
      _runtimeResult = result;
      _checkingRuntime = false;
    });
  }

  String _formatMetrics(VoiceRunMetrics? metrics) {
    if (metrics == null) return 'لا توجد قياسات محفوظة لهذا المسار بعد.';
    final peakMiB = metrics.processPeakRssBytes / (1024 * 1024);
    return 'تحميل النموذج: ${metrics.modelLoadMilliseconds} ms\n'
        'زمن المعالجة: ${metrics.inferenceMilliseconds} ms\n'
        'أعلى ذاكرة للعملية: ${peakMiB.toStringAsFixed(1)} MiB\n'
        'Sherpa: ${metrics.engineVersion} · ONNX Runtime: ${metrics.onnxRuntimeVersion}\n'
        'المرحلة عند الخطأ: ${metrics.errorStage ?? 'لا يوجد'}';
  }

  Future<void> _import(VoicePackKind kind) async {
    if (_importing) return;
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: switch (kind) {
        VoicePackKind.speechRecognition => const ['onnx'],
        VoicePackKind.speechSynthesis => const ['onnx', 'json', 'bin'],
        VoicePackKind.voiceActivityDetection => const ['onnx'],
      },
      dialogTitle: switch (kind) {
        VoicePackKind.speechRecognition => 'الخطوة 1 من 2: اختر ملفات ONNX من المجلد الرئيسي',
        VoicePackKind.speechSynthesis => 'اختر ملفات حزمة توليد الصوت المستخرجة',
        VoicePackKind.voiceActivityDetection => 'اختر ملف silero_vad.onnx',
      },
    );
    if (!mounted || selected.isEmpty) return;

    final files = <PlatformFile>[...selected];
    if (kind == VoicePackKind.speechRecognition) {
      final tokenizerFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowMultiple: true,
        allowedExtensions: const ['txt', 'json'],
        dialogTitle: 'الخطوة 2 من 2: افتح مجلد tokenizer واختر ملفاته الثلاثة',
      );
      if (!mounted) return;
      if (tokenizerFiles.isEmpty) {
        _message('لم يكتمل الاختيار. اختر ملفات tokenizer الثلاثة لإتمام تثبيت حزمة التعرف.');
        return;
      }
      files.addAll(tokenizerFiles);
    }

    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      await _store.importFiles(kind: kind, files: files);
      await _refresh();
      if (!mounted) return;
      _message(switch (kind) {
        VoicePackKind.speechRecognition => 'تم تثبيت حزمة التعرف على الكلام محلياً.',
        VoicePackKind.speechSynthesis => 'تم تثبيت حزمة توليد الصوت محلياً.',
        VoicePackKind.voiceActivityDetection => 'تم تثبيت نموذج اكتشاف نهاية الكلام محلياً.',
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تثبيت حزمة الصوت: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _verify(VoicePackKind kind) async {
    if (_importing || _verifyingKind != null) return;
    setState(() {
      _verifyingKind = kind;
      _error = null;
    });
    try {
      final result = await _store.verifyIntegrity(kind);
      await _refresh();
      if (!mounted) return;
      if (result.valid) {
        _message(result.createdBaseline
            ? 'أنشأ Leo خط أساس محلياً لبصمات SHA-256 للحزمة القديمة. أعد الفحص لاحقاً؛ البصمات لا تثبت مصدر الملفات.'
            : 'اجتازت ملفات الحزمة فحص SHA-256 المحلي.');
      } else {
        _message('فشل فحص سلامة بعض الملفات: ${result.mismatches.join('، ')}');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'تعذر فحص سلامة حزمة الصوت: $error');
    } finally {
      if (mounted) setState(() => _verifyingKind = null);
    }
  }

  Future<void> _openExternal(String url) async {
    final result = await _capabilityHub.openUrl(context, url);
    if (!mounted || result.success || result.cancelled) return;
    _message(result.message);
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        title: const Text('نماذج الصوت المحلية'),
        actions: [
          IconButton(
            tooltip: 'تحديث الحالة',
            onPressed: _loading || _importing || _verifyingKind != null ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                const _InfoCard(
                  icon: Icons.offline_bolt_rounded,
                  title: 'الصوت يعمل محلياً',
                  body: 'Leo لا يضمّن أوزان النماذج داخل التطبيق. نزّل كل حزمة من مصدرها الرسمي، ثم استورد الملفات. ينشئ Leo بصمات SHA-256 محلية لكشف التغييرات بعد الاستيراد؛ لا تثبت هذه البصمات توقيع الناشر أو أصالة المصدر.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorCard(message: _error!),
                ],
                const SizedBox(height: 16),
                _PackCard(
                  title: 'التعرف على الكلام (ASR)',
                  subtitle: 'Qwen3-ASR 0.6B · Int8',
                  description: 'تحويل كلام المستخدم إلى نص. يدعم النموذج 30 لغة، منها العربية والإنجليزية. اختر ملفات ONNX من المجلد الرئيسي أولاً ثم ملفات مجلد tokenizer. حجم الحزمة يقارب 0.94 GB وقد يكون ثقيلاً على بعض الهواتف.',
                  ready: status?.speechRecognitionReady ?? false,
                  missing: status?.speechRecognitionMissing ?? const [],
                  directory: status?.speechRecognitionDirectory ?? '',
                  integrity: status?.speechRecognitionIntegrity ?? VoicePackIntegrity.unavailable,
                  integrityMessage: status?.speechRecognitionIntegrityMessage ?? 'لم يتم فحص الحزمة.',
                  importing: _importing,
                  verifying: _verifyingKind == VoicePackKind.speechRecognition,
                  onVerify: () => _verify(VoicePackKind.speechRecognition),
                  onImport: () => _import(VoicePackKind.speechRecognition),
                  onOpenDownload: () => _openExternal('https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25.tar.bz2'),
                  onOpenDocs: () => _openExternal('https://k2-fsa.github.io/sherpa/onnx/qwen3-asr/pretrained.html'),
                ),
                const SizedBox(height: 14),
                _PackCard(
                  title: 'اكتشاف نهاية الكلام (VAD)',
                  subtitle: 'Silero VAD · ONNX · 16 kHz',
                  description: 'يكتشف توقف المستخدم عن الكلام ويوقف التسجيل تلقائياً بعد نحو 0.8 ثانية من الصمت. حجم النموذج الرسمي نحو 629 KB. التثبيت والتفعيل اختياريان؛ غيابه لا يعطل التسجيل اليدوي ولا يغيّر حد الثلاثين ثانية.',
                  ready: status?.voiceActivityDetectionReady ?? false,
                  missing: status?.voiceActivityDetectionMissing ?? const [],
                  directory: status?.voiceActivityDetectionDirectory ?? '',
                  integrity: status?.voiceActivityDetectionIntegrity ?? VoicePackIntegrity.unavailable,
                  integrityMessage: status?.voiceActivityDetectionIntegrityMessage ?? 'لم يتم فحص الحزمة.',
                  importing: _importing,
                  verifying: _verifyingKind == VoicePackKind.voiceActivityDetection,
                  onVerify: () => _verify(VoicePackKind.voiceActivityDetection),
                  onImport: () => _import(VoicePackKind.voiceActivityDetection),
                  onOpenDownload: () => _openExternal('https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx'),
                  onOpenDocs: () => _openExternal('https://k2-fsa.github.io/sherpa/onnx/vad/silero-vad.html'),
                ),
                const SizedBox(height: 14),
                _PackCard(
                  title: 'تحويل النص إلى كلام (TTS)',
                  subtitle: 'Supertonic 3 · Int8',
                  description: 'توليد صوت عربي وإنجليزي محلياً. يختار Leo العربية أو الإنجليزية تلقائياً في هذا الإصدار ويستخدم معرّف الصوت الافتراضي 0.',
                  ready: status?.speechSynthesisReady ?? false,
                  missing: status?.speechSynthesisMissing ?? const [],
                  directory: status?.speechSynthesisDirectory ?? '',
                  integrity: status?.speechSynthesisIntegrity ?? VoicePackIntegrity.unavailable,
                  integrityMessage: status?.speechSynthesisIntegrityMessage ?? 'لم يتم فحص الحزمة.',
                  importing: _importing,
                  verifying: _verifyingKind == VoicePackKind.speechSynthesis,
                  onVerify: () => _verify(VoicePackKind.speechSynthesis),
                  onImport: () => _import(VoicePackKind.speechSynthesis),
                  onOpenDownload: () => _openExternal('https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2'),
                  onOpenDocs: () => _openExternal('https://k2-fsa.github.io/sherpa/onnx/tts/all/Arabic/supertonic-3-ar.html'),
                ),
                const SizedBox(height: 14),
                Card(
                  color: const Color(0xFF18253A),
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile.adaptive(
                        title: const Text('الإيقاف التلقائي بعد انتهاء الكلام'),
                        subtitle: Text(status?.voiceActivityDetectionReady == true
                            ? 'يتوقف التسجيل بعد اكتشاف الصمت. يظل زر الإيقاف وحد 30 ثانية متاحين.'
                            : 'ثبّت نموذج Silero VAD أولاً. التسجيل اليدوي سيظل يعمل.'),
                        value: _vadAutoStopEnabled,
                        onChanged: status?.voiceActivityDetectionReady == true || _vadAutoStopEnabled
                            ? (value) => unawaited(_setVadEnabled(value))
                            : null,
                      ),
                      const Divider(height: 1),
                      SwitchListTile.adaptive(
                        title: const Text('قياسات الأداء المحلية (اختيارية)'),
                        subtitle: const Text('تحفظ زمن تحميل النموذج والمعالجة وقمة ذاكرة العملية وإصدارات المحرك فقط، دون تسجيل الصوت أو النص.'),
                        value: _metricsEnabled,
                        onChanged: (value) => unawaited(_setMetricsEnabled(value)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _checkingRuntime ? null : _runRuntimeCheck,
                                icon: _checkingRuntime
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.health_and_safety_outlined),
                                label: Text(_checkingRuntime ? 'يفحص مكتبة المحرك...' : 'فحص مكتبة المحرك الأصلية'),
                              ),
                            ),
                            if (_runtimeResult != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _runtimeResult!.success
                                    ? 'المحرك متاح · Sherpa ${_runtimeResult!.engineVersion} · ONNX ${_runtimeResult!.onnxRuntimeVersion} · ${_runtimeResult!.elapsedMilliseconds} ms'
                                    : 'فشل تحميل المحرك بعد ${_runtimeResult!.elapsedMilliseconds} ms: ${_runtimeResult!.error}',
                                style: TextStyle(
                                  color: _runtimeResult!.success ? const Color(0xFF72D6A1) : const Color(0xFFFFA9B5),
                                  height: 1.5,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (_metricsEnabled) ...[
                              const SizedBox(height: 12),
                              Text('آخر قياس للتعرف على الكلام (ASR)\n${_formatMetrics(_asrMetrics)}', style: const TextStyle(fontSize: 12, height: 1.5)),
                              const SizedBox(height: 10),
                              Text('آخر قياس لتوليد الصوت (TTS)\n${_formatMetrics(_ttsMetrics)}', style: const TextStyle(fontSize: 12, height: 1.5)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const _InfoCard(
                  icon: Icons.mic_none_rounded,
                  title: 'إذن الميكروفون',
                  body: 'لا يطلب Leo الإذن عند التثبيت أو التشغيل. يظهر طلب Android عند ضغط زر الميكروفون لأول مرة. على Windows يجب السماح بالميكروفون لتطبيقات سطح المكتب من إعدادات الخصوصية.',
                ),
                const SizedBox(height: 14),
                const _InfoCard(
                  icon: Icons.info_outline_rounded,
                  title: 'حدود الإصدار Alpha',
                  body: 'يبقى التسجيل يدوياً عند تعطيل VAD أو تعذّر تحميله. حد التسجيل 30 ثانية، والنص الناتج يعود إلى مربع الكتابة دون إرسال تلقائي. لا يوجد Wake Word أو استماع في الخلفية، كما أن TTS لا يزال ينشئ ملف الصوت كاملاً قبل التشغيل.',
                ),
              ],
            ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.ready,
    required this.missing,
    required this.directory,
    required this.integrity,
    required this.integrityMessage,
    required this.importing,
    required this.verifying,
    required this.onVerify,
    required this.onImport,
    required this.onOpenDownload,
    required this.onOpenDocs,
  });

  final String title;
  final String subtitle;
  final String description;
  final bool ready;
  final List<String> missing;
  final String directory;
  final VoicePackIntegrity integrity;
  final String integrityMessage;
  final bool importing;
  final bool verifying;
  final VoidCallback onVerify;
  final VoidCallback onImport;
  final VoidCallback onOpenDownload;
  final VoidCallback onOpenDocs;

  @override
  Widget build(BuildContext context) {
    final color = ready ? const Color(0xFF72D6A1) : const Color(0xFFFFC58F);
    return Card(
      color: const Color(0xFF121C2B),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Icon(ready ? Icons.check_circle_rounded : Icons.download_for_offline_outlined,
                    color: color),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Color(0xFF9BAAC0), fontSize: 12)),
            const SizedBox(height: 10),
            Text(description, style: const TextStyle(height: 1.5)),
            const SizedBox(height: 12),
            Text(
              ready
                  ? 'الحزمة مثبتة. $integrityMessage'
                  : missing.isNotEmpty
                      ? 'الملفات الناقصة: ${missing.join('، ')}'
                      : integrityMessage,
              style: TextStyle(color: integrity == VoicePackIntegrity.failed ? const Color(0xFFFFA9B5) : color, fontSize: 12, height: 1.45),
            ),
            if (ready) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: importing || verifying ? null : onVerify,
                  icon: verifying
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(verifying ? 'جارٍ فحص الملفات...' : 'فحص بصمات الملفات'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SelectableText('مجلد الحزمة: $directory',
                style: const TextStyle(fontSize: 11, color: Color(0xFF8796AC))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: onOpenDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('فتح التنزيل الرسمي'),
                ),
                TextButton.icon(
                  onPressed: onOpenDocs,
                  icon: const Icon(Icons.menu_book_rounded, size: 18),
                  label: const Text('دليل النموذج'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: importing || verifying ? null : onImport,
                icon: importing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.drive_folder_upload_outlined),
                label: Text(ready ? 'استبدال الحزمة' : 'اختيار الملفات وتثبيتها'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF18253A),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFF9BB0FF)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(body, style: const TextStyle(height: 1.5, color: Color(0xFFD0D9E8))),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF3B2530),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(message, style: const TextStyle(color: Color(0xFFFFCFD7))),
        ),
      );
}
