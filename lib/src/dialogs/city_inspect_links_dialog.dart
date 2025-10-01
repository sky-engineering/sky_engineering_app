// lib/src/dialogs/city_inspect_links_dialog.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class CityInspectLink {
  final String id;
  final String name;
  final String url;
  final String ownerUid;
  CityInspectLink({required this.id, required this.name, required this.url, required this.ownerUid});
  static CityInspectLink fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return CityInspectLink(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      url: (m['url'] ?? '').toString(),
      ownerUid: (m['ownerUid'] ?? '').toString(),
    );
  }
}

Future<void> showCityInspectLinksDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _CityInspectLinksDialog(),
  );
}

class _CityInspectLinksDialog extends StatelessWidget {
  const _CityInspectLinksDialog();

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection('city_inspect');
    return AlertDialog(
      title: const Text('City Inspect Links'),
      content: SizedBox(
        width: 420,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: col.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final me = FirebaseAuth.instance.currentUser;
            final items = (snap.data?.docs ?? const [])
                .map(CityInspectLink.fromDoc)
                .toList()
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link, size: 72),
                      const SizedBox(height: 12),
                      const Text('No links yet'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: me == null ? null : () => _showEdit(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Link'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                final canEdit = me != null && me.uid == it.ownerUid;
                return ListTile(
                  dense: true,
                  title: Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(it.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => _open(it.url),
                  trailing: IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit),
                    onPressed: canEdit ? () => _showEdit(context, link: it) : null,
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton.icon(
          onPressed: FirebaseAuth.instance.currentUser == null ? null : () => _showEdit(context),
          icon: const Icon(Icons.add),
          label: const Text('Add Link'),
        ),
      ],
    );
  }
}

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _showEdit(BuildContext context, {CityInspectLink? link}) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) return;

  final nameCtl = TextEditingController(text: link?.name ?? '');
  final urlCtl = TextEditingController(text: link?.url ?? '');
  final formKey = GlobalKey<FormState>();
  final col = FirebaseFirestore.instance.collection('city_inspect');

  String? vName(String s) => s.isEmpty ? 'Enter a name' : null;
  String? vUrl(String s) {
    final u = Uri.tryParse(s);
    if (u == null || (!u.isScheme('http') && !u.isScheme('https'))) return 'Enter a valid http(s) URL';
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(link == null ? 'Add Link' : 'Edit Link'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) => vName((v ?? '').trim()),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: urlCtl,
              decoration: const InputDecoration(labelText: 'URL'),
              validator: (v) => vUrl((v ?? '').trim()),
            ),
          ],
        ),
      ),
      actions: [
        if (link != null && link.ownerUid == me.uid)
          TextButton(
            onPressed: () async {
              await col.doc(link.id).delete();
              if (Navigator.of(context).canPop()) Navigator.pop(context);
              if (Navigator.of(context).canPop()) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            final data = {
              'name': nameCtl.text.trim(),
              'url': urlCtl.text.trim(),
              'ownerUid': me.uid,
              'updatedAt': FieldValue.serverTimestamp(),
              if (link == null) 'createdAt': FieldValue.serverTimestamp(),
            };
            if (link == null) {
              await col.add(data);
            } else {
              await col.doc(link.id).update(data);
            }
            if (Navigator.of(context).canPop()) Navigator.pop(context);
            if (Navigator.of(context).canPop()) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
