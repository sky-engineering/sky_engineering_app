// lib/src/data/models/invoice.dart
import 'package:cloud_firestore/cloud_firestore.dart';

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
    if (_statusStored != null && _statusStored!.isNotEmpty) return _statusStored!;
    final fullyPaid = (paidDate != null) || (amountPaid >= invoiceAmount) || (balance <= 0);
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
    double? balanceDue,
    this.dueDate,
    this.paidDate,
    this.documentLink,
    this.ownerUid,
    this.createdAt,
    this.updatedAt,
  })  : projectNumber = _normalizeProjectNumber(projectNumber),
        invoiceNumber = invoiceNumber ?? number ?? '',
        invoiceAmount = (invoiceAmount ?? amount ?? 0.0),
        invoiceDate = invoiceDate ?? issueDate,
        _statusStored = status,
  // Normalize amountPaid to [0, invoiceAmount]
        amountPaid = _normalizePaid(amountPaid ?? _derivePaidFromBalance(balanceDue, (invoiceAmount ?? amount ?? 0.0)),
            (invoiceAmount ?? amount ?? 0.0)),
  // Keep legacy balanceDue field; may be null. If null, we compute a value for writing in toMap().
        balanceDue = balanceDue;

  /// Backward-compatible factory from Firestore doc.
  static Invoice fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? <String, dynamic>{});

    double _toDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? 0.0;
    }

    double? _toDoubleOrNull(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse('$v');
    }

    String? _toProjectNumber(dynamic v) {
      if (v == null) return null;
      if (v is String) {
        final trimmed = v.trim();
        return trimmed.isEmpty ? null : trimmed;
      }
      if (v is num) {
        final text = v.toString();
        return text.isEmpty ? null : text;
      }
      final text = v.toString().trim();
      return text.isEmpty ? null : text;
    }

    DateTime? _toDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    final createdAt = _toDate(data['createdAt']);
    final updatedAt = _toDate(data['updatedAt']);

    final String invNum =
        (data['invoiceNumber'] as String?) ?? (data['number'] as String?) ?? '';

    final double invAmt = data.containsKey('invoiceAmount')
        ? _toDouble(data['invoiceAmount'])
        : _toDouble(data['amount']);

    final DateTime? invDate =
        _toDate(data['invoiceDate']) ?? _toDate(data['issueDate']);

    final String type =
    (data['invoiceType'] as String?) == 'Vendor' ? 'Vendor' : 'Client';

    // Prefer stored amountPaid; otherwise derive from legacy balanceDue.
    final double? storedPaid = _toDoubleOrNull(data['amountPaid']);
    final double? storedBalance = _toDoubleOrNull(data['balanceDue']);
    final double derivedPaid =
        storedPaid ?? _derivePaidFromBalance(storedBalance, invAmt);
    final double normalizedPaid = _normalizePaid(derivedPaid, invAmt);

    // Keep whatever was stored for balanceDue (may be null); UI can use `balance` getter.
    final double? balField = storedBalance;

    return Invoice(
      id: doc.id,
      projectId: (data['projectId'] as String?) ?? '',
      projectNumber: _toProjectNumber(data['projectNumber']),
      invoiceNumber: invNum,
      invoiceAmount: invAmt,
      amountPaid: normalizedPaid,
      balanceDue: balField,
      invoiceDate: invDate,
      dueDate: _toDate(data['dueDate']),
      paidDate: _toDate(data['paidDate']),
      documentLink: data['documentLink'] as String?,
      invoiceType: type,
      ownerUid: data['ownerUid'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,

      // Legacy fields (still persisted in many docs)
      status: data['status'] as String?, // stored status if present
      notes: data['notes'] as String?, // optional passthrough
    );
  }

  /// Map to Firestore. Writes both new keys and legacy mirrors so old screens keep working.
  Map<String, dynamic> toMap() {
    Timestamp? _ts(DateTime? d) => d != null ? Timestamp.fromDate(d) : null;

    // Compute mirrored balanceDue from canonical paid.
    final computedBalance = (invoiceAmount - amountPaid).clamp(0, double.infinity).toDouble();

    final effectiveStatus = _statusStored ??
        ((paidDate != null || amountPaid >= invoiceAmount || computedBalance <= 0)
            ? 'Paid'
            : 'Unpaid');

    return <String, dynamic>{
      // New schema
      'projectId': projectId,
      if (projectNumber != null) 'projectNumber': projectNumber,
      'invoiceNumber': invoiceNumber,
      'invoiceAmount': invoiceAmount,
      'amountPaid': amountPaid,              // <-- canonical
      'balanceDue': computedBalance,         // <-- legacy mirror, kept in sync
      'invoiceDate': _ts(invoiceDate),
      'dueDate': _ts(dueDate),
      'paidDate': _ts(paidDate),
      'documentLink': documentLink,
      'invoiceType': invoiceType,
      'ownerUid': ownerUid,

      // Legacy mirrors
      'number': invoiceNumber,
      'amount': invoiceAmount,
      'issueDate': _ts(invoiceDate),
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

  static String? _normalizeProjectNumber(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  // ---- helpers ----
  static double _derivePaidFromBalance(double? balanceDue, double invoiceAmount) {
    if (balanceDue == null) return 0.0;
    final paid = invoiceAmount - balanceDue;
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
