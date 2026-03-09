import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'auth_screen.dart';
import 'chat_screen.dart';
import 'features/charts/visual_tools_screen.dart';
import 'features/flashcards/flashcard_screen.dart';
import 'history_screen.dart';
import 'models/chat_message.dart';
import 'models/quiz_history.dart';
import 'models/quiz_question.dart';
import 'quiz_screen.dart';
import 'settings_screen.dart';

bool kShowLoginSuccess =
    false; // kept for AuthScreen to read, no longer used in StreamBuilder

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Study Buddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFF5F5F7),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Colors.transparent,
        ),
      ),
      home: const _RootWidget(),
    );
  }
}

// ── Root widget — listens to auth state and navigates imperatively.
// This avoids the StreamBuilder race where switching to HomeScreen
// would interrupt Navigator.push(LoginSuccessScreen) mid-flight.
class _RootWidget extends StatefulWidget {
  const _RootWidget();

  @override
  State<_RootWidget> createState() => _RootWidgetState();
}

class _RootWidgetState extends State<_RootWidget> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            snapshot.connectionState == ConnectionState.none) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // When signed out → show AuthScreen.
        // AuthScreen handles pushing LoginSuccessScreen after login/signup
        // and the stream will transition to HomeScreen after it pops.
        if (snapshot.data == null) return const AuthScreen();
        return const HomeScreen();
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String _selectedFileName = "No file selected";
  String _extractedText = "";
  String _summary = "";
  bool _isLoading = false;
  bool _isGeneratingSummary = false;
  bool _isGeneratingQuiz = false;
  bool _showQuizResults = false;
  List<QuizQuestion> _quizQuestions = [];
  int _quizScore = 0;
  String? _lastQuizId;
  List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  bool _isSendingMessage = false;
  final ScrollController _chatScrollController = ScrollController();
  int _currentTabIndex = 0;
  int _bottomNavIndex = 0;
  late TabController _tabController;

  List<Map<String, dynamic>> _recentSessions = [];

  bool _isStructuredLearningMode = false;
  List<String> _allPdfPagesText = [];
  int _pagesPerModule = 10;
  int _currentModuleIndex = 0;
  int get _totalModules => _allPdfPagesText.isEmpty
      ? 0
      : (_allPdfPagesText.length / _pagesPerModule).ceil();

  // ── API Key State ──────────────────────────────────────────────────────────
  String _userGeminiKey = '';
  String _userGroqKey = '';

  // Gemini endpoint (user key first, then app default)
  String get _activeGeminiKey {
    final userKey = _userGeminiKey.trim();
    return userKey.isNotEmpty ? userKey : (dotenv.env['GEMINI_API_KEY'] ?? '');
  }

  // Groq endpoint (user key first, then app default)
  String get _activeGroqKey {
    final userKey = _userGroqKey.trim();
    return userKey.isNotEmpty ? userKey : (dotenv.env['GROQ_API_KEY'] ?? '');
  }

  // Keep this getter so ChatScreen and other places still compile unchanged
  String get _activeApiKey => _activeGeminiKey;

  static const String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  static const String _groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'llama-3.3-70b-versatile';

  // Color palette
  static const Color _green = Color(0xFF7ED957);
  static const Color _darkNavy = Color(0xFF1A1A2E);
  static const Color _teal = Color(0xFF00C2B2);
  static const Color _bgGray = Color(0xFFF5F5F7);
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);
  static const Color _textGrayLight = Color(0xFFC7C7CC);

  int _totalQuizzes = 0;
  double _avgScore = 0;
  int _streakDays = 0;
  Map<DateTime, int> _activityMap = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    });

    _chatMessages.add(
      ChatMessage(
        text:
            "👋 Hi! I'm your AI study assistant. Ask me anything about your document!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );

    // Small delay to let Firebase Auth token fully propagate to Firestore
    // before making queries — prevents PERMISSION_DENIED on first load
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _loadRecentSessions();
        _loadProfileStats();
        _loadUserApiKeys();
      }
    });
  }

  // ── Load both keys from Firestore ─────────────────────────────────────────
  Future<void> _loadUserApiKeys() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        setState(() {
          _userGeminiKey = doc.data()?['geminiApiKey'] ?? '';
          _userGroqKey = doc.data()?['groqApiKey'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading user API keys: $e');
    }
  }

  // ── Universal AI caller with Gemini → Groq fallback ──────────────────────
  //
  // Returns the response text string on success, throws on total failure.
  Future<String> _callAI(String prompt, {int maxTokens = 2048}) async {
    // ── Step 1: Try Gemini ──────────────────────────────────────────────────
    final geminiKey = _activeGeminiKey;
    if (geminiKey.isNotEmpty) {
      try {
        final url = Uri.parse('$_geminiEndpoint?key=$geminiKey');
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
            "generationConfig": {
              "temperature": 0.7,
              "maxOutputTokens": maxTokens,
            },
          }),
        );

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          return json['candidates'][0]['content']['parts'][0]['text'] as String;
        } else if (response.statusCode == 429) {
          // Rate limited → fall through to Groq
          debugPrint('Gemini rate limited (429), falling back to Groq...');
        } else {
          throw Exception('Gemini API Error: ${response.statusCode}');
        }
      } catch (e) {
        if (e.toString().contains('Gemini API Error')) rethrow;
        debugPrint('Gemini call failed: $e — falling back to Groq');
      }
    }

    // ── Step 2: Fallback to Groq ────────────────────────────────────────────
    final groqKey = _activeGroqKey;
    if (groqKey.isEmpty) {
      throw Exception(
        'All AI keys exhausted. Please add a Groq API key in Settings.',
      );
    }

    final groqResponse = await http.post(
      Uri.parse(_groqEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $groqKey',
      },
      body: jsonEncode({
        "model": _groqModel,
        "messages": [
          {"role": "user", "content": prompt},
        ],
        "max_tokens": maxTokens,
        "temperature": 0.7,
      }),
    );

    if (groqResponse.statusCode == 200) {
      final json = jsonDecode(groqResponse.body);
      return json['choices'][0]['message']['content'] as String;
    } else if (groqResponse.statusCode == 429) {
      throw Exception(
        '⏳ Both Gemini and Groq are rate limited. Please wait a moment.',
      );
    } else {
      throw Exception('Groq API Error: ${groqResponse.statusCode}');
    }
  }

  // ── Profile / session loaders ──────────────────────────────────────────────

  Future<void> _loadProfileStats() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('quiz_history')
          .get();

      int total = snapshot.docs.length;
      double avg = 0;
      Map<DateTime, int> activity = {};

      if (total > 0) {
        double totalScorePercent = 0;
        for (var doc in snapshot.docs) {
          final data = doc.data();
          final score = data['score'] as int? ?? 0;
          final totalQ = data['totalQuestions'] as int? ?? 1;
          totalScorePercent += (score / totalQ);

          final dateStr = data['date'] as String?;
          if (dateStr != null) {
            final dateObj = DateTime.parse(dateStr);
            final day = DateTime(dateObj.year, dateObj.month, dateObj.day);
            activity[day] = (activity[day] ?? 0) + 1;
          }
        }
        avg = (totalScorePercent / total) * 100;
      }

      int streak = 0;
      DateTime checkDate = DateTime.now();
      checkDate = DateTime(checkDate.year, checkDate.month, checkDate.day);

      if (!activity.containsKey(checkDate)) {
        checkDate = checkDate.subtract(const Duration(days: 1));
      }
      while (activity.containsKey(checkDate)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      }

      setState(() {
        _totalQuizzes = total;
        _avgScore = avg;
        _streakDays = streak;
        _activityMap = activity;
      });
    } catch (e) {
      debugPrint('Error loading profile stats: $e');
    }
  }

  Future<void> _loadRecentSessions() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('quiz_history')
          .orderBy('date', descending: true)
          .limit(5)
          .get();

      setState(() {
        _recentSessions = snapshot.docs.map((doc) {
          final data = doc.data();
          final dateStr = data['date'] as String?;
          final dateObj = dateStr != null
              ? DateTime.parse(dateStr)
              : DateTime.now();
          final isStructured = data['isStructured'] == true;
          final moduleIndex = data['moduleIndex'] as int?;
          final totalModules = data['totalModules'] as int?;
          final pdfName = data['pdfName'] ?? 'Untitled';
          final title =
              isStructured && moduleIndex != null && totalModules != null
              ? '$pdfName (Module ${moduleIndex + 1}/$totalModules)'
              : pdfName;

          return {
            'id': doc.id,
            'title': title,
            'date': dateObj,
            'score': data['score'] ?? 0,
            'total': data['totalQuestions'] ?? 0,
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('Error loading recent sessions: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // ── PDF helpers ────────────────────────────────────────────────────────────

  Future<void> _pickAndReadPDF({
    Future<void> Function()? onComplete,
    bool isStructured = false,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        setState(() {
          _isLoading = true;
          _selectedFileName = result.files.first.name;
          _extractedText = "";
          _summary = "";
          _quizQuestions = [];
          _showQuizResults = false;
          _chatMessages.clear();
          _chatMessages.add(
            ChatMessage(
              text:
                  "👋 Hi! I'm your AI study assistant. Ask me anything about your document!",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isStructuredLearningMode = isStructured;
          _allPdfPagesText = [];
          _currentModuleIndex = 0;
        });

        String filePath = result.files.first.path!;
        List<String> pages = await _extractTextFromPDF(filePath);

        setState(() {
          _allPdfPagesText = pages;
          _isLoading = false;
        });

        if (isStructured) {
          Future.microtask(() => _checkStructuredProgressAndPrompt());
        } else {
          setState(() {
            _extractedText = _allPdfPagesText.join('\n');
            _bottomNavIndex = 2;
          });
          if (onComplete != null) await onComplete();
        }
      } else {
        setState(() => _selectedFileName = "No file selected");
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _extractedText = "Error reading PDF: $e";
      });
    }
  }

  Future<void> _checkStructuredProgressAndPrompt() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) {
      _showStructuredConfigSheet();
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('quiz_history')
          .where('pdfName', isEqualTo: _selectedFileName)
          .where('isStructured', isEqualTo: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        int maxModuleIndex = -1;
        Map<String, dynamic>? bestData;

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final mIndex = data['moduleIndex'] as int?;
          if (mIndex != null && mIndex > maxModuleIndex) {
            maxModuleIndex = mIndex;
            bestData = data;
          }
        }

        if (bestData != null) {
          final totalModules = bestData['totalModules'] as int?;
          final pagesPerModule = bestData['pagesPerModule'] as int?;

          if (totalModules != null && pagesPerModule != null) {
            final nextModuleIndex = maxModuleIndex + 1;

            if (nextModuleIndex < totalModules && mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext context) {
                  return AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    title: const Text('Resume Learning?'),
                    content: Text(
                      'You previously completed Module ${maxModuleIndex + 1} of $totalModules.\n\nWould you like to proceed with Module ${nextModuleIndex + 1}, or start over?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showStructuredConfigSheet();
                        },
                        child: const Text(
                          'Start Over',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() => _pagesPerModule = pagesPerModule);
                          _loadModule(nextModuleIndex);
                          setState(() => _bottomNavIndex = 2);
                        },
                        child: const Text('Resume Next Module'),
                      ),
                    ],
                  );
                },
              );
              return;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking progress: $e');
    }

    _showStructuredConfigSheet();
  }

  void _loadModule(int moduleIndex) {
    if (_allPdfPagesText.isEmpty) return;
    int startIndex = moduleIndex * _pagesPerModule;
    int endIndex = (startIndex + _pagesPerModule).clamp(
      0,
      _allPdfPagesText.length,
    );
    setState(() {
      _currentModuleIndex = moduleIndex;
      _extractedText = _allPdfPagesText
          .sublist(startIndex, endIndex)
          .join('\n');
      _summary = "";
      _quizQuestions = [];
    });
  }

  Future<List<String>> _extractTextFromPDF(String filePath) async {
    List<String> pagesText = [];
    try {
      File file = File(filePath);
      List<int> bytes = await file.readAsBytes();
      PdfDocument document = PdfDocument(inputBytes: bytes);
      PdfTextExtractor extractor = PdfTextExtractor(document);
      for (int i = 0; i < document.pages.count; i++) {
        String pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        pagesText.add("--- Page ${i + 1} ---\n$pageText\n");
      }
      document.dispose();
      return pagesText;
    } catch (e) {
      return [
        "Could not extract text. This PDF might be scanned or image-based.\nError: $e",
      ];
    }
  }

  // ── AI Feature Methods ─────────────────────────────────────────────────────

  Future<void> _generateSummary() async {
    if (_extractedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please extract text from a PDF first')),
      );
      return;
    }

    setState(() => _isGeneratingSummary = true);

    try {
      String textToSummarize = _extractedText;

      // Determine document size tier
      final charCount = textToSummarize.length;
      final isLarge = charCount > 20000; // ~10+ pages
      final isHuge = charCount > 60000; // ~30+ pages

      if (isHuge) {
        textToSummarize =
            textToSummarize.substring(0, 60000) +
            "\n\n[Document truncated for analysis — showing first ~30 pages]";
      }

      // Adaptive instructions per size tier
      final executiveSummaryInstruction = isLarge
          ? 'Write 2-3 concise paragraphs covering the document\'s purpose, main argument, and key conclusions. Keep it high-level — no page-by-page breakdown.'
          : 'Write a comprehensive 3-4 paragraph overview of the document\'s purpose, core thesis, and main conclusions.';

      final analysisInstruction = isLarge
          ? 'Identify the 3-5 most critical concepts or arguments. For each, write 1-2 sentences on why it matters. Do NOT analyze individual pages — focus on big-picture insights only.'
          : 'A deep dive into specific details, data points, or technical explanations. Break down complex ideas into manageable parts.';

      final themesInstruction = isLarge
          ? 'List 4-5 major themes as short bullet points with a single sentence each.'
          : 'Identify 5-7 important themes. For each, provide a brief explanation of its significance.';

      final prompt =
          '''Analyze the following document and respond using exactly these section headers. IMPORTANT: Do NOT use square brackets anywhere in your content — only use them for the section headers below.

${isLarge ? 'NOTE: This is a large document. Keep each section concise and high-level. Do NOT do a page-by-page analysis.' : ''}

[EXECUTIVE_SUMMARY]
($executiveSummaryInstruction)

[KEY_THEMES_AND_CONCEPTS]
($themesInstruction)

[DETAILED_ANALYSIS]
($analysisInstruction)

[PRACTICAL_APPLICATIONS]
(${isLarge ? 'List 3 practical takeaways in bullet points.' : 'Explain how the information can be applied in real-world scenarios, professional contexts, or further study.'})

[STUDY_GUIDE_AND_REFLECTIONS]
(Provide ${isLarge ? '3' : '4-5'} thought-provoking questions for further reflection.)

Text to analyze:
$textToSummarize''';

      final tokens = isHuge ? 2048 : (isLarge ? 2560 : 4096);
      final summary = await _callAI(prompt, maxTokens: tokens);

      setState(() {
        _summary = summary;
        _isGeneratingSummary = false;
      });

      _tabController.animateTo(0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Summary generated (${summary.length} chars)'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isGeneratingSummary = false;
        _summary = "Error generating summary: $e";
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _generateQuiz({int count = 5}) async {
    if (_extractedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please extract text from a PDF first')),
      );
      return;
    }

    setState(() {
      _isGeneratingQuiz = true;
      _quizQuestions = [];
      _showQuizResults = false;
    });

    try {
      String textForQuiz = _extractedText;
      if (textForQuiz.length > 25000) {
        textForQuiz =
            textForQuiz.substring(0, 25000) +
            "\n\n[Note: Text truncated for quiz generation...]";
      }

      final prompt =
          '''Based on the following text, generate $count multiple choice quiz questions.
Each question should have 4 options (A, B, C, D) with exactly one correct answer.
Include a brief explanation for why the correct answer is right.
Assign a difficulty level (EASY, MEDIUM, HARD) to each question based on the depth of understanding required.

Return the response in this EXACT JSON format:
{
  "questions": [
    {
      "question": "Question text here?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correctAnswerIndex": 0,
      "explanation": "Explanation why this is correct",
      "difficulty": "MEDIUM"
    }
  ]
}

IMPORTANT: 
- correctAnswerIndex must be 0, 1, 2, or 3
- difficulty must be "EASY", "MEDIUM", or "HARD"
- Make questions challenging but fair
- Base questions strictly on the provided text
- Return ONLY the JSON, no extra text

TEXT:
$textForQuiz

JSON RESPONSE:''';

      final responseText = await _callAI(prompt, maxTokens: 4096);

      RegExp jsonRegex = RegExp(r'\{[\s\S]*\}');
      Match? match = jsonRegex.firstMatch(responseText);

      if (match != null) {
        final quizData = jsonDecode(match.group(0)!);
        if (quizData['questions'] != null && quizData['questions'].isNotEmpty) {
          List<QuizQuestion> questions = (quizData['questions'] as List)
              .map((q) => QuizQuestion.fromJson(q))
              .toList();

          setState(() {
            _quizQuestions = questions;
            _isGeneratingQuiz = false;
          });

          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => QuizScreen(
                  questions: questions,
                  pdfName: _selectedFileName,
                  chapterTitle: 'Document Review',
                  onQuizComplete: (score, completedQuestions, timeTaken) {
                    setState(() {
                      _quizScore = score;
                      _showQuizResults = true;
                    });

                    final Map<String, dynamic> diffAnalysis = {
                      'EASY': {'total': 0, 'correct': 0},
                      'MEDIUM': {'total': 0, 'correct': 0},
                      'HARD': {'total': 0, 'correct': 0},
                    };
                    for (var q in completedQuestions) {
                      final d = q.difficulty.toUpperCase();
                      if (diffAnalysis.containsKey(d)) {
                        diffAnalysis[d]!['total'] =
                            (diffAnalysis[d]!['total'] ?? 0) + 1;
                        if (q.isCorrect) {
                          diffAnalysis[d]!['correct'] =
                              (diffAnalysis[d]!['correct'] ?? 0) + 1;
                        }
                      }
                    }
                    _saveQuizToHistory(timeTaken, diffAnalysis);
                  },
                ),
              ),
            );
          }
        } else {
          throw Exception('No questions in response');
        }
      } else {
        throw Exception('Could not parse quiz JSON');
      }
    } catch (e) {
      setState(() => _isGeneratingQuiz = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating quiz: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _sendMessage() async {
    if (_chatController.text.trim().isEmpty) return;

    String userMessage = _chatController.text.trim();

    setState(() {
      _chatMessages.add(
        ChatMessage(text: userMessage, isUser: true, timestamp: DateTime.now()),
      );
      _chatController.clear();
      _isSendingMessage = true;
    });

    _scrollToBottom();

    try {
      String context = _summary.isNotEmpty ? _summary : _extractedText;

      if (context.isEmpty) {
        setState(() {
          _chatMessages.add(
            ChatMessage(
              text:
                  "Please upload a PDF first so I can answer questions about your document!",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isSendingMessage = false;
        });
        _scrollToBottom();
        return;
      }

      if (context.length > 20000) {
        context = context.substring(0, 20000) + "...";
      }

      final prompt =
          '''You are a helpful study assistant. Answer the user's question based ONLY on the following context.
If the answer cannot be found in the context, say "I don't have enough information about that in the document."

CONTEXT:
$context

USER QUESTION: $userMessage

ANSWER (be concise but helpful):''';

      final aiResponse = await _callAI(prompt, maxTokens: 1024);

      setState(() {
        _chatMessages.add(
          ChatMessage(
            text: aiResponse,
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _isSendingMessage = false;
      });
    } catch (e) {
      setState(() {
        _chatMessages.add(
          ChatMessage(
            text:
                "Sorry, I encountered an error: ${e.toString().substring(0, e.toString().length.clamp(0, 120))}",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
        _isSendingMessage = false;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectAnswer(int questionIndex, int answerIndex) {
    setState(() {
      _quizQuestions[questionIndex].selectedAnswerIndex = answerIndex;
    });
  }

  Future<void> _saveQuizToHistory(
    int timeTaken,
    Map<String, dynamic> difficultyAnalysis,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to save quiz history'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      List<Map<String, dynamic>> questionDetails = [];
      for (var q in _quizQuestions) {
        questionDetails.add({
          'question': q.question,
          'options': q.options,
          'userAnswer': q.selectedAnswerIndex,
          'correctAnswer': q.correctAnswerIndex,
          'isCorrect': q.isCorrect,
          'explanation': q.explanation,
          'difficulty': q.difficulty,
        });
      }

      final history = QuizHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: user.uid,
        date: DateTime.now(),
        pdfName: _selectedFileName,
        score: _quizScore,
        totalQuestions: _quizQuestions.length,
        questions: questionDetails,
        timeTaken: timeTaken,
        difficultyAnalysis: difficultyAnalysis,
        isStructured: _isStructuredLearningMode,
        moduleIndex: _currentModuleIndex,
        totalModules: _totalModules,
        pagesPerModule: _pagesPerModule,
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('quiz_history')
          .doc(history.id)
          .set(history.toMap());

      _lastQuizId = history.id;

      if (mounted) {
        _loadProfileStats();
        _loadRecentSessions();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Quiz saved to history!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error saving quiz history: $e');
    }
  }

  void _submitQuiz() {
    int score = 0;
    for (var question in _quizQuestions) {
      if (question.isCorrect) score++;
    }
    setState(() {
      _quizScore = score;
      _showQuizResults = true;
    });
    _saveQuizToHistory(0, {
      'EASY': {'total': 0, 'correct': 0},
      'MEDIUM': {'total': 0, 'correct': 0},
      'HARD': {'total': 0, 'correct': 0},
    });
  }

  void _resetQuiz() {
    setState(() {
      for (var question in _quizQuestions) {
        question.selectedAnswerIndex = null;
      }
      _showQuizResults = false;
      _quizScore = 0;
    });
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} min ago';
    } else {
      return 'Just now';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final rawName =
        user?.displayName ?? user?.email?.split('@').first ?? 'Student';
    final displayName = rawName.isEmpty ? 'Student' : rawName;

    return Scaffold(
      backgroundColor: _bgGray,
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingState()
            : Column(
                children: [
                  _buildHeader(displayName),
                  Expanded(child: _buildBody()),
                ],
              ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBody() {
    switch (_bottomNavIndex) {
      case 0:
        return _buildEmptyState();
      case 1:
        return HistoryScreen(
          isTab: true,
          onTabChange: (index) => setState(() => _bottomNavIndex = index),
        );
      case 2:
        if (_extractedText.isEmpty) return _buildNoDocumentState();
        return _buildAiToolsTab();
      case 3:
        return _buildProfileTab();
      default:
        return _buildEmptyState();
    }
  }

  Widget _buildNoDocumentState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.upload_file_outlined,
              size: 72,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 24),
            const Text(
              'No Document Loaded',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Upload a PDF from the Home tab to use AI tools.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _textGray, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => setState(() => _bottomNavIndex = 0),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Go to Home'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLearningTab() => _buildChatTab();

  Widget _buildProfileTab() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'user@example.com';
    final rawName = user?.displayName ?? email.split('@').first;
    final name = (rawName.isEmpty ? 'Student' : rawName).toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _cardWhite,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: _green.withOpacity(0.1),
                  child: const Icon(Icons.person, size: 50, color: _green),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(email, style: TextStyle(color: _textGray, fontSize: 14)),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('$_totalQuizzes', 'Quizzes'),
                    _buildStatItem('${_avgScore.round()}%', 'Avg Score'),
                    _buildStatItem('$_streakDays', 'Day Streak'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardWhite,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STUDY CONSISTENCY',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _textGray,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                _buildActivityGraph(),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildProfileAction(Icons.settings_outlined, 'Settings', () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SettingsScreen(
                  currentGeminiKey: _userGeminiKey,
                  currentGroqKey: _userGroqKey,
                  onGeminiKeyChanged: (k) => setState(() => _userGeminiKey = k),
                  onGroqKeyChanged: (k) => setState(() => _userGroqKey = k),
                ),
              ),
            );
          }),
          _buildProfileAction(Icons.help_outline, 'Help Center', () {}),
          _buildProfileAction(Icons.logout, 'Log out', () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Log out?',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                content: const Text('Are you sure you want to log out?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Log out'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              try {
                await FirebaseAuth.instance.signOut();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Logout failed: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            }
          }, color: Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: _textDark,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: _textGray)),
      ],
    );
  }

  Widget _buildProfileAction(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: _cardWhite,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: color ?? _textDark, size: 22),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color ?? _textDark,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right,
                color: color?.withOpacity(0.5) ?? _textGray,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActivityGraph() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(
      Duration(days: today.weekday % 7 + (11 * 7)),
    );

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(12, (weekIndex) {
              final weekStart = startDate.add(Duration(days: weekIndex * 7));
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  children: List.generate(7, (dayIndex) {
                    final date = weekStart.add(Duration(days: dayIndex));
                    final count =
                        _activityMap[DateTime(
                          date.year,
                          date.month,
                          date.day,
                        )] ??
                        0;

                    Color cellColor;
                    if (date.isAfter(today)) {
                      cellColor = Colors.transparent;
                    } else if (count == 0) {
                      cellColor = const Color(0xFFEBEDF0);
                    } else if (count == 1) {
                      cellColor = _green.withOpacity(0.3);
                    } else if (count <= 3) {
                      cellColor = _green.withOpacity(0.6);
                    } else {
                      cellColor = _green;
                    }

                    return Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.symmetric(vertical: 1.5),
                      decoration: BoxDecoration(
                        color: cellColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'Less ',
              style: TextStyle(fontSize: 10, color: _textGray),
            ),
            _buildLegendBox(const Color(0xFFEBEDF0)),
            _buildLegendBox(_green.withOpacity(0.3)),
            _buildLegendBox(_green.withOpacity(0.6)),
            _buildLegendBox(_green),
            const Text(
              ' More',
              style: TextStyle(fontSize: 10, color: _textGray),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendBox(Color color) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_green),
            strokeWidth: 3,
          ),
          const SizedBox(height: 20),
          Text(
            'Extracting text from PDF...',
            style: TextStyle(color: _textGray, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String displayName) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_bottomNavIndex == 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          displayName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(fontSize: 12, color: _textGray),
                        ),
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _textDark,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.notifications_none_rounded,
                        color: _textDark,
                        size: 26,
                      ),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.logout_rounded,
                        color: Colors.red.shade400,
                        size: 22,
                      ),
                      tooltip: 'Logout',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: const Text(
                              'Log out?',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            content: const Text(
                              'Are you sure you want to log out?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Log out'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            await FirebaseAuth.instance.signOut();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Logout failed: $e'),
                                  backgroundColor: Colors.red,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 16),
          Text(
            _getHeaderTitle(),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _textDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  String _getHeaderTitle() {
    switch (_bottomNavIndex) {
      case 0:
        return "Study Buddy AI";
      case 1:
        return "Study History";
      case 2:
        return "AI Study Tools";
      case 3:
        return "My Profile";
      default:
        return "Study Buddy AI";
    }
  }

  Widget _buildAiToolsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isStructuredLearningMode && _totalModules > 0)
            _buildStructuredNavigationBar(),
          _buildAISectionHeader(),
          _buildToolGrid(),
          const SizedBox(height: 24),
          _buildToolOutput(),
        ],
      ),
    );
  }

  Widget _buildStructuredNavigationBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, size: 18),
            color: _currentModuleIndex > 0
                ? Colors.purple.shade700
                : Colors.grey,
            onPressed: _currentModuleIndex > 0
                ? () => _loadModule(_currentModuleIndex - 1)
                : null,
          ),
          Column(
            children: [
              Text(
                'Module ${_currentModuleIndex + 1} of $_totalModules',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.purple.shade700,
                ),
              ),
              Text(
                'Pages ${_currentModuleIndex * _pagesPerModule + 1} - ${(_currentModuleIndex * _pagesPerModule + _pagesPerModule).clamp(1, _allPdfPagesText.length)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.purple.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            color: _currentModuleIndex < _totalModules - 1
                ? Colors.purple.shade700
                : Colors.grey,
            onPressed: _currentModuleIndex < _totalModules - 1
                ? () => _loadModule(_currentModuleIndex + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildAISectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Text(
        'Unlock the power of your documents',
        style: TextStyle(fontSize: 14, color: _textGray),
      ),
    );
  }

  Widget _buildToolGrid() {
    final cards = [
      _ToolCardData(
        'Smart\nSummary',
        'Analytical breakdown',
        Icons.summarize_rounded,
        const Color(0xFF6366F1),
        0,
        _generateSummary,
      ),
      _ToolCardData(
        'Smart\nQuiz',
        'Test your knowledge',
        Icons.quiz_rounded,
        const Color(0xFFF59E0B),
        1,
        _showQuizConfigSheet,
      ),
      _ToolCardData(
        'Smart\nCards',
        'Flashcard system',
        Icons.bolt_rounded,
        const Color(0xFF8B5CF6),
        2,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FlashcardScreen(
                documentText: _extractedText,
                documentName: _selectedFileName,
                activeGeminiKey: _activeGeminiKey,
                activeGroqKey: _activeGroqKey,
              ),
            ),
          );
        },
      ),
      _ToolCardData(
        'Smart\nChat',
        'Q&A Assistant',
        Icons.chat_bubble_rounded,
        const Color(0xFF10B981),
        3,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                extractedText: _extractedText,
                summary: _summary,
                documentName: _selectedFileName,
                activeGeminiKey: _activeGeminiKey,
                activeGroqKey: _activeGroqKey,
              ),
            ),
          );
        },
      ),
      _ToolCardData(
        'Mind\nMap',
        'Visual concept map',
        Icons.hub_rounded,
        const Color(0xFFEC4899),
        4,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VisualToolsScreen(
                documentText: _extractedText,
                documentName: _selectedFileName,
                activeGeminiKey: _activeGeminiKey,
                activeGroqKey: _activeGroqKey,
                initialTab: 0,
              ),
            ),
          );
        },
      ),
      _ToolCardData(
        'Flow\nChart',
        'Step-by-step flow',
        Icons.account_tree_rounded,
        const Color(0xFF0EA5E9),
        5,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VisualToolsScreen(
                documentText: _extractedText,
                documentName: _selectedFileName,
                activeGeminiKey: _activeGeminiKey,
                activeGroqKey: _activeGroqKey,
                initialTab: 1,
              ),
            ),
          );
        },
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = (constraints.maxWidth - 16) / 2;
          // Card height scales with width but has a min/max clamp for all screen sizes
          final cardHeight = (cardWidth * 0.72).clamp(100.0, 160.0);
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: cards.map((card) {
              return SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _buildToolCard(
                  card.title,
                  card.subtitle,
                  card.icon,
                  card.color,
                  card.index,
                  card.onTap,
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildToolCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    int index,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap, // ✅ directly call action — no _currentTabIndex mutation
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color.withOpacity(0.9),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withOpacity(0.6),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolOutput() {
    if (_isGeneratingSummary || _isGeneratingQuiz) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade200,
          highlightColor: Colors.white,
          child: Column(
            children: List.generate(
              3,
              (i) => Container(
                height: 100,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_summary.isNotEmpty) {
      return _buildSummaryTab();
    }

    // Default idle state — just show a soft prompt
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            const Text(
              "Tap a tool above to get started",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildUploadCard(),
          const SizedBox(height: 16),
          _buildActionButtons(),
          const SizedBox(height: 24),
          _buildRecentSessions(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF0FAF0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _green.withOpacity(0.5),
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(80, 80),
                  painter: _DashedBorderPainter(color: _green, radius: 16),
                ),
                Icon(Icons.upload_file_outlined, color: _green, size: 36),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pick your Study Material',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload a PDF to start learning with AI.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _textGray, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showModePicker,
              icon: const Icon(Icons.upload_file_rounded, size: 20),
              label: const Text(
                'Select PDF',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _extractedText.isNotEmpty && !_isGeneratingSummary
                    ? _generateSummary
                    : () => _pickAndReadPDF(onComplete: _generateSummary),
                child: Container(
                  height: 110,
                  decoration: BoxDecoration(
                    color: _green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isGeneratingSummary)
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 32,
                        ),
                      const SizedBox(height: 10),
                      const Text(
                        'Summarize',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: GestureDetector(
                onTap: _extractedText.isNotEmpty && !_isGeneratingQuiz
                    ? _showQuizConfigSheet
                    : () => _pickAndReadPDF(onComplete: _showQuizConfigSheet),
                child: Container(
                  height: 110,
                  decoration: BoxDecoration(
                    color: _darkNavy,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isGeneratingQuiz)
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      else
                        const Icon(
                          Icons.quiz_outlined,
                          color: Colors.white,
                          size: 32,
                        ),
                      const SizedBox(height: 10),
                      const Text(
                        'Generate\nQuiz',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: _extractedText.isNotEmpty
              ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FlashcardScreen(
                      documentText: _extractedText,
                      documentName: _selectedFileName,
                      activeGeminiKey: _activeGeminiKey,
                      activeGroqKey: _activeGroqKey,
                    ),
                  ),
                )
              : () => _pickAndReadPDF(
                  onComplete: () async {
                    if (_extractedText.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FlashcardScreen(
                            documentText: _extractedText,
                            documentName: _selectedFileName,
                            activeGeminiKey: _activeGeminiKey,
                            activeGroqKey: _activeGroqKey,
                          ),
                        ),
                      );
                    }
                  },
                ),
          child: Container(
            width: double.infinity,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.orange.shade400,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.shade400.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_stories_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Study Flashcards',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white70,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSessions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT SESSIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _textGray,
                letterSpacing: 1.2,
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              ),
              child: const Text(
                'View All',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _green,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _recentSessions.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: _cardWhite,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.history,
                      size: 40,
                      color: _textGray.withOpacity(0.5),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No recent sessions yet',
                      style: TextStyle(color: _textGray, fontSize: 14),
                    ),
                  ],
                ),
              )
            : Column(
                children: _recentSessions.asMap().entries.map((entry) {
                  final session = entry.value;
                  final icons = [
                    Icons.menu_book_rounded,
                    Icons.science_rounded,
                    Icons.calculate_rounded,
                    Icons.history_edu_rounded,
                    Icons.psychology_rounded,
                  ];
                  final colors = [
                    Colors.blue.shade100,
                    Colors.orange.shade100,
                    Colors.purple.shade100,
                    Colors.teal.shade100,
                    Colors.pink.shade100,
                  ];
                  final iconColors = [
                    Colors.blue.shade600,
                    Colors.orange.shade600,
                    Colors.purple.shade600,
                    Colors.teal.shade600,
                    Colors.pink.shade600,
                  ];
                  final idx = entry.key % icons.length;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _cardWhite,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors[idx],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            icons[idx],
                            color: iconColors[idx],
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session['title'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${_formatTimeAgo(session['date'])} • ${session['total']} Questions',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _textGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: _textGray,
                          size: 22,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  Widget _buildDocumentView() {
    return Column(
      children: [
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSummaryTab(),
              _buildQuizTabView(),
              _buildChatTab(),
              _buildFlashcardsTab(),
            ],
          ),
        ),
        if (_currentTabIndex == 3) _buildChatInputBar(),
      ],
    );
  }

  Widget _buildFlashcardsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: const BoxDecoration(
              color: Color(0xFFF3E8FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              size: 64,
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Master your Document',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Generate interactive flashcards from your PDF\nto memorize key concepts faster.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textGray, height: 1.5),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FlashcardScreen(
                    documentText: _extractedText,
                    documentName: _selectedFileName,
                    activeGeminiKey: _activeGeminiKey,
                    activeGroqKey: _activeGroqKey,
                  ),
                ),
              ),
              icon: const Icon(Icons.bolt_rounded),
              label: const Text('GENERATE FLASHCARDS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_summary.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Tap "Summarize" above to generate a premium analysis',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textGray),
              ),
            ],
          ),
        ),
      );
    }

    String executiveSummary = "";
    String keyThemes = "";
    String analysis = "";
    String practicalApps = "";
    String studyGuide = "";

    try {
      // Robust extraction: find each tag by indexOf, then substring between them.
      // Handles \r\n line endings, extra whitespace, and ** wrapping by the AI.
      // Strip any ** wrapping the AI might add around headers first.
      final cleaned = _summary
          .replaceAll(RegExp(r'\*\*\['), '[')
          .replaceAll(RegExp(r'\]\*\*'), ']');

      int _tagEnd(String tag) {
        final idx = cleaned.indexOf('[$tag]');
        return idx == -1 ? -1 : idx + '[$tag]'.length;
      }

      String _extract(String tag, String? nextTag) {
        final start = _tagEnd(tag);
        if (start == -1) return '';
        final end = nextTag != null ? cleaned.indexOf('[$nextTag]', start) : -1;
        final raw = end == -1
            ? cleaned.substring(start)
            : cleaned.substring(start, end);
        return raw.trim();
      }

      executiveSummary = _extract(
        'EXECUTIVE_SUMMARY',
        'KEY_THEMES_AND_CONCEPTS',
      );
      keyThemes = _extract('KEY_THEMES_AND_CONCEPTS', 'DETAILED_ANALYSIS');
      analysis = _extract('DETAILED_ANALYSIS', 'PRACTICAL_APPLICATIONS');
      practicalApps = _extract(
        'PRACTICAL_APPLICATIONS',
        'STUDY_GUIDE_AND_REFLECTIONS',
      );
      studyGuide = _extract(
        'STUDY_GUIDE_AND_REFLECTIONS',
        null,
      ); // last — no next tag
    } catch (e) {
      executiveSummary = _summary;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummarySection(
            'Executive Summary',
            executiveSummary,
            Icons.summarize_rounded,
            _green.withOpacity(0.1),
            _green,
          ),
          const SizedBox(height: 16),
          if (keyThemes.isNotEmpty) ...[
            _buildSummarySection(
              'Key Themes & Concepts',
              keyThemes,
              Icons.auto_awesome_mosaic_rounded,
              const Color(0xFF3B82F6).withOpacity(0.1),
              const Color(0xFF3B82F6),
            ),
            const SizedBox(height: 16),
          ],
          if (analysis.isNotEmpty) ...[
            _buildSummarySection(
              'Detailed Analysis',
              analysis,
              Icons.analytics_outlined,
              const Color(0xFF8B5CF6).withOpacity(0.1),
              const Color(0xFF8B5CF6),
            ),
            const SizedBox(height: 16),
          ],
          if (practicalApps.isNotEmpty) ...[
            _buildSummarySection(
              'Practical Applications',
              practicalApps,
              Icons.lightbulb_outline_rounded,
              const Color(0xFFF59E0B).withOpacity(0.1),
              const Color(0xFFF59E0B),
            ),
            const SizedBox(height: 16),
          ],
          if (studyGuide.isNotEmpty) ...[
            _buildSummarySection(
              'Study Guide & Reflections',
              studyGuide,
              Icons.menu_book_rounded,
              const Color(0xFFEC4899).withOpacity(0.1),
              const Color(0xFFEC4899),
            ),
            const SizedBox(height: 24),
          ],
          Row(
            children: [
              Expanded(
                child: _buildSummaryActionButton(
                  'Copy Analysis',
                  Icons.copy_rounded,
                  () {
                    Clipboard.setData(ClipboardData(text: _summary));
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied to clipboard')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryActionButton(
                  'Regenerate',
                  Icons.refresh_rounded,
                  () {
                    HapticFeedback.mediumImpact();
                    _generateSummary();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSummarySection(
    String title,
    String content,
    IconData icon,
    Color bgColor,
    Color accentColor,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildMarkdownText(content, _textDark.withOpacity(0.85)),
        ],
      ),
    );
  }

  /// Renders a subset of markdown without requiring any external package:
  /// **bold**, *italic*, bullet lists (- / *), numbered lists, and plain paragraphs.
  Widget _buildMarkdownText(String raw, Color textColor) {
    final lines = raw.split('\n');
    final widgets = <Widget>[];
    bool inList = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        if (inList) inList = false;
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // Bullet list item: starts with - or *
      final bulletMatch = RegExp(r'^[-*]\s+(.+)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        inList = true;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: textColor.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _inlineMarkdown(bulletMatch.group(1)!, textColor),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Numbered list: starts with "1." "2." etc.
      final numberedMatch = RegExp(r'^(\d+)\.\s+(.+)$').firstMatch(trimmed);
      if (numberedMatch != null) {
        inList = true;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${numberedMatch.group(1)}.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _inlineMarkdown(numberedMatch.group(2)!, textColor),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      // Plain paragraph (may contain **bold** / *italic*)
      if (inList) {
        widgets.add(const SizedBox(height: 4));
        inList = false;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _inlineMarkdown(trimmed, textColor),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  /// Renders **bold** and *italic* inline markdown using RichText.
  Widget _inlineMarkdown(String text, Color textColor) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|([^*]+)');
    for (final m in pattern.allMatches(text)) {
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: textColor,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: TextStyle(
              fontStyle: FontStyle.italic,
              color: textColor,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: TextStyle(color: textColor, fontSize: 14, height: 1.6),
          ),
        );
      }
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _buildSummaryActionButton(
    String label,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: _textGray),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textDark.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizTabView() {
    return _quizQuestions.isEmpty
        ? Center(
            child: Text(
              'Tap "Quiz" above to generate a quiz',
              style: TextStyle(color: _textGray),
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: _buildQuizTab(),
          );
  }

  Widget _buildChatInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: _cardWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _bgGray,
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                controller: _chatController,
                decoration: InputDecoration(
                  hintText: _extractedText.isEmpty
                      ? 'Upload a PDF first...'
                      : 'Ask your Study Buddy anything...',
                  hintStyle: TextStyle(color: _textGray, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) =>
                    _extractedText.isNotEmpty ? _sendMessage() : null,
                enabled: _extractedText.isNotEmpty && !_isSendingMessage,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _extractedText.isNotEmpty && !_isSendingMessage
                ? _sendMessage
                : null,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isSendingMessage || _extractedText.isEmpty
                    ? Colors.grey.shade300
                    : _teal,
                shape: BoxShape.circle,
              ),
              child: _isSendingMessage
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : const Icon(
                      Icons.arrow_upward_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            itemCount: _chatMessages.length,
            itemBuilder: (context, index) {
              final message = _chatMessages[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: message.isUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  children: [
                    if (!message.isUser) ...[
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Color(0xFF7B2FBE),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: message.isUser ? _darkNavy : _cardWhite,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomLeft: message.isUser
                                ? const Radius.circular(16)
                                : const Radius.circular(4),
                            bottomRight: message.isUser
                                ? const Radius.circular(4)
                                : const Radius.circular(16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          message.text,
                          style: TextStyle(
                            color: message.isUser ? Colors.white : _textDark,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (message.isUser) ...[
                      const SizedBox(width: 10),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade500,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.library_books_rounded, 'label': 'Library'},
      {'icon': Icons.auto_fix_high_rounded, 'label': 'AI Tools'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: _cardWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final isSelected = _bottomNavIndex == i;
          return GestureDetector(
            onTap: () {
              setState(() => _bottomNavIndex = i);
              if (i == 0) _loadRecentSessions();
              if (i == 3) _loadProfileStats();
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 70,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    items[i]['icon'] as IconData,
                    color: isSelected ? _green : _textGray,
                    size: 26,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i]['label'] as String,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected ? _green : _textGray,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildQuizTab() {
    return Column(
      children: [
        if (_showQuizResults)
          Column(
            children: [
              Center(
                child: Container(
                  width: 200,
                  height: 200,
                  padding: const EdgeInsets.all(20),
                  child: Stack(
                    children: [
                      Center(
                        child: SizedBox(
                          width: 160,
                          height: 160,
                          child: CircularProgressIndicator(
                            value: _quizScore / _quizQuestions.length,
                            strokeWidth: 12,
                            backgroundColor: Colors.grey.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _quizScore / _quizQuestions.length >= 0.7
                                  ? _green
                                  : Colors.orange,
                            ),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${((_quizScore / _quizQuestions.length) * 100).round()}',
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                color: _textDark,
                              ),
                            ),
                            Text(
                              'SCORE',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _textGray,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _quizScore / _quizQuestions.length >= 0.7
                    ? 'Excellent Work!'
                    : 'Keep Practicing',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _quizScore / _quizQuestions.length >= 0.7
                      ? _green
                      : Colors.red.shade600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Review the material and try again.',
                style: TextStyle(color: _textGray, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildResultPill(
                    Icons.timer_outlined,
                    '12m 45s',
                    Colors.green,
                  ),
                  const SizedBox(width: 12),
                  _buildResultPill(
                    Icons.check_circle_outline_rounded,
                    '${((_quizScore / _quizQuestions.length) * 100).round()}% Accuracy',
                    Colors.green,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1FDF4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _green.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: _green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
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
                            "You've shown good progress! Focus on ${(_quizQuestions.isNotEmpty ? _quizQuestions[0].question.split(' ').take(3).join(' ') : 'these topics')} in your next session.",
                            style: TextStyle(
                              fontSize: 12,
                              color: _textDark.withOpacity(0.7),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Difficulty Analysis',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                        ),
                      ),
                      Text(
                        'GLOBAL AVG: 72%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textGray.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildDifficultyRow('Foundational', 1.0, Colors.green),
                  const SizedBox(height: 16),
                  _buildDifficultyRow('Intermediate', 0.85, Colors.orange),
                  const SizedBox(height: 16),
                  _buildDifficultyRow('Advanced', 0.70, Colors.red),
                ],
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => setState(() => _showQuizResults = false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Review Detailed Answers',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _resetQuiz,
                child: Text(
                  'Retake Quiz',
                  style: TextStyle(
                    color: _textGray,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        if (!_showQuizResults)
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: ListView.builder(
              padding: const EdgeInsets.all(4),
              itemCount: _quizQuestions.length,
              itemBuilder: (context, index) {
                final question = _quizQuestions[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: _cardWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _showQuizResults
                          ? question.isCorrect
                                ? Colors.green.shade200
                                : Colors.red.shade200
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                question.question,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ...List.generate(question.options.length, (optIndex) {
                          final isSelected =
                              question.selectedAnswerIndex == optIndex;
                          final isCorrect =
                              question.correctAnswerIndex == optIndex;

                          Color? backgroundColor;
                          Color? textColor;
                          IconData? trailingIcon;

                          if (_showQuizResults) {
                            if (isCorrect) {
                              backgroundColor = Colors.green.shade50;
                              textColor = Colors.green.shade700;
                              trailingIcon = Icons.check_circle;
                            } else if (isSelected && !isCorrect) {
                              backgroundColor = Colors.red.shade50;
                              textColor = Colors.red.shade700;
                              trailingIcon = Icons.cancel;
                            }
                          } else if (isSelected) {
                            backgroundColor = Colors.blue.shade50;
                            textColor = Colors.blue.shade700;
                          }

                          return GestureDetector(
                            onTap: _showQuizResults
                                ? null
                                : () => _selectAnswer(index, optIndex),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: backgroundColor ?? Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? Colors.blue.shade300
                                      : Colors.grey.shade300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.blue
                                            : Colors.grey.shade400,
                                        width: 2,
                                      ),
                                      color: isSelected
                                          ? Colors.blue
                                          : Colors.transparent,
                                    ),
                                    child: isSelected && !_showQuizResults
                                        ? const Center(
                                            child: Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      question.options[optIndex],
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: textColor ?? _textDark,
                                      ),
                                    ),
                                  ),
                                  if (trailingIcon != null)
                                    Icon(
                                      trailingIcon,
                                      color: textColor,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                        if (_showQuizResults && question.explanation.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    question.explanation,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade800,
                                      height: 1.4,
                                    ),
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
            ),
          ),
        if (!_showQuizResults && _quizQuestions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _submitQuiz,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Submit Quiz',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResultPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultyRow(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textDark,
              ),
            ),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: value,
          backgroundColor: Colors.grey.shade100,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }

  // ── Bottom Sheet helpers ───────────────────────────────────────────────────

  void _showModePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose Study Mode',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Select how you want to study your PDF',
                style: TextStyle(fontSize: 13, color: _textGray),
              ),
            ),
            const SizedBox(height: 20),

            // Standard Mode Card
            _buildModeCard(
              icon: Icons.bolt_rounded,
              iconColor: _green,
              iconBg: const Color(0xFFEBFBDF),
              title: 'Standard Mode',
              description:
                  'Load the entire PDF at once. Best for short documents, quick revision, or when you want a full overview — summary, quiz, flashcards and chat all at once.',
              badge: 'Recommended',
              badgeColor: _green,
              onTap: () {
                Navigator.pop(ctx);
                _pickAndReadPDF(isStructured: false);
              },
            ),
            const SizedBox(height: 14),

            // Structured Mode Card
            _buildModeCard(
              icon: Icons.view_module_rounded,
              iconColor: Colors.purple.shade500,
              iconBg: Colors.purple.shade50,
              title: 'Structured Mode',
              description:
                  'Split the PDF into modules and study chapter by chapter. Ideal for large textbooks or when you want to track progress across multiple sessions.',
              badge: 'For large PDFs',
              badgeColor: Colors.purple.shade400,
              onTap: () {
                Navigator.pop(ctx);
                _pickAndReadPDF(isStructured: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String description,
    required String badge,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade200, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 16),
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _textDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: _textGray,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStructuredConfigSheet() async {
    int selectedPages = 10;
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Icon(
                    Icons.view_module_rounded,
                    color: Colors.purple.shade400,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Structured Learning',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Pages per Module',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Divide your document into bite-sized segments (1-50 pages).',
                  style: TextStyle(fontSize: 13, color: _textGray),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildCountButton(
                    setSheetState,
                    selectedPages,
                    (val) => setSheetState(() => selectedPages = val),
                    maxVal: 50,
                  ),
                  Text(
                    '$selectedPages',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: Colors.purple.shade400,
                    ),
                  ),
                  _buildCountButton(
                    setSheetState,
                    selectedPages,
                    (val) => setSheetState(() => selectedPages = val),
                    isAdd: true,
                    maxVal: 50,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.purple.shade400,
                  inactiveTrackColor: Colors.purple.shade100,
                  thumbColor: Colors.purple.shade400,
                  overlayColor: Colors.purple.withOpacity(0.2),
                  valueIndicatorColor: _textDark,
                  trackHeight: 6,
                ),
                child: Slider(
                  value: selectedPages.toDouble(),
                  min: 1,
                  max: 50,
                  divisions: 49,
                  label: selectedPages.toString(),
                  onChanged: (value) =>
                      setSheetState(() => selectedPages = value.round()),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _pagesPerModule = selectedPages;
                      _bottomNavIndex = 2;
                    });
                    _loadModule(0);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade400,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Start Learning',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showQuizConfigSheet() async {
    int selectedCount = 5;
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.quiz_rounded, color: _green, size: 28),
                  SizedBox(width: 12),
                  Text(
                    'Quiz Settings',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Number of Questions',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Choose how many questions you want to solve (1-15)',
                  style: TextStyle(fontSize: 13, color: _textGray),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildCountButton(
                    setSheetState,
                    selectedCount,
                    (val) => setSheetState(() => selectedCount = val),
                  ),
                  Text(
                    '$selectedCount',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.w900,
                      color: _green,
                    ),
                  ),
                  _buildCountButton(
                    setSheetState,
                    selectedCount,
                    (val) => setSheetState(() => selectedCount = val),
                    isAdd: true,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _green,
                  inactiveTrackColor: _green.withOpacity(0.1),
                  thumbColor: _green,
                  overlayColor: _green.withOpacity(0.2),
                  valueIndicatorColor: _textDark,
                  trackHeight: 6,
                ),
                child: Slider(
                  value: selectedCount.toDouble(),
                  min: 1,
                  max: 15,
                  divisions: 14,
                  label: selectedCount.toString(),
                  onChanged: (val) =>
                      setSheetState(() => selectedCount = val.toInt()),
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _generateQuiz(count: selectedCount);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Start Generating',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountButton(
    void Function(void Function()) setSheetState,
    int current,
    void Function(int) onChanged, {
    bool isAdd = false,
    int maxVal = 15,
  }) {
    bool disabled = isAdd ? current >= maxVal : current <= 1;
    return GestureDetector(
      onTap: disabled
          ? null
          : () => onChanged(isAdd ? current + 1 : current - 1),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: disabled ? Colors.grey.shade100 : _green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(
          isAdd ? Icons.add_rounded : Icons.remove_rounded,
          color: disabled ? Colors.grey.shade300 : _green,
          size: 28,
        ),
      ),
    );
  }
}

// ── Tool card data helper ──────────────────────────────────────────────────────
class _ToolCardData {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int index;
  final VoidCallback onTap;

  const _ToolCardData(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.index,
    this.onTap,
  );
}

// ── Custom painter for dashed border ──────────────────────────────────────────
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
          Radius.circular(radius),
        ),
      );

    const dashWidth = 6.0;
    const dashSpace = 4.0;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final start = distance;
        final end = (distance + dashWidth).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(start, end), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
