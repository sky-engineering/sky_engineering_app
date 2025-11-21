import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/user_repository.dart';
import '../utils/phone_utils.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _repo = UserRepository();

  // Controllers
  final _userNameCtl = TextEditingController();
  final _userPhoneCtl = TextEditingController();
  final _userAddressCtl = TextEditingController();
  final _clientNumberCtl = TextEditingController();

  String? _userType;
  bool _seeded = false;

  User? get _me => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    final u = _me;
    if (u != null) {
      _repo.createIfMissing(u.uid);
    }
  }

  @override
  void dispose() {
    _userNameCtl.dispose();
    _userPhoneCtl.dispose();
    _userAddressCtl.dispose();
    _clientNumberCtl.dispose();
    super.dispose();
  }

  void _seedIfNeeded(UserProfile? p) {
    if (_seeded) return;
    _userType = p?.userType;
    _userNameCtl.text = p?.userName ?? '';
    _userPhoneCtl.text = formatPhoneForDisplay(p?.userPhone);
    _userAddressCtl.text = p?.userAddress ?? '';
    _clientNumberCtl.text = p?.clientNumber ?? '';
    _seeded = true;
  }

  @override
  Widget build(BuildContext context) {
    final u = _me;
    if (u == null) {
      return const Scaffold(
        body: Center(child: Text('Please sign in to view your profile')),
      );
    }

    return StreamBuilder<UserProfile?>(
      stream: _repo.streamByUid(u.uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snap.data;
        _seedIfNeeded(profile);

        return Scaffold(
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---------------- Your Info ----------------
                  _sectionCard(
                    context,
                    child: Column(
                      children: [
                        _kvInputRow(
                          context,
                          label: 'Name',
                          child: TextFormField(
                            controller: _userNameCtl,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'e.g., Jane Smith',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _kvInputRow(
                          context,
                          label: 'Phone',
                          child: TextFormField(
                            controller: _userPhoneCtl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: '(555) 123-4567',
                            ),
                            inputFormatters: const [UsPhoneInputFormatter()],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _kvInputRow(
                          context,
                          label: 'Address',
                          child: TextFormField(
                            controller: _userAddressCtl,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Street, City, State',
                            ),
                          ),
                          alignTop: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---------------- Admin ----------------
                  _sectionCard(
                    context,
                    child: Column(
                      children: [
                        _kvInputRow(
                          context,
                          label: 'Client ID',
                          child: TextFormField(
                            controller: _clientNumberCtl,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'e.g., C-1024',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _kvInputRow(
                          context,
                          label: 'User Type',
                          child: DropdownButtonFormField<String>(
                            initialValue:
                                UserProfile.allowedUserTypes.contains(_userType)
                                    ? _userType
                                    : null,
                            items: UserProfile.allowedUserTypes
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _userType = v),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'Select your type',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: _signOut,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.logout_outlined, size: 18),
                          label: const Text('Sign Out'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _onSave,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _kvReadOnlyRow(
                    context,
                    label: 'UID',
                    value: u.uid,
                  ),

                  const SizedBox(height: 32),

                  const Divider(),
                  const SizedBox(height: 8),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _confirmDeleteAccount,
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Text('Delete Account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onSave() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final u = _me;
    if (u == null) return;

    final normalizedPhone = normalizePhone(_userPhoneCtl.text);

    final profile = UserProfile(
      uid: u.uid,
      userType: _userType ?? 'Other',
      clientNumber: _clientNumberCtl.text.trim().isNotEmpty
          ? _clientNumberCtl.text.trim()
          : null,
      userName:
          _userNameCtl.text.trim().isNotEmpty ? _userNameCtl.text.trim() : null,
      userPhone: normalizedPhone,
      userAddress: _userAddressCtl.text.trim().isNotEmpty
          ? _userAddressCtl.text.trim()
          : null,
    );

    try {
      await _repo.save(profile);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile saved')));
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: ${e.message ?? e.code}')),
        );
      }
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _confirmDeleteAccount() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This will remove your profile and delete your account. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    final user = _me;
    if (user == null) return;
    final uid = user.uid;

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Delete failed: ${e.code}')),
        );
      }
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
      return;
    }

    try {
      await _repo.delete(uid);
    } catch (_) {
      // Best-effort cleanup; ignore if the document is already gone.
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Account deleted')));
    await FirebaseAuth.instance.signOut();
  }
  // ---------------- Helpers ----------------

  // Make the label column nice and tight so the value column has more space.
  double _labelWidthFor(BuildContext context) {
    return 92; // ~6 chars narrower than before
  }

  Widget _sectionCard(BuildContext context, {required Widget child}) {
    return Card(
      color: _subtleSurfaceTint(context),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Color _subtleSurfaceTint(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return Color.alphaBlend(const Color(0x14FFFFFF), surface);
  }

  /// A single “Label  [widget]” row. If [alignTop] is true, label aligns to top.
  Widget _kvInputRow(
    BuildContext context, {
    required String label,
    required Widget child,
    bool alignTop = false,
  }) {
    final labelWidth = _labelWidthFor(context);
    return Row(
      crossAxisAlignment:
          alignTop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }

  /// A single read-only “Label  value” row.
  /// A single read-only “Label  value” row that visually aligns with TextFormField rows.
  Widget _kvReadOnlyRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final labelWidth = _labelWidthFor(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        // Use a read-only TextFormField to match padding/metrics of editable fields
        Expanded(
          child: TextFormField(
            readOnly: true,
            initialValue: value,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
