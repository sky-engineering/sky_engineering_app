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

const int _minVisibleEventBands = 4;
const double _eventBandHeight = 4;
const double _eventBandSpacing = 2;
const double _minDayCellHeight =
    32 + (_minVisibleEventBands * (_eventBandHeight + _eventBandSpacing));

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
  bool _isYearGridView = false;
  late int _gridYear;

  late List<_EventType> _eventTypes;
  late List<_CalendarEvent> _events;

  @override
  void initState() {
    super.initState();
    _eventTypes = _defaultEventTypes();
    _events = const <_CalendarEvent>[];
    _loadEventTypes();
    _loadEvents();
    _gridYear = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleInitialJump();
    final theme = Theme.of(context);
    final now = DateTime.now();
    final gridStartYear = now.year - 1;
    final gridEndYear = gridStartYear + 3;
    final clampedGridYear = _gridYear.clamp(gridStartYear, gridEndYear) as int;
    if (clampedGridYear != _gridYear) {
      _gridYear = clampedGridYear;
    }
    final years = _isYearGridView
        ? <int>[clampedGridYear]
        : List<int>.generate(4, (index) => gridStartYear + index);
    final canGoPrevYear = _gridYear > gridStartYear;
    final canGoNextYear = _gridYear < gridEndYear;
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
          tooltip:
              _isYearGridView ? 'Show timeline view' : 'Show year grid view',
          onPressed: _toggleYearView,
          icon: Icon(
            _isYearGridView
                ? Icons.view_agenda_outlined
                : Icons.calendar_view_month,
          ),
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
            if (!_isYearGridView) ...[
              SliverPersistentHeader(
                floating: true,
                pinned: true,
                delegate: _WeekdayHeaderDelegate(),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.md),
              ),
            ],
            for (final year in years)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: _isYearGridView
                      ? _CompactYearView(
                          year: year,
                          onDayTap: _handleDayTap,
                          onDayLongPress: _handleDayLongPress,
                          onShiftYear: _shiftGridYear,
                          canShiftPrev: canGoPrevYear,
                          canShiftNext: canGoNextYear,
                        )
                      : _YearSection(
                          year: year,
                          events: _events,
                          eventTypes: eventTypeMap,
                          monthKeyProvider: _monthKeyFor,
                          onDayTap: _handleDayTap,
                          onDayLongPress: _handleDayLongPress,
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
    final result = await _openEventDialog();
    if (result != null) {
      await _addEvent(result);
    }
  }

  Future<_CalendarEvent?> _openEventDialog({
    DateTime? initialDate,
    _CalendarEvent? initialEvent,
  }) async {
    if (_eventTypes.isEmpty) {
      await _promptForEventTypeSetup();
      return null;
    }

    return showDialog<_CalendarEvent>(
      context: context,
      builder: (context) => _AddEventDialog(
        eventTypes: _eventTypes,
        initialEvent: initialEvent,
        initialDate: initialDate,
      ),
    );
  }

  Future<void> _promptForEventTypeSetup() async {
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
  }

  void _handleDayTap(DateTime date) {
    _showDayDetails(date);
  }

  void _handleDayLongPress(DateTime date) {
    _quickAddEvent(date);
  }

  Future<void> _quickAddEvent(DateTime date) async {
    final created = await _openEventDialog(initialDate: date);
    if (created != null) {
      await _addEvent(created);
    }
  }

  Future<void> _showDayDetails(DateTime date) async {
    final typeMap = {
      for (final type in _eventTypes) type.id: type,
    };

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final eventsForDay = _events
                .where(
                  (event) =>
                      event.occursOn(date) &&
                      (typeMap[event.eventTypeId]?.enabled ?? false),
                )
                .toList(growable: false)
              ..sort((a, b) => a.startDate.compareTo(b.startDate));
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('EEEE, MMM d, y').format(date),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (eventsForDay.isEmpty)
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: AppSpacing.md),
                          child: Text('No events scheduled for this day.'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 360),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: eventsForDay.length,
                            itemBuilder: (context, index) {
                              final event = eventsForDay[index];
                              final type = typeMap[event.eventTypeId];
                              return _DayEventTile(
                                event: event,
                                eventType: type,
                                onEdit: () async {
                                  final updated = await _openEventDialog(
                                    initialEvent: event,
                                  );
                                  if (updated != null) {
                                    await _updateEvent(event, updated);
                                    setModalState(() {});
                                  }
                                },
                                onDelete: () async {
                                  final confirmed =
                                      await _confirmDeleteEvent(event);
                                  if (confirmed) {
                                    await _deleteEvent(event);
                                    setModalState(() {});
                                  }
                                },
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: AppSpacing.sm),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final created =
                                await _openEventDialog(initialDate: date);
                            if (created != null) {
                              await _addEvent(created);
                              setModalState(() {});
                            }
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Event'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmDeleteEvent(_CalendarEvent event) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete "${event.title}"?'),
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
    return result ?? false;
  }

  Future<void> _addEvent(_CalendarEvent event) async {
    if (!mounted) return;
    setState(() => _events = [..._events, event]);
    await _persistEvents();
    _showEventSnackBar(
        'Saved "${event.title}" (${_eventTypeName(event.eventTypeId)}).');
  }

  Future<void> _updateEvent(
    _CalendarEvent original,
    _CalendarEvent updated,
  ) async {
    final index = _events.indexOf(original);
    if (index == -1 || !mounted) return;
    setState(() {
      final next = [..._events];
      next[index] = updated;
      _events = next;
    });
    await _persistEvents();
    _showEventSnackBar(
      'Updated "${updated.title}" (${_eventTypeName(updated.eventTypeId)}).',
    );
  }

  Future<void> _deleteEvent(_CalendarEvent target) async {
    if (!mounted) return;
    final next =
        _events.where((event) => event != target).toList(growable: false);
    if (next.length == _events.length) return;
    setState(() => _events = next);
    await _persistEvents();
    _showEventSnackBar(
      'Deleted "${target.title}" (${_eventTypeName(target.eventTypeId)}).',
    );
  }

  void _showEventSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleYearView() {
    setState(() {
      _isYearGridView = !_isYearGridView;
    });
  }

  void _shiftGridYear(int delta) {
    setState(() {
      final now = DateTime.now();
      final startYear = now.year - 1;
      final endYear = startYear + 3;
      final nextYear = (_gridYear + delta).clamp(startYear, endYear) as int;
      _gridYear = nextYear;
    });
  }

  String _eventTypeName(String id) {
    for (final type in _eventTypes) {
      if (type.id == id) return type.name;
    }
    return 'Event';
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
    final baseStyle = theme.textTheme.labelMedium;
    final baseColor = baseStyle?.color;
    final weekendColor = baseColor?.withOpacity(0.6);
    const horizontalPadding = AppSpacing.md;
    final verticalPadding = AppSpacing.xs / 2;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withOpacity(0.5),
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rawWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width;
          final contentWidth = rawWidth - (horizontalPadding * 2);
          final columnWidth =
              contentWidth <= 0 ? 0.0 : contentWidth / _weekdayLabels.length;
          final useExpanded = columnWidth <= 0;
          return Padding(
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: horizontalPadding,
            ),
            child: Row(
              children: List.generate(_weekdayLabels.length, (index) {
                final label = _weekdayLabels[index];
                final isWeekend =
                    index == 0 || index == _weekdayLabels.length - 1;
                final style = baseStyle?.copyWith(
                  color: isWeekend ? weekendColor : baseColor,
                );
                final text = Center(
                  child: Text(
                    label,
                    style: style,
                  ),
                );
                if (useExpanded) {
                  return Expanded(child: text);
                }
                return SizedBox(width: columnWidth, child: text);
              }),
            ),
          );
        },
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
    required this.onDayTap,
    this.onDayLongPress,
  });

  final int year;
  final List<_CalendarEvent> events;
  final Map<String, _EventType> eventTypes;
  final GlobalKey Function(int year, int month) monthKeyProvider;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime>? onDayLongPress;

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
            onDayTap: onDayTap,
            onDayLongPress: onDayLongPress,
          ),
          if (i != months.length - 1) const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }
}

