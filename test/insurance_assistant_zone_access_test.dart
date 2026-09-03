import 'package:daily_order/presentation/orders/widgets/insurance_assistant_zone_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InsuranceAssistantZoneAccess', () {
    test('enables Zone4 including harmless formatting differences', () {
      expect(InsuranceAssistantZoneAccess.isEnabled('Zone4'), isTrue);
      expect(InsuranceAssistantZoneAccess.isEnabled(' zone4 '), isTrue);
      expect(InsuranceAssistantZoneAccess.isEnabled('Zone 4'), isTrue);
      expect(InsuranceAssistantZoneAccess.isEnabled('ZONE-4'), isTrue);
    });

    test('rejects every other or unresolved zone', () {
      for (final zone in <String?>[
        null,
        '',
        'Zone O',
        'Zone O–AD',
        'Zone1',
        'Zone3',
        'Zone5',
        'Zone6',
        'Zone7',
      ]) {
        expect(
          InsuranceAssistantZoneAccess.isEnabled(zone),
          isFalse,
          reason: '$zone must not see Insurance AI',
        );
      }
    });
  });
}
