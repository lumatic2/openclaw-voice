import 'message_type.dart';

class ChatMessage {
  final String id;
  final String role;
  final String text;
  final DateTime timestamp;
  final MessageType type;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'type': type.name,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? MessageType.text.name;
    final resolvedType = MessageType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => MessageType.text,
    );
    return ChatMessage(
      id: json['id'] as String? ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      role: json['role'] as String? ?? 'user',
      text: json['text'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      type: resolvedType,
    );
  }
}
