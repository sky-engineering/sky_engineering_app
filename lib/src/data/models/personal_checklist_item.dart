// lib/src/data/models/personal_checklist_item.dart
class PersonalChecklistItem {
  const PersonalChecklistItem({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  final String id;
  final String title;
  final bool isDone;

  PersonalChecklistItem copyWith({String? id, String? title, bool? isDone}) {
    return PersonalChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'id': id, 'title': title, 'isDone': isDone};
  }

  factory PersonalChecklistItem.fromMap(Map<String, dynamic> map) {
    return PersonalChecklistItem(
      id: (map['id'] as String?) ?? '',
      title: (map['title'] as String?) ?? '',
      isDone: map['isDone'] is bool
          ? map['isDone'] as bool
          : (map['isDone']?.toString().toLowerCase() == 'true'),
    );
  }
}
