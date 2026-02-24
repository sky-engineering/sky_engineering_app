import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/tokens.dart';
import '../widgets/app_page_scaffold.dart';

const List<String> _weekdayLabels = <String>['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const List<Color> _eventColorOptions = <Color>[
  Color(0xFFE57373),
  Color(0xFFF06292),
  Color(0xFFBA68C8),
  Color(0xFF9575CD),
  Color(0xFF7986CB),
  Color(0xFF64B5F6),
  Color(0xFF4DD0E1),
  Color(0xFF4DB6AC),
  Color(0xFF81C784),
  Color(0xFFFFB74D),
  Color(0xFFA1887F),
];

class YearlyCalendarPage extends StatefulWidget {
  const YearlyCalendarPage({super.key});

  @override
  State<YearlyCalendarPage> createState() => _YearlyCalendarPageState();
}

class _YearlyCalendarPageState extends State<YearlyCalendarPage> {
  static const _eventTypesPrefsKey = 'yearly_calendar_event_types';
  static const _eventsPrefsKey = 'yearly_calendar_events';

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _monthKeys = <String, GlobalKey>{};
  bool _hasJumpedToCurrentMonth = false;

  late List<_EventType> _eventTypes;
  late List<_CalendarEvent> _events;

  @override
  void initState() {
    super.initState();
    _eventTypes = _defaultEventTypes();
    _events = const <_CalendarEvent>[];
    _loadEventTypes();
    _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startYear = DateTime.now().year - 1;
    final years = List<int>.generate(4, (index) => startYear + index);
    final eventTypeMap = <String, _EventType>{
      for (final type in _eventTypes) type.id: type,
    };

    return AppPageScaffold(
      title: 'Yearly Calendar',
      actions: [
        IconButton(
          tooltip: 'Event types',
          onPressed: _openEventTypesDialog,
          icon: const Icon(Icons.info_outline),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            hoverColor: Colors.white24,
          ),
        ),
        IconButton(
          tooltip: 'Add event',
          onPressed: _showAddEventDialog,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            hoverColor: Colors.white24,
          ),
        ),
      ],
      scrollable: false,
      useSafeArea: true,
      padding: EdgeInsets.zero,
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPersistentHeader(
              floating: true,
              pinned: true,
              delegate: _WeekdayHeaderDelegate(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.md),
            ),
            for (final year in years)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: _YearSection(
                    year: year,
                    events: _events,
                    eventTypes: eventTypeMap,
                    monthKeyProvider: _monthKeyFor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEventTypesDialog() async {
    final updated = await showDialog<List<_EventType>>(
      context: context,
      builder: (context) => _EventTypesDialog(initialTypes: _eventTypes),
    );
    if (updated != null) {
      setState(() => _eventTypes = updated);
      await _persistEventTypes();
    }
  }

  void _scheduleInitialJump() {
    if (_hasJumpedToCurrentMonth) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasJumpedToCurrentMonth) return;
      final success = _jumpToCurrentMonth();
      if (success) {
        _hasJumpedToCurrentMonth = true;
      }
    });
  }

  bool _jumpToCurrentMonth() {
    final now = DateTime.now();
    final key = _monthKeys[_monthKeyId(now.year, now.month)];
    final context = key?.currentContext;
    if (context == null) return false;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 250),
      alignment: 0,
      curve: Curves.easeOut,
    );
    return true;
  }

  GlobalKey _monthKeyFor(int year, int month) {
    final id = _monthKeyId(year, month);
    return _monthKeys.putIfAbsent(id, () => GlobalKey());
  }

  String _monthKeyId(int year, int month) => '$year-$month';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _showAddEventDialog() async {
    if (_eventTypes.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Event'),
          content: const Text('Create an event type before adding events.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openEventTypesDialog();
              },
              child: const Text('Manage Event Types'),
            ),
          ],
        ),
      );
      return;
    }

    final result = await showDialog<_CalendarEvent>(
      context: context,
      builder: (context) => _AddEventDialog(eventTypes: _eventTypes),
    );

    if (result != null && mounted) {
      setState(() => _events = [..._events, result]);
      await _persistEvents();
      final matchingType =
          _eventTypes.where((type) => type.id == result.eventTypeId);
      final typeName =
          matchingType.isNotEmpty ? matchingType.first.name : 'Event';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "${result.title}" ($typeName).'),
        ),
      );
    }
  }

  List<_EventType> _defaultEventTypes() {
    return [
      _EventType(
        id: 'milestones',
        name: 'Milestones',
        color: const Color(0xFFFFB74D),
      ),
      _EventType(
        id: 'deadlines',
        name: 'Deadlines',
        color: const Color(0xFF64B5F6),
      ),
    ];
  }

  Future<void> _loadEventTypes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_eventTypesPrefsKey);
      if (raw == null) {
        await _persistEventTypes(prefs: prefs);
        return;
      }
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        final decoded = parsed
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => _EventType.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .toList(growable: false);
        if (decoded.isNotEmpty) {
          setState(() => _eventTypes = decoded);
        }
      }
    } catch (_) {
      // Ignore malformed preference data and keep defaults.
    }
  }

  Future<void> _loadEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_eventsPrefsKey);
      if (raw == null) return;
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        final decoded = parsed
            .whereType<Map<dynamic, dynamic>>()
            .map((item) => _CalendarEvent.fromJson(
                  item.map((key, value) => MapEntry(key.toString(), value)),
                ))
            .toList(growable: false);
        setState(() => _events = decoded);
      }
    } catch (_) {
      // Ignore malformed preference data.
    }
  }

  Future<void> _persistEventTypes({SharedPreferences? prefs}) async {
    final target = prefs ?? await SharedPreferences.getInstance();
    final payload = jsonEncode(
      _eventTypes.map((type) => type.toJson()).toList(growable: false),
    );
    await target.setString(_eventTypesPrefsKey, payload);
  }

  Future<void> _persistEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      _events.map((event) => event.toJson()).toList(growable: false),
    );
    await prefs.setString(_eventsPrefsKey, payload);
  }
}

