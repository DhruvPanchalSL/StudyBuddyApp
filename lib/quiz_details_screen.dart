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
    if (percentage >= 0.8) return Colors.green;
    if (percentage >= 0.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Quiz Review',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 2,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Summary', icon: Icon(Icons.analytics)),
            Tab(text: 'Questions', icon: Icon(Icons.quiz)),
          ],
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: TabBarView(
          controller: _tabController,
          children: [
            // Summary Tab
            _buildSummaryTab(),
            // Questions Tab
            _buildQuestionsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Score Card
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'Your Score',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 150,
                        height: 150,
                        child: CircularProgressIndicator(
                          value:
                              widget.history.score /
                              widget.history.totalQuestions,
                          strokeWidth: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _getScoreColor(),
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Text(
                            '${widget.history.score}/${widget.history.totalQuestions}',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: _getScoreColor(),
                            ),
                          ),
                          Text(
                            '${((widget.history.score / widget.history.totalQuestions) * 100).round()}%',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildInfoRow(
                    icon: Icons.picture_as_pdf,
                    label: 'Document',
                    value: widget.history.pdfName,
                  ),
                  _buildInfoRow(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: _formatDate(widget.history.date),
                  ),
                  _buildInfoRow(
                    icon: Icons.check_circle,
                    label: 'Correct Answers',
                    value: '${widget.history.score}',
                    valueColor: Colors.green,
                  ),
                  _buildInfoRow(
                    icon: Icons.cancel,
                    label: 'Wrong Answers',
                    value:
                        '${widget.history.totalQuestions - widget.history.score}',
                    valueColor: Colors.red,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Performance Breakdown Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Performance Breakdown',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  ..._getPerformanceBreakdown(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade300),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: valueColor ?? Colors.black87,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _getPerformanceBreakdown() {
    List<Widget> widgets = [];
    var questions = widget.history.questions;

    // Calculate statistics
    int easyCorrect = 0;
    int mediumCorrect = 0;
    int hardCorrect = 0;

    // This is simplified - you can make it more sophisticated
    for (var q in questions) {
      bool isCorrect = q['isCorrect'] ?? false;
      // Just a simple categorization for demo
      if (isCorrect) {
        if (questions.indexOf(q) % 3 == 0)
          easyCorrect++;
        else if (questions.indexOf(q) % 3 == 1)
          mediumCorrect++;
        else
          hardCorrect++;
      }
    }

    widgets.add(
      _buildProgressIndicator(
        'Easy Questions',
        easyCorrect,
        questions.length ~/ 3,
        Colors.green,
      ),
    );
    widgets.add(
      _buildProgressIndicator(
        'Medium Questions',
        mediumCorrect,
        questions.length ~/ 3,
        Colors.orange,
      ),
    );
    widgets.add(
      _buildProgressIndicator(
        'Hard Questions',
        hardCorrect,
        questions.length - (questions.length ~/ 3 * 2),
        Colors.red,
      ),
    );

    return widgets;
  }

  Widget _buildProgressIndicator(
    String label,
    int correct,
    int total,
    Color color,
  ) {
    if (total == 0) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(
                '$correct/$total',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: correct / total,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
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
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Question header
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: question['isCorrect'] == true
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          question['isCorrect'] == true
                              ? Icons.check
                              : Icons.close,
                          size: 18,
                          color: question['isCorrect'] == true
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Question ${index + 1}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Question text
                Text(
                  question['question'] ?? 'No question',
                  style: const TextStyle(fontSize: 15),
                ),

                const SizedBox(height: 16),

                // Options
                ...List.generate((question['options'] as List).length, (
                  optIndex,
                ) {
                  String option = question['options'][optIndex];
                  bool isUserAnswer = question['userAnswer'] == optIndex;
                  bool isCorrectAnswer = question['correctAnswer'] == optIndex;

                  Color bgColor = Colors.transparent;
                  Color borderColor = Colors.grey.shade300;

                  if (isCorrectAnswer) {
                    bgColor = Colors.green.shade50;
                    borderColor = Colors.green;
                  } else if (isUserAnswer && !isCorrectAnswer) {
                    bgColor = Colors.red.shade50;
                    borderColor = Colors.red;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${String.fromCharCode(65 + optIndex)}.',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: borderColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            option,
                            style: TextStyle(
                              fontWeight:
                                  isCorrectAnswer ||
                                      (isUserAnswer && !isCorrectAnswer)
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isCorrectAnswer)
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 18,
                          ),
                        if (isUserAnswer && !isCorrectAnswer)
                          const Icon(Icons.cancel, color: Colors.red, size: 18),
                      ],
                    ),
                  );
                }),

                // Explanation
                if (question['explanation'] != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb,
                          size: 20,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Explanation',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(question['explanation']),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
