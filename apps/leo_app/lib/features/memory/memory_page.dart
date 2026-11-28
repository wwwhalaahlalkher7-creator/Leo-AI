import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import '../../core/memory/memory_repository.dart';
import '../../core/memory/memory_backup_service.dart';
import '../../core/memory/memory_intelligence_service.dart';

class MemoryPage extends StatefulWidget {
  const MemoryPage({
    super.key,
    this.repository,
    this.suggestionContent,
    this.suggestionSourceReference,
  });

  final MemoryRepository? repository;
  final String? suggestionContent;
  final String? suggestionSourceReference;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  late final MemoryRepository _repository;
  final _searchController = TextEditingController();
  List<LeoMemoryEntry> _entries = const [];
  List<LeoMemorySearchHit> _searchHits = const [];
  String? _error;
  bool _loading = true;
  bool _working = false;
  bool _searching = false;
  bool _showSearchResults = false;
  _MemoryFilter _filter = _MemoryFilter.all;
  final MemoryIntelligenceService _intelligence =
      const MemoryIntelligenceService();

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? LocalMemoryRepository();
    _refresh();
    if (widget.suggestionContent?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reviewSuggestedMemory();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _showSearchResults = false;
      });
    }
    try {
      final entries = await _repository.list(includePending: true, limit: 200);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر الوصول إلى الذاكرة المحلية: $error';
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      await _refresh();
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final hits = await _repository.search(query, limit: 20);
      if (!mounted) return;
      setState(() {
        _searchHits = hits;
        _showSearchResults = true;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = 'تعذر البحث في الذاكرة: $error';
      });
    }
  }

  List<LeoMemoryEntry> get _visibleEntries {
    return _entries
        .where((entry) {
          switch (_filter) {
            case _MemoryFilter.all:
              return true;
            case _MemoryFilter.active:
              return entry.userApproved && entry.active;
            case _MemoryFilter.pending:
              return !entry.userApproved;
            case _MemoryFilter.disabled:
              return entry.userApproved && !entry.active;
          }
        })
        .toList(growable: false);
  }

  Future<void> _reviewSuggestedMemory() async {
    await _refresh();
    if (!mounted) return;
    final draft = await showDialog<_MemoryDraft>(
      context: context,
      builder: (context) => _MemoryEditorDialog(
        initialContent: widget.suggestionContent,
        initialSourceReference: widget.suggestionSourceReference,
        proposeOnly: true,
      ),
    );
    if (draft == null) return;
    await _run(() async {
      final findings = _intelligence.reviewCandidate(
        content: draft.content,
        kind: draft.kind,
        existing: _entries,
      );
      if (findings.any(
        (finding) =>
            finding.kind == MemoryFindingKind.duplicate &&
            finding.similarity >= .999,
      )) {
        _showMessage('توجد ذاكرة مطابقة؛ لم يُنشأ اقتراح مكرر.');
        return;
      }
      if (findings.isNotEmpty && !await _reviewFindings(findings)) return;
      await _repository.propose(
        kind: draft.kind,
        content: draft.content,
        tags: draft.tags,
        sourceReference: draft.sourceReference,
      );
      _showMessage(
        'أُضيف اقتراح الذاكرة إلى قائمة المراجعة. لن يستخدمه Leo قبل اعتمادك وتفعيله.',
      );
      await _refresh();
    });
  }

  Future<void> _createMemory() async {
    final draft = await showDialog<_MemoryDraft>(
      context: context,
      builder: (context) => const _MemoryEditorDialog(),
    );
    if (draft == null) return;
    await _run(() async {
      final findings = _intelligence.reviewCandidate(
        content: draft.content,
        kind: draft.kind,
        existing: _entries,
      );
      if (findings.any(
        (finding) =>
            finding.kind == MemoryFindingKind.duplicate &&
            finding.similarity >= .999,
      )) {
        _showMessage(
          'هذه المعلومة موجودة بالفعل بصورة مطابقة؛ لم تتم إضافة نسخة مكررة.',
        );
        return;
      }
      final saveAsProposal = findings.isNotEmpty
          ? await _reviewFindings(findings)
          : false;
      if (findings.isNotEmpty && !saveAsProposal) return;
      if (saveAsProposal) {
        await _repository.propose(
          kind: draft.kind,
          content: draft.content,
          tags: draft.tags,
          sourceReference: draft.sourceReference,
        );
        _showMessage('أُضيفت كاقتراح غير مفعّل؛ راجعها قبل اعتمادها.');
      } else {
        await _repository.saveApproved(
          kind: draft.kind,
          content: draft.content,
          tags: draft.tags,
          sourceReference: draft.sourceReference,
        );
        _showMessage('تم حفظ الذاكرة بعد موافقتك.');
      }
      await _refresh();
    });
  }

  Future<bool> _reviewFindings(List<MemoryReviewFinding> findings) async {
    final saveAsProposal = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مراجعة ذاكرة مشابهة'),
        content: SizedBox(
          width: math.min(480.0, MediaQuery.sizeOf(context).width * .82),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: findings
                  .map(
                    (finding) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            finding.kind == MemoryFindingKind.duplicate
                                ? 'تشابه مرتفع (${(finding.similarity * 100).round()}%)'
                                : 'احتمال تعارض (${(finding.similarity * 100).round()}%)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(finding.existing.content),
                          const SizedBox(height: 3),
                          Text(
                            finding.explanation,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إضافة كاقتراح للمراجعة'),
          ),
        ],
      ),
    );
    return saveAsProposal == true;
  }

  Future<String?> _askPassphrase({required bool confirm}) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(confirm ? 'تصدير نسخة مشفرة' : 'استيراد نسخة مشفرة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة مرور النسخة',
                  helperText: '12 محرفاً على الأقل. احتفظ بها؛ لا يمكن استعادة النسخة دونها.',
                ),
              ),
              if (confirm)
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد كلمة المرور',
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.runes.length < 12 ||
                    (confirm && controller.text != confirmController.text)) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text('تحقق من طول كلمة المرور وتطابقها.'),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, controller.text);
              },
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _exportBackup() async {
    final passphrase = await _askPassphrase(confirm: true);
    if (passphrase == null || !mounted) return;
    await _run(() async {
      final bytes = await MemoryBackupService(_repository)
          .exportEncrypted(passphrase);
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة ذاكرة Leo المشفرة',
        fileName: 'leo-memory-backup.leomem',
        bytes: bytes,
      );
      if (saved == null) return;
      _showMessage(
        'تم إنشاء النسخة الاحتياطية المشفرة. احتفظ بكلمة مرورها منفصلة عن الملف.',
      );
    });
  }

  Future<void> _importBackup() async {
    final passphrase = await _askPassphrase(confirm: false);
    if (passphrase == null || !mounted) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['leomem'],
      withData: true,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    await _run(() async {
      final file = picked.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null)
        throw const FormatException('تعذر قراءة ملف النسخة الاحتياطية.');
      final report = await MemoryBackupService(_repository)
          .importEncrypted(bytes, passphrase);
      _showMessage(
        'استيراد مكتمل: ${report.proposed} اقتراح، ${report.duplicatesSkipped} مكرر، ${report.invalidSkipped} غير صالح. كل المستوردات تنتظر موافقتك.',
      );
      await _refresh();
    });
  }

  Future<void> _rotateKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تدوير مفتاح تشفير الذاكرة'),
        content: const Text(
          'سيعيد Leo تشفير سجلات الذاكرة بمفتاح جديد. لا تغلق التطبيق أثناء العملية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تدوير المفتاح'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _repository.rotateEncryptionKey();
      _showMessage('تم تدوير مفتاح التشفير بنجاح.');
      await _refresh();
    });
  }

  Future<void> _eraseAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح الذاكرة بالكامل؟'),
        content: const Text(
          'سيحذف Leo قاعدة الذاكرة وملفات SQLite الجانبية ومفتاح التشفير المحلي. هذا الإجراء نهائي. أنشئ نسخة احتياطية مشفرة أولاً إن احتجت إليها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('مسح نهائي'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      final verified = await _repository.eraseAllAndVerify();
      if (!verified)
        throw StateError('لم يكتمل التحقق من حذف قاعدة الذاكرة ومفتاحها.');
      _showMessage(
        'تم مسح الذاكرة المحلية والتحقق من اختفاء قاعدة البيانات ومفتاحها.',
      );
      await _refresh();
    });
  }

  Future<void> _editMemory(LeoMemoryEntry entry) async {
    final draft = await showDialog<_MemoryDraft>(
      context: context,
      builder: (context) => _MemoryEditorDialog(entry: entry),
    );
    if (draft == null) return;
    await _run(() async {
      await _repository.updateApproved(
        memoryId: entry.id,
        content: draft.content,
        tags: draft.tags,
        sourceReference: draft.sourceReference,
      );
      _showMessage('تم تحديث الذاكرة وإعادة فهرستها.');
      await _refresh();
    });
  }

  Future<void> _approve(LeoMemoryEntry entry) async {
    await _run(() async {
      await _repository.approve(entry.id);
      _showMessage('تم اعتماد الذاكرة وأصبحت متاحة للاسترجاع عند الحاجة.');
      await _refresh();
    });
  }

  Future<void> _toggleActive(LeoMemoryEntry entry) async {
    await _run(() async {
      await _repository.setActive(entry.id, !entry.active);
      _showMessage(
        entry.active ? 'تم إيقاف استخدام الذاكرة.' : 'تم تفعيل الذاكرة.',
      );
      await _refresh();
    });
  }

  Future<void> _delete(LeoMemoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الذاكرة؟'),
        content: const Text(
          'سيتم حذف هذه المعلومة نهائياً من قاعدة Leo المحلية.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _repository.delete(entry.id);
      _showMessage('تم حذف الذاكرة.');
      await _refresh();
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await operation();
    } catch (error) {
      _showMessage('تعذر إكمال العملية: $error');
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

  @override
  Widget build(BuildContext context) {
    final entries = _showSearchResults
        ? _searchHits.map((hit) => hit.entry).toList(growable: false)
        : _visibleEntries;

    return Scaffold(
      backgroundColor: const Color(0xFF0A101C),
      appBar: AppBar(
        title: const Text('ذاكرة Leo'),
        backgroundColor: const Color(0xFF0A101C),
        actions: [
          PopupMenuButton<String>(
            enabled: !_working && !_loading,
            onSelected: (value) {
              switch (value) {
                case 'export':
                  _exportBackup();
                  break;
                case 'import':
                  _importBackup();
                  break;
                case 'rotate':
                  _rotateKey();
                  break;
                case 'erase':
                  _eraseAll();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'export', child: Text('تصدير نسخة مشفرة')),
              PopupMenuItem(value: 'import', child: Text('استيراد نسخة مشفرة')),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'rotate',
                child: Text('تدوير مفتاح التشفير'),
              ),
              PopupMenuItem(value: 'erase', child: Text('مسح الذاكرة بالكامل')),
            ],
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _working || _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _working ? null : _createMemory,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة ذاكرة'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildPrivacyNotice(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: 'ابحث في الذكريات المعتمدة...',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: IconButton(
                          tooltip: 'مسح البحث',
                          onPressed: () {
                            _searchController.clear();
                            _refresh();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF121C2B),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _searching || _working ? null : _search,
                    icon: _searching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search_rounded),
                  ),
                ],
              ),
            ),
            if (!_showSearchResults)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    _filterChip('الكل', _MemoryFilter.all),
                    _filterChip('النشطة', _MemoryFilter.active),
                    _filterChip('بانتظار الموافقة', _MemoryFilter.pending),
                    _filterChip('المعطلة', _MemoryFilter.disabled),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'نتائج البحث (${_searchHits.length})',
                        style: const TextStyle(color: Color(0xFFADBBD0)),
                      ),
                    ),
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('عرض كل الذكريات'),
                    ),
                  ],
                ),
              ),
            if (_working) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: _buildList(entries)),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNotice() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF17263A),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF2B4262)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: Color(0xFF9BB0FF), size: 19),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'تُحفظ الذكريات محلياً داخل مساحة التطبيق. المحتوى والوسوم والمصادر وفهرس البحث مشفرة بـ AES-256-GCM ومربوطة بهوية السجل؛ ومفتاحها محفوظ في التخزين الآمن للنظام. تبقى بعض بيانات الفهرسة الوصفية ظاهرة داخل قاعدة SQLite، ومنها نوع الذاكرة ومعرّفها وأوقات الإنشاء والتحديث وحالة الموافقة/التفعيل وإصدار المخطط/التشفير وبصمة محتوى مبهمة مشتقة بمفتاح محلي. لا يستخدم Leo الذكريات في المحادثات إلا بعد اعتمادها وتفعيلها. احتفظ بكلمة مرور النسخة الاحتياطية منفصلة؛ فقدان مفتاح الجهاز دون نسخة احتياطية قد يمنع الاستعادة.',
              style: TextStyle(
                color: Color(0xFFC4D0E2),
                fontSize: 12,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _MemoryFilter filter) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == filter,
        onSelected: (_) => setState(() => _filter = filter),
      ),
    );
  }

  Widget _buildList(List<LeoMemoryEntry> entries) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFFC58F),
                size: 34,
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _refresh,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.psychology_alt_rounded,
                size: 46,
                color: Color(0xFF7485A3),
              ),
              const SizedBox(height: 14),
              Text(
                _showSearchResults
                    ? 'لم نعثر على ذكريات مطابقة.'
                    : 'لا توجد ذكريات محفوظة بعد.',
                style: const TextStyle(color: Color(0xFFADBBD0), fontSize: 15),
                textAlign: TextAlign.center,
              ),
              if (!_showSearchResults) ...[
                const SizedBox(height: 8),
                const Text(
                  'أضف المعلومات التي تريد من Leo تذكرها واستخدامها لاحقاً.',
                  style: TextStyle(color: Color(0xFF8292AB), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (context, index) => _MemoryCard(
        entry: entries[index],
        working: _working,
        onApprove: () => _approve(entries[index]),
        onToggleActive: () => _toggleActive(entries[index]),
        onEdit: () => _editMemory(entries[index]),
        onDelete: () => _delete(entries[index]),
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  const _MemoryCard({
    required this.entry,
    required this.working,
    required this.onApprove,
    required this.onToggleActive,
    required this.onEdit,
    required this.onDelete,
  });

  final LeoMemoryEntry entry;
  final bool working;
  final VoidCallback onApprove;
  final VoidCallback onToggleActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = entry.isPending
        ? 'بانتظار الموافقة'
        : entry.active
        ? 'نشطة'
        : 'معطلة';
    final statusColor = entry.isPending
        ? const Color(0xFFFFC58F)
        : entry.active
        ? const Color(0xFF92D6A6)
        : const Color(0xFF9AA8BC);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111B2A),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF25354D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _smallLabel(
                      _kindLabel(entry.kind),
                      const Color(0xFF9BB0FF),
                    ),
                    _smallLabel(status, statusColor),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !working,
                onSelected: (value) {
                  switch (value) {
                    case 'approve':
                      onApprove();
                      break;
                    case 'toggle':
                      onToggleActive();
                      break;
                    case 'edit':
                      onEdit();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (entry.isPending)
                    const PopupMenuItem(
                      value: 'approve',
                      child: Text('اعتماد الذاكرة'),
                    ),
                  if (!entry.isPending)
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(
                        entry.active ? 'إيقاف الاستخدام' : 'تفعيل الذاكرة',
                      ),
                    ),
                  if (!entry.isPending)
                    const PopupMenuItem(value: 'edit', child: Text('تعديل')),
                  const PopupMenuItem(value: 'delete', child: Text('حذف')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 9),
          SelectableText(
            entry.content,
            style: const TextStyle(
              color: Color(0xFFE0E8F4),
              height: 1.6,
              fontSize: 14,
            ),
          ),
          if (entry.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: entry.tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      backgroundColor: const Color(0xFF1C2A3F),
                      side: BorderSide.none,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (entry.sourceReference != null &&
              entry.sourceReference!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'المصدر: ${entry.sourceReference}',
              style: const TextStyle(color: Color(0xFF8292AB), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallLabel(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(text, style: TextStyle(color: color, fontSize: 10)),
  );

  String _kindLabel(LeoMemoryKind kind) => switch (kind) {
    LeoMemoryKind.personal => 'شخصية',
    LeoMemoryKind.episodic => 'حدث وتجربة',
    LeoMemoryKind.semantic => 'معلومة',
    LeoMemoryKind.procedural => 'طريقة عمل',
    LeoMemoryKind.project => 'مشروع',
  };
}

class _MemoryDraft {
  const _MemoryDraft({
    required this.kind,
    required this.content,
    required this.tags,
    this.sourceReference,
  });

  final LeoMemoryKind kind;
  final String content;
  final List<String> tags;
  final String? sourceReference;
}

class _MemoryEditorDialog extends StatefulWidget {
  const _MemoryEditorDialog({
    this.entry,
    this.initialContent,
    this.initialSourceReference,
    this.proposeOnly = false,
  });

  final LeoMemoryEntry? entry;
  final String? initialContent;
  final String? initialSourceReference;
  final bool proposeOnly;

  @override
  State<_MemoryEditorDialog> createState() => _MemoryEditorDialogState();
}

class _MemoryEditorDialogState extends State<_MemoryEditorDialog> {
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  late final TextEditingController _sourceController;
  late LeoMemoryKind _kind;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _kind = entry?.kind ?? LeoMemoryKind.personal;
    _contentController = TextEditingController(
      text: entry?.content ?? widget.initialContent ?? '',
    );
    _tagsController = TextEditingController(text: entry?.tags.join(', ') ?? '');
    _sourceController = TextEditingController(
      text: entry?.sourceReference ?? widget.initialSourceReference ?? '',
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    _tagsController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.proposeOnly
            ? 'مراجعة اقتراح ذاكرة'
            : widget.entry == null
            ? 'إضافة ذاكرة'
            : 'تعديل الذاكرة',
      ),
      content: SizedBox(
        width: math.min(480.0, MediaQuery.sizeOf(context).width * .82),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<LeoMemoryKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'نوع الذاكرة'),
                items: LeoMemoryKind.values
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(_kindLabel(kind)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: widget.entry == null
                    ? (value) {
                        if (value != null) setState(() => _kind = value);
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentController,
                minLines: 3,
                maxLines: 7,
                maxLength: 20_000,
                decoration: const InputDecoration(
                  labelText: 'المعلومة التي تريد حفظها',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'وسوم (افصل بينها بفاصلة)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sourceController,
                decoration: const InputDecoration(
                  labelText: 'المصدر (اختياري)',
                  hintText: 'مثلاً: مشروع Leo أو ملاحظة شخصية',
                  border: OutlineInputBorder(),
                ),
              ),
              if (widget.entry == null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.proposeOnly
                      ? 'هذا اقتراح مستخرج من رسالة اخترتها. راجعه وعدّله؛ سيبقى غير معتمد ولن يدخل سياق المحادثات حتى توافق عليه لاحقاً.'
                      : 'عند الحفظ، ستُعتمد هذه الذاكرة بموافقتك ويمكن لـLeo استرجاعها عند صلتها بالمحادثة.',
                  style: const TextStyle(
                    color: Color(0xFF9AAAC1),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(
            widget.proposeOnly
                ? 'إضافة كاقتراح للمراجعة'
                : widget.entry == null
                ? 'حفظ واعتماد'
                : 'حفظ التعديلات',
          ),
        ),
      ],
    );
  }

  void _save() {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    final tags = _tagsController.text
        .split(',')
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final source = _sourceController.text.trim();
    Navigator.pop(
      context,
      _MemoryDraft(
        kind: _kind,
        content: content,
        tags: tags,
        sourceReference: source.isEmpty ? null : source,
      ),
    );
  }

  String _kindLabel(LeoMemoryKind kind) => switch (kind) {
    LeoMemoryKind.personal => 'شخصية',
    LeoMemoryKind.episodic => 'حدث وتجربة',
    LeoMemoryKind.semantic => 'معلومة',
    LeoMemoryKind.procedural => 'طريقة عمل',
    LeoMemoryKind.project => 'مشروع',
  };
}

enum _MemoryFilter { all, active, pending, disabled }
