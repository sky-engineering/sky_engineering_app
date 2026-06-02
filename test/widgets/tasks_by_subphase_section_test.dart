import 'package:flutter_test/flutter_test.dart';
import 'package:sky_engineering_app/src/data/models/project.dart';
import 'package:sky_engineering_app/src/widgets/tasks_by_subphase_section.dart'
    show
        formatSubphaseInvoicedPercent,
        formatSubphaseLabel,
        isProjectTaskActiveStatus;

void main() {
  group('isProjectTaskActiveStatus', () {
    test('only treats In Progress tasks as active', () {
      expect(isProjectTaskActiveStatus('In Progress'), isTrue);
      expect(isProjectTaskActiveStatus(' in progress '), isTrue);
      expect(isProjectTaskActiveStatus('Pending'), isFalse);
      expect(isProjectTaskActiveStatus('pending'), isFalse);
      expect(isProjectTaskActiveStatus('On Hold'), isFalse);
      expect(isProjectTaskActiveStatus('Completed'), isFalse);
      expect(isProjectTaskActiveStatus(null), isFalse);
    });
  });

  group('formatSubphaseInvoicedPercent', () {
    test('formats invoiced amount as percent of contract amount', () {
      const subphase = SelectedSubphase(
        code: '0201',
        name: 'Concept Site Plan',
        isDeliverable: true,
        contractAmount: 1000,
        invoicedAmount: 425,
      );

      expect(formatSubphaseInvoicedPercent(subphase), ' (43%)');
    });

    test('returns zero percent when contract exists without invoicing', () {
      const subphase = SelectedSubphase(
        code: '0201',
        name: 'Concept Site Plan',
        isDeliverable: true,
        contractAmount: 1000,
      );

      expect(formatSubphaseInvoicedPercent(subphase), ' (0%)');
    });

    test('omits percent when contract amount is missing or zero', () {
      const missingContract = SelectedSubphase(
        code: '0201',
        name: 'Concept Site Plan',
        isDeliverable: true,
        invoicedAmount: 425,
      );
      const zeroContract = SelectedSubphase(
        code: '0201',
        name: 'Concept Site Plan',
        isDeliverable: true,
        contractAmount: 0,
        invoicedAmount: 425,
      );

      expect(formatSubphaseInvoicedPercent(missingContract), isEmpty);
      expect(formatSubphaseInvoicedPercent(zeroContract), isEmpty);
    });
  });

  group('formatSubphaseLabel', () {
    test('does not append stored subphase status', () {
      const subphase = SelectedSubphase(
        code: '0201',
        name: 'Concept Site Plan',
        isDeliverable: true,
        status: 'On Hold',
        contractAmount: 1000,
        invoicedAmount: 500,
      );

      expect(formatSubphaseLabel(subphase), '0201  Concept Site Plan (50%)');
    });
  });
}
