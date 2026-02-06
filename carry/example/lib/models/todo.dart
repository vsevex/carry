/// A todo item model.
class Todo {
  Todo({
    required this.id,
    required this.title,
    this.completed = false,
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Create a Todo from JSON payload.
  factory Todo.fromJson(Map<String, dynamic> json) {
    return Todo(
      id: json['id'] as String,
      title: json['title'] as String,
      completed: json['completed'] as bool? ?? false,
      createdAt:
          json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  final String id;
  final String title;
  final bool completed;
  final int createdAt;

  /// Convert to JSON payload.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
        'createdAt': createdAt,
      };

  /// Create a copy with updated fields.
  Todo copyWith({
    String? id,
    String? title,
    bool? completed,
    int? createdAt,
  }) =>
      Todo(
        id: id ?? this.id,
        title: title ?? this.title,
        completed: completed ?? this.completed,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  String toString() => 'Todo($id: $title, completed: $completed)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Todo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
