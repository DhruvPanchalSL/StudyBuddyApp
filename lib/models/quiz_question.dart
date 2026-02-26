// Quiz Question Model
class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctAnswerIndex;
  final String explanation;
  int? selectedAnswerIndex;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctAnswerIndex,
    required this.explanation,
    this.selectedAnswerIndex,
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      question: json['question'] ?? 'No question',
      options: List<String>.from(json['options'] ?? ['A', 'B', 'C', 'D']),
      correctAnswerIndex: json['correctAnswerIndex'] ?? 0,
      explanation: json['explanation'] ?? 'No explanation available',
    );
  }

  bool get isCorrect => selectedAnswerIndex == correctAnswerIndex;
  bool get isAttempted => selectedAnswerIndex != null;
}
