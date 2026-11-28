import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/simple.dart' as rust_api;
import '../../src/rust/rust_bridge_initializer.dart';

/// Domain-facing memory types keep the UI independent from generated bridge DTOs.
enum LeoMemoryKind { personal, episodic, semantic, procedural, project }

class LeoMemoryEntry {
  const LeoMemoryEntry({
    required this.id,
    required this.kind,
    required this.content,
    required this.tags,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.userApproved,
    required this.active,
    this.sourceReference,
  });

  final String id;
  final LeoMemoryKind kind;
  final String content;
  final List<String> tags;
  final String createdAtUtc;
  final String updatedAtUtc;
  final bool userApproved;
  final bool active;
  final String? sourceReference;

  bool get isPending => !userApproved;
}

class LeoMemorySearchHit {
  const LeoMemorySearchHit({required this.entry, required this.score});

  final LeoMemoryEntry entry;
  final double score;
}

/// Injectable secure-key port so key recovery and rotation can be tested
/// without invoking Android Keystore or Windows Credential Manager.
abstract interface class MemoryKeyStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

class _FlutterMemoryKeyStore implements MemoryKeyStore {
  _FlutterMemoryKeyStore() : _storage = const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);
  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

abstract interface class MemoryRepository {
  Future<List<LeoMemoryEntry>> list({
    bool includePending = true,
    int limit = 200,
  });
  Future<List<LeoMemorySearchHit>> search(String query, {int limit = 5});
  Future<LeoMemoryEntry> propose({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  });
  Future<LeoMemoryEntry> saveApproved({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  });
  Future<LeoMemoryEntry> approve(String memoryId);
  Future<LeoMemoryEntry> setActive(String memoryId, bool active);
  Future<LeoMemoryEntry> updateApproved({
    required String memoryId,
    required String content,
    required List<String> tags,
    String? sourceReference,
  });
  Future<bool> delete(String memoryId);
  Future<void> rotateEncryptionKey();
  Future<bool> eraseAllAndVerify();
}

