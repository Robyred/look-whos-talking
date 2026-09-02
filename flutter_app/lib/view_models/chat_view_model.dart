import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

class ChatMessage {
  final String role; // "user" | "assistant"
  final String text;
  const ChatMessage(this.role, this.text);
}

class ChatViewModel extends ChangeNotifier {
  final String jobId;
  final Map<String, String> nameMap;
  final ApiService _api;

  ChatViewModel({
    required this.jobId,
    required this.nameMap,
    ApiService? api,
  }) : _api = api ?? ApiService();

  final List<ChatMessage> messages = [];
  bool sending = false;

  Future<void> send(String text) async {
    if (text.trim().isEmpty || sending) return;
    messages.add(ChatMessage('user', text.trim()));
    sending = true;
    notifyListeners();

    final history = messages
        .map((m) => {'role': m.role, 'content': m.text})
        .toList();
    try {
      final answer = await _api.askQuestion(jobId, history, nameMap);
      messages.add(ChatMessage('assistant', answer));
    } catch (e) {
      messages.add(ChatMessage('assistant', 'Error: $e'));
    }
    sending = false;
    notifyListeners();
  }
}