class _CompactYearView extends StatelessWidget {
  const _CompactYearView({
    required this.year,
    required this.onDayTap,
    this.onDayLongPress,
    this.onShiftYear,
    this.canShiftPrev = false,
    this.canShiftNext = false,
  });

  final int year;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime>? onDayLongPress;
  final ValueChanged<int>? onShiftYear;
  final bool canShiftPrev;
  final bool canShiftNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final months = List<int>.generate(12, (index) => index + 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('$year', style: theme.textTheme.titleLarge),
            const SizedBox(width: AppSpacing.sm),
            if (onShiftYear != null)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous year',
                    onPressed: canShiftPrev ? () => onShiftYear!(-1) : null,
                    icon: const Icon(Icons.chevron_left, size: 18),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next year',
                    onPressed: canShiftNext ? () => onShiftYear!(1) : null,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Column(
          children: [
            for (var row = 0; row < 4; row++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col != 0) const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _CompactMonthCard(
                        year: year,
                        month: months[row * 3 + col],
                        onDayTap: onDayTap,
                        onDayLongPress: onDayLongPress,
                      ),
                    ),
                  ],
                ],
              ),
              if (row != 3) const SizedBox(height: AppSpacing.xs),
            ],
          ],
        ),
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
    required this.onDayTap,
    this.onDayLongPress,
  });

  final int year;
  final int month;
  final List<_CalendarEvent> events;
  final Map<String, _EventType> eventTypes;
  final GlobalKey monthKey;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime>? onDayLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthName = DateFormat('MMMM').format(DateTime(year, month));
    final weeks = _generateWeekRows(year, month);
    final today = DateTime.now();
    final layout = _buildMonthEventLayout();

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
                              date: _resolveMonthDate(
                                year,
                                month,
                                weeks[weekIndex][dayIndex],
                              ),
                              isToday: weeks[weekIndex][dayIndex] != null &&
                                  today.year == year &&
                                  today.month == month &&
                                  today.day == weeks[weekIndex][dayIndex],
                              isWeekend: dayIndex == 0 || dayIndex == 6,
                              eventBands: layout.bandsFor(
                                weeks[weekIndex][dayIndex],
                              ),
                              eventTypes: eventTypes,
                              onTap: onDayTap,
                              onLongPress: onDayLongPress,
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

  _MonthEventLayout _buildMonthEventLayout() {
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month + 1, 0);
    final bandMap = <int, List<_EventBandSegment>>{};
    final laneAvailability = <int>[];

    final relevantEvents = events.where((event) {
      final type = eventTypes[event.eventTypeId];
      if (type == null || !type.enabled) return false;
      final normalizedStart = _normalizeDate(event.startDate);
      final normalizedEnd = _normalizeDate(event.endDate ?? event.startDate);
      return !normalizedEnd.isBefore(monthStart) &&
          !normalizedStart.isAfter(monthEnd);
    }).toList(growable: false)
      ..sort((a, b) {
        final startCompare = a.startDate.compareTo(b.startDate);
        if (startCompare != 0) return startCompare;
        return a.title.compareTo(b.title);
      });

    for (final event in relevantEvents) {
      final normalizedStart = _normalizeDate(event.startDate);
      final normalizedEnd = _normalizeDate(event.endDate ?? event.startDate);
      final displayStart =
          normalizedStart.isBefore(monthStart) ? monthStart : normalizedStart;
      final displayEnd =
          normalizedEnd.isAfter(monthEnd) ? monthEnd : normalizedEnd;
      final startDay = displayStart.day;
      final endDay = displayEnd.day;

      var lane = -1;
      for (var laneIndex = 0;
          laneIndex < laneAvailability.length;
          laneIndex++) {
        if (laneAvailability[laneIndex] < startDay) {
          lane = laneIndex;
          laneAvailability[laneIndex] = endDay;
          break;
        }
      }

      if (lane == -1) {
        lane = laneAvailability.length;
        laneAvailability.add(endDay);
      }

      for (var day = startDay; day <= endDay; day++) {
        final date = DateTime(year, month, day);
        final segments = bandMap.putIfAbsent(day, () => <_EventBandSegment>[]);
        segments.add(
          _EventBandSegment(
            event: event,
            lane: lane,
            continuesFromPreviousDay: date.isAfter(normalizedStart),
            continuesToNextDay: date.isBefore(normalizedEnd),
          ),
        );
      }
    }

    for (final daySegments in bandMap.values) {
      daySegments.sort((a, b) => a.lane.compareTo(b.lane));
    }

    return _MonthEventLayout(bandMap: bandMap);
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }
}

