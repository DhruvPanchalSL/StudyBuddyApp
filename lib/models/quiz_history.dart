class QuizHistory {
  final String id;
  final String userId; // Add this
  final DateTime date;
  final String pdfName;
  final int score;
  final int totalQuestions;
  final List<Map<String, dynamic>> questions;

  QuizHistory({
    required this.id,
    required this.userId, // Add this
    required this.date,
    required this.pdfName,
    required this.score,
    required this.totalQuestions,
    required this.questions,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId, // Add this
      'date': date.toIso8601String(),
      'pdfName': pdfName,
      'score': score,
      'totalQuestions': totalQuestions,
      'questions': questions,
    };
  }

  factory QuizHistory.fromMap(Map<String, dynamic> map) {
    return QuizHistory(
      id: map['id'],
      userId: map['userId'], // Add this
      date: DateTime.parse(map['date']),
      pdfName: map['pdfName'],
      score: map['score'],
      totalQuestions: map['totalQuestions'],
      questions: List<Map<String, dynamic>>.from(map['questions']),
    );
  }
}
