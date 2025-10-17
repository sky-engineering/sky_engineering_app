// lib/src/data/repositories/invoice_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/invoice.dart';
import '../../utils/data_parsers.dart';

class InvoiceRepository {
  final _col = FirebaseFirestore.instance.collection('invoices');

  /// All invoices (no filter). Sorted client-side by invoiceDate/createdAt desc.
  Stream<List<Invoice>> streamAll() {
    return _col.snapshots().map(_docsToSortedInvoices);
  }

  /// Invoices owned by a specific user. (InvoicesPage uses this.)
  Stream<List<Invoice>> streamAllForUser(String ownerUid) {
    return _col.where('ownerUid', isEqualTo: ownerUid).snapshots().map((snap) {
      final list = snap.docs.map((d) => Invoice.fromDoc(d)).toList();
      list.sort((a, b) {
        final ad = a.invoiceDate ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.invoiceDate ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  /// Invoices for a single project by id.
  Stream<List<Invoice>> streamByProject(String projectId) {
    return _col
        .where('projectId', isEqualTo: projectId)
        .snapshots()
        .map(_docsToSortedInvoices);
  }

  /// Invoices for a project, matching by `projectId` or `projectNumber`.
  Stream<List<Invoice>> streamForProject({
    required String projectId,
    String? projectNumber,
  }) {
    return streamAll().map(
      (list) => Invoice.filterForProject(
        list,
        projectId: projectId,
        projectNumber: projectNumber,
      ),
    );
  }

  Future<Invoice?> getById(String id) async {
    final d = await _col.doc(id).get();
    if (!d.exists) return null;
    return Invoice.fromDoc(d);
  }

  /// Returns the new document id.
  ///
  /// NOTE: The Invoice model's `toMap()` always writes both:
  ///   - `amountPaid` (canonical)
  ///   - `balanceDue` (mirrored = max(0, invoiceAmount - amountPaid))
  /// as well as a legacy `status`.
  Future<String> add(Invoice inv) async {
    final ref = _col.doc();
    final data = inv.copyWith(id: ref.id).toMap();
    await ref.set({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// Partial update with normalization:
  /// - Ensures `amountPaid` and `balanceDue` stay consistent even if caller only supplies one.
  /// - Derives legacy `status` (Paid/Unpaid) for backward compatibility.
  Future<void> update(String id, Map<String, dynamic> partial) async {
    final snap = await _col.doc(id).get();
    if (!snap.exists) return;

    final data = mapFrom(snap.data());
    final mutable = Map<String, dynamic>.from(partial);

    if (mutable.containsKey('projectNumber')) {
      final raw = mutable['projectNumber'];
      if (raw is! FieldValue) {
        mutable['projectNumber'] = parseStringOrNull(raw);
      }
    }

    final currentAmount = data.containsKey('invoiceAmount')
        ? parseDouble(data['invoiceAmount'])
        : parseDouble(data['amount']);
    final currentPaid = data.containsKey('amountPaid')
        ? parseDouble(data['amountPaid'])
        : (data.containsKey('balanceDue')
            ? currentAmount - parseDouble(data['balanceDue'])
            : 0.0);

    final incomingAmount = mutable.containsKey('invoiceAmount')
        ? parseDouble(mutable['invoiceAmount'], fallback: currentAmount)
        : currentAmount;

    double nextPaid;
    if (mutable.containsKey('amountPaid')) {
      nextPaid = parseDouble(mutable['amountPaid'], fallback: currentPaid);
    } else if (mutable.containsKey('balanceDue')) {
      final incomingBalance = parseDouble(
        mutable['balanceDue'],
        fallback: incomingAmount - currentPaid,
      );
      nextPaid = incomingAmount - incomingBalance;
    } else {
      nextPaid = currentPaid;
    }

    if (nextPaid.isNaN || nextPaid < 0) nextPaid = 0.0;
    if (incomingAmount <= 0) nextPaid = 0.0;
    if (nextPaid > incomingAmount) nextPaid = incomingAmount;

    final computedBalance =
        (incomingAmount - nextPaid).clamp(0, double.infinity).toDouble();

    var status = parseStringOrNull(mutable['status']);
    status ??= (computedBalance <= 0 ||
            mutable['paidDate'] != null ||
            data['paidDate'] != null)
        ? 'Paid'
        : 'Unpaid';

    final merged = {
      ...mutable,
      'invoiceAmount': incomingAmount,
      'amountPaid': nextPaid,
      'balanceDue': computedBalance,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _col.doc(id).update(merged);
  }

  Future<void> delete(String id) => _col.doc(id).delete();

  List<Invoice> _docsToSortedInvoices(QuerySnapshot<Map<String, dynamic>> snap) {
    final list = snap.docs.map((d) => Invoice.fromDoc(d)).toList();
    list.sort((a, b) {
      final ad = a.invoiceDate ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.invoiceDate ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }
}
