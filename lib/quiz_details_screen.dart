import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'models/quiz_history.dart';

class QuizDetailsScreen extends StatefulWidget {
  final QuizHistory history;

  const QuizDetailsScreen({super.key, required this.history});

  @override
  State<QuizDetailsScreen> createState() => _QuizDetailsScreenState();
}

class _QuizDetailsScreenState extends State<QuizDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showAnswers = false;

  // Brand colors
  static const Color _green = Color(0xFF7ED957);
  static const Color _greenDark = Color(0xFF5BBF35);
  static const Color _bgWhite = Colors.white;
  static const Color _bgGray = Color(0xFFF7F7F7);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);
  static const Color _red = Color(0xFFFF3B30);

  bool _isGeneratingInsight = false;
  String _aiInsight = "Our AI is analyzing your performance...";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _generateAIInsight();
  }

  Future<void> _generateAIInsight() async {
    setState(() => _isGeneratingInsight = true);
    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) throw Exception('API key not found');

      final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey');
      
      final score = widget.history.score;
      final total = widget.history.totalQuestions;
      final time = widget.history.timeTaken;
      
      final wrongQuestions = widget.history.questions
          .where((q) => q['isCorrect'] == false)
          .map((q) => "${q['question']} (Correct: ${q['options'][q['correctAnswer']]})")
          .join("\n- ");

      final prompt = '''As an AI Study Tutor, provide a brief, professional, and encouraging performance analysis for a student who just completed a quiz.
      
DATA:
- Score: $score/$total (${(score/total*100).round()}%)
- Time Taken: ${_formatDuration(time)}
- Topics missed:
${wrongQuestions.isEmpty ? "None! Perfect score." : "- " + wrongQuestions}

REQUIREMENTS:
1. Keep it under 3-4 sentences.
2. Be specific about their performance.
3. Provide one actionable tip for improvement (or maintenance if they did great).
4. Tone: Professional, supportive, and analytical.

INSIGHT:''';

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [{"parts": [{"text": prompt}]}],
          "generationConfig": {"temperature": 0.7, "maxOutputTokens": 200}
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final insight = data['candidates'][0]['content']['parts'][0]['text'].trim();
        setState(() {
          _aiInsight = insight;
          _isGeneratingInsight = false;
        });
      } else {
        throw Exception('API Error');
      }
    } catch (e) {
      debugPrint('Error generating insight: $e');
      setState(() {
        _aiInsight = "Great effort! Focus on reviewing the questions you missed to reinforce your understanding of ${widget.history.pdfName}. Consistent review is key to mastery.";
        _isGeneratingInsight = false;
      });
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double _getPercentage() =>
      (widget.history.score / widget.history.totalQuestions) * 100;

  Color _getScoreColor() {
    double pct = _getPercentage();
    if (pct >= 80) return _green;
    if (pct >= 60) return Colors.orange;
    return _red;
  }

  String _getScoreLabel() {
    double pct = _getPercentage();
    if (pct >= 80) return 'Mastery Achieved';
    if (pct >= 60) return 'Good Progress';
    return 'Keep Practicing';
  }

  String _getScoreSubtitle() {
    double pct = _getPercentage();
    if (pct >= 80) return 'You performed exceptionally well. Great job!';
    if (pct >= 60) return 'You\'re making solid progress. Keep it up!';
    return 'Review the material and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _getPercentage().round();
    final scoreColor = _getScoreColor();
    final accuracy =
        ((widget.history.score / widget.history.totalQuestions) * 100).round();

    return Scaffold(
      backgroundColor: _bgWhite,
      appBar: AppBar(
        backgroundColor: _bgWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: _textDark, size: 24),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Quiz Results',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: _textDark,
            fontSize: 17,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Score circle section
            Container(
              width: double.infinity,
              color: _bgWhite,
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                children: [
                  // Circular score
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: CircularProgressIndicator(
                            value:
                                widget.history.score /
                                widget.history.totalQuestions,
                            strokeWidth: 10,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              scoreColor,
                            ),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$percentage',
                              style: TextStyle(
                                fontSize: 52,
                                fontWeight: FontWeight.w800,
                                color: _textDark,
                                height: 1.0,
                              ),
                            ),
                            const Text(
                              'SCORE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: _textGray,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _getScoreLabel(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: scoreColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getScoreSubtitle(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: _textGray,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Stat chips row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildStatChip(
                        Icons.access_time_rounded,
                        _formatDuration(widget.history.timeTaken),
                        const Color(0xFFF0FAF0),
                        _green,
                      ),
                      const SizedBox(width: 12),
                      _buildStatChip(
                        Icons.check_circle_outline_rounded,
                        '$accuracy% Accuracy',
                        const Color(0xFFF0FAF0),
                        _green,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // AI Insight card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5FFF0),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _green.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: _isGeneratingInsight
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: CircularProgressIndicator(strokeWidth: 2, color: _greenDark),
                          )
                        : const Icon(
                            Icons.auto_awesome,
                            color: _greenDark,
                            size: 18,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AI Learning Insight',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _aiInsight,
                          style: TextStyle(
                            fontSize: 13,
                            color: _textDark.withOpacity(0.75),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Difficulty Analysis
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Difficulty Analysis',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildDifficultyBlock(
                    'EASY',
                    'Foundational',
                    _getDiffPct('EASY'),
                    _green,
                  ),
                  const SizedBox(height: 16),
                  _buildDifficultyBlock(
                    'MEDIUM',
                    'Intermediate',
                    _getDiffPct('MEDIUM'),
                    Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  _buildDifficultyBlock(
                    'HARD',
                    'Advanced',
                    _getDiffPct('HARD'),
                    _red,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Review Detailed Answers button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _showAnswers = !_showAnswers);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: Text(
                    _showAnswers
                        ? 'Hide Detailed Answers'
                        : 'Review Detailed Answers',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Retake Quiz - plain text link
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Retake Quiz',
                  style: TextStyle(
                    fontSize: 14,
                    color: _textGray,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            // Detailed Answers section
            if (_showAnswers) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const SizedBox(height: 12),
                    const Text(
                      'Detailed Answers',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...List.generate(widget.history.questions.length, (index) {
                      final q = widget.history.questions[index];
                      final isCorrect = q['isCorrect'] ?? false;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: _bgWhite,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCorrect
                                ? _green.withOpacity(0.4)
                                : _red.withOpacity(0.3),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: isCorrect
                                          ? _green.withOpacity(0.15)
                                          : _red.withOpacity(0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isCorrect ? Icons.check : Icons.close,
                                      size: 15,
                                      color: isCorrect ? _green : _red,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Question ${index + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: _textDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                q['question'] ?? '',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: _textDark,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...List.generate((q['options'] as List).length, (
                                optIndex,
                              ) {
                                final option = q['options'][optIndex];
                                final isUserAnswer =
                                    q['userAnswer'] == optIndex;
                                final isCorrectAnswer =
                                    q['correctAnswer'] == optIndex;

                                Color bgColor = Colors.transparent;
                                if (isCorrectAnswer)
                                  bgColor = const Color(0xFFF0FAF0);
                                if (isUserAnswer && !isCorrectAnswer)
                                  bgColor = const Color(0xFFFFF0F0);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bgColor,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isCorrectAnswer
                                          ? _green.withOpacity(0.4)
                                          : isUserAnswer && !isCorrectAnswer
                                          ? _red.withOpacity(0.3)
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${String.fromCharCode(65 + optIndex)}.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: isCorrectAnswer
                                              ? _green
                                              : isUserAnswer && !isCorrectAnswer
                                              ? _red
                                              : _textGray,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          option,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _textDark.withOpacity(0.85),
                                          ),
                                        ),
                                      ),
                                      if (isCorrectAnswer)
                                        Icon(
                                          Icons.check_circle,
                                          color: _green,
                                          size: 18,
                                        ),
                                      if (isUserAnswer && !isCorrectAnswer)
                                        Icon(
                                          Icons.cancel,
                                          color: _red,
                                          size: 18,
                                        ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, Color bg, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  int _getDiffPct(String level) {
    if (widget.history.difficultyAnalysis == null) return 0;
    final data = widget.history.difficultyAnalysis![level];
    if (data == null || data['total'] == 0) return 0;
    return ((data['correct'] / data['total']) * 100).round();
  }

  Widget _buildDifficultyBlock(
    String level,
    String name,
    int percentage,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left: level label + name
        SizedBox(
          width: 110,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                level,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _textGray,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ],
          ),
        ),
        // Middle: progress bar
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percentage / 100,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Right: percentage
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$percentage%',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _textDark,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
