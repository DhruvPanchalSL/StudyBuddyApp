import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
    if (pct >= 80) return 'You performed better than 92% of users today.';
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
        actions: [
          IconButton(
            icon: const Icon(
              Icons.ios_share_outlined,
              color: _textDark,
              size: 22,
            ),
            onPressed: () {},
          ),
        ],
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
                        '12m 45s',
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
                    child: const Icon(
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
                          'AI Insight',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'You\'ve mastered "Quantum Fundamentals". We recommend focusing on "Wave-Particle Duality" next.',
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
                      Text(
                        'GLOBAL AVG: 72%',
                        style: TextStyle(
                          fontSize: 11,
                          color: _textGray,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildDifficultyBlock(
                    'EASY',
                    'Foundational',
                    100,
                    _green,
                    '+2%',
                  ),
                  const SizedBox(height: 16),
                  _buildDifficultyBlock(
                    'MEDIUM',
                    'Intermediate',
                    85,
                    Colors.orange,
                    '-4%',
                  ),
                  const SizedBox(height: 16),
                  _buildDifficultyBlock('HARD', 'Advanced', 70, _red, '+3%'),
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

  Widget _buildDifficultyBlock(
    String level,
    String name,
    int percentage,
    Color color,
    String delta,
  ) {
    final isPositive = delta.startsWith('+');
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
        // Right: percentage + delta
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isPositive
                    ? _green.withOpacity(0.15)
                    : _red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                delta,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isPositive ? _green : _red,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
