import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/chat/assistant_runtime_client.dart';
import '../../core/skills/skill_execution_service.dart';
import '../../core/skills/skill_learning_service.dart';
import '../../core/skills/skill_markdown_codec.dart';
import '../../core/skills/skill_models.dart';
import '../../core/skills/skill_repository.dart';

class SkillLibraryPage extends StatefulWidget {
  const SkillLibraryPage({
    super.key,
    this.repository,
    this.runRepository,
    this.runtime,
  });

  final SkillRepository? repository;
  final SkillRunRepository? runRepository;
  final AssistantRuntimeClient? runtime;

  @override
  State<SkillLibraryPage> createState() => _SkillLibraryPageState();
}

class _SkillLibraryPageState extends State<SkillLibraryPage> {
  late final SkillRepository _repository;
  late final SkillRunRepository _runRepository;
  List<LeoSkill> _skills = const [];
  List<LeoSkillRunRecord> _runs = const [];
  bool _loading = true;
  bool _working = false;
  String? _error;
  LeoSkillStatus? _filter;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FileSkillRepository();
    _runRepository = widget.runRepository ?? SkillRunRepository();
    _refresh();
  }

  Future<void> _importSkill() async {
    if (_working) return;
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['md'],
      );
      if (file == null) return;
      final length = await file.length();
      if (length > SkillMarkdownCodec.maxDocumentCharacters) {
        _message('ملف المهارة أكبر من الحد المسموح (64 كيلوبايت).');
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > SkillMarkdownCodec.maxDocumentCharacters) {
        _message('ملف المهارة أكبر من الحد المسموح (64 كيلوبايت).');
        return;
      }
      final document = utf8.decode(bytes, allowMalformed: false);
      final imported = SkillMarkdownCodec.decode(document);
      await _run(() async {
        final existing = await _repository.list();
        final duplicate = existing.any((skill) =>
            skill.name.trim().toLowerCase() == imported.name.trim().toLowerCase() &&
            skill.description.trim() == imported.description.trim());
        if (duplicate) {
          throw StateError('توجد مهارة مطابقة في المكتبة بالفعل.');
        }
        await _repository.createProposal(
          name: imported.name,
          description: imported.description,
          triggers: imported.triggers,
          instructions: imported.instructions,
          steps: imported.steps,
          testCases: imported.testCases,
          requiredCapabilities: imported.requiredCapabilities,
          sourceTaskId: null,
        );
        _message('تم استيراد المهارة كاقتراح غير نشط. راجعها وافحصها قبل اعتمادها.');
        await _refresh();
      });
    } on FormatException catch (error) {
      _message('ملف SKILL.md غير صالح: ${error.message}');
    } catch (error) {
      _message('تعذر استيراد المهارة: $error');
    }
  }

  Future<void> _exportSkill(LeoSkill skill) async {
    if (_working) return;
    try {
      final content = SkillMarkdownCodec.encode(skill);
      final safeName = skill.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'-+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
      final fileName = '${safeName.isEmpty ? 'leo-skill' : safeName}.md';
      final result = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(content)),
        dialogTitle: 'تصدير مهارة Leo',
      );
      if (result != null) _message('تم تصدير المهارة بصيغة SKILL.md.');
    } catch (error) {
      _message('تعذر تصدير المهارة: $error');
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final skills = await _repository.list();
      List<LeoSkillRunRecord> runs = const [];
      try {
        runs = await _runRepository.list();
      } catch (_) {
        // A damaged optional run-history value must not hide the skill library.
      }
      if (!mounted) return;
      setState(() {
        _skills = skills;
        _runs = runs;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر فتح مكتبة المهارات المحلية: $error';
      });
    }
  }

  List<LeoSkill> get _visibleSkills => _filter == null
      ? _skills
      : _skills.where((skill) => skill.status == _filter).toList();

  Future<void> _createSkill() async {
    final draft = await showDialog<_SkillDraft>(
      context: context,
      builder: (_) => const _SkillEditorDialog(),
    );
    if (draft == null) return;
    await _run(() async {
      await _repository.createProposal(
        name: draft.name,
        description: draft.description,
        triggers: draft.triggers,
        instructions: draft.instructions,
        steps: draft.steps,
        testCases: draft.testCases,
        requiredCapabilities: draft.requiredCapabilities,
        sourceTaskId: draft.sourceTaskId,
      );
      _message('تم حفظ المهارة كاقتراح. لن تستخدمها Leo قبل الفحص واعتمادك.');
      await _refresh();
    });
  }

  Future<void> _editSkill(LeoSkill skill) async {
    final draft = await showDialog<_SkillDraft>(
      context: context,
      builder: (_) => _SkillEditorDialog(skill: skill),
    );
    if (draft == null) return;
    await _run(() async {
      await _repository.updateProposal(
        skillId: skill.id,
        name: draft.name,
        description: draft.description,
        triggers: draft.triggers,
        instructions: draft.instructions,
        steps: draft.steps,
        testCases: draft.testCases,
        requiredCapabilities: draft.requiredCapabilities,
        changeSummary: draft.changeSummary,
      );
      _message('تم إنشاء إصدار جديد كاقتراح. الإصدار السابق محفوظ في سجل المهارة.');
      await _refresh();
    });
  }

  Future<void> _validate(LeoSkill skill) async {
    await _run(() async {
      final updated = await _repository.validate(skill.id);
      _message(updated.isValidated
          ? 'اجتاز الفحص البنيوي الأولي. راجع التقرير قبل الاعتماد.'
          : 'لم تجتز المهارة جميع شروط الفحص. راجع النقاط المطلوبة.');
      await _refresh();
    });
  }

  Future<void> _activate(LeoSkill skill) async {
    final confirmed = await _confirm(
      title: 'اعتماد المهارة؟',
      message:
          'ستصبح هذه المهارة متاحة للاسترجاع في المحادثات المستقبلية. اعتمادها لا يمنحها صلاحيات جهاز ولا ينفذ أوامر تلقائياً.',
      confirmLabel: 'اعتماد',
    );
    if (!confirmed) return;
    await _run(() async {
      await _repository.activate(skill.id);
      _message('تم اعتماد المهارة وإتاحتها للاسترجاع عند الحاجة.');
      await _refresh();
    });
  }

  Future<void> _disable(LeoSkill skill) async {
    await _run(() async {
      await _repository.disable(skill.id);
      _message('تم إيقاف استخدام المهارة.');
      await _refresh();
    });
  }

  Future<void> _reject(LeoSkill skill) async {
    final confirmed = await _confirm(
      title: 'رفض الاقتراح؟',
      message: 'سيتم استبعاد المهارة من الاستخدام. يمكنك حذفها لاحقاً.',
      confirmLabel: 'رفض الاقتراح',
    );
    if (!confirmed) return;
    await _run(() async {
      await _repository.reject(skill.id);
      _message('تم رفض اقتراح المهارة.');
      await _refresh();
    });
  }

  Future<void> _delete(LeoSkill skill) async {
    final confirmed = await _confirm(
      title: 'حذف المهارة نهائياً؟',
      message: 'سيتم حذف تعريف المهارة وسجل إصداراتها من هذا الجهاز.',
      confirmLabel: 'حذف نهائياً',
    );
    if (!confirmed) return;
    await _run(() async {
      await _repository.delete(skill.id);
      _message('تم حذف المهارة.');
      await _refresh();
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<void> Function() operation) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await operation();
    } catch (error) {
      _message('تعذر تنفيذ العملية: $error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final skills = _visibleSkills;
    return Scaffold(
      appBar: AppBar(
        title: const Text('مهارات Leo'),
        actions: [
          IconButton(
            tooltip: 'استيراد SKILL.md',
            onPressed: _working || _loading ? null : _importSkill,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _working || _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : _createSkill,
        icon: const Icon(Icons.add_rounded),
        label: const Text('تعلم مهارة'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const _SkillSafetyNotice(),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  _filterChip('الكل', null),
                  _filterChip('مقترحة', LeoSkillStatus.proposed),
                  _filterChip('قيد الفحص', LeoSkillStatus.testing),
                  _filterChip('نشطة', LeoSkillStatus.active),
                  _filterChip('متوقفة', LeoSkillStatus.disabled),
                  _filterChip('مرفوضة', LeoSkillStatus.rejected),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorPanel(message: _error!, onRetry: _refresh)
                      : skills.isEmpty
                          ? _EmptySkills(onCreate: _createSkill)
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                              itemCount: skills.length,
                              itemBuilder: (context, index) =>
                                  _skillCard(skills[index]),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, LeoSkillStatus? status) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: FilterChip(
          label: Text(label),
          selected: _filter == status,
          onSelected: _working
              ? null
              : (_) => setState(() => _filter = status),
        ),
      );

  Widget _skillCard(LeoSkill skill) {
    final color = _statusColor(skill.status);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: const Color(0xFF121C2B),
      child: ExpansionTile(
        key: PageStorageKey<String>(skill.id),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .14),
          child: Icon(Icons.auto_awesome_motion_rounded, color: color),
        ),
        title: Text(skill.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${skill.description}\nالإصدار ${skill.version} • ${_statusLabel(skill.status)}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: skill.triggers
                  .map((trigger) => Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(trigger),
                      ))
                  .toList(growable: false),
            ),
          ),
          if (skill.sourceTaskId != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('مصدر التعلم: ${skill.sourceTaskId}'),
            ),
          if (skill.validationReport != null)
            _ValidationReportView(report: skill.validationReport!),
          _skillRunHistory(skill),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _actionsFor(skill),
          ),
          if (skill.history.isNotEmpty) ...[
            const Divider(height: 24),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('سجل الإصدارات (${skill.history.length})',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final item in skill.history.reversed.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded, size: 18),
                title: Text('v${item.version}'),
                subtitle: Text(item.changeSummary),
              ),
          ],
        ],
      ),
    );
  }

  Widget _skillRunHistory(LeoSkill skill) {
    final runs = _runs.where((run) => run.skillId == skill.id).take(5).toList();
    if (runs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        Text('سجل التشغيل والمراجعة', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final run in runs) ...[
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(_runStatusIcon(run.status), color: _runStatusColor(run.status)),
            title: Text(_runStatusLabel(run.status)),
            subtitle: Text(
              '${run.skillVersion} • ${run.toolApprovals} إجراءات وافق عليها المستخدم\n${run.lastEvent}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (run.status == LeoSkillRunStatus.awaitingReview ||
              run.status == LeoSkillRunStatus.needsChanges) ...[
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                'راجع كل خطوة بناءً على النتيجة الفعلية. تأكيدك يسجل مراجعتك ولا يمثل فحصاً تقنياً مستقلاً.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
            for (final step in run.steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${step.index + 1}. ${step.instruction}'),
                    if (step.status != LeoSkillStepReviewStatus.pending)
                      Text(
                        step.status == LeoSkillStepReviewStatus.confirmed
                            ? 'أكد المستخدم اكتمال الخطوة'
                            : 'أفاد المستخدم أن الخطوة لم تكتمل',
                        style: const TextStyle(fontSize: 11, color: Colors.white60),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _working || step.status == LeoSkillStepReviewStatus.confirmed
                              ? null
                              : () => _reviewSkillStep(run, step, LeoSkillStepReviewStatus.confirmed),
                          icon: const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text('تم'),
                        ),
                        TextButton.icon(
                          onPressed: _working || step.status == LeoSkillStepReviewStatus.notCompleted
                              ? null
                              : () => _reviewSkillStep(run, step, LeoSkillStepReviewStatus.notCompleted),
                          icon: const Icon(Icons.error_outline, size: 18),
                          label: const Text('لم يتم'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
          if (run.status == LeoSkillRunStatus.verified && widget.runtime != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _working ? null : () => _learnFromCompletedRun(run),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('استخلاص مهارة من هذا التشغيل'),
              ),
            ),
          const Divider(height: 16),
        ],
      ],
    );
  }

  Future<void> _learnFromCompletedRun(LeoSkillRunRecord run) async {
    final runtime = widget.runtime;
    if (runtime == null || _working) return;
    final approved = await _confirm(
      title: 'استخلاص مهارة من سير عمل مكتمل؟',
      message:
          'سيُرسل إلى نموذج Leo المحلي ملخص إجرائي منقّح فقط: اسم المهارة ووصفها والخطوات التي أكدت اكتمالها. لن تُرسل المحادثة أو هدف المهمة أو الملاحظات أو نتائج الأدوات أو معاملات الأدوات أو أسماء الملفات أو المسارات أو محتوياتها. تزال الأنماط الشائعة للبريد والروابط والأرقام والرموز السرية قبل التحليل، وقد لا يكتشف المنقّح كل معلومات الهوية؛ راجع الاقتراح الناتج قبل استخدامه. سيُحفظ الاقتراح غير نشط ولن يكتسب قدرات جديدة.',
      confirmLabel: 'استخلاص محلي',
    );
    if (!approved || !mounted) return;
    await _run(() async {
      final proposal = await SkillLearningService(
        runtime: runtime,
        repository: _repository,
        runRepository: _runRepository,
      ).proposeFromVerifiedRun(run.taskId);
      _message('تم إنشاء اقتراح مهارة من سير العمل: ${proposal.name}. راجعه وافحصه قبل الاعتماد.');
      await _refresh();
    });
  }

  Future<void> _reviewSkillStep(
    LeoSkillRunRecord run,
    LeoSkillStepReview step,
    LeoSkillStepReviewStatus status,
  ) async {
    await _run(() async {
      final updated = await _runRepository.reviewStep(
        taskId: run.taskId,
        stepIndex: step.index,
        status: status,
      );
      _message(switch (updated.status) {
        LeoSkillRunStatus.verified => 'اكتملت مراجعة جميع خطوات المهارة حسب تأكيدك.',
        LeoSkillRunStatus.needsChanges => 'توجد خطوات لم تكتمل؛ لا تُسجل المهارة كتشغيل ناجح.',
        _ => 'تم تسجيل مراجعة الخطوة. أكمل مراجعة بقية الخطوات.',
      });
      await _refresh();
    });
  }

  String _runStatusLabel(LeoSkillRunStatus status) => switch (status) {
        LeoSkillRunStatus.running => 'قيد التنفيذ',
        LeoSkillRunStatus.paused => 'متوقفة مؤقتاً — قابلة للاستعادة من المحادثة',
        LeoSkillRunStatus.awaitingApproval => 'ينتظر موافقة إجراء',
        LeoSkillRunStatus.awaitingReview => 'ينتظر مراجعة الخطوات',
        LeoSkillRunStatus.verified => 'أكد المستخدم اكتمال الخطوات',
        LeoSkillRunStatus.needsChanges => 'توجد خطوات غير مكتملة',
        LeoSkillRunStatus.failed => 'فشل التشغيل',
        LeoSkillRunStatus.cancelled => 'أُلغي التشغيل',
      };

  IconData _runStatusIcon(LeoSkillRunStatus status) => switch (status) {
        LeoSkillRunStatus.running => Icons.sync_rounded,
        LeoSkillRunStatus.paused => Icons.pause_circle_outline,
        LeoSkillRunStatus.awaitingApproval => Icons.lock_clock_outlined,
        LeoSkillRunStatus.awaitingReview => Icons.rate_review_outlined,
        LeoSkillRunStatus.verified => Icons.verified_outlined,
        LeoSkillRunStatus.needsChanges => Icons.warning_amber_rounded,
        LeoSkillRunStatus.failed => Icons.error_outline,
        LeoSkillRunStatus.cancelled => Icons.cancel_outlined,
      };

  Color _runStatusColor(LeoSkillRunStatus status) => switch (status) {
        LeoSkillRunStatus.running => Colors.blueAccent,
        LeoSkillRunStatus.paused => Colors.blueGrey,
        LeoSkillRunStatus.awaitingApproval => Colors.orangeAccent,
        LeoSkillRunStatus.awaitingReview => Colors.amber,
        LeoSkillRunStatus.verified => Colors.greenAccent,
        LeoSkillRunStatus.needsChanges => Colors.deepOrangeAccent,
        LeoSkillRunStatus.failed || LeoSkillRunStatus.cancelled => Colors.redAccent,
      };

  List<Widget> _actionsFor(LeoSkill skill) {
    final actions = <Widget>[];
    if (skill.status == LeoSkillStatus.proposed ||
        skill.status == LeoSkillStatus.testing) {
      actions.add(OutlinedButton.icon(
        onPressed: _working ? null : () => _validate(skill),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('فحص مبدئي'),
      ));
      if (skill.isValidated) {
        actions.add(FilledButton.icon(
          onPressed: _working ? null : () => _activate(skill),
          icon: const Icon(Icons.verified_outlined),
          label: const Text('اعتماد'),
        ));
      }
      actions.add(TextButton(
        onPressed: _working ? null : () => _editSkill(skill),
        child: const Text('تعديل'),
      ));
      actions.add(TextButton(
        onPressed: _working ? null : () => _reject(skill),
        child: const Text('رفض'),
      ));
    }
    if (skill.status == LeoSkillStatus.active) {
      actions.add(OutlinedButton.icon(
        onPressed: _working ? null : () => _disable(skill),
        icon: const Icon(Icons.pause_rounded),
        label: const Text('إيقاف الاستخدام'),
      ));
    }
    if (skill.status == LeoSkillStatus.disabled) {
      actions.add(FilledButton.icon(
        onPressed: _working || !skill.isValidated
            ? null
            : () => _activate(skill),
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('إعادة التفعيل'),
      ));
      actions.add(TextButton(
        onPressed: _working ? null : () => _editSkill(skill),
        child: const Text('إنشاء إصدار جديد'),
      ));
    }
    actions.add(OutlinedButton.icon(
      onPressed: _working ? null : () => _exportSkill(skill),
      icon: const Icon(Icons.file_download_outlined),
      label: const Text('تصدير SKILL.md'),
    ));
    actions.add(TextButton.icon(
      onPressed: _working ? null : () => _delete(skill),
      icon: const Icon(Icons.delete_outline_rounded),
      label: const Text('حذف'),
    ));
    return actions;
  }
}

class _SkillSafetyNotice extends StatelessWidget {
  const _SkillSafetyNotice();

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF18263A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF30435E)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined, size: 20, color: Color(0xFF9BB0FF)),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'المهارات تحفظ طرق العمل وتُسترجع عند ملاءمتها. يمكنك استيرادها وتصديرها كملفات SKILL.md نصية؛ لا تُستورد السكربتات أو الملفات التنفيذية. الفحص الحالي بنيوي فقط ولا يشغّل أمثلة الاختبار. لا تمنح المهارة صلاحيات الجهاز، وتظل الموافقات مطلوبة للإجراءات الحساسة. تُحفظ البيانات في مساحة التطبيق الخاصة دون تشفير مستقل حالياً.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      );
}

