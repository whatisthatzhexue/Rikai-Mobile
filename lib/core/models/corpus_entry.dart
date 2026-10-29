class CorpusEntry {
  const CorpusEntry({
    required this.id,
    required this.createdAt,
    required this.title,
    required this.imagePath,
    required this.text,
    required this.engine,
    required this.mode,
    required this.orientation,
    this.blocksJson = '[]',
  });

  final String id;
  final DateTime createdAt;
  final String title;
  final String imagePath;
  final String text;
  final String engine;
  final String mode;
  final String orientation;
  final String blocksJson;

  factory CorpusEntry.fromMap(Map<String, Object?> map) {
    return CorpusEntry(
      id: map['id']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      title: map['title'] as String? ?? '',
      imagePath: map['image_path'] as String? ?? '',
      text: map['text'] as String? ?? '',
      engine: map['engine'] as String? ?? '',
      mode: map['mode'] as String? ?? '',
      orientation: map['orientation'] as String? ?? '',
      blocksJson: map['blocks_json'] as String? ?? '[]',
    );
  }
}
