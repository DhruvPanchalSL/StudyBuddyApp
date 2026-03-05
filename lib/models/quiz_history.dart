class QuizHistory {
  final String id;
  final String userId; // Add this
  final DateTime date;
  final String pdfName;
  final int score;
  final int totalQuestions;
  final List<Map<String, dynamic>> questions;

  final int timeTaken; // in seconds
  final Map<String, dynamic>? difficultyAnalysis;

  // Structured Learning fields
  final bool isStructured;
  final int? moduleIndex;
  final int? totalModules;
  final int? pagesPerModule;

  QuizHistory({
    required this.id,
    required this.userId,
    required this.date,
    required this.pdfName,
    required this.score,
    required this.totalQuestions,
    required this.questions,
    this.timeTaken = 0,
    this.difficultyAnalysis,
    this.isStructured = false,
    this.moduleIndex,
    this.totalModules,
    this.pagesPerModule,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'date': date.toIso8601String(),
      'pdfName': pdfName,
      'score': score,
      'totalQuestions': totalQuestions,
      'questions': questions,
      'timeTaken': timeTaken,
      'difficultyAnalysis': difficultyAnalysis,
      'isStructured': isStructured,
      'moduleIndex': moduleIndex,
      'totalModules': totalModules,
      'pagesPerModule': pagesPerModule,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory QuizHistory.fromMap(Map<String, dynamic> map) {
    return QuizHistory(
      id: map['id'],
      userId: map['userId'],
      date: DateTime.parse(map['date']),
      pdfName: map['pdfName'],
      score: map['score'],
      totalQuestions: map['totalQuestions'],
      questions: List<Map<String, dynamic>>.from(map['questions']),
      timeTaken: map['timeTaken'] ?? 0,
      difficultyAnalysis: map['difficultyAnalysis'],
      isStructured: map['isStructured'] ?? false,
      moduleIndex: map['moduleIndex'],
      totalModules: map['totalModules'],
      pagesPerModule: map['pagesPerModule'],
    );
  }
}
