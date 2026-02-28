import 'package:flutter/material.dart';

import 'models/quiz_question.dart';

/// A dedicated full-screen quiz experience matching the design reference.
/// Pass [questions], [pdfName] and an optional [onQuizComplete] callback.
class QuizScreen extends StatefulWidget {
  final List<QuizQuestion> questions;
  final String pdfName;
  final String? chapterTitle;
  final void Function(int score, List<QuizQuestion> questions)? onQuizComplete;

  const QuizScreen({
    super.key,
    required this.questions,
    required this.pdfName,
    this.chapterTitle,
    this.onQuizComplete,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen>
    with SingleTickerProviderStateMixin {
  // ── Brand colors ──────────────────────────────────────────────
  static const Color _green = Color(0xFF7ED957);
  static const Color _greenLight = Color(0xFFEBFBDF);
  static const Color _bgGray = Color(0xFFF5F5F7);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);
  static const Color _white = Colors.white;

  int _currentIndex = 0;

  // Animation for option tap feedback
  late AnimationController _bounceController;
  late Animation<double> _bounceAnim;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _bounceAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  QuizQuestion get _current => widget.questions[_currentIndex];
  int get _total => widget.questions.length;

  void _selectOption(int index) {
    setState(() => _current.selectedAnswerIndex = index);
    _bounceController.forward().then((_) => _bounceController.reverse());
  }

  void _submitOrNext() {
    if (_current.selectedAnswerIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select an answer first'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.orange,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    if (_currentIndex < _total - 1) {
      setState(() => _currentIndex++);
    } else {
      // Quiz complete
      int score = widget.questions.where((q) => q.isCorrect).length;
      widget.onQuizComplete?.call(score, widget.questions);
      Navigator.pop(context);
    }
  }

  void _resetCurrentQuestion() {
    setState(() => _current.selectedAnswerIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_currentIndex + 1) / _total;
    final questionNumber = (_currentIndex + 1).toString().padLeft(2, '0');
    final totalStr = _total.toString().padLeft(2, '0');

    return Scaffold(
      backgroundColor: _bgGray,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────
            _buildHeader(),

            // ── Progress bar ─────────────────────────────────────
            _buildProgressBar(progress, questionNumber, totalStr),

            // ── Scrollable content ───────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question chip
                    _buildQuestionChip(questionNumber),
                    const SizedBox(height: 20),

                    // Question text
                    Text(
                      _current.question,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                        height: 1.35,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Options
                    ...List.generate(_current.options.length, (i) {
                      return _buildOptionTile(i);
                    }),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // ── Bottom action bar ────────────────────────────────
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Sub-widgets ─────────────────────────────────────────────────

  Widget _buildHeader() {
    final title = widget.pdfName
        .replaceAll('.pdf', '')
        .toUpperCase()
        .split(' ')
        .take(3)
        .join(' ');
    final chapter = widget.chapterTitle ?? 'DOCUMENT REVIEW';

    return Container(
      color: _white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, color: _textDark, size: 22),
            onPressed: () => Navigator.pop(context),
          ),

          // Title block
          Expanded(
            child: Column(
              children: [
                Text(
                  title.isEmpty ? 'STUDY QUIZ' : title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  chapter.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: _textGray,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Three-dot menu
          IconButton(
            icon: const Icon(Icons.more_horiz, color: _textDark, size: 22),
            onPressed: () => _showQuizMenu(),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(
    double progress,
    String questionNumber,
    String totalStr,
  ) {
    return Container(
      color: _white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'QUIZ PROGRESS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: _textGray,
                  letterSpacing: 1.3,
                ),
              ),
              Text(
                '$questionNumber / $totalStr',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _textGray,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(_green),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionChip(String number) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _greenLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'QUESTION $number',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _green,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildOptionTile(int index) {
    final isSelected = _current.selectedAnswerIndex == index;
    final letter = String.fromCharCode(65 + index); // A, B, C, D
    final optionText = _current.options[index];

    return AnimatedBuilder(
      animation: _bounceAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: isSelected ? _bounceAnim.value : 1.0,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () => _selectOption(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? _greenLight : _white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _green : Colors.grey.shade200,
              width: isSelected ? 2 : 1.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _green.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Letter circle
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected ? _green : Colors.grey.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? _green : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? _white : _textGray,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Option text
              Expanded(
                child: Text(
                  optionText,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? _textDark : _textDark.withOpacity(0.85),
                    height: 1.3,
                  ),
                ),
              ),

              // Selected indicator dot
              if (isSelected) ...[
                const SizedBox(width: 12),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final isLast = _currentIndex == _total - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: _white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Submit / Next button
          Expanded(
            child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _submitOrNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: _white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      isLast ? 'Submit Quiz' : 'Submit Answer',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Reset / refresh button
          GestureDetector(
            onTap: _resetCurrentQuestion,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200, width: 1.5),
              ),
              child: Icon(Icons.refresh_rounded, color: _textGray, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuizMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _menuItem(
              Icons.restart_alt_rounded,
              'Restart Quiz',
              Colors.orange,
              () {
                Navigator.pop(context);
                setState(() {
                  _currentIndex = 0;
                  for (var q in widget.questions) {
                    q.selectedAnswerIndex = null;
                  }
                });
              },
            ),
            _menuItem(Icons.exit_to_app_rounded, 'Exit Quiz', Colors.red, () {
              Navigator.pop(context);
              Navigator.pop(context);
            }),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      onTap: onTap,
    );
  }
}