class _WeekdayHeaderDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withOpacity(0.5),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      alignment: Alignment.center,
      child: Row(
        children: _weekdayLabels
            .map(
              (label) => Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium,
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _WeekdayHeaderDelegate oldDelegate) => false;
}

class _YearSection extends StatelessWidget {
  const _YearSection({
    required this.year,
    required this.events,
    required this.eventTypes,
    required this.monthKeyProvider,
  });

  final int year;
  final List<_CalendarEvent> events;
  final Map<String, _EventType> eventTypes;
  final GlobalKey Function(int year, int month) monthKeyProvider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = List<int>.generate(12, (index) => index + 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$year',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < months.length; i++) ...[
          _MonthCalendarCard(
            year: year,
            month: months[i],
            events: events,
            eventTypes: eventTypes,
            monthKey: monthKeyProvider(year, months[i]),
          ),
          if (i != months.length - 1) const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _MonthCalendarCard extends StatelessWidget {
  const _MonthCalendarCard({
    required this.year,
    required this.month,
    required this.events,
    required this.eventTypes,
    required this.monthKey,
  });

  final int year;
  final int month;
  final List<_CalendarEvent> events;
  final Map<String, _EventType> eventTypes;
  final GlobalKey monthKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthName = DateFormat('MMMM').format(DateTime(year, month));
    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startOffset = firstDay.weekday % 7;
    final weeks = _buildWeekRows(startOffset, daysInMonth);
    final today = DateTime.now();

    return Card(
      key: monthKey,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              monthName,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Column(
              children: [
                for (var weekIndex = 0;
                    weekIndex < weeks.length;
                    weekIndex++) ...[
                  if (weekIndex != 0)
                    Divider(
                      height: 1,
                      color: theme.dividerColor.withOpacity(0.5),
                    ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      children: [
                        for (var dayIndex = 0;
                            dayIndex < weeks[weekIndex].length;
                            dayIndex++)
                          Expanded(
                            child: _DayCell(
                              date: _resolveDate(
                                weeks[weekIndex][dayIndex],
                              ),
                              isToday: weeks[weekIndex][dayIndex] != null &&
                                  today.year == year &&
                                  today.month == month &&
                                  today.day == weeks[weekIndex][dayIndex],
                              isWeekend: dayIndex == 0 || dayIndex == 6,
                              events: _eventsForDay(
                                weeks[weekIndex][dayIndex],
                              ),
                              eventTypes: eventTypes,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _resolveDate(int? dayNumber) {
    if (dayNumber == null) return null;
    return DateTime(year, month, dayNumber);
  }

  List<_CalendarEvent> _eventsForDay(int? dayNumber) {
    if (dayNumber == null) return const <_CalendarEvent>[];
    final date = DateTime(year, month, dayNumber);
    return events
        .where((event) => event.occursOn(date))
        .toList(growable: false);
  }

  List<List<int?>> _buildWeekRows(int startOffset, int daysInMonth) {
    final weekCount = ((startOffset + daysInMonth + 6) ~/ 7);
    return List<List<int?>>.generate(weekCount, (week) {
      return List<int?>.generate(7, (dayOfWeek) {
        final cellIndex = week * 7 + dayOfWeek;
        final dayNumber = cellIndex - startOffset + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return null;
        }
        return dayNumber;
      });
    });
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isWeekend,
    required this.events,
    required this.eventTypes,
  });

  final DateTime? date;
  final bool isToday;
  final bool isWeekend;
  final List<_CalendarEvent> events;
  final Map<String, _EventType> eventTypes;

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      return const SizedBox(height: 28);
    }
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium;
    final weekendColor = baseStyle?.color?.withOpacity(0.6);
    final textStyle = baseStyle?.copyWith(
      color: isWeekend ? weekendColor : baseStyle?.color,
      fontWeight: isToday ? FontWeight.bold : baseStyle?.fontWeight,
    );

    final barWidgets = <Widget>[];
    for (final event in events) {
      final type = eventTypes[event.eventTypeId];
      if (type == null || !type.enabled) continue;
      barWidgets.add(
        Container(
          height: 4,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: type.color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      );
    }

    final displayBars = barWidgets.take(3).toList(growable: false);
    final overflow = barWidgets.length - displayBars.length;

    final decoration = isToday
        ? BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
            borderRadius: AppRadii.sm,
          )
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: decoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('${date!.day}', style: textStyle),
          if (displayBars.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: displayBars,
              ),
            ),
          if (overflow > 0)
            Text(
              '+$overflow',
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );
  }
}

class _EventTypesDialog extends StatefulWidget {
  const _EventTypesDialog({required this.initialTypes});

  final List<_EventType> initialTypes;

  @override
  State<_EventTypesDialog> createState() => _EventTypesDialogState();
}

class _EventTypesDialogState extends State<_EventTypesDialog> {
  late List<_EventType> _types;

  @override
  void initState() {
    super.initState();
    _types = widget.initialTypes.map((type) => type.copyWith()).toList();
  }

  @override
  Widget build(BuildContext context) {
    final content = _types.isEmpty
        ? const Center(child: Text('No event types yet.'))
        : ListView.separated(
            itemCount: _types.length,
            itemBuilder: (context, index) => _EventTypeRow(
              type: _types[index],
              onToggle: (value) => _updateType(
                _types[index].copyWith(enabled: value),
              ),
              onRename: () => _renameType(_types[index]),
              onColorTap: () => _changeColor(_types[index]),
              onDelete: () => _deleteType(_types[index]),
            ),
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          );

    return AlertDialog(
      title: const Text('Event Types'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: content),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addType,
                icon: const Icon(Icons.add),
                label: const Text('Add Event Type'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_types),
          child: const Text('Done'),
        ),
      ],
    );
  }

  void _updateType(_EventType updated) {
    setState(() {
      _types = _types
          .map((type) => type.id == updated.id ? updated : type)
          .toList(growable: false);
    });
  }

  Future<void> _renameType(_EventType type) async {
    final controller = TextEditingController(text: type.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Event Type'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Title'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.of(context).pop(trimmed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      _updateType(type.copyWith(name: result.trim()));
    }
  }

  Future<void> _changeColor(_EventType type) async {
    Color selected = type.color;
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Select Color'),
            content: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: _eventColorOptions
                  .map(
                    (color) => GestureDetector(
                      onTap: () => setState(() => selected = color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: AppRadii.sm,
                          border: Border.all(
                            color: selected == color
                                ? Colors.white
                                : Colors.black26,
                            width: selected == color ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(selected),
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      _updateType(type.copyWith(color: result));
    }
  }

  Future<void> _addType() async {
    final controller = TextEditingController();
    Color selected = _eventColorOptions.first;
    final result = await showDialog<_EventType>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Event Type'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'Title'),
                  autofocus: true,
                ),
                const SizedBox(height: AppSpacing.md),
                const Text('Color'),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: _eventColorOptions
                      .map(
                        (color) => GestureDetector(
                          onTap: () => setState(() => selected = color),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: AppRadii.sm,
                              border: Border.all(
                                color: selected == color
                                    ? Colors.white
                                    : Colors.black26,
                                width: selected == color ? 2 : 1,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final trimmed = controller.text.trim();
                  if (trimmed.isEmpty) return;
                  Navigator.of(context).pop(
                    _EventType(
                      id: DateTime.now().microsecondsSinceEpoch.toString(),
                      name: trimmed,
                      color: selected,
                    ),
                  );
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      setState(() => _types = [..._types, result]);
    }
  }

  Future<void> _deleteType(_EventType type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event Type'),
        content: Text('Delete "${type.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _types = _types
            .where((existing) => existing.id != type.id)
            .toList(growable: false);
      });
    }
  }
}

class _EventTypeRow extends StatelessWidget {
  const _EventTypeRow({
    required this.type,
    required this.onToggle,
    required this.onRename,
    required this.onColorTap,
    required this.onDelete,
  });

  final _EventType type;
  final ValueChanged<bool> onToggle;
  final VoidCallback onRename;
  final VoidCallback onColorTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Switch(
          value: type.enabled,
          onChanged: onToggle,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Expanded(
          child: TextButton(
            onPressed: onRename,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                type.name,
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ),
        GestureDetector(
          onTap: onColorTap,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: type.color,
              borderRadius: AppRadii.sm,
              border: Border.all(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete event type',
          visualDensity: VisualDensity.compact,
          splashRadius: 18,
        ),
      ],
    );
  }
}

class _AddEventDialog extends StatefulWidget {
  const _AddEventDialog({required this.eventTypes});

  final List<_EventType> eventTypes;

  @override
  State<_AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<_AddEventDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  String? _selectedTypeId;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _useDateRange = false;

  @override
  void initState() {
    super.initState();
    if (widget.eventTypes.isNotEmpty) {
      _selectedTypeId = widget.eventTypes.first.id;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Event Title'),
          autofocus: true,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          value: _selectedTypeId,
          decoration: const InputDecoration(labelText: 'Event Type'),
          items: widget.eventTypes
              .map(
                (type) => DropdownMenuItem(
                  value: type.id,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: type.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(type.name),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (value) => setState(() => _selectedTypeId = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _buildDateControls(theme),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notes',
            alignLabelWithHint: true,
          ),
          minLines: 3,
          maxLines: 5,
        ),
      ],
    );

    return AlertDialog(
      title: const Text('Add Event'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 520,
          child: body,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit()
              ? () {
                  Navigator.of(context).pop(
                    _CalendarEvent(
                      title: _titleController.text.trim(),
                      eventTypeId: _selectedTypeId!,
                      startDate: _startDate!,
                      endDate: _useDateRange ? _endDate : null,
                      notes: _notesController.text.trim().isEmpty
                          ? null
                          : _notesController.text.trim(),
                    ),
                  );
                }
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }

  Widget _buildDateControls(ThemeData theme) {
    final dateStyle = theme.textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Event Date', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickStartDate,
                icon: const Icon(Icons.today),
                label: Text(
                  _startDate != null
                      ? DateFormat('MM/dd/yy').format(_startDate!)
                      : 'Select date',
                  style: dateStyle,
                ),
              ),
            ),
            if (_useDateRange) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickEndDate,
                  icon: const Icon(Icons.event),
                  label: Text(
                    _endDate != null
                        ? DateFormat('MM/dd/yy').format(_endDate!)
                        : 'End date',
                    style: dateStyle,
                  ),
                ),
              ),
            ],
          ],
        ),
        SwitchListTile(
          value: _useDateRange,
          contentPadding: EdgeInsets.zero,
          title: const Text('Use date range'),
          onChanged: (value) {
            setState(() {
              _useDateRange = value;
              if (!value) {
                _endDate = null;
              }
            });
          },
        ),
      ],
    );
  }

  bool _canSubmit() {
    if (_selectedTypeId == null) return false;
    if (_titleController.text.trim().isEmpty) return false;
    if (_startDate == null) return false;
    if (_useDateRange &&
        (_endDate == null || _endDate!.isBefore(_startDate!))) {
      return false;
    }
    return true;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final initial = _startDate ?? now;
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (result != null) {
      setState(() {
        _startDate = result;
        if (_endDate != null && _endDate!.isBefore(result)) {
          _endDate = result;
        }
      });
    }
  }

  Future<void> _pickEndDate() async {
    final now = DateTime.now();
    final base = _endDate ?? _startDate ?? now;
    final result = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (result != null) {
      setState(() {
        _endDate = result;
        if (_startDate != null && result.isBefore(_startDate!)) {
          _startDate = result;
        }
      });
    }
  }
}

