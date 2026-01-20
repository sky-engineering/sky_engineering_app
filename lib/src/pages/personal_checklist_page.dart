// lib/src/pages/personal_checklist_page.dart
import 'package:flutter/material.dart';

import '../data/models/personal_checklist_item.dart';
import '../services/personal_checklist_service.dart';
import '../dialogs/personal_task_edit_dialog.dart';
import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';

class PersonalChecklistPage extends StatefulWidget {
  const PersonalChecklistPage({super.key, this.showAppBar = false});

  final bool showAppBar;

  @override
  State<PersonalChecklistPage> createState() => _PersonalChecklistPageState();
}

class _PersonalChecklistPageState extends State<PersonalChecklistPage> {
  final PersonalChecklistService _service = PersonalChecklistService.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    _service.ensureLoaded().then((_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _addItem() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Checklist Item'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What do you need to remember?',
            ),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) {
      return;
    }

    await _service.addItem(result);
  }

  Future<void> _toggleItem(PersonalChecklistItem item, bool value) async {
    await _service.setCompletion(item.id, value);
  }

  Future<void> _toggleStar(PersonalChecklistItem item) async {
    await _service.setStarred(item.id, !item.isStarred);
  }

  Future<void> _editItem(PersonalChecklistItem item) async {
    final result = await showPersonalTaskEditDialog(
      context,
      initialTitle: item.title,
      initialIsDone: item.isDone,
    );

    if (result == null) return;

    await _service.updateItem(
      id: item.id,
      title: result.title,
      isDone: result.isDone,
    );
  }

  Future<void> _removeItem(PersonalChecklistItem item) async {
    await _service.removeItem(item.id);
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    final currentIds =
        _service.items.map((item) => item.id).toList(growable: true);
    if (oldIndex < 0 || oldIndex >= currentIds.length) {
      return;
    }
    if (newIndex > currentIds.length) {
      newIndex = currentIds.length;
    }
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (newIndex < 0 || newIndex >= currentIds.length) {
      newIndex = currentIds.length - 1;
    }
    if (oldIndex == newIndex) {
      return;
    }
    final moved = currentIds.removeAt(oldIndex);
    currentIds.insert(newIndex, moved);
    await _service.reorderItems(currentIds);
  }

  Future<void> _clearCompleted() async {
    await _service.clearCompleted();
  }

  @override
  Widget build(BuildContext context) {
    final items = _service.items;
    final hasCompleted = items.any((item) => item.isDone);

    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      content = const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: _EmptyState(),
        ),
      );
    } else {
      content = ReorderableListView.builder(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        buildDefaultDragHandles: false,
        proxyDecorator: (child, index, animation) {
          final radius = BorderRadius.circular(16);
          return Material(
            elevation: 4,
            borderRadius: radius,
            clipBehavior: Clip.antiAlias,
            child: child,
          );
        },
        itemCount: items.length,
        onReorder: _handleReorder,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            key: ValueKey(item.id),
            padding: EdgeInsets.only(
              bottom: index == items.length - 1 ? 0 : AppSpacing.md,
            ),
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: _SwipeablePersonalChecklistTile(
                item: item,
                onToggleComplete: (value) => _toggleItem(item, value),
                onToggleStar: () => _toggleStar(item),
                onEdit: () => _editItem(item),
                onDelete: () => _removeItem(item),
              ),
            ),
          );
        },
      );
    }

    final canClearCompleted = !_loading && hasCompleted;

    final body = Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: canClearCompleted ? _clearCompleted : null,
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear Completed'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(child: content),
      ],
    );

    return AppPageScaffold(
      title: widget.showAppBar ? 'Personal Tasks' : null,
      useSafeArea: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add checklist item',
        backgroundColor: const Color(0xFFF1C400),
        foregroundColor: Colors.black,
        onPressed: _addItem,
        child: const Icon(Icons.add),
      ),
      fabLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _PersonalChecklistTile extends StatelessWidget {
  const _PersonalChecklistTile({
    required this.item,
    required this.onToggleComplete,
    required this.onToggleStar,
    required this.onEdit,
  });

  final PersonalChecklistItem item;
  final ValueChanged<bool> onToggleComplete;
  final VoidCallback onToggleStar;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filledStar = theme.colorScheme.secondary;
    final hollowStar = theme.colorScheme.onSurfaceVariant;
    final baseTitle = DefaultTextStyle.of(context).style;
    final titleStyle = baseTitle.copyWith(
      fontWeight: FontWeight.w600,
      decoration: item.isDone ? TextDecoration.lineThrough : null,
    );
    final cardColor =
        item.isDone ? theme.colorScheme.surfaceContainerHighest : null;

    return Card(
      color: cardColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                iconSize: 20,
                tooltip: item.isStarred ? 'Unstar' : 'Star',
                splashRadius: 20,
                icon: Icon(
                  item.isStarred ? Icons.star : Icons.star_border,
                  color: item.isStarred ? filledStar : hollowStar,
                ),
                onPressed: onToggleStar,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.title,
                  style: titleStyle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: item.isDone ? 'Mark incomplete' : 'Mark complete',
                child: Checkbox(
                  value: item.isDone,
                  onChanged: (value) {
                    if (value == null) return;
                    onToggleComplete(value);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeablePersonalChecklistTile extends StatefulWidget {
  const _SwipeablePersonalChecklistTile({
    required this.item,
    required this.onToggleComplete,
    required this.onToggleStar,
    required this.onEdit,
    required this.onDelete,
  });

  final PersonalChecklistItem item;
  final Future<void> Function(bool value) onToggleComplete;
  final Future<void> Function() onToggleStar;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  State<_SwipeablePersonalChecklistTile> createState() =>
      _SwipeablePersonalChecklistTileState();
}

class _SwipeablePersonalChecklistTileState
    extends State<_SwipeablePersonalChecklistTile> {
  static const double _completeThreshold = 0.6;
  static const double _deleteThreshold = 0.85;

  double _dragProgress = 0.0;
  DismissDirection? _currentDirection;

  bool get _completeArmed =>
      _currentDirection == DismissDirection.startToEnd &&
      _dragProgress >= _completeThreshold;

  bool get _deleteArmed =>
      _currentDirection == DismissDirection.endToStart &&
      _dragProgress >= _deleteThreshold;

  void _resetDrag() {
    if (_dragProgress != 0.0 || _currentDirection != null) {
      setState(() {
        _dragProgress = 0.0;
        _currentDirection = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('checklist-${widget.item.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: _completeThreshold,
        DismissDirection.endToStart: _deleteThreshold,
      },
      background: _buildSwipeBackground(context, isStartToEnd: true),
      secondaryBackground: _buildSwipeBackground(context, isStartToEnd: false),
      onUpdate: (details) {
        final progress = details.progress.abs().clamp(0.0, 1.0);
        final direction = (details.direction == DismissDirection.startToEnd ||
                details.direction == DismissDirection.endToStart)
            ? details.direction
            : null;
        if (_dragProgress != progress || _currentDirection != direction) {
          setState(() {
            _dragProgress = progress;
            _currentDirection = direction;
          });
        }
      },
      confirmDismiss: (direction) async {
        final progress = _dragProgress;
        _resetDrag();
        if (direction == DismissDirection.startToEnd &&
            progress >= _completeThreshold) {
          await widget.onToggleComplete(!widget.item.isDone);
        } else if (direction == DismissDirection.endToStart &&
            progress >= _deleteThreshold) {
          await widget.onDelete();
        }
        return false;
      },
      child: _PersonalChecklistTile(
        item: widget.item,
        onToggleComplete: (value) => widget.onToggleComplete(value),
        onToggleStar: widget.onToggleStar,
        onEdit: widget.onEdit,
      ),
    );
  }

  Widget _buildSwipeBackground(
    BuildContext context, {
    required bool isStartToEnd,
  }) {
    final theme = Theme.of(context);
    final isActive = _currentDirection ==
        (isStartToEnd
            ? DismissDirection.startToEnd
            : DismissDirection.endToStart);
    final isArmed = isStartToEnd ? _completeArmed : _deleteArmed;
    final color = isStartToEnd
        ? theme.colorScheme.primary.withValues(
            alpha: isActive && isArmed ? 0.25 : 0.12,
          )
        : Colors.transparent;

    final icon = isStartToEnd ? Icons.check : Icons.delete;
    final alignment =
        isStartToEnd ? Alignment.centerLeft : Alignment.centerRight;

    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.only(
        left: isStartToEnd ? 6 : 0,
        right: isStartToEnd ? 0 : 6,
      ),
      alignment: alignment,
      child: Icon(
        icon,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fact_check_outlined, size: 48),
            SizedBox(height: 12),
            Text(
              'Nothing on your personal task list yet. Use the add button to add a personal task and tap the star to send it to Starred Tasks.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
