import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../data/models/user_profile.dart';

/// Exposes the authenticated Firebase user together with their profile so
/// widgets can make consistent access-control decisions (like admin overrides).
class UserAccess {
  const UserAccess({
    required this.user,
    this.profile,
  });

  /// The currently signed-in Firebase user, if any.
  final User? user;

  /// The user's Firestore profile document, if any.
  final UserProfile? profile;

  String? get uid => user?.uid;

  bool get isAdmin =>
      profile != null && profile!.userType.toLowerCase() == 'admin';

  /// Returns true if the current user should be treated as the owner for the
  /// provided [ownerUid]. Admins automatically pass.
  bool canEditOwnedContent(String? ownerUid) {
    if (isAdmin) return true;
    final current = uid;
    if (current == null) return false;
    if (ownerUid == null || ownerUid.isEmpty) return false;
    return ownerUid == current;
  }
}

/// Lightweight singleton that non-widget code can consult.
class UserAccessController {
  UserAccessController._();

  static final UserAccessController instance = UserAccessController._();

  UserAccess? _current;

  UserAccess? get current => _current;

  bool get isAdmin => _current?.isAdmin ?? false;

  String? get uid => _current?.uid;

  bool canEditOwnedContent(String? ownerUid) =>
      _current?.canEditOwnedContent(ownerUid) ?? false;

  void update(UserAccess access) {
    _current = access;
  }

  void clear() {
    _current = null;
  }
}

class UserAccessScope extends InheritedWidget {
  const UserAccessScope({
    super.key,
    required this.access,
    required super.child,
  });

  final UserAccess access;

  static UserAccess? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<UserAccessScope>()
        ?.access;
  }

  static UserAccess of(BuildContext context) {
    final access = maybeOf(context);
    if (access == null) {
      throw StateError('UserAccessScope not found in context');
    }
    return access;
  }

  @override
  bool updateShouldNotify(UserAccessScope oldWidget) {
    final old = oldWidget.access;
    return access.uid != old.uid || access.isAdmin != old.isAdmin;
  }
}
