// Chat Message Model
class ChatMessage {
  final String text;
  final bool isUser; // true for user, false for AI
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
