import 'package:flutter_test/flutter_test.dart';
import 'package:sky_engineering_app/src/data/models/invoice.dart';

void main() {
  group('InvoiceDirectExpense', () {
    test('round trips through map data', () {
      final expense = InvoiceDirectExpense.fromMap({
        'description': 'Permit fee',
        'amount': 125.50,
      });

      expect(expense.description, 'Permit fee');
      expect(expense.amount, 125.50);
      expect(expense.toMap(), {
        'description': 'Permit fee',
        'amount': 125.50,
      });
    });
  });

  group('Invoice', () {
    test('writes direct expenses with invoice data', () {
      final invoice = Invoice(
        id: 'invoice-1',
        projectId: 'project-1',
        invoiceNumber: '1220',
        invoiceAmount: 625.50,
        directExpenses: const [
          InvoiceDirectExpense(
            description: 'Permit fee',
            amount: 125.50,
          ),
        ],
      );

      final map = invoice.toMap();

      expect(map['invoiceAmount'], 625.50);
      expect(map['directExpenses'], [
        {
          'description': 'Permit fee',
          'amount': 125.50,
        },
      ]);
    });
  });
}
