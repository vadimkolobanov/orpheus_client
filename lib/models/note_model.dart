enum NoteSourceType {
  manual,
  contact,
  room,
  oracle,
}

class NoteEntry {
  NoteEntry({
    this.id,
    required this.text,
    required this.createdAt,
    required this.sourceType,
    this.sourceId,
    this.sourceLabel,
  });

  final int? id;
  final String text;
  final DateTime createdAt;
  final NoteSourceType sourceType;
  final String? sourceId;
  final String? sourceLabel;

  static NoteSourceType parseSourceType(String raw) {
    return NoteSourceType.values.firstWhere(
      (type) => type.name == raw,
      orElse: () => NoteSourceType.manual,
    );
  }

  factory NoteEntry.fromMap(Map<String, dynamic> map) {
    return NoteEntry(
      id: map['id'] as int?,
      text: map['text'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at'] as int? ?? 0,
      ),
      sourceType: parseSourceType(map['source_type'] as String? ?? 'manual'),
      sourceId: map['source_id'] as String?,
      sourceLabel: map['source_label'] as String?,
    );
  }
}
