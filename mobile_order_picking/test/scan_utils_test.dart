import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_order_picking/core/scan_utils.dart';

void main() {
  test('scan matches barcode or item code', () {
    expect(
      scanMatches(
        scanned: ' 6291109120100 ',
        itemCode: '16-01-02517',
        barcode: '6291109120100',
      ),
      isTrue,
    );

    expect(
      scanMatches(
        scanned: '16-01-02517',
        itemCode: '16-01-02517',
        barcode: '6291109120100',
      ),
      isTrue,
    );

    expect(
      scanMatches(
        scanned: 'wrong-item',
        itemCode: '16-01-02517',
        barcode: '6291109120100',
      ),
      isFalse,
    );
  });
}