class _CalendarEvent {
  const _CalendarEvent({
    required this.title,
    required this.eventTypeId,
    required this.startDate,
    this.endDate,
    this.notes,
  });

  final String title;
  final String eventTypeId;
  final DateTime startDate;
  final DateTime? endDate;
  final String? notes;

  bool occursOn(DateTime date) {
    final day = _normalize(date);
    final start = _normalize(startDate);
    final finish = _normalize(endDate ?? startDate);
    return !day.isBefore(start) && !day.isAfter(finish);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'title': title,
      'eventTypeId': eventTypeId,
      'startDate': startDate.toIso8601String(),
      if (endDate != null) 'endDate': endDate!.toIso8601String(),
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
    };
  }

  factory _CalendarEvent.fromJson(Map<String, dynamic> json) {
    return _CalendarEvent(
      title: json['title'] as String,
      eventTypeId: json['eventTypeId'] as String,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] != null
          ? DateTime.parse(json['endDate'] as String)
          : null,
      notes: json['notes'] as String?,
    );
  }

  DateTime _normalize(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class _EventType {
  const _EventType({
    required this.id,
    required this.name,
    required this.color,
    this.enabled = true,
  });

  final String id;
  final String name;
  final Color color;
  final bool enabled;

  _EventType copyWith({
    String? name,
    Color? color,
    bool? enabled,
  }) {
    return _EventType(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'color': color.value,
      'enabled': enabled,
    };
  }

  factory _EventType.fromJson(Map<String, dynamic> json) {
    return _EventType(
      id: json['id'] as String,
      name: json['name'] as String,
      color: Color(json['color'] as int),
      enabled: json['enabled'] as bool? ?? true,
    );
  }
}
