import 'package:daily_order/core/config/tibah_max_config.dart';
import 'package:daily_order/domain/entities/tibah_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('temporary routing can be retired without changing ordinary Max', () {
    expect(TibahOrderType.upp.branchName, 'tibah upp');
    expect(TibahOrderType.regular.branchName, 'tibah regular');
    expect(TibahOrder.isBranch('Tibah UPP'), TibahMaxConfig.enabled);
    expect(TibahOrder.isBranch('tibah regular'), TibahMaxConfig.enabled);
    expect(TibahOrder.isBranch('Tibah'), false);
    expect(TibahOrder.isBranch('Another branch'), false);
  });
}
