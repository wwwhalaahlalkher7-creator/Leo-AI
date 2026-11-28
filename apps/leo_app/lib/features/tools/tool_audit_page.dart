import 'package:flutter/material.dart';

import '../../core/tools/tool_execution_gateway.dart';

class ToolAuditPage extends StatefulWidget {
  const ToolAuditPage({super.key, this.gateway});

  final ToolExecutionGateway? gateway;

  @override
  State<ToolAuditPage> createState() => _ToolAuditPageState();
}

class _ToolAuditPageState extends State<ToolAuditPage> {
  late final ToolExecutionGateway _gateway;
  late Future<List<ToolAuditRecord>> _records;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? ToolExecutionGateway();
    _records = _gateway.loadAudit();
  }

  Future<void> _refresh() async {
    setState(() => _records = _gateway.loadAudit());
  }

  String _statusLabel(String status) => switch (status) {
    'started' => 'قيد التنفيذ',
    'succeeded' => 'اكتملت',
    'failed' => 'فشلت',
    'cancelled' => 'أُلغيت',
    _ => status,
  };

  String _toolLabel(String name) => switch (name) {
    'files.read_selected' => 'قراءة ملف محدد',
    'workspace.write_file' => 'إنشاء أو تعديل ملف بموافقة',
    'contacts.list' => 'قراءة جهات الاتصال',
    'email.compose' => 'إنشاء مسودة بريد',
    'phone.dial' => 'فتح لوحة الاتصال',
    'messages.compose' => 'إنشاء مسودة رسالة',
    'web.open' => 'فتح رابط',
    'app.launch' => 'فتح تطبيق',
    _ => name,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل تنفيذ الأدوات'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<ToolAuditRecord>>(
        future: _records,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final records = snapshot.data ?? const <ToolAuditRecord>[];
          if (records.isEmpty) {
            return const Center(child: Text('لم ينفذ Leo أي أداة بعد.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: records.length + 1,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'يحفظ هذا السجل اسم الأداة وحالتها ووقت التنفيذ فقط. لا يحفظ عناوين البريد أو أرقام الهواتف أو نصوص الرسائل أو محتويات الملفات أو جهات الاتصال.',
                    ),
                  ),
                );
              }
              final record = records[index - 1];
              final localTime = DateTime.tryParse(record.timestampUtc)
                  ?.toLocal();
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.build_circle_outlined),
                  title: Text(_toolLabel(record.toolName)),
                  subtitle: Text(
                    '${_statusLabel(record.status)}${localTime == null ? '' : '\n${localTime.toString()}'}\n${record.summary}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
