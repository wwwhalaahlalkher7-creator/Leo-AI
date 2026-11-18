import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leo_app/core/capabilities/capability_repository.dart';
import 'package:leo_app/features/capabilities/capability_center_page.dart';

class _FakeCapabilityRepository implements CapabilityRepository {
  final records = <LeoPermissionRecord>[];

  @override
  Future<List<LeoCapability>> list(String platform) async => const [
        LeoCapability(
          id: 'device.open_url',
          displayName: 'Open a link',
          description: 'Open an HTTP or HTTPS link in the registered browser.',
          platforms: ['android', 'windows'],
          providerOrder: ['operating_system'],
          grantScope: 'link_handoff',
          risk: LeoCapabilityRisk.moderate,
          availableOffline: true,
          supportedInAlpha: true,
        ),
      ];

  @override
  Future<List<LeoPermissionRecord>> listPermissions({int limit = 200}) async => records;

  @override
  Future<LeoPermissionCheck> check({required String capabilityId, required String scope, required bool osPermissionGranted}) async =>
      const LeoPermissionCheck(status: LeoPermissionStatus.requestFirstUse, allowed: false, needsLeoConsent: true, needsOsPermission: false, needsScopeUpgrade: false);

  @override
  Future<LeoPermissionRecord> recordDecision({required String capabilityId, required String scope, required bool granted}) async {
    final record = LeoPermissionRecord(
      id: 'grant-1',
      capabilityId: capabilityId,
      scope: scope,
      granted: granted,
      grantedAtUtc: '2026-11-16T00:00:00Z',
      updatedAtUtc: '2026-11-16T00:00:00Z',
    );
    records.add(record);
    return record;
  }

  @override
  Future<bool> revoke({required String capabilityId, required String scope}) async => true;

  @override
  Future<bool> actionRequiresConfirmation({required LeoCapabilityRisk risk, required bool externalEffect, required bool destructive}) async => false;
}

void main() {
  testWidgets('capability centre explains first-use permissions without requesting them on open', (tester) async {
    final repository = _FakeCapabilityRepository();
    await tester.pumpWidget(MaterialApp(home: CapabilityCenterPage(repository: repository)));
    await tester.pumpAndSettle();

    expect(find.text('قدرات الجهاز والصلاحيات'), findsOneWidget);
    expect(find.text('يُطلب عند أول استخدام'), findsOneWidget);
    expect(find.textContaining('لا يطلب Leo صلاحيات عند التشغيل الأول'), findsOneWidget);
    expect(repository.records, isEmpty);
  });
}
