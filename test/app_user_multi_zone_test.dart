import 'package:daily_order/domain/entities/app_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('effectiveZones merges legacy and multi-zone assignments safely', () {
    const user = AppUser(
      userId: 'user-1',
      role: 'zone_manager',
      zone: 'Zone6',
      zones: ['Zone7', 'Zone6', ''],
      isActive: true,
    );

    expect(user.effectiveZones, ['Zone6', 'Zone7']);
  });

  test('effectiveZones keeps the legacy zone before migration', () {
    const user = AppUser(
      userId: 'user-1',
      role: 'zone_manager',
      zone: 'Zone1',
      isActive: true,
    );

    expect(user.effectiveZones, ['Zone1']);
  });
}
