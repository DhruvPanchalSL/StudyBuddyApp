import 'package:flutter/material.dart';

import 'models/quiz_history.dart';

const Color _kLime = Color(0xFFAAFF00);
const Color _kDark = Color(0xFF1C1C2E);

class QuizDetailsScreen extends StatefulWidget {
  final QuizHistory history;

  const QuizDetailsScreen({super.key, required this.history});

  @override
  State<QuizDetailsScreen> createState() => _QuizDetailsScreenState();
}

class _QuizDetailsScreenState extends State<QuizDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  Color _getScoreColor() {
    double percentage = widget.history.score / widget.history.totalQuestions;
    if (percentage >= 0.8) return const Color(0xFF22C55E);
    if (percentage >= 0.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kDark,
        elevation: 0,
        title: const Text(
          'Quiz Results',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined, color: _kDark),
            onPressed: () {},
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Questions'),
          ],
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
          labelColor: _kDark,
          unselectedLabelColor: Colors.grey,
          indicatorColor: _kLime,
          indicatorWeight: 3,
          dividerColor: Colors.grey.shade200,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSummaryTab(),
          _buildQuestionsTab(),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    final pct = ((widget.history.score / widget.history.totalQuestions) * 100).round();
    final label = pct >= 80
        ? 'Mastery Achieved'
        : pct >= 50
            ? 'Good Progress'
            : 'Keep Practicing';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // Circular Score
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: CircularProgressIndicator(
                  value: widget.history.score / widget.history.totalQuestions,
                  strokeWidth: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor()),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pct',
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: _kDark,
                    ),
                  ),
                  Text(
                    'SCORE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _getScoreColor(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.history.pdfName,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 18),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                  Icons.check_circle_outline,
                  '${widget.history.score} Correct',
                  const Color(0xFFDCFCE7),
                  const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatChip(
                  Icons.percent_rounded,
                  '$pct% Accuracy',
                  const Color(0xFFDCFCE7),
                  const Color(0xFF22C55E),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Doc info card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              children: [
                _buildInfoRow(Icons.picture_as_pdf_rounded, 'Document', widget.history.pdfName),
                _buildInfoRow(Icons.calendar_today_outlined, 'Date', _formatDate(widget.history.date)),
                _buildInfoRow(Icons.check_circle_outline, 'Correct Answers',
                    '${widget.history.score}', valueColor: const Color(0xFF22C55E)),
                _buildInfoRow(Icons.cancel_outlined, 'Wrong Answers',
                    '${widget.history.totalQuestions - widget.history.score}', valueColor: Colors.red),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Difficulty breakdown card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Difficulty Analysis',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _kDark,
                  ),
                ),
                const SizedBox(height: 12),
                ..._getPerformanceBreakdown(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text, Color bg, Color iconColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: iconColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade400),
          const SizedBox(width: 10),
          Text(
            '$label:',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? _kDark,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _getPerformanceBreakdown() {
    List<Widget> widgets = [];
    var questions = widget.history.questions;

    int easyCorrect = 0;
    int mediumCorrect = 0;
    int hardCorrect = 0;

    for (var q in questions) {
      bool isCorrect = q['isCorrect'] ?? false;
      if (isCorrect) {
        if (questions.indexOf(q) % 3 == 0)
          easyCorrect++;
        else if (questions.indexOf(q) % 3 == 1)
          mediumCorrect++;
        else
          hardCorrect++;
      }
    }

    widgets.add(_buildProgressRow('Easy', easyCorrect, questions.length ~/ 3, Colors.green));
    widgets.add(_buildProgressRow('Intermediate', mediumCorrect, questions.length ~/ 3, Colors.orange));
    widgets.add(_buildProgressRow('Advanced', hardCorrect, questions.length - (questions.length ~/ 3 * 2), Colors.red));

    return widgets;
  }

  Widget _buildProgressRow(String label, int correct, int total, Color color) {
    if (total <= 0) return const SizedBox();
    final pct = (correct / total * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kDark),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: correct / total,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 6,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '$pct%',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.history.questions.length,
      itemBuilder: (context, index) {
        final question = widget.history.questions[index];
        final isCorrect = question['isCorrect'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCorrect ? const Color(0xFF22C55E).withOpacity(0.3) : Colors.red.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isCorrect ? const Color(0xFFDCFCE7) : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        isCorrect ? Icons.check_rounded : Icons.close_rounded,
                        size: 16,
                        color: isCorrect ? const Color(0xFF22C55E) : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      question['question'] ?? 'No question',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kDark,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              ...List.generate((question['options'] as List).length, (optIndex) {
                String option = question['options'][optIndex];
                bool isUserAnswer = question['userAnswer'] == optIndex;
                bool isCorrectAnswer = question['correctAnswer'] == optIndex;
                final letter = String.fromCharCode(65 + optIndex);

                Color bgColor = Colors.grey.shade50;
                Color borderColor = Colors.grey.shade200;

                if (isCorrectAnswer) {
                  bgColor = const Color(0xFFDCFCE7);
                  borderColor = const Color(0xFF22C55E);
                } else if (isUserAnswer && !isCorrectAnswer) {
                  bgColor = Colors.red.shade50;
                  borderColor = Colors.red;
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 7),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: isCorrectAnswer
                              ? const Color(0xFF22C55E)
                              : isUserAnswer && !isCorrectAnswer
                                  ? Colors.red
                                  : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCorrectAnswer
                                ? const Color(0xFF22C55E)
                                : isUserAnswer && !isCorrectAnswer
                                    ? Colors.red
                                    : Colors.grey.shade300,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            letter,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: (isCorrectAnswer || (isUserAnswer && !isCorrectAnswer))
                                  ? Colors.white
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: (isCorrectAnswer || (isUserAnswer && !isCorrectAnswer))
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: _kDark,
                          ),
                        ),
                      ),
                      if (isCorrectAnswer)
                        const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 16),
                      if (isUserAnswer && !isCorrectAnswer)
                        const Icon(Icons.cancel, color: Colors.red, size: 16),
                    ],
                  ),
                );
              }),

              if (question['explanation'] != null)
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _kLime.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _kLime.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded, size: 16, color: _kDark),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Explanation',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: _kDark,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              question['explanation'],
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
