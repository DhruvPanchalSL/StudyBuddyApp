import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'models/chat_message.dart';

class ChatScreen extends StatefulWidget {
  final String extractedText;
  final String summary;
  final String documentName;
  final String activeGeminiKey;
  final String activeGroqKey;

  const ChatScreen({
    super.key,
    required this.extractedText,
    required this.summary,
    required this.documentName,
    required this.activeGeminiKey,
    required this.activeGroqKey,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _green = Color(0xFF7ED957);
  static const Color _darkNavy = Color(0xFF1A1A2E);
  static const Color _teal = Color(0xFF00C2B2);
  static const Color _bgGray = Color(0xFFF5F5F7);
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);

  static const String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  static const String _groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.3-70b-versatile';

  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSendingMessage = false;
  List<ChatMessage> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    _chatMessages.add(
      ChatMessage(
        text:
            "👋 Hi! I'm your AI study assistant. Ask me anything about your document!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Gemini → Groq fallback ─────────────────────────────────────────────────
  Future<String> _callAI(String prompt) async {
    // Step 1: Try Gemini
    if (widget.activeGeminiKey.isNotEmpty) {
      try {
        final url = Uri.parse('$_geminiEndpoint?key=${widget.activeGeminiKey}');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "contents": [
              {
                "parts": [
                  {"text": prompt},
                ],
              },
            ],
            "generationConfig": {"temperature": 0.7, "maxOutputTokens": 1024},
          }),
        );

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          return json['candidates'][0]['content']['parts'][0]['text'] as String;
        } else if (response.statusCode == 429) {
          debugPrint('Gemini rate limited, falling back to Groq...');
          // fall through to Groq
        } else {
          throw Exception('Gemini API Error: ${response.statusCode}');
        }
      } catch (e) {
        if (e.toString().contains('Gemini API Error')) rethrow;
        debugPrint('Gemini failed: $e — trying Groq');
      }
    }

    // Step 2: Fallback to Groq
    if (widget.activeGroqKey.isEmpty) {
      throw Exception(
        'All AI keys exhausted. Please add a Groq API key in Settings.',
      );
    }

    final groqResponse = await http.post(
      Uri.parse(_groqEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.activeGroqKey}',
      },
      body: jsonEncode({
        "model": _groqModel,
        "messages": [
          {"role": "user", "content": prompt},
        ],
        "max_tokens": 1024,
        "temperature": 0.7,
      }),
    );

    if (groqResponse.statusCode == 200) {
      final json = jsonDecode(groqResponse.body);
      return json['choices'][0]['message']['content'] as String;
    } else if (groqResponse.statusCode == 429) {
      throw Exception(
        '⏳ Both Gemini and Groq are rate limited. Please wait a moment.',
      );
    } else {
      throw Exception('Groq API Error: ${groqResponse.statusCode}');
    }
  }

  Future<void> _sendMessage() async {
    if (_chatController.text.trim().isEmpty) return;

    final userMessage = _chatController.text.trim();
    setState(() {
      _chatMessages.add(
        ChatMessage(text: userMessage, isUser: true, timestamp: DateTime.now()),
      );
      _chatController.clear();
      _isSendingMessage = true;
    });
    _scrollToBottom();

    try {
      String context = widget.summary.isNotEmpty
          ? widget.summary
          : widget.extractedText;
      if (context.length > 20000) {
        context = context.substring(0, 20000) + "...";
      }

      final prompt =
          '''You are a helpful study assistant. Answer the user\'s question based ONLY on the following context.
If the answer cannot be found in the context, say "I don\'t have enough information about that in the document."

CONTEXT:
$context

USER QUESTION: $userMessage

ANSWER (be concise but helpful):''';

      final aiResponse = await _callAI(prompt);

      setState(() {
        _chatMessages.add(
          ChatMessage(
            text: aiResponse,
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _isSendingMessage = false;
      });
    } catch (e) {
      setState(() {
        _chatMessages.add(
          ChatMessage(
            text:
                "Sorry, I encountered an error: ${e.toString().substring(0, e.toString().length.clamp(0, 120))}",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _isSendingMessage = false;
      });
    }
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: _textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Chat',
              style: TextStyle(
                color: _textDark,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            Text(
              widget.documentName,
              style: const TextStyle(color: _textGray, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_rounded,
              color: Color(0xFF10B981),
              size: 18,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _chatMessages.length,
              itemBuilder: (context, index) {
                final message = _chatMessages[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: message.isUser
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      if (!message.isUser) ...[
                        Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Color(0xFF7B2FBE),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: message.isUser ? _darkNavy : _cardWhite,
                            borderRadius: BorderRadius.circular(16).copyWith(
                              bottomLeft: message.isUser
                                  ? const Radius.circular(16)
                                  : const Radius.circular(4),
                              bottomRight: message.isUser
                                  ? const Radius.circular(4)
                                  : const Radius.circular(16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            message.text,
                            style: TextStyle(
                              color: message.isUser ? Colors.white : _textDark,
                              fontSize: 14,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ),
                      if (message.isUser) ...[
                        const SizedBox(width: 10),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade500,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: _cardWhite,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _bgGray,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TextField(
                      controller: _chatController,
                      decoration: const InputDecoration(
                        hintText: 'Ask your Study Buddy anything...',
                        hintStyle: TextStyle(color: _textGray, fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      enabled: !_isSendingMessage,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _isSendingMessage ? null : _sendMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isSendingMessage ? Colors.grey.shade300 : _teal,
                      shape: BoxShape.circle,
                    ),
                    child: _isSendingMessage
                        ? const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
