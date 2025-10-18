// lib/src/data/models/invoice.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../utils/data_parsers.dart';

/// Canonical invoice model (new schema), with legacy shims so the current UI
/// continues to compile and run while we migrate screens.
///
/// New canonical fields:
/// - invoiceNumber
/// - projectNumber (optional)
/// - invoiceAmount
/// - amountPaid             <-- NEW canonical paid field
/// - balanceDue (legacy mirror; derived from amountPaid when writing)
/// - invoiceDate (optional)
/// - dueDate (optional)
/// - paidDate (optional)
/// - documentLink (optional)
/// - invoiceType ('Client' | 'Vendor')
///
/// Keep:
/// - projectId (relation to Project)
/// - ownerUid
/// - createdAt / updatedAt
///
/// Legacy shims (constructor params + getters + mirrored map keys):
/// - number    <-> invoiceNumber
/// - amount    <-> invoiceAmount
/// - issueDate <-> invoiceDate
/// - status (stored) with fallback to derived
/// - notes (optional, passthrough)
class Invoice {
  final String id;

  // Relationship
  final String projectId;

  // New schema
  final String invoiceNumber;
  final String? projectNumber;
  final double invoiceAmount;

  /// Canonical paid amount. Defaults to 0.0 when absent.
  final double amountPaid;

  /// Legacy/interop: stored if present on disk; we also derive & write it.
  final double? balanceDue;
  final DateTime? invoiceDate;
  final DateTime? dueDate;
  final DateTime? paidDate;
  final String? documentLink;
  final String invoiceType; // 'Client' | 'Vendor'

  // Meta
  final String? ownerUid;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Stored legacy status (optional) + notes passthrough
  final String? _statusStored;
  final String? notes;

  // ---- Legacy getters used by existing UI ----
  String get number => invoiceNumber;
  double get amount => invoiceAmount;
  DateTime? get issueDate => invoiceDate;

  /// Derived current balance (always computed from invoiceAmount & amountPaid).
  double get balance =>
      (invoiceAmount - amountPaid).clamp(0, double.infinity).toDouble();

  String get status {
    // Prefer stored status if present; otherwise derive from paid.
    final storedStatus = _statusStored;
    if (storedStatus != null && storedStatus.isNotEmpty) return storedStatus;
    final fullyPaid =
        (paidDate != null) || (amountPaid >= invoiceAmount) || (balance <= 0);
    return fullyPaid ? 'Paid' : 'Unpaid';
  }

  /// Flexible constructor to support both new and legacy named params.
  /// Provide either the new names (preferred) or the old names.
  Invoice({
    required this.id,
    required this.projectId,

    // NEW names (preferred)
    String? invoiceNumber,
    double? invoiceAmount,
    DateTime? invoiceDate,
    double? amountPaid,

    // LEGACY names (still accepted)
    String? number,
    double? amount,
    DateTime? issueDate,
    String? status,
    this.notes,

    this.invoiceType = 'Client', // default
    String? projectNumber,
    this.balanceDue,
    this.dueDate,
    this.paidDate,
    this.documentLink,
    this.ownerUid,
    this.createdAt,
    this.updatedAt,
  }) : projectNumber = _normalizeProjectNumber(projectNumber),
       invoiceNumber = invoiceNumber ?? number ?? '',
       invoiceAmount = (invoiceAmount ?? amount ?? 0.0),
       invoiceDate = invoiceDate ?? issueDate,
       _statusStored = status,
       // Normalize amountPaid to [0, invoiceAmount]
       amountPaid = _normalizePaid(
         amountPaid ??
             _derivePaidFromBalance(
               balanceDue,
               (invoiceAmount ?? amount ?? 0.0),
             ),
         (invoiceAmount ?? amount ?? 0.0),
       );

