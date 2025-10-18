// lib/src/data/models/checklist.dart
class Checklist {
  Checklist({required this.id, required this.title, required this.items});

  final String id;
  final String title;
  final List<ChecklistItem> items;

  Checklist copyWith({String? id, String? title, List<ChecklistItem>? items}) {
    return Checklist(
      id: id ?? this.id,
      title: title ?? this.title,
      items: items ?? this.items,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'items': items.map((item) => item.toMap()).toList(growable: false),
    };
  }

  factory Checklist.fromMap(Map<String, Object?> map) {
    final parsedItems = <ChecklistItem>[];
    final rawItems = map['items'];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          final typed = <String, Object?>{};
          entry.forEach((key, value) {
            typed[key.toString()] = value;
          });
          parsedItems.add(ChecklistItem.fromMap(typed));
        }
      }
    }

    return Checklist(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      items: parsedItems,
    );
  }
}

class ChecklistItem {
  ChecklistItem({required this.id, required this.title, required this.isDone});

  final String id;
  final String title;
  final bool isDone;

  ChecklistItem copyWith({String? id, String? title, bool? isDone}) {
    return ChecklistItem(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{'id': id, 'title': title, 'isDone': isDone};
  }

  factory ChecklistItem.fromMap(Map<String, Object?> map) {
    return ChecklistItem(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      isDone: map['isDone'] as bool? ?? false,
    );
  }

  static ChecklistItem create({required String title}) {
    return ChecklistItem(id: _generateId(), title: title, isDone: false);
  }

  static String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toString();
}
