import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'flashcard_model.dart';

class FlashcardService {
  final String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  // Generate flashcards from text using AI
  Future<List<Flashcard>> generateFlashcards(String text) async {
    try {
      String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) throw Exception('API key not found');

      final url = Uri.parse('$_geminiEndpoint?key=$apiKey');

      // Limit text length
      String processedText = text;
      if (processedText.length > 25000) {
        processedText =
            processedText.substring(0, 25000) +
            "\n\n[Note: Text truncated for flashcard generation...]";
      }

      // Enhanced prompt for better flashcards
      String prompt =
          '''
Based on the following text, create 10 high-quality flashcards for studying.
Each flashcard should have a clear question/term on the front and a comprehensive answer/definition on the back.

Guidelines:
- Front should be a specific question or term
- Back should provide a complete but concise explanation
- Categorize by difficulty (easy, medium, hard) based on complexity
- Assign a relevant category/topic

Return as JSON array:
[
  {
    "front": "What is the main function of mitochondria?",
    "back": "Mitochondria are the powerhouses of the cell, generating ATP through cellular respiration.",
    "category": "Cell Biology",
    "difficulty": "medium"
  }
]

Text: $processedText
''';

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

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        String responseText =
            jsonResponse['candidates'][0]['content']['parts'][0]['text'];

        // Extract JSON array from response
        RegExp jsonRegex = RegExp(r'\[[\s\S]*\]');
        Match? match = jsonRegex.firstMatch(responseText);

        if (match != null) {
          String jsonStr = match.group(0)!;
          List<dynamic> cardsJson = jsonDecode(jsonStr);

          // Convert to Flashcard objects
          return cardsJson.map((json) => Flashcard.fromJson(json)).toList();
        } else {
          // Try to find any JSON object if array not found
          RegExp objectRegex = RegExp(r'\{[\s\S]*\}');
          match = objectRegex.firstMatch(responseText);

          if (match != null) {
            // If single object, wrap in array
            var singleCard = jsonDecode(match.group(0)!);
            return [Flashcard.fromJson(singleCard)];
          }
        }
      }
      return [];
    } catch (e) {
      print('Error generating flashcards: $e');
      return [];
    }
  }

  // Spaced Repetition Algorithm (SM-2 style)
  void updateCardAfterReview(
    Flashcard card,
    bool wasCorrect,
    int responseTimeMs,
  ) {
    card.timesReviewed++;
    card.lastReviewedAt = DateTime.now();

    if (wasCorrect) {
      card.timesCorrect++;

      // SM-2 algorithm for spaced repetition
      if (card.timesReviewed == 1) {
        card.interval = 1; // 1 day
      } else if (card.timesReviewed == 2) {
        card.interval = 3; // 3 days
      } else {
        // Increase interval based on ease factor
        card.interval = (card.interval * card.easeFactor).round();
      }

      // Adjust ease factor (between 1.3 and 3.5)
      card.easeFactor =
          card.easeFactor + (0.1 - (5 - card.timesCorrect) * 0.08);
      if (card.easeFactor < 1.3) card.easeFactor = 1.3;
      if (card.easeFactor > 3.5) card.easeFactor = 3.5;
    } else {
      // If wrong, reset interval and decrease ease factor
      card.interval = 1;
      card.easeFactor = (card.easeFactor - 0.2).clamp(1.3, 3.5);
    }

    // Calculate next review date
    card.nextReviewDate = DateTime.now().add(Duration(days: card.interval));
  }

  // Save flashcard deck to Firestore
  Future<String?> saveDeckToFirestore({
    required String title,
    required List<Flashcard> cards,
    required String sourceDocument,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      final deckId = DateTime.now().millisecondsSinceEpoch.toString();

      // Create deck document
      final deck = FlashcardDeck(
        id: deckId,
        title: title,
        cards: cards,
        createdAt: DateTime.now(),
        sourceDocument: sourceDocument,
        userId: user.uid,
      );

      // Save deck metadata
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .doc(deckId)
          .set(deck.toMap());

      // Save individual cards as subcollection
      for (var card in cards) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('flashcard_decks')
            .doc(deckId)
            .collection('cards')
            .doc(card.id)
            .set(card.toMap());
      }

      return deckId;
    } catch (e) {
      print('Error saving deck: $e');
      return null;
    }
  }

  // Load a specific deck with all cards
  Future<FlashcardDeck?> loadDeck(String deckId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not logged in');

      // Get deck metadata
      final deckDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .doc(deckId)
          .get();

      if (!deckDoc.exists) return null;

      // Get all cards in deck
      final cardsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .doc(deckId)
          .collection('cards')
          .get();

      final cards = cardsSnapshot.docs
          .map((doc) => Flashcard.fromMap(doc.data()))
          .toList();

      // Create deck object with cards
      final deckData = deckDoc.data()!;
      return FlashcardDeck(
        id: deckId,
        title: deckData['title'] ?? 'Untitled',
        cards: cards,
        createdAt: DateTime.parse(deckData['createdAt']),
        lastStudiedAt: deckData['lastStudiedAt'] != null
            ? DateTime.parse(deckData['lastStudiedAt'])
            : null,
        sourceDocument: deckData['sourceDocument'] ?? 'Unknown',
        userId: user.uid,
      );
    } catch (e) {
      print('Error loading deck: $e');
      return null;
    }
  }

  // Get all decks for current user
  Future<List<FlashcardDeck>> getUserDecks() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return [];

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return FlashcardDeck(
          id: doc.id,
          title: data['title'] ?? 'Untitled',
          cards: [], // Don't load cards here for performance
          createdAt: DateTime.parse(data['createdAt']),
          lastStudiedAt: data['lastStudiedAt'] != null
              ? DateTime.parse(data['lastStudiedAt'])
              : null,
          sourceDocument: data['sourceDocument'] ?? 'Unknown',
          userId: user.uid,
        );
      }).toList();
    } catch (e) {
      print('Error getting decks: $e');
      return [];
    }
  }

  // Update deck's last studied time
  Future<void> updateLastStudied(String deckId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .doc(deckId)
          .update({'lastStudiedAt': DateTime.now().toIso8601String()});
    } catch (e) {
      print('Error updating last studied: $e');
    }
  }

  // Update individual card after review
  Future<void> updateCardAfterReviewInFirestore(
    String deckId,
    Flashcard card,
    bool wasCorrect,
    int responseTimeMs,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Update card in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .doc(deckId)
          .collection('cards')
          .doc(card.id)
          .update(card.toMap());

      // Save review history
      final review = FlashcardReview(
        cardId: card.id,
        deckId: deckId,
        wasCorrect: wasCorrect,
        responseTimeMs: responseTimeMs,
        reviewedAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_reviews')
          .add(review.toMap());

      // Update deck last studied
      await updateLastStudied(deckId);
    } catch (e) {
      print('Error updating card: $e');
    }
  }

  // Delete a deck
  Future<void> deleteDeck(String deckId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Delete all cards in deck
      final cardsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .doc(deckId)
          .collection('cards')
          .get();

      for (var doc in cardsSnapshot.docs) {
        await doc.reference.delete();
      }

      // Delete deck document
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('flashcard_decks')
          .doc(deckId)
          .delete();
    } catch (e) {
      print('Error deleting deck: $e');
    }
  }

  // Get study statistics for user
  Future<Map<String, dynamic>> getStudyStats() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return {};

      final decks = await getUserDecks();

      int totalCards = 0;
      int masteredCards = 0;
      int dueToday = 0;

      for (var deck in decks) {
        final fullDeck = await loadDeck(deck.id);
        if (fullDeck != null) {
          totalCards += fullDeck.totalCards;
          masteredCards += fullDeck.masteredCards;
          dueToday += fullDeck.dueCards;
        }
      }

      return {
        'totalDecks': decks.length,
        'totalCards': totalCards,
        'masteredCards': masteredCards,
        'dueToday': dueToday,
        'masteryPercentage': totalCards > 0
            ? (masteredCards / totalCards * 100).round()
            : 0,
      };
    } catch (e) {
      print('Error getting stats: $e');
      return {};
    }
  }

  // In-memory storage for temporary decks (not saved)
  static final List<FlashcardDeck> _memoryDecks = [];

  void saveDeckToMemory(FlashcardDeck deck) {
    _memoryDecks.add(deck);
  }

  List<FlashcardDeck> getMemoryDecks() => _memoryDecks;

  void clearMemoryDecks() {
    _memoryDecks.clear();
  }
}