  /// Backward-compatible factory from Firestore doc.
  static Invoice fromDoc(DocumentSnapshot doc) {
    final data = mapFrom(doc.data() as Map<String, dynamic>?);

    final invoiceNumberKey = data.containsKey('invoiceNumber')
        ? 'invoiceNumber'
        : 'number';
    final invoiceAmountKey = data.containsKey('invoiceAmount')
        ? 'invoiceAmount'
        : 'amount';

    final invoiceNumber = readString(data, invoiceNumberKey);
    final invoiceAmount = readDouble(data, invoiceAmountKey);
    final normalizedPaid = _normalizePaid(
      readDoubleOrNull(data, 'amountPaid') ??
          _derivePaidFromBalance(
            readDoubleOrNull(data, 'balanceDue'),
            invoiceAmount,
          ),
      invoiceAmount,
    );

    final invoiceTypeRaw = parseString(data['invoiceType'], fallback: 'Client');
    final invoiceType = invoiceTypeRaw.toLowerCase() == 'vendor'
        ? 'Vendor'
        : 'Client';

    return Invoice(
      id: doc.id,
      projectId: readString(data, 'projectId'),
      projectNumber: readStringOrNull(data, 'projectNumber'),
      invoiceNumber: invoiceNumber,
      invoiceAmount: invoiceAmount,
      amountPaid: normalizedPaid,
      balanceDue: readDoubleOrNull(data, 'balanceDue'),
      invoiceDate:
          readDateTime(data, 'invoiceDate') ?? readDateTime(data, 'issueDate'),
      dueDate: readDateTime(data, 'dueDate'),
      paidDate: readDateTime(data, 'paidDate'),
      documentLink: readStringOrNull(data, 'documentLink'),
      invoiceType: invoiceType,
      ownerUid: readStringOrNull(data, 'ownerUid'),
      createdAt: readDateTime(data, 'createdAt'),
      updatedAt: readDateTime(data, 'updatedAt'),
      status: readStringOrNull(data, 'status'),
      notes: readStringOrNull(data, 'notes'),
    );
  }

  /// Map to Firestore. Writes both new keys and legacy mirrors so old screens keep working.
  Map<String, dynamic> toMap() {
    final computedBalance = (invoiceAmount - amountPaid)
        .clamp(0, double.infinity)
        .toDouble();

    final effectiveStatus =
        _statusStored ??
        ((paidDate != null ||
                amountPaid >= invoiceAmount ||
                computedBalance <= 0)
            ? 'Paid'
            : 'Unpaid');

    return <String, dynamic>{
      // New schema
      'projectId': projectId,
      if (projectNumber != null) 'projectNumber': projectNumber,
      'invoiceNumber': invoiceNumber,
      'invoiceAmount': invoiceAmount,
      'amountPaid': amountPaid,
      'balanceDue': computedBalance,
      'invoiceDate': timestampFromDate(invoiceDate),
      'dueDate': timestampFromDate(dueDate),
      'paidDate': timestampFromDate(paidDate),
      'documentLink': documentLink,
      'invoiceType': invoiceType,
      'ownerUid': ownerUid,

      // Legacy mirrors
      'number': invoiceNumber,
      'amount': invoiceAmount,
      'issueDate': timestampFromDate(invoiceDate),
      'status': effectiveStatus,
      if (notes != null) 'notes': notes,
    };
  }

  Invoice copyWith({
    String? id,
    String? projectId,
    String? projectNumber,
    String? invoiceNumber,
    double? invoiceAmount,
    double? amountPaid,
    double? balanceDue,
    DateTime? invoiceDate,
    DateTime? dueDate,
    DateTime? paidDate,
    String? documentLink,
    String? invoiceType,
    String? ownerUid,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? status,
    String? notes,
  }) {
    final newInvoiceAmount = invoiceAmount ?? this.invoiceAmount;
    final newPaid = amountPaid ?? this.amountPaid;
    final newProjectNumber = projectNumber == null
        ? this.projectNumber
        : _normalizeProjectNumber(projectNumber);

    return Invoice(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      projectNumber: newProjectNumber,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      invoiceAmount: newInvoiceAmount,
      amountPaid: _normalizePaid(newPaid, newInvoiceAmount),
      balanceDue: balanceDue ?? this.balanceDue,
      invoiceDate: invoiceDate ?? this.invoiceDate,
      dueDate: dueDate ?? this.dueDate,
      paidDate: paidDate ?? this.paidDate,
      documentLink: documentLink ?? this.documentLink,
      invoiceType: invoiceType ?? this.invoiceType,
      ownerUid: ownerUid ?? this.ownerUid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? _statusStored,
      notes: notes ?? this.notes,
    );
  }