class _ValidationReportView extends StatelessWidget {
  const _ValidationReportView({required this.report});

  final LeoSkillValidationReport report;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: report.passed
              ? const Color(0xFF173327)
              : const Color(0xFF382629),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  report.passed ? Icons.check_circle : Icons.error_outline,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(report.passed
                      ? 'اجتاز الفحص البنيوي الأولي'
                      : 'الفحص يحتاج إلى تعديلات'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final check in report.checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      check.passed ? Icons.check : Icons.close,
                      size: 16,
                      color: check.passed
                          ? const Color(0xFF72D6A2)
                          : const Color(0xFFFFA4A4),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '${check.title}: ${check.details}',
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              report.disclaimer,
              style: const TextStyle(fontSize: 11, color: Color(0xFFC0CBDC)),
            ),
          ],
        ),
      );
}

class _EmptySkills extends StatelessWidget {
  const _EmptySkills({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_motion_rounded,
                  size: 48, color: Color(0xFF8292AB)),
              const SizedBox(height: 14),
              const Text('مكتبة المهارات فارغة حالياً'),
              const SizedBox(height: 8),
              const Text(
                'أضف طريقة عمل تريد من Leo تذكرها، ثم افحصها واعتمدها حتى تصبح قابلة للاسترجاع.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF9AAAC2), height: 1.5),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('إنشاء أول مهارة'),
              ),
            ],
          ),
        ),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
}

