import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'capability_repository.dart';
import '../tools/workspace_write_policy.dart';
import 'package:leo_platform_capabilities/leo_platform_capabilities.dart';

class CapabilityExecutionResult {
  const CapabilityExecutionResult({
    required this.success,
    required this.message,
    this.data = const <String, Object?>{},
    this.cancelled = false,
  });

  final bool success;
  final String message;
  final Map<String, Object?> data;
  final bool cancelled;
}

/// User-facing policy gateway for all OS/app capabilities.
///
/// Flow: discover capability -> show Leo consent on first use -> request/check
/// native OS access -> record scoped grant -> request one-action approval when
/// required -> delegate to the OS/app. Native adapters never make AI decisions.
class LeoSelectedFile {
  const LeoSelectedFile._({this.uri, this.path, required this.platform});

  final String? uri;
  final String? path;
  final String platform;
}

class CapabilityHubService {
  CapabilityHubService({
    CapabilityRepository? repository,
    LeoPlatformCapabilities? platform,
  })  : _repository = repository ?? LocalCapabilityRepository(),
        _platform = platform ?? LeoPlatformCapabilities();

  final CapabilityRepository _repository;
  final LeoPlatformCapabilities _platform;

  Future<String> get platformName async {
    final nativePlatform = await _platform.getPlatform();
    if (nativePlatform != 'unknown') return nativePlatform;
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return 'unsupported';
  }

  Future<CapabilityExecutionResult> _invoke(
    BuildContext context, {
    required String capabilityId,
    required String scope,
    required String operation,
    required String actionSummary,
    required String impactSummary,
    Map<String, Object?> arguments = const <String, Object?>{},
    bool externalEffect = false,
    bool destructive = false,
    bool skipActionConfirmation = false,
    Future<bool> Function()? actionApproval,
  }) async {
    final operationAllowed = _operationAllowed(capabilityId, operation);
    if (!operationAllowed) {
      return const CapabilityExecutionResult(
        success: false,
        message: 'العملية المطلوبة غير مرتبطة بالقدرة المعلنة.',
      );
    }
    final platform = await platformName;
    final capabilities = await _repository.list(platform);
    LeoCapability? capability;
    for (final item in capabilities) {
      if (item.id == capabilityId) {
        capability = item;
        break;
      }
    }
    if (capability == null || !capability.supportedInAlpha) {
      return const CapabilityExecutionResult(
        success: false,
        message: 'هذه القدرة غير مفعّلة بعد في إصدار Alpha الحالي.',
      );
    }

    var osGranted = await _platform.checkOsPermission(capabilityId);
    var permission = await _repository.check(
      capabilityId: capabilityId,
      scope: scope,
      osPermissionGranted: osGranted,
    );

    if (permission.needsLeoConsent) {
      final consent = await _showConsent(context, capability, scope);
      if (!consent || !context.mounted) {
        if (!consent) {
          await _repository.recordDecision(
            capabilityId: capabilityId,
            scope: scope,
            granted: false,
          );
        }
        return const CapabilityExecutionResult(
          success: false,
          cancelled: true,
          message: 'لم يتم منح الإذن؛ لم ينفذ Leo العملية.',
        );
      }
      // This stores Leo's app-level consent only. The OS grant is independently
      // requested and checked below before the native operation can proceed.
      await _repository.recordDecision(
        capabilityId: capabilityId,
        scope: scope,
        granted: true,
      );
      permission = await _repository.check(
        capabilityId: capabilityId,
        scope: scope,
        osPermissionGranted: osGranted,
      );
    }

    if (!osGranted || permission.needsOsPermission) {
      final granted = await _platform.requestOsPermission(capabilityId);
      osGranted = await _platform.checkOsPermission(capabilityId);
      if (!granted || !osGranted) {
        return const CapabilityExecutionResult(
          success: false,
          message: 'لم يمنح نظام التشغيل الإذن المطلوب. يمكنك مراجعته من إعدادات النظام.',
        );
      }
    }

    permission = await _repository.check(
      capabilityId: capabilityId,
      scope: scope,
      osPermissionGranted: osGranted,
    );
    if (!permission.allowed) {
      return CapabilityExecutionResult(
        success: false,
        message: 'تعذر اعتماد الإذن المطلوب: ${permission.status.name}.',
      );
    }

    final requiresConfirmation = await _repository.actionRequiresConfirmation(
      risk: capability.risk,
      externalEffect: externalEffect,
      destructive: destructive,
    );
    if (requiresConfirmation && !skipActionConfirmation) {
      if (!context.mounted) {
        return const CapabilityExecutionResult(
          success: false,
          cancelled: true,
          message: 'أُغلقت الشاشة قبل تأكيد الإجراء؛ لم ينفذه Leo.',
        );
      }
      final approved = actionApproval != null
          ? await actionApproval()
          : await _showActionApproval(
              context,
              title: actionSummary,
              impact: impactSummary,
            );
      if (!approved || !context.mounted) {
        return const CapabilityExecutionResult(
          success: false,
          cancelled: true,
          message: 'لم تتم الموافقة على الإجراء؛ لم ينفذه Leo.',
        );
      }
    }

    try {
      final data = await _platform.execute(operation, arguments: arguments);
      final success = data['success'] != false && data['cancelled'] != true;
      return CapabilityExecutionResult(
        success: success,
        cancelled: data['cancelled'] == true,
        data: data,
        message: success
            ? (data['message']?.toString() ?? 'تم تسليم العملية إلى تطبيق أو خدمة النظام.')
            : (data['message']?.toString() ?? 'لم تكتمل العملية في النظام.'),
      );
    } catch (error) {
      return CapabilityExecutionResult(
        success: false,
        message: 'تعذر تنفيذ العملية عبر النظام: $error',
      );
    }
  }


