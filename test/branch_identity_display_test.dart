import 'package:daily_order/core/utils/branch_csv_display.dart';
import 'package:daily_order/core/utils/store_branch_identity_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    StoreBranchIdentityRegistry.groups.value = const {
      'AL AIN': '71',
      'CITY': 'APG',
      'A,"B': '71',
    };
  });

  tearDown(() => StoreBranchIdentityRegistry.groups.value = const {});

  test('prefixes only group 71 and does not prefix twice', () {
    expect(StoreBranchIdentityRegistry.displayName('Al Ain'), '71 Al Ain');
    expect(StoreBranchIdentityRegistry.displayName('71 Al Ain'), '71 Al Ain');
    expect(StoreBranchIdentityRegistry.displayName('City'), 'City');
    expect(
      StoreBranchIdentityRegistry.exportValue('branch_name', 'Al Ain'),
      '71 Al Ain',
    );
    expect(
      StoreBranchIdentityRegistry.exportValue('item_name', 'Al Ain'),
      'Al Ain',
    );
  });

  test('decorates a selected CSV field and preserves quoted neighbours', () {
    expect(
      decorateBranchCsvField('123,"Al Ain","item, one"', 1),
      '123,"71 Al Ain","item, one"',
    );
    expect(
      decorateBranchCsvField('123,"A,""B","item, one"', 1),
      '123,"71 A,""B","item, one"',
    );
    expect(decorateBranchCsvField('123,City,item', 1), '123,City,item');
  });
}