/// Uses the app-private support directory. Memory payload fields are AES-256-GCM
/// encrypted in SQLite using a key held in OS-backed secure storage. The key
/// is never reconstructed silently when an encrypted database already exists.
class LocalMemoryRepository implements MemoryRepository {
  LocalMemoryRepository({
    Future<Directory> Function()? supportDirectoryProvider,
    MemoryKeyStore? keyStore,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _keyStore = keyStore ?? _FlutterMemoryKeyStore();

  static const keyStorageName = 'leo.memory.encryption_key.v1';
  static const pendingKeyStorageName = 'leo.memory.encryption_key.pending.v1';

  final Future<Directory> Function() _supportDirectoryProvider;
  final MemoryKeyStore _keyStore;

  // All repository instances in the UI isolate share one queue. Key rotation
  // and erase therefore cannot race with chat retrieval or a memory edit.
  static Future<void> _databaseQueue = Future<void>.value();

  Future<String> _databasePath() async {
    final support = await _supportDirectoryProvider();
    final directory = Directory(path.join(support.path, 'leo', 'memory'));
    await directory.create(recursive: true);
    return path.join(directory.path, 'leo-memory.sqlite3');
  }

  Future<void> _initializeBridge() => RustBridgeInitializer.ensureInitialized();

  Future<List<int>> _decodeKey(String value) async {
    final bytes = base64Decode(value);
    if (bytes.length != 32) {
      throw const FormatException(
        'مفتاح تشفير الذاكرة غير صالح؛ لم يتم تغييره تلقائياً.',
      );
    }
    return bytes;
  }

  List<int> _newKey() {
    final random = Random.secure();
    return List<int>.generate(32, (_) => random.nextInt(256), growable: false);
  }

  /// Recovers an interrupted key promotion by testing the pending key against
  /// the authenticated database marker before considering the active key.
  Future<List<int>> _loadOrCreateKey(String databasePath) async {
    final pending = await _keyStore.read(key: pendingKeyStorageName);
    final active = await _keyStore.read(key: keyStorageName);
    if (pending != null) {
      final pendingBytes = await _decodeKey(pending);
      try {
        await rust_api.memoryList(
          databasePath: databasePath,
          encryptionKey: pendingBytes,
          includePending: true,
          limit: 1,
        );
        await _keyStore.write(key: keyStorageName, value: pending);
        await _keyStore.delete(key: pendingKeyStorageName);
        return pendingBytes;
      } catch (_) {
        if (active != null) {
          final activeBytes = await _decodeKey(active);
          try {
            await rust_api.memoryList(
              databasePath: databasePath,
              encryptionKey: activeBytes,
              includePending: true,
              limit: 1,
            );
            await _keyStore.delete(key: pendingKeyStorageName);
            return activeBytes;
          } catch (_) {
            // Do not overwrite either key or the database when neither works.
          }
        }
        throw StateError(
          'تعذر استعادة مفتاح الذاكرة؛ احتفظ بملف النسخة الاحتياطية ولا تحذف بيانات التطبيق.',
        );
      }
    }
    if (active != null) return _decodeKey(active);

    final status = await rust_api.memoryStorageStatus(
      databasePath: databasePath,
    );
    if (status == 'encrypted') {
      throw StateError(
        'قاعدة الذاكرة مشفرة لكن مفتاحها غير موجود في التخزين الآمن. لن يتم إنشاء مفتاح بديل حتى لا تفقد بياناتك.',
      );
    }
    final key = _newKey();
    await _keyStore.write(key: keyStorageName, value: base64Encode(key));
    return key;
  }

  Future<T> _withDatabase<T>(
    Future<T> Function(String databasePath, List<int> encryptionKey) operation,
  ) => _serialize(() async {
    final databasePath = await _databasePath();
    final encryptionKey = await _loadOrCreateKey(databasePath);
    return operation(databasePath, encryptionKey);
  });

  /// Reads do not recreate a fresh database/key immediately after the user
  /// explicitly erased memory. A legacy plaintext database still proceeds to
  /// key creation and transactional migration; an encrypted database without
  /// its key continues to fail closed in [_loadOrCreateKey].
  Future<T?> _withExistingDatabase<T>(
    Future<T> Function(String databasePath, List<int> encryptionKey) operation,
  ) => _serialize(() async {
    final databasePath = await _databasePath();
    final active = await _keyStore.read(key: keyStorageName);
    final pending = await _keyStore.read(key: pendingKeyStorageName);
    final status = await rust_api.memoryStorageStatus(
      databasePath: databasePath,
    );
    if (status == 'empty' && active == null && pending == null) {
      return null;
    }
    final encryptionKey = await _loadOrCreateKey(databasePath);
    return operation(databasePath, encryptionKey);
  });

  Future<T> _serialize<T>(Future<T> Function() action) {
    final operation = _databaseQueue.then((_) => action());
    _databaseQueue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  @override
  Future<List<LeoMemoryEntry>> list({
    bool includePending = true,
    int limit = 200,
  }) async {
    await _initializeBridge();
    final entries = await _withExistingDatabase((
      databasePath,
      encryptionKey,
    ) async {
      final values = await rust_api.memoryList(
        databasePath: databasePath,
        encryptionKey: encryptionKey,
        includePending: includePending,
        limit: limit,
      );
      return values.map(_fromDto).toList(growable: false);
    });
    return entries ?? const <LeoMemoryEntry>[];
  }

  @override
  Future<List<LeoMemorySearchHit>> search(String query, {int limit = 5}) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return const [];
    await _initializeBridge();
    final hits = await _withExistingDatabase((
      databasePath,
      encryptionKey,
    ) async {
      final values = await rust_api.memorySearch(
        databasePath: databasePath,
        encryptionKey: encryptionKey,
        query: normalizedQuery,
        limit: limit,
      );
      return values
          .map(
            (hit) => LeoMemorySearchHit(
              entry: _fromDto(hit.entry),
              score: hit.score,
            ),
          )
          .toList(growable: false);
    });
    return hits ?? const <LeoMemorySearchHit>[];
  }

  @override
  Future<LeoMemoryEntry> propose({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) async {
    await _initializeBridge();
    return _withDatabase((databasePath, encryptionKey) async {
      final entry = await rust_api.memoryPropose(
        databasePath: databasePath,
        encryptionKey: encryptionKey,
        id: _newMemoryId(),
        kind: kind.name,
        content: content,
        sourceReference: sourceReference,
        tags: tags,
        createdAtUtc: DateTime.now().toUtc().toIso8601String(),
      );
      return _fromDto(entry);
    });
  }

  @override
  Future<LeoMemoryEntry> saveApproved({
    required LeoMemoryKind kind,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) async {
    await _initializeBridge();
    return _withDatabase((databasePath, encryptionKey) async {
      final entry = await rust_api.memorySaveApproved(
        databasePath: databasePath,
        encryptionKey: encryptionKey,
        id: _newMemoryId(),
        kind: kind.name,
        content: content,
        sourceReference: sourceReference,
        tags: tags,
        createdAtUtc: DateTime.now().toUtc().toIso8601String(),
      );
      return _fromDto(entry);
    });
  }

  @override
  Future<LeoMemoryEntry> approve(String memoryId) async {
    await _initializeBridge();
    return _withDatabase(
      (databasePath, encryptionKey) async => _fromDto(
        await rust_api.memoryApprove(
          databasePath: databasePath,
          encryptionKey: encryptionKey,
          memoryId: memoryId,
        ),
      ),
    );
  }

  @override
  Future<LeoMemoryEntry> setActive(String memoryId, bool active) async {
    await _initializeBridge();
    return _withDatabase(
      (databasePath, encryptionKey) async => _fromDto(
        await rust_api.memorySetActive(
          databasePath: databasePath,
          encryptionKey: encryptionKey,
          memoryId: memoryId,
          active: active,
        ),
      ),
    );
  }

  @override
  Future<LeoMemoryEntry> updateApproved({
    required String memoryId,
    required String content,
    required List<String> tags,
    String? sourceReference,
  }) async {
    await _initializeBridge();
    return _withDatabase(
      (databasePath, encryptionKey) async => _fromDto(
        await rust_api.memoryUpdateApproved(
          databasePath: databasePath,
          encryptionKey: encryptionKey,
          memoryId: memoryId,
          content: content,
          tags: tags,
          sourceReference: sourceReference,
        ),
      ),
    );
  }

  @override
  Future<bool> delete(String memoryId) async {
    await _initializeBridge();
    return _withDatabase(
      (databasePath, encryptionKey) async => rust_api.memoryDelete(
        databasePath: databasePath,
        encryptionKey: encryptionKey,
        memoryId: memoryId,
      ),
    );
  }

  @override
  Future<void> rotateEncryptionKey() async {
    await _initializeBridge();
    await _serialize(() async {
      final databasePath = await _databasePath();
      final oldKey = await _loadOrCreateKey(databasePath);
      final newKey = _newKey();
      final encodedNewKey = base64Encode(newKey);
      await _keyStore.write(key: pendingKeyStorageName, value: encodedNewKey);
      // If rotation commits but promoting the secure key fails, the pending
      // key remains available for authenticated recovery on the next access.
      await rust_api.memoryRotateEncryptionKey(
        databasePath: databasePath,
        oldKey: oldKey,
        newKey: newKey,
      );
      await _keyStore.write(key: keyStorageName, value: encodedNewKey);
      await _keyStore.delete(key: pendingKeyStorageName);
    });
  }

  @override
  Future<bool> eraseAllAndVerify() async {
    await _initializeBridge();
    return _serialize(() async {
      final databasePath = await _databasePath();
      final erased = await rust_api.memoryEraseDatabase(
        databasePath: databasePath,
      );
      if (!erased) return false;
      await _keyStore.delete(key: pendingKeyStorageName);
      await _keyStore.delete(key: keyStorageName);
      final fileAbsent =
          !File(databasePath).existsSync() &&
          !File('$databasePath-wal').existsSync() &&
          !File('$databasePath-shm').existsSync() &&
          !File('$databasePath-journal').existsSync();
      final keysAbsent =
          await _keyStore.read(key: pendingKeyStorageName) == null &&
          await _keyStore.read(key: keyStorageName) == null;
      final state = await rust_api.memoryStorageStatus(
        databasePath: databasePath,
      );
      return fileAbsent && keysAbsent && state == 'empty';
    });
  }

  LeoMemoryEntry _fromDto(rust_api.MemoryEntryDto dto) => LeoMemoryEntry(
    id: dto.id,
    kind: LeoMemoryKind.values.byName(dto.kind),
    content: dto.content,
    tags: List.unmodifiable(dto.tags),
    createdAtUtc: dto.createdAtUtc,
    updatedAtUtc: dto.updatedAtUtc,
    userApproved: dto.userApproved,
    active: dto.active,
    sourceReference: dto.sourceReference,
  );

  String _newMemoryId() => 'memory-${DateTime.now().microsecondsSinceEpoch}';
}
