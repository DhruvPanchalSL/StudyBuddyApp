class Flashcard {
  final String id;
  final String front;
  final String back;
  final String category;
  final String difficulty;
  int timesReviewed;
  int timesCorrect;
  DateTime? nextReviewDate;
  DateTime? lastReviewedAt;
  double easeFactor; // For spaced repetition algorithm
  int interval; // Days until next review

  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.category = 'General',
    this.difficulty = 'medium',
    this.timesReviewed = 0,
    this.timesCorrect = 0,
    this.nextReviewDate,
    this.lastReviewedAt,
    this.easeFactor = 2.5, // Default ease factor (like Anki)
    this.interval = 1, // Default interval in days
  });

  // Calculate mastery level (0-100%)
  double get masteryPercentage {
    if (timesReviewed == 0) return 0;
    return (timesCorrect / timesReviewed) * 100;
  }

  // Determine if card is due for review
  bool get isDueForReview {
    if (nextReviewDate == null) return true;
    return DateTime.now().isAfter(nextReviewDate!);
  }

  // Get status based on mastery
  String get status {
    if (timesReviewed == 0) return 'New';
    if (masteryPercentage >= 80) return 'Mastered';
    if (masteryPercentage >= 50) return 'Learning';
    return 'Needs Practice';
  }

  // Factory method to create from JSON (what AI returns)
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

  // Convert to Map for storage (Firestore)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'front': front,
      'back': back,
      'category': category,
      'difficulty': difficulty,
      'timesReviewed': timesReviewed,
      'timesCorrect': timesCorrect,
      'nextReviewDate': nextReviewDate?.toIso8601String(),
      'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      'easeFactor': easeFactor,
      'interval': interval,
    };
  }

  // Create from Map (Firestore)
  factory Flashcard.fromMap(Map<String, dynamic> map) {
    return Flashcard(
      id: map['id'] ?? '',
      front: map['front'] ?? '',
      back: map['back'] ?? '',
      category: map['category'] ?? 'General',
      difficulty: map['difficulty'] ?? 'medium',
      timesReviewed: map['timesReviewed'] ?? 0,
      timesCorrect: map['timesCorrect'] ?? 0,
      nextReviewDate: map['nextReviewDate'] != null
          ? DateTime.parse(map['nextReviewDate'])
          : null,
      lastReviewedAt: map['lastReviewedAt'] != null
          ? DateTime.parse(map['lastReviewedAt'])
          : null,
      easeFactor: (map['easeFactor'] ?? 2.5).toDouble(),
      interval: map['interval'] ?? 1,
    );
  }
}

class FlashcardDeck {
  final String id;
  final String title;
  final List<Flashcard> cards;
  final DateTime createdAt;
  final DateTime? lastStudiedAt;
  final String sourceDocument; // PDF filename
  final String userId; // Owner of the deck

  FlashcardDeck({
    required this.id,
    required this.title,
    required this.cards,
    required this.createdAt,
    required this.sourceDocument,
    required this.userId,
    this.lastStudiedAt,
  });

  // Statistics
  int get totalCards => cards.length;
  int get masteredCards => cards.where((c) => c.masteryPercentage >= 80).length;
  int get learningCards => cards
      .where((c) => c.masteryPercentage > 0 && c.masteryPercentage < 80)
      .length;
  int get newCards => cards.where((c) => c.timesReviewed == 0).length;
  int get dueCards => cards.where((c) => c.isDueForReview).length;

  double get masteryPercentage {
    if (cards.isEmpty) return 0;
    return masteredCards / cards.length * 100;
  }

  // Get cards due for review
  List<Flashcard> getCardsForReview({int limit = 20}) {
    // First get all due cards
    List<Flashcard> due = cards.where((c) => c.isDueForReview).toList();

    // Sort by priority: lowest mastery first, then oldest
    due.sort((a, b) {
      // New cards first
      if (a.timesReviewed == 0 && b.timesReviewed > 0) return -1;
      if (b.timesReviewed == 0 && a.timesReviewed > 0) return 1;

      // Then by mastery percentage (lowest first)
      if (a.masteryPercentage != b.masteryPercentage) {
        return a.masteryPercentage.compareTo(b.masteryPercentage);
      }

      // Then by last reviewed (oldest first)
      if (a.lastReviewedAt != null && b.lastReviewedAt != null) {
        return a.lastReviewedAt!.compareTo(b.lastReviewedAt!);
      }

      return 0;
    });

    return due.take(limit).toList();
  }

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'lastStudiedAt': lastStudiedAt?.toIso8601String(),
      'sourceDocument': sourceDocument,
      'userId': userId,
      'totalCards': totalCards,
      'masteredCards': masteredCards,
      'masteryPercentage': masteryPercentage,
    };
  }

  // Create from Map
  factory FlashcardDeck.fromMap(Map<String, dynamic> map) {
    return FlashcardDeck(
      id: map['id'] ?? '',
      title: map['title'] ?? 'Untitled Deck',
      cards: [], // Cards are stored separately
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      lastStudiedAt: map['lastStudiedAt'] != null
          ? DateTime.parse(map['lastStudiedAt'])
          : null,
      sourceDocument: map['sourceDocument'] ?? 'Unknown',
      userId: map['userId'] ?? '',
    );
  }
}

// For storing individual card reviews in history
class FlashcardReview {
  final String cardId;
  final String deckId;
  final bool wasCorrect;
  final int responseTimeMs; // How long user took to respond
  final DateTime reviewedAt;

  FlashcardReview({
    required this.cardId,
    required this.deckId,
    required this.wasCorrect,
    required this.responseTimeMs,
    required this.reviewedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'cardId': cardId,
      'deckId': deckId,
      'wasCorrect': wasCorrect,
      'responseTimeMs': responseTimeMs,
      'reviewedAt': reviewedAt.toIso8601String(),
    };
  }
}