class _CompactMonthCard extends StatelessWidget {
  const _CompactMonthCard({
    required this.year,
    required this.month,
    required this.onDayTap,
    this.onDayLongPress,
  });

  final int year;
  final int month;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<DateTime>? onDayLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthLabel = DateFormat('MMM').format(DateTime(year, month));
    final weeks = _generateWeekRows(year, month);
    final today = DateTime.now();
    final isCurrentMonth = year == today.year && month == today.month;
    return Card(
      margin: EdgeInsets.zero,
      color: isCurrentMonth
          ? theme.colorScheme.secondaryContainer.withOpacity(0.25)
          : null,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              monthLabel,
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: AppSpacing.xs / 2),
            Column(
              children: [
                for (final week in weeks)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var dayIndex = 0;
                          dayIndex < week.length;
                          dayIndex++) ...[
                        if (dayIndex != 0)
                          const SizedBox(width: AppSpacing.xs / 2),
                        Expanded(
                          child: _CompactDayCell(
                            date:
                                _resolveMonthDate(year, month, week[dayIndex]),
                            isToday: week[dayIndex] != null &&
                                today.year == year &&
                                today.month == month &&
                                today.day == week[dayIndex],
                            isWeekend: dayIndex == 0 || dayIndex == 6,
                            onTap: onDayTap,
                            onLongPress: onDayLongPress,
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthEventLayout {
  const _MonthEventLayout({
    required this.bandMap,
  });

  final Map<int, List<_EventBandSegment>> bandMap;

  List<_EventBandSegment> bandsFor(int? day) {
    if (day == null) return const <_EventBandSegment>[];
    return bandMap[day] ?? const <_EventBandSegment>[];
  }
}

class _EventBandSegment {
  const _EventBandSegment({
    required this.event,
    required this.lane,
    required this.continuesFromPreviousDay,
    required this.continuesToNextDay,
  });

  final _CalendarEvent event;
  final int lane;
  final bool continuesFromPreviousDay;
  final bool continuesToNextDay;
}

class _CompactDayCell extends StatelessWidget {
  const _CompactDayCell({
    required this.date,
    required this.isToday,
    required this.isWeekend,
    required this.onTap,
    this.onLongPress,
  });

  static const double _cellHeight = 24;

  final DateTime? date;
  final bool isToday;
  final bool isWeekend;
  final ValueChanged<DateTime>? onTap;
  final ValueChanged<DateTime>? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      return const SizedBox(height: _cellHeight);
    }
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.labelSmall;
    final weekendColor = baseStyle?.color?.withOpacity(0.6);
    final textStyle = baseStyle?.copyWith(
      color: isWeekend ? weekendColor : baseStyle?.color,
    );
    final decoration = isToday
        ? BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
            borderRadius: AppRadii.sm,
          )
        : null;
    final content = Container(
      height: _cellHeight,
      alignment: Alignment.center,
      decoration: decoration,
      child: Text('${date!.day}', style: textStyle),
    );
    if (onTap == null && onLongPress == null) {
      return content;
    }
    return InkWell(
      onTap: onTap != null ? () => onTap!(date!) : null,
      onLongPress: onLongPress != null ? () => onLongPress!(date!) : null,
      borderRadius: AppRadii.sm,
      child: content,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.isToday,
    required this.isWeekend,
    required this.eventBands,
    required this.eventTypes,
    this.onTap,
    this.onLongPress,
  });

  final DateTime? date;
  final bool isToday;
  final bool isWeekend;
  final List<_EventBandSegment> eventBands;
  final Map<String, _EventType> eventTypes;
  final ValueChanged<DateTime>? onTap;
  final ValueChanged<DateTime>? onLongPress;

  @override
  Widget build(BuildContext context) {
    if (date == null) {
      return const SizedBox(height: _minDayCellHeight);
    }
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyMedium;
    final weekendColor = baseStyle?.color?.withOpacity(0.6);
    final textStyle = baseStyle?.copyWith(
      color: isWeekend ? weekendColor : baseStyle?.color,
      fontWeight: isToday ? FontWeight.bold : baseStyle?.fontWeight,
    );

    final maxLane = eventBands.fold<int>(-1, (value, segment) {
      return segment.lane > value ? segment.lane : value;
    });

    final laneColors = <Color>[];
    if (maxLane >= 0) {
      final segmentsByLane = <int, _EventBandSegment>{
        for (final segment in eventBands) segment.lane: segment,
      };
      for (var lane = 0; lane <= maxLane; lane++) {
        final segment = segmentsByLane[lane];
        if (segment == null) continue;
        final type = eventTypes[segment.event.eventTypeId];
        if (type == null) continue;
        laneColors.add(type.color);
      }
    }

    final decoration = isToday
        ? BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
            borderRadius: AppRadii.sm,
          )
        : null;

    final backgroundBands = laneColors.isEmpty
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < laneColors.length; i++) ...[
                Container(
                  height: _eventBandHeight,
                  color: laneColors[i],
                ),
                if (i != laneColors.length - 1)
                  const SizedBox(height: _eventBandSpacing),
              ],
            ],
          );

    final content = Container(
      constraints: const BoxConstraints(minHeight: _minDayCellHeight),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: decoration,
      child: Stack(
        children: [
          if (backgroundBands != null)
            Positioned(
              top: 4,
              left: 0,
              right: 0,
              child: backgroundBands,
            ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text('${date!.day}', style: textStyle),
            ),
          ),
        ],
      ),
    );

    if (onTap == null && onLongPress == null) {
      return content;
    }

    return InkWell(
      onTap: onTap != null ? () => onTap!(date!) : null,
      onLongPress: onLongPress != null ? () => onLongPress!(date!) : null,
      borderRadius: AppRadii.sm,
      child: content,
    );
  }
}

