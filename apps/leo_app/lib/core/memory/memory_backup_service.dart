import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'memory_repository.dart';

class MemoryBackupImportReport {
  const MemoryBackupImportReport({
    required this.proposed,
    required this.duplicatesSkipped,
    required this.invalidSkipped,
  });

  final int proposed;
  final int duplicatesSkipped;
  final int invalidSkipped;
}

/// Password-encrypted, authenticated export/import. Imported records are always
/// pending proposals; the backup cannot restore approval or activation state.
class MemoryBackupService {
  MemoryBackupService(this._repository);

  static const format = 'leo-memory-backup';
  static const schemaVersion = 1;
  static const kdfIterations = 210000;
  static const maxBackupBytes = 5 * 1024 * 1024;
  static const maxEntries = 1_000;
  static const maxContentCharacters = 20000;

  final MemoryRepository _repository;
  final AesGcm _cipher = AesGcm.with256bits();
  final Random _random = Random.secure();

  Future<List<int>> exportEncrypted(String passphrase) async {
    _validatePassphrase(passphrase);
    final entries = await _repository.list(
      includePending: true,
      limit: maxEntries + 1,
    );
    if (entries.length > maxEntries) {
      throw const FormatException(
        'تحتوي الذاكرة على سجلات أكثر من حد النسخ الاحتياطي.',
      );
    }
    final payload = <String, Object?>{
      'format': format,
      'version': schemaVersion,
      'createdAtUtc': DateTime.now().toUtc().toIso8601String(),
      'records': entries
          .map(
            (entry) => <String, Object?>{
              'kind': entry.kind.name,
              'content': entry.content,
              'tags': entry.tags,
              'createdAtUtc': entry.createdAtUtc,
              // Approval/active state and source paths are intentionally omitted.
            },
          )
          .toList(growable: false),
    };
    final clearBytes = utf8.encode(jsonEncode(payload));
    if (clearBytes.length > maxBackupBytes) {
      throw const FormatException(
        'حجم بيانات الذاكرة أكبر من حد ملف النسخة الاحتياطية.',
      );
    }
    final salt = _randomBytes(16);
    final derivedKey = await _deriveKey(passphrase, salt);
    final box = await _cipher.encrypt(clearBytes, secretKey: derivedKey);
    final envelope = <String, Object?>{
      'format': format,
      'version': schemaVersion,
      'cipher': 'AES-256-GCM',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': kdfIterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    };
    final bytes = utf8.encode(jsonEncode(envelope));
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('ملف النسخة الاحتياطية تجاوز الحد المسموح.');
    }
    return bytes;
  }

  Future<MemoryBackupImportReport> importEncrypted(
    List<int> bytes,
    String passphrase,
  ) async {
    _validatePassphrase(passphrase);
    if (bytes.isEmpty || bytes.length > maxBackupBytes) {
      throw const FormatException('حجم ملف النسخة الاحتياطية غير صالح.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['version'] != schemaVersion ||
        decoded['cipher'] != 'AES-256-GCM' ||
        decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
        decoded['iterations'] != kdfIterations) {
      throw const FormatException('صيغة ملف النسخة الاحتياطية غير مدعومة.');
    }
    final salt = _decodeField(decoded, 'salt', expectedLength: 16);
    final nonce = _decodeField(decoded, 'nonce', expectedLength: 12);
    final cipherText = _decodeField(decoded, 'ciphertext');
    final mac = _decodeField(decoded, 'mac', expectedLength: 16);
    final derivedKey = await _deriveKey(passphrase, salt);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: derivedKey,
    );
    if (clear.length > maxBackupBytes) {
      throw const FormatException(
        'محتوى النسخة الاحتياطية أكبر من الحد المسموح.',
      );
    }
    final payload = jsonDecode(utf8.decode(clear));
    if (payload is! Map<String, dynamic> ||
        payload['format'] != format ||
        payload['version'] != schemaVersion ||
        payload['records'] is! List) {
      throw const FormatException('محتوى النسخة الاحتياطية غير صالح.');
    }
    final records = payload['records'] as List;
    if (records.length > maxEntries) {
      throw const FormatException(
        'تحتوي النسخة الاحتياطية على سجلات أكثر من الحد المسموح.',
      );
    }

    var proposed = 0;
    var duplicates = 0;
    var invalid = 0;
    for (final raw in records) {
      if (raw is! Map<String, dynamic>) {
        invalid++;
        continue;
      }
      final kindName = raw['kind'];
      final content = raw['content'];
      final tagsValue = raw['tags'];
      final createdAtValue = raw['createdAtUtc'];
      final kind = kindName is String
          ? LeoMemoryKind.values
                .where((value) => value.name == kindName)
                .firstOrNull
          : null;
      if (kind == null ||
          content is! String ||
          content.trim().isEmpty ||
          content.runes.length > maxContentCharacters ||
          tagsValue is! List ||
          tagsValue.length > 20 ||
          tagsValue.any((tag) => tag is! String) ||
          createdAtValue is! String ||
          DateTime.tryParse(createdAtValue) == null) {
        invalid++;
        continue;
      }
      try {
        await _repository.propose(
          kind: kind,
          content: content,
          tags: tagsValue.cast<String>(),
          sourceReference: 'encrypted-backup-import:v1',
        );
        proposed++;
      } catch (error) {
        if (error.toString().toLowerCase().contains('duplicate') ||
            error.toString().contains('مكررة')) {
          duplicates++;
        } else {
          invalid++;
        }
      }
    }
    return MemoryBackupImportReport(
      proposed: proposed,
      duplicatesSkipped: duplicates,
      invalidSkipped: invalid,
    );
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) {
    final kdf = Pbkdf2.hmacSha256(iterations: kdfIterations, bits: 256);
    return kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256), growable: false);

  List<int> _decodeField(
    Map<String, dynamic> envelope,
    String field, {
    int? expectedLength,
  }) {
    final value = envelope[field];
    if (value is! String || value.length > maxBackupBytes * 2) {
      throw FormatException('حقل النسخة الاحتياطية غير صالح: $field');
    }
    final bytes = base64Decode(value);
    if (expectedLength != null && bytes.length != expectedLength) {
      throw FormatException('طول حقل النسخة الاحتياطية غير صالح: $field');
    }
    return bytes;
  }

  void _validatePassphrase(String passphrase) {
    if (passphrase.runes.length < 12 ||
        utf8.encode(passphrase).length > 256 ||
        passphrase.trim() != passphrase) {
      throw const FormatException(
        'يجب أن تتكون كلمة مرور النسخة من 12 محرفاً على الأقل، دون مسافات طرفية.',
      );
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