  /// Returns true when this invoice should be considered part of the project
  /// identified by [projectId] and/or [projectNumber].
  bool matchesProjectKey({required String projectId, String? projectNumber}) {
    if (projectId.isNotEmpty && this.projectId == projectId) {
      return true;
    }

    if (projectNumber == null || projectNumber.trim().isEmpty) {
      return false;
    }

    final candidate = this.projectNumber;
    if (candidate == null || candidate.trim().isEmpty) {
      return false;
    }

    final canonicalTarget = canonicalProjectNumber(projectNumber);
    final canonicalCandidate = canonicalProjectNumber(candidate);
    if (canonicalTarget.isNotEmpty &&
        canonicalCandidate.isNotEmpty &&
        canonicalTarget == canonicalCandidate) {
      return true;
    }

    final digitsTarget = projectNumberDigitsValue(projectNumber);
    final digitsCandidate = projectNumberDigitsValue(candidate);
    if (digitsTarget != null &&
        digitsCandidate != null &&
        digitsTarget == digitsCandidate) {
      return true;
    }

    return false;
  }

  /// Returns invoices from [invoices] that match the provided project key.
  static List<Invoice> filterForProject(
    Iterable<Invoice> invoices, {
    required String projectId,
    String? projectNumber,
  }) {
    final seen = <String>{};
    final result = <Invoice>[];
    for (final inv in invoices) {
      if (inv.matchesProjectKey(
            projectId: projectId,
            projectNumber: projectNumber,
          ) &&
          seen.add(inv.id)) {
        result.add(inv);
      }
    }
    return mergeAndSort([result]);
  }

  /// Merge multiple invoice lists, deduplicate by id, and sort newest first.
  static List<Invoice> mergeAndSort(Iterable<Iterable<Invoice>> sources) {
    final map = <String, Invoice>{};
    for (final group in sources) {
      for (final inv in group) {
        map[inv.id] = inv;
      }
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final ad = a.invoiceDate ?? a.createdAt ?? a.updatedAt;
      final bd = b.invoiceDate ?? b.createdAt ?? b.updatedAt;
      if (ad != null && bd != null) return bd.compareTo(ad);
      if (ad == null && bd != null) return 1;
      if (ad != null && bd == null) return -1;
      return b.invoiceNumber.compareTo(a.invoiceNumber);
    });
    return list;
  }

  /// Canonical form for project numbers: letters/digits only, lowercase.
  static String canonicalProjectNumber(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return '';
    final cleaned = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return cleaned.toLowerCase();
  }

  /// Integer representation of the digits in a project number (ignores letters).
  static int? projectNumberDigitsValue(String? value) {
    final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == null || digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  static String? _normalizeProjectNumber(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  // ---- helpers ----
  static double _derivePaidFromBalance(
    double? balanceDueParam,
    double invoiceAmount,
  ) {
    if (balanceDueParam == null) return 0.0;
    final paid = invoiceAmount - balanceDueParam;
    if (paid.isNaN) return 0.0;
    return paid;
  }

  static double _normalizePaid(double paid, double invoiceAmount) {
    if (paid.isNaN) return 0.0;
    if (paid < 0) return 0.0;
    if (invoiceAmount <= 0) return 0.0;
    if (paid > invoiceAmount) return invoiceAmount;
    return paid;
  }
}
