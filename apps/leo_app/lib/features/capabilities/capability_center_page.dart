import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/capabilities/capability_repository.dart';

class CapabilityCenterPage extends StatefulWidget {
  const CapabilityCenterPage({super.key, this.repository});

  final CapabilityRepository? repository;

  @override
  State<CapabilityCenterPage> createState() => _CapabilityCenterPageState();
}

class _CapabilityCenterPageState extends State<CapabilityCenterPage> {
  late final CapabilityRepository _repository;
  bool _loading = true;
  String? _error;
  String _platform = 'unknown';
  List<LeoCapability> _capabilities = const [];
  List<LeoPermissionRecord> _permissions = const [];

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? LocalCapabilityRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final platform = Platform.isWindows
          ? 'windows'
          : Platform.isAndroid
          ? 'android'
          : 'unsupported';
      final values = await _repository.list(platform);
      final grants = await _repository.listPermissions();
      if (!mounted) return;
      setState(() {
        _platform = platform;
        _capabilities = values;
        _permissions = grants;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  LeoPermissionRecord? _recordFor(LeoCapability capability) {
    for (final record in _permissions) {
      if (record.capabilityId == capability.id &&
          record.scope == capability.grantScope) {
        return record;
      }
    }
    return null;
  }

  Future<void> _revoke(LeoPermissionRecord record) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('إيقاف إذن Leo؟'),
            content: Text(
              'سيمنع هذا Leo من استخدام ${record.capabilityId} ضمن النطاق ${record.scope}. لا يؤدي ذلك إلى سحب صلاحية Android أو Windows من إعدادات النظام.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('إيقاف'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _repository.revoke(
      capabilityId: record.capabilityId,
      scope: record.scope,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('قدرات الجهاز والصلاحيات'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorPanel(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  const _NoticeCard(),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'قدرات $_platform',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Chip(label: Text(_platform.toUpperCase())),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final capability in _capabilities)
                    _CapabilityTile(
                      capability: capability,
                      record: _recordFor(capability),
                      onRevoke: _recordFor(capability)?.granted == true
                          ? () => _revoke(_recordFor(capability)!)
                          : null,
                    ),
                  const SizedBox(height: 24),
                  const Text(
                    'سجل الأذونات',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  if (_permissions.isEmpty)
                    const _EmptyPermissions()
                  else
                    for (final record in _permissions)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            record.granted
                                ? Icons.verified_user_outlined
                                : Icons.block_outlined,
                            color: record.granted
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                          title: Text(record.capabilityId),
                          subtitle: Text(
                            '${record.scope}\n${record.granted ? 'مسموح داخل Leo' : 'مرفوض أو ملغى'}',
                          ),
                          isThreeLine: true,
                          trailing: record.granted
                              ? IconButton(
                                  tooltip: 'إلغاء إذن Leo',
                                  onPressed: () => _revoke(record),
                                  icon: const Icon(Icons.remove_circle_outline),
                                )
                              : const Icon(Icons.do_not_disturb_on_outlined),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard();

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF18263A),
    child: const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFF9BB0FF)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'لا يطلب Leo صلاحيات عند التشغيل الأول. عند تنفيذ مهمة تحتاج إلى قدرة معينة، سيشرح سبب الطلب ويطلب موافقتك أولاً، ثم يطلب إذن النظام عند الحاجة. الموافقة على استخدام القدرة لا تعني الموافقة التلقائية على إرسال رسالة أو حذف ملف أو تنفيذ إجراء حساس.',
              style: TextStyle(height: 1.55),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({
    required this.capability,
    required this.record,
    required this.onRevoke,
  });

  final LeoCapability capability;
  final LeoPermissionRecord? record;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final ready = capability.supportedInAlpha;
    final granted = record?.granted == true;
    final status = !ready
        ? 'غير مفعّلة بعد'
        : granted
        ? 'إذن Leo مفعّل'
        : record != null
        ? 'لم يُمنح أو تم إلغاؤه'
        : 'يُطلب عند أول استخدام';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    capability.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Chip(label: Text(status), visualDensity: VisualDensity.compact),
              ],
            ),
            Text(capability.description, style: const TextStyle(height: 1.45)),
            const SizedBox(height: 7),
            Text(
              'المعرّف: ${capability.id}  •  مستوى الخطورة: ${capability.risk.name}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: const Color(0xFF9EADC3)),
            ),
            if (onRevoke != null)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: onRevoke,
                  icon: const Icon(Icons.block_outlined, size: 17),
                  label: const Text('إلغاء إذن Leo'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPermissions extends StatelessWidget {
  const _EmptyPermissions();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, size: 30, color: Color(0xFF9BB0FF)),
          const SizedBox(height: 8),
          const Text('لم يمنح Leo أي أذونات بعد.'),
          const SizedBox(height: 4),
          Text(
            'ستظهر هنا الأذونات التي وافقت عليها عند استخدامها.',
            style: Theme.of(context).textTheme.bodySmall,
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
          const Icon(Icons.error_outline, size: 36),
          const SizedBox(height: 10),
          const Text('تعذر تحميل قدرات الجهاز.'),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}
