// lib/src/data/models/personal_checklist_item.dart
const _starredOrderSentinel = Object();

class PersonalChecklistItem {
  const PersonalChecklistItem({
    required this.id,
    required this.title,
    this.isDone = false,
    this.isStarred = false,
    this.starredOrder,
  });

  final String id;
  final String title;
  final bool isDone;
  final bool isStarred;
  final int? starredOrder;

  PersonalChecklistItem copyWith({
    String? id,
    String? title,
    bool? isDone,
    bool? isStarred,
    Object? starredOrder = _starredOrderSentinel,
  }) {
    return PersonalChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      isStarred: isStarred ?? this.isStarred,
      starredOrder: identical(starredOrder, _starredOrderSentinel)
          ? this.starredOrder
          : starredOrder as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'isDone': isDone,
      'isStarred': isStarred,
      if (starredOrder != null) 'starredOrder': starredOrder,
    };
  }

  factory PersonalChecklistItem.fromMap(Map<String, dynamic> map) {
    return PersonalChecklistItem(
      id: (map['id'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      isDone: map['isDone'] is bool
          ? map['isDone'] as bool
          : (map['isDone']?.toString().toLowerCase() == 'true'),
      isStarred: map['isStarred'] is bool
          ? map['isStarred'] as bool
          : (map['isStarred']?.toString().toLowerCase() == 'true'),
      starredOrder: map['starredOrder'] is num
          ? (map['starredOrder'] as num).toInt()
          : null,
    );
  }
}
