import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import '../models/chat_message.dart';

class LlmService {
  LlmService({required this.baseUrl, required this.token, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  http.Client _client;

  static const Duration _requestTimeout = Duration(seconds: 30);

  Future<String> chat(
      {required String message, required List<ChatMessage> history}) async {
    final uri = Uri.parse('$baseUrl/api/chat');
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            if (token.isNotEmpty) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'message': message,
            'history': history
                .map((m) => {
                      'role': m.role,
                      'content': m.text,
                    })
                .toList(),
          }),
        )
        .timeout(_requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    final reply = _extractReply(decoded);
    if (reply != null && reply.trim().isNotEmpty) {
      return reply.trim();
    }

    throw Exception('Invalid response from bridge');
  }

  String? _extractReply(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final directReply = decoded['reply'];
      if (directReply is String) return directReply;

      final message = decoded['message'];
      if (message is String) return message;

      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final msg = first['message'];
          if (msg is Map<String, dynamic>) {
            final content = msg['content'];
            if (content is String) return content;
          }
        }
      }
    }

    return null;
  }

  void cancelActiveRequest() {
    _client.close();
    _client = http.Client();
  }
}