class _SkillDraft {
  const _SkillDraft({
    required this.name,
    required this.description,
    required this.triggers,
    required this.instructions,
    required this.steps,
    required this.testCases,
    required this.requiredCapabilities,
    this.sourceTaskId,
    this.changeSummary = '',
  });

  final String name;
  final String description;
  final List<String> triggers;
  final String instructions;
  final List<String> steps;
  final List<LeoSkillTestCase> testCases;
  final List<String> requiredCapabilities;
  final String? sourceTaskId;
  final String changeSummary;
}

class _SkillEditorDialog extends StatefulWidget {
  const _SkillEditorDialog({this.skill});

  final LeoSkill? skill;

  @override
  State<_SkillEditorDialog> createState() => _SkillEditorDialogState();
}

class _SkillEditorDialogState extends State<_SkillEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _triggers;
  late final TextEditingController _instructions;
  late final TextEditingController _steps;
  late final TextEditingController _tests;
  late final TextEditingController _capabilities;
  late final TextEditingController _sourceTask;
  late final TextEditingController _changeSummary;

  @override
  void initState() {
    super.initState();
    final skill = widget.skill;
    _name = TextEditingController(text: skill?.name ?? '');
    _description = TextEditingController(text: skill?.description ?? '');
    _triggers = TextEditingController(text: skill?.triggers.join('\n') ?? '');
    _instructions = TextEditingController(text: skill?.instructions ?? '');
    _steps = TextEditingController(text: skill?.steps.join('\n') ?? '');
    _tests = TextEditingController(
      text: skill?.testCases
              .map((item) => '${item.input} => ${item.expectedOutcome}')
              .join('\n') ??
          '',
    );
    _capabilities = TextEditingController(
        text: skill?.requiredCapabilities.join(', ') ?? '');
    _sourceTask = TextEditingController(text: skill?.sourceTaskId ?? '');
    _changeSummary = TextEditingController();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _triggers,
      _instructions,
      _steps,
      _tests,
      _capabilities,
      _sourceTask,
      _changeSummary,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _lines(TextEditingController controller) => controller.text
      .split('\n')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);

  List<String> _commaSeparated(TextEditingController controller) =>
      controller.text
          .split(RegExp(r'[,;\n]+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);

  List<LeoSkillTestCase> _testCases() {
    final result = <LeoSkillTestCase>[];
    for (final line in _tests.text.split('\n')) {
      final separator = line.indexOf('=>');
      if (separator < 0) continue;
      final input = line.substring(0, separator).trim();
      final expected = line.substring(separator + 2).trim();
      if (input.isEmpty || expected.isEmpty) continue;
      result.add(LeoSkillTestCase(input: input, expectedOutcome: expected));
    }
    return result;
  }

  void _save() {
    if (_name.text.trim().isEmpty || _description.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      _SkillDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        triggers: _lines(_triggers),
        instructions: _instructions.text.trim(),
        steps: _lines(_steps),
        testCases: _testCases(),
        requiredCapabilities: _commaSeparated(_capabilities),
        sourceTaskId: _sourceTask.text.trim().isEmpty
            ? null
            : _sourceTask.text.trim(),
        changeSummary: _changeSummary.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.skill == null ? 'تعليم مهارة جديدة' : 'تحديث المهارة'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(_name, 'اسم المهارة', maxLines: 1),
                _field(_description, 'وصف مختصر', maxLines: 2),
                _field(_triggers, 'متى يستدعي Leo المهارة؟ (كل عبارة في سطر)', maxLines: 3),
                _field(_instructions, 'التعليمات العامة', maxLines: 5),
                _field(_steps, 'خطوات العمل (كل خطوة في سطر)', maxLines: 5),
                _field(
                  _tests,
                  'أمثلة الفحص: الطلب => النتيجة المتوقعة (كل مثال في سطر)',
                  maxLines: 4,
                ),
                _field(_capabilities, 'معرفات القدرات المطلوبة (اختياري)', maxLines: 2),
                if (widget.skill == null)
                  _field(_sourceTask, 'معرف المهمة المصدر (اختياري)', maxLines: 1)
                else
                  _field(_changeSummary, 'ملخص التغيير في هذا الإصدار', maxLines: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(onPressed: _save, child: const Text('حفظ كاقتراح')),
        ],
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          minLines: maxLines == 1 ? 1 : maxLines,
          maxLines: maxLines,
          textDirection: TextDirection.rtl,
          decoration: InputDecoration(
            labelText: label,
            alignLabelWithHint: maxLines > 1,
            filled: true,
            fillColor: const Color(0xFF0E1725),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
}

Color _statusColor(LeoSkillStatus status) => switch (status) {
      LeoSkillStatus.proposed => const Color(0xFFFFC66D),
      LeoSkillStatus.testing => const Color(0xFF9BB0FF),
      LeoSkillStatus.active => const Color(0xFF72D6A2),
      LeoSkillStatus.disabled => const Color(0xFF9AAAC2),
      LeoSkillStatus.rejected => const Color(0xFFFF9292),
    };

String _statusLabel(LeoSkillStatus status) => switch (status) {
      LeoSkillStatus.proposed => 'مقترحة',
      LeoSkillStatus.testing => 'قيد الفحص',
      LeoSkillStatus.active => 'نشطة',
      LeoSkillStatus.disabled => 'متوقفة',
      LeoSkillStatus.rejected => 'مرفوضة',
    };
