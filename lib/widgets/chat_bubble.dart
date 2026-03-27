import 'package:flutter/material.dart';

import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isGroupedWithPrevious,
  });

  final ChatMessage message;
  final bool isGroupedWithPrevious;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final textColor =
        isUser ? Colors.white : Colors.white.withValues(alpha: 0.94);
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 4 : 18),
      bottomRight: Radius.circular(isUser ? 18 : 4),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: isGroupedWithPrevious ? 4 : 12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF3B82F6) : const Color(0xFF1E1E2E),
              borderRadius: borderRadius,
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _timeText(message.timestamp),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                ),
          ),
        ],
      ),
    );
  }

  String _timeText(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