class _DayEventTile extends StatelessWidget {
  const _DayEventTile({
    required this.event,
    required this.eventType,
    required this.onEdit,
    required this.onDelete,
  });

  final _CalendarEvent event;
  final _EventType? eventType;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = eventType?.color ?? theme.colorScheme.secondary;
    final typeName = eventType?.name ?? 'Event';
    final dateFormat = DateFormat('MMM d, yyyy');
    final startLabel = dateFormat.format(event.startDate);
    final endDate = event.endDate;
    final endLabel = endDate != null ? dateFormat.format(endDate) : null;
    final rangeLabel = endLabel == null || endLabel == startLabel
        ? startLabel
        : '$startLabel – $endLabel';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: AppRadii.sm,
        border: Border.all(
          color: theme.dividerColor.withOpacity(0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(AppSpacing.xs),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  '$typeName • $rangeLabel',
                  style: theme.textTheme.bodySmall,
                ),
                if (event.notes != null && event.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      event.notes!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Edit event',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                splashRadius: 18,
              ),
              IconButton(
                tooltip: 'Delete event',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                splashRadius: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

List<List<int?>> _generateWeekRows(int year, int month) {
  final firstDay = DateTime(year, month, 1);
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final startOffset = firstDay.weekday % 7;
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

DateTime? _resolveMonthDate(int year, int month, int? dayNumber) {
  if (dayNumber == null) return null;
  return DateTime(year, month, dayNumber);
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
  const _AddEventDialog({
    required this.eventTypes,
    this.initialEvent,
    this.initialDate,
  });

  final List<_EventType> eventTypes;
  final _CalendarEvent? initialEvent;
  final DateTime? initialDate;

  bool get isEditing => initialEvent != null;

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
    final initial = widget.initialEvent;
    if (initial != null) {
      _titleController.text = initial.title;
      _notesController.text = initial.notes ?? '';
      _selectedTypeId = widget.eventTypes.any(
        (type) => type.id == initial.eventTypeId,
      )
          ? initial.eventTypeId
          : (widget.eventTypes.isNotEmpty ? widget.eventTypes.first.id : null);
      _startDate = DateTime(
        initial.startDate.year,
        initial.startDate.month,
        initial.startDate.day,
      );
      if (initial.endDate != null) {
        _endDate = DateTime(
          initial.endDate!.year,
          initial.endDate!.month,
          initial.endDate!.day,
        );
        _useDateRange = true;
      }
    } else {
      if (widget.eventTypes.isNotEmpty) {
        _selectedTypeId = widget.eventTypes.first.id;
      }
      if (widget.initialDate != null) {
        final date = widget.initialDate!;
        _startDate = DateTime(date.year, date.month, date.day);
      }
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
      title: Text(widget.isEditing ? 'Edit Event' : 'Add Event'),
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
          child: Text(widget.isEditing ? 'Save' : 'Add'),
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
