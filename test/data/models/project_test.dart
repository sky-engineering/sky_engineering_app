import 'package:flutter_test/flutter_test.dart';
import 'package:sky_engineering_app/src/data/models/project.dart';

void main() {
  group('SelectedSubphase', () {
    test('reads and writes subphase amounts', () {
      final subphase = SelectedSubphase.fromMap({
        'code': '0201',
        'name': 'Concept Site Plan',
        'isDeliverable': true,
        'status': 'In Progress',
        'contractAmount': 1250.50,
        'invoicedAmount': 500.25,
      });

      expect(subphase.contractAmount, 1250.50);
      expect(subphase.invoicedAmount, 500.25);
      expect(subphase.toMap()['contractAmount'], 1250.50);
      expect(subphase.toMap()['invoicedAmount'], 500.25);
    });

    test('can clear subphase amounts through copyWith', () {
      const subphase = SelectedSubphase(
        code: '0201',
        name: 'Concept Site Plan',
        isDeliverable: true,
        contractAmount: 1250.50,
        invoicedAmount: 500.25,
      );

      final updated = subphase.copyWith(
        contractAmount: null,
        invoicedAmount: null,
      );

      expect(updated.contractAmount, isNull);
      expect(updated.invoicedAmount, isNull);
      expect(updated.toMap().containsKey('contractAmount'), isFalse);
      expect(updated.toMap().containsKey('invoicedAmount'), isFalse);
    });
  });
}
