import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../src/rust/api/simple.dart' as rust_api;
import '../../src/rust/rust_bridge_initializer.dart';

enum LeoCapabilityRisk { readOnly, low, moderate, high, critical }

enum LeoPermissionStatus {
  requestFirstUse,
  allowed,
  previouslyDenied,
  expiredGrant,
  osPermissionRequired,
  osPermissionRevoked,
  scopeUpgradeRequired,
}

class LeoCapability {
  const LeoCapability({
    required this.id,
    required this.displayName,
    required this.description,
    required this.platforms,
    required this.providerOrder,
    required this.grantScope,
    required this.risk,
    required this.availableOffline,
    required this.supportedInAlpha,
  });

  final String id;
  final String displayName;
  final String description;
  final List<String> platforms;
  final List<String> providerOrder;
  final String grantScope;
  final LeoCapabilityRisk risk;
  final bool availableOffline;
  final bool supportedInAlpha;

  factory LeoCapability.fromDto(rust_api.CapabilityDto dto) => LeoCapability(
    id: dto.id,
    displayName: dto.displayName,
    description: dto.description,
    platforms: List.unmodifiable(dto.platforms),
    providerOrder: List.unmodifiable(dto.providerOrder),
    grantScope: dto.grantScope,
    risk: LeoCapabilityRisk.values.byName(_riskNameToDart(dto.risk)),
    availableOffline: dto.availableOffline,
    supportedInAlpha: dto.supportedInAlpha,
  );
}

class LeoPermissionRecord {
  const LeoPermissionRecord({
    required this.id,
    required this.capabilityId,
    required this.scope,
    required this.granted,
    required this.grantedAtUtc,
    required this.updatedAtUtc,
    this.expiresAtUtc,
  });

  final String id;
  final String capabilityId;
  final String scope;
  final bool granted;
  final String grantedAtUtc;
  final String updatedAtUtc;
  final String? expiresAtUtc;

  factory LeoPermissionRecord.fromDto(rust_api.PermissionRecordDto dto) =>
      LeoPermissionRecord(
        id: dto.id,
        capabilityId: dto.capabilityId,
        scope: dto.scope,
        granted: dto.granted,
        grantedAtUtc: dto.grantedAtUtc,
        updatedAtUtc: dto.updatedAtUtc,
        expiresAtUtc: dto.expiresAtUtc,
      );
}

class LeoPermissionCheck {
  const LeoPermissionCheck({
    required this.status,
    required this.allowed,
    required this.needsLeoConsent,
    required this.needsOsPermission,
    required this.needsScopeUpgrade,
  });

  final LeoPermissionStatus status;
  final bool allowed;
  final bool needsLeoConsent;
  final bool needsOsPermission;
  final bool needsScopeUpgrade;

  factory LeoPermissionCheck.fromDto(rust_api.PermissionCheckDto dto) =>
      LeoPermissionCheck(
        status: LeoPermissionStatus.values.byName(
          _statusNameToDart(dto.status),
        ),
        allowed: dto.allowed,
        needsLeoConsent: dto.needsLeoConsent,
        needsOsPermission: dto.needsOsPermission,
        needsScopeUpgrade: dto.needsScopeUpgrade,
      );
}

abstract interface class CapabilityRepository {
  Future<List<LeoCapability>> list(String platform);
  Future<List<LeoPermissionRecord>> listPermissions({int limit = 200});
  Future<LeoPermissionCheck> check({
    required String capabilityId,
    required String scope,
    required bool osPermissionGranted,
  });
  Future<LeoPermissionRecord> recordDecision({
    required String capabilityId,
    required String scope,
    required bool granted,
  });
  Future<bool> revoke({required String capabilityId, required String scope});
  Future<bool> actionRequiresConfirmation({
    required LeoCapabilityRisk risk,
    required bool externalEffect,
    required bool destructive,
  });
}

