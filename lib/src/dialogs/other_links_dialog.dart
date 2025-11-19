// lib/src/dialogs/other_links_dialog.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/user_access_scope.dart';

class OtherLink {
  final String id;
  final String name;
  final String url;
  final String ownerUid;

  OtherLink({
    required this.id,
    required this.name,
    required this.url,
    required this.ownerUid,
  });

  static OtherLink fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return OtherLink(
      id: d.id,
      name: (m['name'] ?? '').toString(),
      url: (m['url'] ?? '').toString(),
      ownerUid: (m['ownerUid'] ?? '').toString(),
    );
  }
}

Future<void> showOtherLinksDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (_) => const _OtherLinksDialog(),
  );
}

class _OtherLinksDialog extends StatelessWidget {
  const _OtherLinksDialog();

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance.collection('other_links');
    return AlertDialog(
      title: const Text('Other Links'),
      content: SizedBox(
        width: 420,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: col.snapshots(),
          builder: (context, snap) {
            final me = FirebaseAuth.instance.currentUser;
            final access = UserAccessScope.maybeOf(context);
            final isAdmin = access?.isAdmin ?? false;

            if (snap.hasError) {
              return _OtherLinksDialogMessage(
                icon: Icons.error_outline,
                title: 'Unable to load links',
                message: _loadErrorMessage(snap.error),
                onAdd: me == null ? null : () => _showEdit(context),
              );
            }

            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final items = (snap.data?.docs ?? const [])
                .map(OtherLink.fromDoc)
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              );

            if (items.isEmpty) {
              return _OtherLinksDialogMessage(
                icon: Icons.link,
                title: 'No links yet',
                message: 'Add the first link to share with the team.',
                onAdd: me == null ? null : () => _showEdit(context),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final it = items[i];
                final canEdit =
                    (me != null && me.uid == it.ownerUid) || isAdmin;
                return ListTile(
                  dense: true,
                  title: Text(
                    it.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    it.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _open(it.url),
                  trailing: IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit),
                    onPressed:
                        canEdit ? () => _showEdit(context, link: it) : null,
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
          onPressed: FirebaseAuth.instance.currentUser == null
              ? null
              : () => _showEdit(context),
          icon: const Icon(Icons.add),
          label: const Text('Add Link'),
        ),
      ],
    );
  }
}

class _OtherLinksDialogMessage extends StatelessWidget {
  const _OtherLinksDialogMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onAdd,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Link'),
          ),
        ],
      ),
    );
  }
}

String _loadErrorMessage(Object? error) {
  if (error is FirebaseException) {
    return error.message ?? 'Unknown error';
  }
  return error?.toString() ?? 'Unknown error';
}

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> _showEdit(BuildContext context, {OtherLink? link}) async {
  final me = FirebaseAuth.instance.currentUser;
  if (me == null) return;
  final access = UserAccessScope.maybeOf(context);

  final nameCtl = TextEditingController(text: link?.name ?? '');
  final urlCtl = TextEditingController(text: link?.url ?? '');
  final formKey = GlobalKey<FormState>();
  final col = FirebaseFirestore.instance.collection('other_links');
  final parentNavigator = Navigator.of(context);

  String? vName(String s) => s.isEmpty ? 'Enter a name' : null;
  String? vUrl(String s) {
    final u = Uri.tryParse(s);
    if (u == null || (!u.isScheme('http') && !u.isScheme('https'))) {
      return 'Enter a valid http(s) URL';
    }
    return null;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final dialogNavigator = Navigator.of(dialogContext);
      return AlertDialog(
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
          if (link != null &&
              (access?.canEditOwnedContent(link.ownerUid) ?? false))
            TextButton(
              onPressed: () async {
                try {
                  await col.doc(link.id).delete();
                  if (!dialogNavigator.mounted) return;
                  dialogNavigator.pop();
                  if (parentNavigator.mounted && parentNavigator.canPop()) {
                    parentNavigator.pop();
                  }
                } on FirebaseException catch (error) {
                  if (!dialogContext.mounted) return;
                  await _showOtherLinksSaveError(dialogContext, error);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  await _showOtherLinksSaveError(dialogContext, error);
                }
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => dialogNavigator.pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final data = {
                'name': nameCtl.text.trim(),
                'url': urlCtl.text.trim(),
                'ownerUid': link?.ownerUid ?? me.uid,
                'updatedAt': FieldValue.serverTimestamp(),
                if (link == null) 'createdAt': FieldValue.serverTimestamp(),
              };
              try {
                if (link == null) {
                  await col.add(data);
                } else {
                  await col.doc(link.id).update(data);
                }
                if (!dialogNavigator.mounted) return;
                dialogNavigator.pop();
                if (parentNavigator.mounted && parentNavigator.canPop()) {
                  parentNavigator.pop();
                }
              } on FirebaseException catch (error) {
                if (!dialogContext.mounted) return;
                await _showOtherLinksSaveError(dialogContext, error);
              } catch (error) {
                if (!dialogContext.mounted) return;
                await _showOtherLinksSaveError(dialogContext, error);
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}

Future<void> _showOtherLinksSaveError(
  BuildContext context,
  Object error,
) async {
  final message = error is FirebaseException
      ? (error.message ?? 'Unknown error')
      : error.toString();

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Save failed'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
