// lib/src/dialogs/city_inspect_links_dialog.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firestore collection for links:
///   /city_inspect/{id} : { name: string, url: string, ownerUid: string, createdAt: Timestamp, updatedAt: Timestamp }
///
/// Make sure your firestore.rules include the match for /city_inspect (see note at bottom).
Future<void> showCityInspectLinksDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => const _CityInspectDialog(),
  );
}

class _CityInspectDialog extends StatefulWidget {
  const _CityInspectDialog();

  @override
  State<_CityInspectDialog> createState() => _CityInspectDialogState();
}

class _CityInspectDialogState extends State<_CityInspectDialog> {
  static const _coll = 'city_inspect';

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;
    final colRef = FirebaseFirestore.instance.collection(_coll).orderBy('name');

    return AlertDialog(
      title: const Text('City Inspect Links'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            // Small permission hint
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                me == null
                    ? 'Viewing as guest — sign in to add or edit.'
                    : 'Signed in as ${me.email ?? me.uid}. You can edit links you created.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: colRef.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return _EmptyState(onSeed: _seedStGeorge);
                  }
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final data = d.data();
                      final name = (data['name'] as String?)?.trim() ?? '';
                      final url = (data['url'] as String?)?.trim() ?? '';
                      final ownerUid = (data['ownerUid'] as String?) ?? '';

                      final canSuggestEdit = me != null; // UI-level; server enforces exact owner

                      return Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          dense: true,
                          contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          title: Text(
                            name.isEmpty ? '(unnamed)' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            url.isEmpty ? '—' : url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              IconButton(
                                tooltip: 'Open',
                                icon: const Icon(Icons.launch),
                                onPressed: url.isEmpty ? null : () => _open(url),
                                visualDensity: VisualDensity.compact,
                              ),
                              IconButton(
                                tooltip: ownerUid == me?.uid
                                    ? 'Edit'
                                    : 'Request edit (you may lack permission)',
                                icon: const Icon(Icons.edit),
                                onPressed: canSuggestEdit
                                    ? () => _editCity(d.id, name, url)
                                    : null,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (me != null)
          FilledButton.icon(
            onPressed: _addCity,
            icon: const Icon(Icons.add),
            label: const Text('Add City'),
          ),
      ],
    );
  }

  Future<void> _open(String urlStr) async {
    final uri = Uri.tryParse(urlStr);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Invalid URL')));
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not open link')));
    }
  }

  Future<void> _addCity() async {
    await _showEditDialog();
  }

  Future<void> _editCity(String id, String name, String url) async {
    await _showEditDialog(id: id, initialName: name, initialUrl: url);
  }

  Future<void> _showEditDialog({
    String? id,
    String initialName = '',
    String initialUrl = '',
  }) async {
    final me = FirebaseAuth.instance.currentUser;
    final nameCtl = TextEditingController(text: initialName);
    final urlCtl = TextEditingController(text: initialUrl);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(id == null ? 'Add City' : 'Edit City'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtl,
                    decoration: const InputDecoration(
                      labelText: 'City Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: urlCtl,
                    decoration: const InputDecoration(
                      labelText: 'City Inspect URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final user = FirebaseAuth.instance.currentUser;
                if (user == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please sign in to save.')),
                  );
                  return;
                }

                final payload = <String, dynamic>{
                  'name': nameCtl.text.trim(),
                  'url': urlCtl.text.trim(),
                  'ownerUid': user.uid,
                  'updatedAt': FieldValue.serverTimestamp(),
                  if (id == null) 'createdAt': FieldValue.serverTimestamp(),
                };

                try {
                  final col = FirebaseFirestore.instance.collection('city_inspect');
                  if (id == null) {
                    await col.add(payload);
                  } else {
                    await col.doc(id).update(payload);
                  }
                  if (!mounted) return;
                  Navigator.pop(context);
                } on FirebaseException catch (e) {
                  if (!mounted) return;
                  final msg = (e.code == 'permission-denied')
                      ? 'You don’t have permission to modify this item.'
                      : 'Failed to save: ${e.message ?? e.code}';
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _seedStGeorge() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to seed a starter city.')),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('city_inspect').add({
        'name': 'St George',
        'url': 'https://stg.cityinspect.com/builder',
        'ownerUid': me.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = (e.code == 'permission-denied')
          ? 'You don’t have permission to add cities.'
          : 'Failed to seed: ${e.message ?? e.code}';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to seed: $e')));
    }
  }
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onSeed;
  const _EmptyState({required this.onSeed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No cities yet'),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onSeed,
              child: const Text('Add "St George" to start'),
            ),
          ],
        ),
      ),
    );
  }
}