  Future<LeoSelectedFile?> pickFile(BuildContext context) async {
    final platform = await platformName;
    final result = await _invoke(
      context,
      capabilityId: 'files.read',
      scope: 'selected_files',
      operation: 'pickFile',
      actionSummary: 'اختيار ملف لقراءته',
      impactSummary: 'سيقرأ Leo الملف الذي تختاره فقط، ولا يمنحه هذا الإذن وصولاً عاماً إلى ملفات الجهاز.',
    );
    if (!result.success || result.cancelled) return null;
    final uri = result.data['uri']?.toString();
    final selectedPath = result.data['path']?.toString();
    if ((uri == null || uri.isEmpty) && (selectedPath == null || selectedPath.isEmpty)) {
      return null;
    }
    return LeoSelectedFile._(
      uri: uri,
      path: selectedPath,
      platform: platform,
    );
  }

  Future<String?> readSelectedText(
    BuildContext context,
    LeoSelectedFile file,
  ) async {
    final result = await _invoke(
      context,
      capabilityId: 'files.read',
      scope: 'selected_files',
      operation: 'readTextFile',
      actionSummary: 'قراءة الملف الذي اخترته',
      impactSummary: 'سيقرأ Leo محتوى الملف المحدد فقط، بحد أقصى 2 MiB.',
      arguments: file.platform == 'android'
          ? <String, Object?>{'uri': file.uri}
          : <String, Object?>{'path': file.path},
    );
    if (!result.success) return null;
    return result.data['text']?.toString();
  }