/// Persistent broker. The database is kept under Leo's app-private directory;
/// a saved Leo consent never substitutes for checking the live OS permission.
class LocalCapabilityRepository implements CapabilityRepository {
  LocalCapabilityRepository({
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectoryProvider;

  Future<void> _initialize() => RustBridgeInitializer.ensureInitialized();

  Future<String> _databasePath() async {
    final support = await _supportDirectoryProvider();
    final directory = Directory(path.join(support.path, 'leo', 'permissions'));
    await directory.create(recursive: true);
    return path.join(directory.path, 'leo-permissions.sqlite3');
  }

  @override
  Future<List<LeoCapability>> list(String platform) async {
    await _initialize();
    final values = await rust_api.capabilityList(platform: platform);
    return values.map(LeoCapability.fromDto).toList(growable: false);
  }

  @override
  Future<List<LeoPermissionRecord>> listPermissions({int limit = 200}) async {
    await _initialize();
    final databasePath = await _databasePath();
    final records = await rust_api.permissionList(
      databasePath: databasePath,
      limit: limit,
    );
    return records.map(LeoPermissionRecord.fromDto).toList(growable: false);
  }

  @override
  Future<LeoPermissionCheck> check({
    required String capabilityId,
    required String scope,
    required bool osPermissionGranted,
  }) async {
    await _initialize();
    final databasePath = await _databasePath();
    final value = await rust_api.permissionCheck(
      databasePath: databasePath,
      capabilityId: capabilityId,
      scope: scope,
      operatingSystemGranted: osPermissionGranted,
      nowUtc: DateTime.now().toUtc().toIso8601String(),
    );
    return LeoPermissionCheck.fromDto(value);
  }

  @override
  Future<LeoPermissionRecord> recordDecision({
    required String capabilityId,
    required String scope,
    required bool granted,
  }) async {
    await _initialize();
    final databasePath = await _databasePath();
    final value = await rust_api.permissionRecordDecision(
      databasePath: databasePath,
      grantId: 'grant-${DateTime.now().microsecondsSinceEpoch}',
      capabilityId: capabilityId,
      scope: scope,
      granted: granted,
      grantedAtUtc: DateTime.now().toUtc().toIso8601String(),
      expiresAtUtc: null,
    );
    return LeoPermissionRecord.fromDto(value);
  }

  @override
  Future<bool> revoke({
    required String capabilityId,
    required String scope,
  }) async {
    await _initialize();
    final databasePath = await _databasePath();
    return rust_api.permissionRevoke(
      databasePath: databasePath,
      capabilityId: capabilityId,
      scope: scope,
      revokedAtUtc: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<bool> actionRequiresConfirmation({
    required LeoCapabilityRisk risk,
    required bool externalEffect,
    required bool destructive,
  }) async {
    await _initialize();
    final name = switch (risk) {
      LeoCapabilityRisk.readOnly => 'read_only',
      LeoCapabilityRisk.low => 'low',
      LeoCapabilityRisk.moderate => 'moderate',
      LeoCapabilityRisk.high => 'high',
      LeoCapabilityRisk.critical => 'critical',
    };
    return rust_api.actionConfirmationRequired(
      risk: name,
      externalEffect: externalEffect,
      destructive: destructive,
    );
  }
}

String _riskNameToDart(String value) => switch (value) {
  'read_only' => 'readOnly',
  'low' => 'low',
  'moderate' => 'moderate',
  'high' => 'high',
  'critical' => 'critical',
  _ => throw FormatException('Unknown capability risk: $value'),
};

String _statusNameToDart(String value) => switch (value) {
  'request_first_use' => 'requestFirstUse',
  'allowed' => 'allowed',
  'previously_denied' => 'previouslyDenied',
  'expired_grant' => 'expiredGrant',
  'os_permission_required' => 'osPermissionRequired',
  'os_permission_revoked' => 'osPermissionRevoked',
  'scope_upgrade_required' => 'scopeUpgradeRequired',
  _ => throw FormatException('Unknown permission status: $value'),
};
