import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// Flashcard Model
class Flashcard {
  final String id;
  final String front;
  final String back;
  final String category;
  final String difficulty;
  int timesReviewed;
  int timesCorrect;
  DateTime? nextReviewDate;

  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.category = 'General',
    this.difficulty = 'medium',
    this.timesReviewed = 0,
    this.timesCorrect = 0,
    this.nextReviewDate,
  });

  double get masteryPercentage {
    if (timesReviewed == 0) return 0;
    return (timesCorrect / timesReviewed) * 100;
  }

  factory Flashcard.fromJson(Map<String, dynamic> json) {
    return Flashcard(
      id:
          DateTime.now().millisecondsSinceEpoch.toString() +
          (json['front'] ?? '').hashCode.toString(),
      front: json['front'] ?? '',
      back: json['back'] ?? '',
      category: json['category'] ?? 'General',
      difficulty: json['difficulty'] ?? 'medium',
    );
  }
}

class FlashcardScreen extends StatefulWidget {
  final String documentText;
  final String documentName;
  final String activeGeminiKey;
  final String activeGroqKey;

  const FlashcardScreen({
    Key? key,
    required this.documentText,
    required this.documentName,
    required this.activeGeminiKey,
    required this.activeGroqKey,
  }) : super(key: key);

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen>
    with TickerProviderStateMixin {
  List<Flashcard> _cards = [];
  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _isLoading = false;
  bool _isGenerated = false;

  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  // FIX: Track mastered count separately — mastered cards are removed from
  // _cards so we can't count them from the list anymore.
  int _masteredCount = 0;
  int _learningCount = 0; // cards seen at least once but not yet mastered
  int _totalGenerated = 0; // total cards originally generated

  final String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  final String _groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  final String _groqModel = 'llama-3.3-70b-versatile';

  Future<String> _callAI(String prompt) async {
    // Try Gemini first
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
          "generationConfig": {"temperature": 0.3, "maxOutputTokens": 4096},
        }),
      );
      if (response.statusCode == 429) throw Exception('rate_limit');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      }
      throw Exception('Gemini error ${response.statusCode}');
    } catch (e) {
      if (!e.toString().contains('rate_limit') && !e.toString().contains('429'))
        rethrow;
    }

    // Fallback to Groq
    final url = Uri.parse(_groqEndpoint);
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.activeGroqKey}',
      },
      body: jsonEncode({
        "model": _groqModel,
        "messages": [
          {"role": "user", "content": prompt},
        ],
        "max_tokens": 4096,
        "temperature": 0.3,
      }),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['choices'][0]['message']['content'];
    }
    throw Exception('Both Gemini and Groq failed (${response.statusCode})');
  }

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  Future<void> _generateFlashcards() async {
    setState(() => _isLoading = true);

    try {
      String processedText = widget.documentText;
      if (processedText.length > 25000) {
        processedText = processedText.substring(0, 25000) + '...';
      }

      final prompt =
          '''
Based on the following text, create 10 flashcards for studying.
Each flashcard should have a question/term on the front and answer/definition on the back.
Categorize them by difficulty (easy, medium, hard) and topic.

Return as JSON array only, no explanation:
[
  {
    "front": "What is photosynthesis?",
    "back": "Process plants use to convert light into energy",
    "category": "Biology",
    "difficulty": "easy"
  }
]

Text: $processedText
''';

      final responseText = await _callAI(prompt);

      final jsonRegex = RegExp(r'\[[\s\S]*\]');
      final match = jsonRegex.firstMatch(responseText);
      if (match == null) throw Exception('Could not parse flashcard JSON');

      final cardsJson = jsonDecode(match.group(0)!) as List<dynamic>;
      final cards = cardsJson.map((j) => Flashcard.fromJson(j)).toList()
        ..shuffle();

      setState(() {
        _cards = cards;
        _totalGenerated = cards.length;
        _masteredCount = 0;
        _learningCount = 0;
        _currentIndex = 0;
        _isFlipped = false;
        _isGenerated = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating flashcards: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _handleSwipe(bool knowIt) {
    if (_cards.isEmpty || _currentIndex >= _cards.length) return;

    final currentCard = _cards[_currentIndex];

    currentCard.timesReviewed++;
    if (knowIt) currentCard.timesCorrect++;

    if (knowIt && currentCard.masteryPercentage >= 80) {
      // ✅ Mastered — remove from deck and increment separate counter
      _cards.removeAt(_currentIndex);
      _masteredCount++;
    } else if (!knowIt) {
      // ❌ Don't know — move to end for another round
      _cards.add(currentCard);
      _cards.removeAt(_currentIndex);
    } else {
      // 🔄 Know it but not mastered yet — advance
      _currentIndex++;
    }

    // FIX: Recount learning cards from remaining deck
    _learningCount = _cards.where((c) => c.timesReviewed > 0).length;

    // FIX: Always clamp index BEFORE setState to prevent out-of-bounds rebuild
    if (_cards.isNotEmpty && _currentIndex >= _cards.length) {
      _currentIndex = 0;
    }

    setState(() {
      _isFlipped = false;
    });
  }

  void _resetDeck() {
    setState(() {
      _cards.shuffle();
      _currentIndex = 0;
      _isFlipped = false;
      _masteredCount = 0;
      _learningCount = 0;
      for (var card in _cards) {
        card.timesReviewed = 0;
        card.timesCorrect = 0;
      }
    });
  }

  // FIX: Safe progress value — always clamped 0.0–1.0
  double get _progressValue {
    if (_totalGenerated == 0) return 0;
    return (_masteredCount / _totalGenerated).clamp(0.0, 1.0);
  }

  // Cards remaining in deck
  int get _remainingCount => _cards.length;

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      case 'hard':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Flashcards',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isGenerated)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.purple),
              onPressed: _resetDeck,
              tooltip: 'Shuffle deck',
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.purple.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'AI is creating your flashcards...',
                    style: TextStyle(color: Colors.purple.shade700),
                  ),
                ],
              ),
            )
          : !_isGenerated
          ? _buildGenerateScreen()
          : _cards.isEmpty
          ? _buildCompletionScreen()
          : _buildStudyScreen(),
    );
  }

  Widget _buildGenerateScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_stories,
              size: 80,
              color: Colors.purple.shade300,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            widget.documentName == 'No file selected'
                ? 'No document loaded'
                : 'Ready to create flashcards',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              widget.documentName == 'No file selected'
                  ? 'Please upload a PDF first'
                  : "AI will create 10+ flashcards from '${widget.documentName}'",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 32),
          if (widget.documentName != 'No file selected')
            ElevatedButton.icon(
              onPressed: _generateFlashcards,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate Flashcards'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events, size: 80, color: Colors.amber),
          const SizedBox(height: 16),
          const Text(
            'Congratulations!',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'You mastered all $_totalGenerated flashcards!',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _generateFlashcards,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate New Set'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudyScreen() {
    // FIX: Safe guard — should never happen but prevents index crash
    if (_currentIndex >= _cards.length) _currentIndex = 0;

    return Column(
      children: [
        // ── Stats Bar ─────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.shade100,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                icon: Icons.layers_rounded,
                value: '$_remainingCount',
                label: 'Remaining',
                color: Colors.purple,
              ),
              Container(height: 30, width: 1, color: Colors.purple.shade200),
              _buildStatItem(
                icon: Icons.star_rounded,
                value: '$_masteredCount',
                label: 'Mastered',
                color: Colors.amber,
              ),
              Container(height: 30, width: 1, color: Colors.purple.shade200),
              _buildStatItem(
                icon: Icons.school_rounded,
                value: '$_learningCount',
                label: 'Seen',
                color: Colors.blue,
              ),
            ],
          ),
        ),

        // ── Overall mastery progress bar ──────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    // FIX: Show mastered/total — not currentIndex/remaining
                    'Mastered $_masteredCount of $_totalGenerated',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  Text(
                    '${(_progressValue * 100).round()}%',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progressValue, // FIX: clamped 0.0–1.0
                backgroundColor: Colors.purple.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.purple.shade700,
                ),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Flashcard ─────────────────────────────────────────────
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: () => setState(() => _isFlipped = !_isFlipped),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 320,
                height: 420,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isFlipped
                        ? [Colors.purple.shade50, Colors.white]
                        : [Colors.purple.shade700, Colors.purple.shade500],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.purple.shade200,
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: SingleChildScrollView(
                          child: Text(
                            _isFlipped
                                ? _cards[_currentIndex].back
                                : _cards[_currentIndex].front,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: _isFlipped
                                  ? Colors.purple.shade800
                                  : Colors.white,
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _cards[_currentIndex].category,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _getDifficultyColor(
                            _cards[_currentIndex].difficulty,
                          ).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getDifficultyColor(
                                  _cards[_currentIndex].difficulty,
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _cards[_currentIndex].difficulty.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: _getDifficultyColor(
                                  _cards[_currentIndex].difficulty,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _isFlipped
                                ? Colors.purple.shade200
                                : Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app,
                                size: 16,
                                color: _isFlipped
                                    ? Colors.purple.shade800
                                    : Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isFlipped
                                    ? 'Tap to flip back'
                                    : 'Tap to reveal',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _isFlipped
                                      ? Colors.purple.shade800
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Action buttons ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(30, 0, 30, 30),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.red, size: 40),
                  onPressed: () => _handleSwipe(false),
                  tooltip: "Don't know",
                ),
              ),
              const SizedBox(width: 40),
              Container(
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.check, color: Colors.green, size: 40),
                  onPressed: () => _handleSwipe(true),
                  tooltip: 'Know it',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