  /// Proposes a single text-file create/update inside a folder chosen through
  /// the native system picker. The native adapter keeps the folder token only
  /// for this process and re-checks the original file hash immediately before
  /// applying an atomic replacement. No path from the model is treated as an
  /// absolute path, and the user reviews the exact before/after content first.
  Future<CapabilityExecutionResult> writeWorkspaceTextFile(
    BuildContext context, {
    required String relativePath,
    required String content,
  }) async {
    final validationError = WorkspaceWritePolicy.validate(
      relativePath: relativePath,
      content: content,
    );
    if (validationError != null) {
      return CapabilityExecutionResult(success: false, message: validationError);
    }
    final platform = await platformName;
    if (platform != 'android' && platform != 'windows') {
      return const CapabilityExecutionResult(
        success: false,
        message: 'تعديل الملفات غير مدعوم على هذه المنصة.',
      );
    }

    final workspace = await _invoke(
      context,
      capabilityId: 'files.write',
      scope: 'selected_workspace',
      operation: 'pickWorkspace',
      actionSummary: 'اختيار مجلد مساحة العمل',
      impactSummary: 'سيعمل Leo داخل المجلد الذي تختاره فقط. لن يحصل على وصول عام إلى ملفات الجهاز.',
      skipActionConfirmation: true,
    );
    if (!workspace.success || workspace.cancelled) return workspace;
    final token = workspace.data['workspaceToken']?.toString() ?? '';
    final workspaceLabel = workspace.data['workspaceLabel']?.toString() ?? 'المجلد الذي اخترته';
    if (token.isEmpty || token.length > 80) {
      return const CapabilityExecutionResult(
        success: false,
        message: 'لم يُرجع منتقي المجلد رمز مساحة عمل صالحاً.',
      );
    }

    try {
      final preview = await _platform.execute(
        'previewWorkspaceWrite',
        arguments: <String, Object?>{
          'workspaceToken': token,
          'relativePath': relativePath,
          'content': content,
        },
      );
      if (preview['success'] != true) {
        await _releaseWorkspace(token);
        return CapabilityExecutionResult(
          success: false,
          message: preview['message']?.toString() ?? 'تعذر إنشاء معاينة آمنة للملف.',
        );
      }
      final exists = preview['exists'] == true;
      final previousContent = preview['currentContent']?.toString() ?? '';
      final expectedHash = preview['currentHash']?.toString() ?? '';
      final expectedNewHash = preview['proposedHash']?.toString() ?? '';
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedNewHash) ||
          (exists && !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedHash)) ||
          (!exists && expectedHash.isNotEmpty)) {
        await _releaseWorkspace(token);
        return const CapabilityExecutionResult(
          success: false,
          message: 'لم تُرجع المنصة بصمات تحقق صالحة للمعاينة؛ لم تتم الكتابة.',
        );
      }
      if (previousContent == content && exists) {
        await _releaseWorkspace(token);
        return const CapabilityExecutionResult(
          success: true,
          message: 'الملف يحتوي بالفعل على المحتوى نفسه؛ لم تُجرَ أي كتابة.',
        );
      }

      final outcome = await _invoke(
        context,
        capabilityId: 'files.write',
        scope: 'selected_workspace',
        operation: 'applyWorkspaceWrite',
        actionSummary: exists ? 'تعديل الملف $relativePath' : 'إنشاء الملف $relativePath',
        impactSummary: exists
            ? 'سيستبدل Leo محتوى هذا الملف فقط بعد مقارنة بصمته الحالية بالبصمة التي عُرضت لك.'
            : 'سينشئ Leo ملفاً نصياً واحداً داخل المجلد المختار، ولن يستبدل ملفاً موجوداً.',
        arguments: <String, Object?>{
          'workspaceToken': token,
          'relativePath': relativePath,
          'content': content,
          'expectedHash': expectedHash,
          'expectedNewHash': expectedNewHash,
        },
        actionApproval: () => _showWorkspaceWriteApproval(
          context,
          relativePath: relativePath,
          workspaceLabel: workspaceLabel,
          before: previousContent,
          after: content,
          exists: exists,
        ),
      );
      if (!outcome.success) await _releaseWorkspace(token);
      return outcome;
    } catch (error) {
      await _releaseWorkspace(token);
      return CapabilityExecutionResult(
        success: false,
        message: 'تعذر إعداد أو تطبيق التعديل بأمان: $error',
      );
    }
  }

  Future<void> _releaseWorkspace(String token) async {
    try {
      await _platform.execute(
        'releaseWorkspace',
        arguments: <String, Object?>{'workspaceToken': token},
      );
    } catch (_) {
      // Native session tokens expire with the process and are bounded in count.
    }
  }


  /// First-use microphone grant. Android has a runtime OS permission prompt.
  /// Windows desktop apps instead use the OS microphone privacy page; the OS
  /// does not expose a reliable per-app check through this plugin, so actual
  /// Media Foundation capture remains the final enforcement point.
  Future<CapabilityExecutionResult> requestMicrophoneAccess(
    BuildContext context,
  ) async {
    final platform = await platformName;
    if (platform != 'android' && platform != 'windows') {
      return const CapabilityExecutionResult(
        success: false,
        message: 'استخدام الميكروفون غير مدعوم على هذه المنصة.',
      );
    }

    final available = await _repository.list(platform);
    LeoCapability? capability;
    for (final item in available) {
      if (item.id == 'audio.microphone') {
        capability = item;
        break;
      }
    }
    if (capability == null || !capability.supportedInAlpha) {
      return const CapabilityExecutionResult(
        success: false,
        message: 'قدرة الميكروفون غير مفعّلة في هذه النسخة.',
      );
    }

    // Windows does not offer a queryable runtime permission API to the
    // desktop plugin. Treat only the Leo-level consent as checked here; the
    // OS privacy switch is explained/opened below and enforced by capture.
    var osGranted = platform == 'windows'
        ? true
        : await _platform.checkOsPermission('audio.microphone');
    var permission = await _repository.check(
      capabilityId: 'audio.microphone',
      scope: 'microphone_access',
      osPermissionGranted: osGranted,
    );
    final needsLeoConsent = permission.needsLeoConsent ||
        permission.status == LeoPermissionStatus.previouslyDenied;
    final firstUse = permission.needsLeoConsent;
    final shouldOpenWindowsSettings = firstUse ||
        permission.status == LeoPermissionStatus.previouslyDenied ||
        permission.status == LeoPermissionStatus.osPermissionRevoked;

    if (needsLeoConsent) {
      final consent = await _showConsent(
        context,
        capability,
        'microphone_access',
      );
      if (!consent || !context.mounted) {
        if (!consent) {
          await _repository.recordDecision(
            capabilityId: 'audio.microphone',
            scope: 'microphone_access',
            granted: false,
          );
        }
        return const CapabilityExecutionResult(
          success: false,
          cancelled: true,
          message: 'لم تمنح Leo إذن استخدام الميكروفون.',
        );
      }
      await _repository.recordDecision(
        capabilityId: 'audio.microphone',
        scope: 'microphone_access',
        granted: true,
      );
      permission = await _repository.check(
        capabilityId: 'audio.microphone',
        scope: 'microphone_access',
        osPermissionGranted: osGranted,
      );
    }

    // The Android runtime request must happen after Leo consent but before the
    // final permission check: the permission repository intentionally reports
    // a missing OS grant as RevokedByOperatingSystem until Android grants it.
    if (platform == 'android' && !osGranted) {
      final requested = await _platform.requestOsPermission('audio.microphone');
      osGranted = await _platform.checkOsPermission('audio.microphone');
      if (!requested || !osGranted) {
        return const CapabilityExecutionResult(
          success: false,
          message: 'لم يمنح Android إذن الميكروفون. لم يبدأ التسجيل.',
        );
      }
      permission = await _repository.check(
        capabilityId: 'audio.microphone',
        scope: 'microphone_access',
        osPermissionGranted: osGranted,
      );
    }

    if (!permission.allowed) {
      return CapabilityExecutionResult(
        success: false,
        message: 'تعذر اعتماد إذن الميكروفون: ${permission.status.name}.',
      );
    }

    if (platform == 'windows' && shouldOpenWindowsSettings) {
      final opened = await _platform.openWindowsMicrophonePrivacySettings();
      return CapabilityExecutionResult(
        success: false,
        cancelled: !opened,
        message: opened
            ? 'فتح Leo إعدادات خصوصية الميكروفون في Windows. فعّل السماح بالوصول إلى الميكروفون والسماح لتطبيقات سطح المكتب، ثم ارجع واضغط الميكروفون مرة أخرى.'
            : 'تعذر فتح إعدادات خصوصية الميكروفون. افتح Settings > Privacy & security > Microphone يدوياً ثم أعد المحاولة.',
      );
    }

    return const CapabilityExecutionResult(
      success: true,
      message: 'تم اعتماد إذن Leo للميكروفون. سيظل Windows يفرض إعدادات خصوصيته عند بدء الالتقاط.',
    );
  }

  Future<bool> openWindowsMicrophonePrivacySettings() async {
    if (await platformName != 'windows') return false;
    return _platform.openWindowsMicrophonePrivacySettings();
  }

  Future<CapabilityExecutionResult> readContacts(BuildContext context) {
    // Preserve denial/cancellation separately from a successful empty result.
    // The caller must not tell the model that the permission-denied case meant
    // the device had no contacts.
    return _invoke(
      context,
      capabilityId: 'contacts.read',
      scope: 'contacts_read',
      operation: 'readContacts',
      actionSummary: 'قراءة قائمة جهات الاتصال',
      impactSummary: 'سيقرأ Leo أسماء وأرقام جهات الاتصال محلياً على الجهاز، ولن يرسلها إلى أي جهة خارجية.',
    );
  }

  Future<CapabilityExecutionResult> composeEmail(
    BuildContext context, {
    required String to,
    required String subject,
    required String body,
  }) {
    final safeRecipient = to.trim();
    if (safeRecipient.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(safeRecipient) ||
        subject.length > 998 || body.length > 8192 ||
        _containsAsciiControl(safeRecipient) ||
        _containsAsciiControl(subject) ||
        _containsUnsafeTextControl(body)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'بيانات البريد غير صالحة أو تتجاوز الحدود المسموحة.',
      ));
    }
    final mailto = Uri(
      scheme: 'mailto',
      path: safeRecipient,
      queryParameters: <String, String>{'subject': subject, 'body': body},
    ).toString();
    if (mailto.length > 100000) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'مسودة البريد كبيرة جداً لتسليمها إلى تطبيق البريد بأمان.',
      ));
    }
    return _invoke(
        context,
        capabilityId: 'email.compose',
        scope: 'mail_app_handoff',
        operation: 'composeEmail',
        actionSummary: 'فتح رسالة بريد جاهزة إلى $safeRecipient',
        impactSummary: 'المستلم: $safeRecipient\nالموضوع: $subject\nالنص:\n$body\n\nسيفتح Leo تطبيق البريد كمسودة فقط، ولن يرسلها تلقائياً.',
        arguments: <String, Object?>{
          'to': safeRecipient,
          'subject': subject,
          'body': body,
          'mailto': mailto,
        },
        externalEffect: true,
      );
  }

  Future<CapabilityExecutionResult> openDialer(
    BuildContext context,
    String number,
  ) {
    if (!_isSafePhoneNumber(number)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'رقم الهاتف غير صالح.',
      ));
    }
    return _invoke(
        context,
        capabilityId: 'phone.dial',
        scope: 'dialer_handoff',
        operation: 'openDialer',
        actionSummary: 'فتح لوحة الاتصال للرقم $number',
        impactSummary: 'سيفتح Leo تطبيق الاتصال بالرقم المطلوب؛ لن يبدأ المكالمة بنفسه.',
        arguments: <String, Object?>{'number': number.trim()},
        externalEffect: true,
      );
  }

  Future<CapabilityExecutionResult> composeMessage(
    BuildContext context, {
    required String number,
    required String body,
  }) {
    if (!_isSafePhoneNumber(number) || body.length > 4096 || _containsUnsafeTextControl(body)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'رقم الهاتف أو نص الرسالة غير صالح أو يتجاوز الحد المسموح.',
      ));
    }
    return _invoke(
        context,
        capabilityId: 'messages.compose',
        scope: 'messaging_app_handoff',
        operation: 'composeMessage',
        actionSummary: 'فتح رسالة إلى $number',
        impactSummary: 'الرقم: $number\nنص الرسالة:\n$body\n\nسيفتح Leo تطبيق الرسائل كمسودة فقط، ولن يرسلها تلقائياً.',
        arguments: <String, Object?>{'number': number.trim(), 'body': body},
        externalEffect: true,
      );
  }

  Future<CapabilityExecutionResult> openSelectedFile(BuildContext context) async {
    final selection = await _invoke(
      context,
      capabilityId: 'files.open_selected',
      scope: 'selected_file_open',
      operation: 'pickFile',
      actionSummary: 'اختيار ملف لفتحه',
      impactSummary: 'سيختار المستخدم ملفاً واحداً. لن يفتح Leo أنواع الملفات التنفيذية أو السكربتات.',
    );
    if (!selection.success || selection.cancelled) return selection;
    final uri = selection.data['uri']?.toString();
    final path = selection.data['path']?.toString();
    if ((uri == null || uri.isEmpty) && (path == null || path.isEmpty)) {
      return const CapabilityExecutionResult(success: false, message: 'لم يُرجع منتقي الملفات مرجعاً صالحاً.');
    }
    return _invoke(
      context,
      capabilityId: 'files.open_selected',
      scope: 'selected_file_open',
      operation: 'openSelectedFile',
      actionSummary: 'فتح الملف المحدد بالتطبيق المناسب',
      impactSummary: 'سيفتح نظام التشغيل الملف الذي اخترته في تطبيقه المرتبط. لن يشغّل Leo ملفاً تنفيذياً أو سكربتاً.',
      arguments: <String, Object?>{
        if (uri != null && uri.isNotEmpty) 'uri': uri,
        if (path != null && path.isNotEmpty) 'path': path,
      },
      externalEffect: true,
    );
  }

  Future<CapabilityExecutionResult> createCalendarEventDraft(
    BuildContext context, {
    required String title,
    required DateTime start,
    required DateTime end,
    String location = '',
    String description = '',
  }) {
    final startUtc = start.toUtc();
    final endUtc = end.toUtc();
    final duration = endUtc.difference(startUtc);
    if (title.trim().isEmpty || title.runes.length > 200 ||
        location.runes.length > 300 || description.runes.length > 2048 ||
        startUtc.millisecondsSinceEpoch <= 0 || duration <= Duration.zero ||
        duration > const Duration(days: 7) ||
        _containsInlineControl(title) || _containsInlineControl(location) ||
        _containsUnsafeTextControl(description)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'بيانات الموعد غير صالحة أو تتجاوز الحدود المسموحة.',
      ));
    }
    return _invoke(
      context,
      capabilityId: 'calendar.create_event',
      scope: 'calendar_event_draft',
      operation: 'createCalendarEventDraft',
      actionSummary: 'إنشاء مسودة موعد: ${title.trim()}',
      impactSummary: 'سيُفتح تطبيق التقويم بموعد مقترح. لن يُحفظ الموعد ولن تُرسل دعوات حتى تحفظه بنفسك داخل تطبيق التقويم.\n\nالعنوان: ${title.trim()}\nالبداية: ${startUtc.toIso8601String()}\nالنهاية: ${endUtc.toIso8601String()}\nالمكان: $location\nالوصف: $description',
      arguments: <String, Object?>{
        'title': title.trim(),
        'startEpochMs': startUtc.millisecondsSinceEpoch,
        'endEpochMs': endUtc.millisecondsSinceEpoch,
        'location': location,
        'description': description,
      },
      externalEffect: true,
    );
  }

  Future<CapabilityExecutionResult> copyTextToClipboard(
    BuildContext context,
    String content,
  ) {
    if (content.length > 10000 || content.isEmpty ||
        utf8.encode(content).length > 16 * 1024 || _containsUnsafeTextControl(content)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'النص المراد نسخه فارغ أو غير صالح أو يتجاوز الحد المسموح.',
      ));
    }
    final preview = content.length > 3000 ? '${content.substring(0, 3000)}\n[معاينة مختصرة]' : content;
    return _invoke(
      context,
      capabilityId: 'clipboard.write',
      scope: 'system_clipboard_write',
      operation: 'copyText',
      actionSummary: 'نسخ النص إلى حافظة النظام',
      impactSummary: 'سيستبدل Leo محتوى الحافظة الحالي بالنص التالي بعد موافقتك. لا يقرأ Leo محتوى الحافظة السابق.\n\n$preview',
      arguments: <String, Object?>{'content': content},
      externalEffect: true,
    );
  }

  Future<CapabilityExecutionResult> openUrl(
    BuildContext context,
    String url,
  ) {
    final parsed = Uri.tryParse(url);
    if (url.length > 2048 ||
        parsed == null ||
        !const {'http', 'https'}.contains(parsed.scheme.toLowerCase()) ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        _containsAsciiControl(url)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'يسمح بفتح روابط HTTP وHTTPS صالحة فقط.',
      ));
    }
    final normalizedUrl = parsed.replace(scheme: parsed.scheme.toLowerCase()).toString();
    return _invoke(
        context,
        capabilityId: 'device.open_url',
        scope: 'link_handoff',
        operation: 'openUrl',
        actionSummary: 'فتح موقع خارجي',
        impactSummary: 'سيتم فتح هذا الرابط في المتصفح: $normalizedUrl',
        arguments: <String, Object?>{'url': normalizedUrl},
        externalEffect: true,
      );
  }

  Future<CapabilityExecutionResult> launchAndroidApp(
    BuildContext context,
    String packageName,
  ) {
    if (packageName.length > 255 ||
        !RegExp(r'^[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)+$').hasMatch(packageName)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'معرّف تطبيق Android غير صالح.',
      ));
    }
    return _invoke(
        context,
        capabilityId: 'device.app_launch',
        scope: 'selected_application',
        operation: 'launchApp',
        actionSummary: 'فتح التطبيق $packageName',
        impactSummary: 'سيتم فتح التطبيق المثبت فقط دون مشاركة بيانات معه.',
        arguments: <String, Object?>{'packageName': packageName},
      );
  }

  Future<CapabilityExecutionResult> launchWindowsApp(
    BuildContext context,
    String appTarget,
  ) {
    if (appTarget.length > 512 || _containsNul(appTarget)) {
      return Future.value(const CapabilityExecutionResult(
        success: false,
        message: 'هدف تطبيق Windows غير صالح.',
      ));
    }
    return _invoke(
        context,
        capabilityId: 'device.app_launch',
        scope: 'selected_application',
        operation: 'launchApp',
        actionSummary: 'فتح تطبيق Windows',
        impactSummary: appTarget,
        arguments: <String, Object?>{'target': appTarget},
      );
  }

  bool _operationAllowed(String capabilityId, String operation) {
    const allowed = <String, Set<String>>{
      'files.read': {'pickFile', 'readTextFile'},
      'files.open_selected': {'pickFile', 'openSelectedFile'},
      'calendar.create_event': {'createCalendarEventDraft'},
      'clipboard.write': {'copyText'},
      'files.write': {'pickWorkspace', 'applyWorkspaceWrite'},
      'device.app_launch': {'launchApp'},
      'device.open_url': {'openUrl'},
      'phone.dial': {'openDialer'},
      'email.compose': {'composeEmail'},
      'messages.compose': {'composeMessage'},
      'contacts.read': {'readContacts'},
    };
    return allowed[capabilityId]?.contains(operation) ?? false;
  }

  bool _isSafePhoneNumber(String value) =>
      value.length <= 32 && RegExp(r'^[0-9+*#(). -]{1,32}$').hasMatch(value.trim());

  bool _containsNul(String value) => value.contains('\u0000');

  bool _containsAsciiControl(String value) =>
      value.runes.any((rune) => rune < 0x20 || rune == 0x7f);

  bool _containsUnsafeTextControl(String value) => value.runes.any(
        (rune) => rune == 0x7f ||
            (rune < 0x20 && rune != 0x09 && rune != 0x0a && rune != 0x0d),
      );

  bool _containsInlineControl(String value) => value.runes.any(
        (rune) => rune < 0x20 || rune == 0x7f,
      );

  Future<bool> _showWorkspaceWriteApproval(
    BuildContext context, {
    required String relativePath,
    required String workspaceLabel,
    required String before,
    required String after,
    required bool exists,
  }) async {
    if (!context.mounted) return false;
    final diff = WorkspaceWritePolicy.buildDiff(before: before, after: after);
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(exists ? 'مراجعة تعديل الملف' : 'مراجعة إنشاء الملف'),
            content: SizedBox(
              width: 620,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 460),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workspaceLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(relativePath),
                      const SizedBox(height: 8),
                      Text(exists
                          ? 'الأسطر المحذوفة تبدأ بـ - والمضافة بـ +. لن يتغير الملف قبل موافقتك.'
                          : 'سيُنشأ هذا الملف داخل المجلد الذي اخترته. راجع المحتوى قبل الكتابة.'),
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            diff,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('موافقة وتطبيق التعديل'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showConsent(
    BuildContext context,
    LeoCapability capability,
    String scope,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('السماح لـLeo: ${capability.displayName}؟'),
            content: Text(
              '${capability.description}\n\nالنطاق المطلوب: $scope\n\nسيُطلب إذن نظام التشغيل أيضاً عند الحاجة. يمكنك رفض الطلب دون تعطيل بقية وظائف Leo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('رفض'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('السماح'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _showActionApproval(
    BuildContext context, {
    required String title,
    required String impact,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            scrollable: true,
            title: const Text('تأكيد تنفيذ الإجراء'),
            content: Text('$title\n\nالتأثير المتوقع: $impact\n\nهذه موافقة مستقلة عن إذن استخدام القدرة.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('تأكيد التنفيذ'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
