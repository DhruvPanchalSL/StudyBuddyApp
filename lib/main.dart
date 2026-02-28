import 'dart:convert';
import 'dart:io';

import 'package:StudyBuddy/quiz_details_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'auth_screen.dart';
import 'features/flashcards/flashcard_screen.dart';
import 'history_screen.dart';
import 'models/chat_message.dart';
import 'models/quiz_history.dart';
import 'models/quiz_question.dart';
import 'quiz_screen.dart';

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
      home: StreamBuilder(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            User? user = snapshot.data;
            if (user == null) {
              return const AuthScreen();
            }
            return const HomeScreen();
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        },
      ),
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

  List<QuizQuestion> _quizQuestions = [];
  bool _isGeneratingQuiz = false;
  bool _showQuizResults = false;
  int _quizScore = 0;
  String? _lastQuizId;

  List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  bool _isSendingMessage = false;
  final ScrollController _chatScrollController = ScrollController();

  bool _isLoading = false;
  bool _isGeneratingSummary = false;

  late TabController _tabController;
  int _currentTabIndex = 0;
  int _bottomNavIndex = 0;

  List<Map<String, dynamic>> _recentSessions = [];

  final String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  // Color palette matching design
  static const Color _green = Color(0xFF7ED957);
  static const Color _darkNavy = Color(0xFF1A1A2E);
  static const Color _teal = Color(0xFF00C2B2);
  static const Color _bgGray = Color(0xFFF5F5F7);
  static const Color _cardWhite = Colors.white;
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);

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

    _loadRecentSessions();
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
          return {
            'id': doc.id,
            'title': data['pdfName'] ?? 'Untitled',
            'date': (data['date'] as Timestamp).toDate(),
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

  Future<void> _pickAndReadPDF() async {
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
        });

        String filePath = result.files.first.path!;
        String text = await _extractTextFromPDF(filePath);

        setState(() {
          _extractedText = text;
          _isLoading = false;
        });
      } else {
        setState(() {
          _selectedFileName = "No file selected";
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _extractedText = "Error reading PDF: $e";
      });
      debugPrint("Error: $e");
    }
  }

  Future<String> _extractTextFromPDF(String filePath) async {
    try {
      File file = File(filePath);
      List<int> bytes = await file.readAsBytes();

      PdfDocument document = PdfDocument(inputBytes: bytes);
      PdfTextExtractor extractor = PdfTextExtractor(document);

      StringBuffer allText = StringBuffer();

      for (int i = 0; i < document.pages.count; i++) {
        String pageText = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );
        allText.writeln("--- Page ${i + 1} ---");
        allText.writeln(pageText);
        allText.writeln("");
      }

      document.dispose();
      return allText.toString();
    } catch (e) {
      return "Could not extract text. This PDF might be scanned or image-based.\nError: $e";
    }
  }

  Future<void> _generateSummary() async {
    if (_extractedText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please extract text from a PDF first')),
      );
      return;
    }

    setState(() {
      _isGeneratingSummary = true;
    });

    try {
      String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty)
        throw Exception('API key not found. Check your .env file');

      final url = Uri.parse('$_geminiEndpoint?key=$apiKey');

      String textToSummarize = _extractedText;
      if (textToSummarize.length > 30000) {
        textToSummarize =
            textToSummarize.substring(0, 30000) +
            "\n\n[Note: Text truncated due to length...]";
      }

      String prompt =
          '''Please provide a clear and concise summary of the following text. 
Focus on the main points and key ideas:\n\n$textToSummarize\n\nSummary:''';

      final requestBody = {
        "contents": [
          {
            "parts": [
              {"text": prompt},
            ],
          },
        ],
        "generationConfig": {"temperature": 0.7, "maxOutputTokens": 2048},
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final summary =
            jsonResponse['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          _summary = summary;
          _isGeneratingSummary = false;
        });

        _tabController.animateTo(1);

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
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isGeneratingSummary = false;
        _summary = "Error generating summary: $e";
      });
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

  Future<void> _generateQuiz() async {
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
      String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty)
        throw Exception('API key not found. Check your .env file');

      final url = Uri.parse('$_geminiEndpoint?key=$apiKey');

      String textForQuiz = _extractedText;
      if (textForQuiz.length > 25000) {
        textForQuiz =
            textForQuiz.substring(0, 25000) +
            "\n\n[Note: Text truncated for quiz generation...]";
      }

      String prompt =
          '''Based on the following text, generate 5 multiple choice quiz questions.
Each question should have 4 options (A, B, C, D) with exactly one correct answer.
Include a brief explanation for why the correct answer is right.

Return the response in this EXACT JSON format:
{
  "questions": [
    {
      "question": "Question text here?",
      "options": ["Option A", "Option B", "Option C", "Option D"],
      "correctAnswerIndex": 0,
      "explanation": "Explanation why this is correct"
    }
  ]
}

IMPORTANT: 
- correctAnswerIndex must be 0, 1, 2, or 3
- Make questions challenging but fair
- Base questions strictly on the provided text

TEXT:
$textForQuiz

JSON RESPONSE:''';

      final requestBody = {
        "contents": [
          {
            "parts": [
              {"text": prompt},
            ],
          },
        ],
        "generationConfig": {"temperature": 0.7, "maxOutputTokens": 4096},
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        String responseText =
            jsonResponse['candidates'][0]['content']['parts'][0]['text'];

        RegExp jsonRegex = RegExp(r'\{[\s\S]*\}');
        Match? match = jsonRegex.firstMatch(responseText);

        if (match != null) {
          String jsonStr = match.group(0)!;
          final quizData = jsonDecode(jsonStr);

          if (quizData['questions'] != null &&
              quizData['questions'].isNotEmpty) {
            List<QuizQuestion> questions = [];
            for (var q in quizData['questions']) {
              questions.add(QuizQuestion.fromJson(q));
            }

            setState(() {
              _quizQuestions = questions;
              _isGeneratingQuiz = false;
            });

            // Navigate to the dedicated full-screen QuizScreen
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QuizScreen(
                    questions: questions,
                    pdfName: _selectedFileName,
                    chapterTitle: 'Document Review',
                    onQuizComplete: (score, completedQuestions) {
                      setState(() {
                        _quizScore = score;
                        _showQuizResults = true;
                      });
                      _saveQuizToHistory();
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
      } else if (response.statusCode == 429) {
        setState(() => _isGeneratingQuiz = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '⏳ Rate limit reached. Please wait a minute and try again.',
            ),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _isGeneratingQuiz = false);
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
      String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) throw Exception('API key not found');

      final url = Uri.parse('$_geminiEndpoint?key=$apiKey');

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

      if (context.length > 20000) context = context.substring(0, 20000) + "...";

      String prompt =
          '''You are a helpful study assistant. Answer the user's question based ONLY on the following context.
If the answer cannot be found in the context, say "I don't have enough information about that in the document."

CONTEXT:
$context

USER QUESTION: $userMessage

ANSWER (be concise but helpful):''';

      final requestBody = {
        "contents": [
          {
            "parts": [
              {"text": prompt},
            ],
          },
        ],
        "generationConfig": {"temperature": 0.7, "maxOutputTokens": 1024},
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        String aiResponse =
            jsonResponse['candidates'][0]['content']['parts'][0]['text'];
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
      } else if (response.statusCode == 429) {
        setState(() {
          _chatMessages.add(
            ChatMessage(
              text:
                  "⏳ Rate limit reached. Please wait a minute before sending more messages.",
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isSendingMessage = false;
        });
      } else {
        throw Exception('API Error: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _chatMessages.add(
          ChatMessage(
            text:
                "Sorry, I encountered an error: ${e.toString().substring(0, 100)}",
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

  Future<void> _saveQuizToHistory() async {
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
      );

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('quiz_history')
          .doc(history.id)
          .set(history.toMap());

      _lastQuizId = history.id;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Quiz saved to history!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      _loadRecentSessions();
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
    _saveQuizToHistory();
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

  void _clearAll() {
    setState(() {
      _selectedFileName = "No file selected";
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
    });
    _tabController.animateTo(0);
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@').first ?? 'Alex Johnson';
    final formattedName = userName[0].toUpperCase() + userName.substring(1);
    final displayName = formattedName.split('.').first;

    return Scaffold(
      backgroundColor: _bgGray,
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingState()
            : Column(
                children: [
                  _buildHeader(displayName),
                  Expanded(
                    child: _extractedText.isEmpty
                        ? _buildEmptyState()
                        : _buildDocumentView(),
                  ),
                ],
              ),
      ),
      bottomNavigationBar: _buildBottomNav(),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Avatar
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
                    onPressed: () async =>
                        await FirebaseAuth.instance.signOut(),
                    tooltip: 'Logout',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Study Buddy AI',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _textDark,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          // Pill Tab Bar
          _buildPillTabBar(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildPillTabBar() {
    // Show tabs relevant to state
    final tabs = _extractedText.isEmpty
        ? ['Text', 'Summary', 'Quiz']
        : ['Text', 'Summary', 'Quiz', 'Chat'];

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFFE8E8ED),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isSelected = _currentTabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (_extractedText.isNotEmpty) {
                  _tabController.animateTo(i);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected ? _textDark : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      i == 0
                          ? Icons.text_snippet_outlined
                          : i == 1
                          ? Icons.auto_awesome_outlined
                          : i == 2
                          ? Icons.quiz_outlined
                          : Icons.chat_outlined,
                      size: 14,
                      color: isSelected ? Colors.white : _textGray,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected ? Colors.white : _textGray,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Upload Card
          _buildUploadCard(),
          const SizedBox(height: 16),
          // Action Buttons
          _buildActionButtons(),
          const SizedBox(height: 24),
          // Recent Sessions
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
          // Dashed border icon container
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
            'Select a PDF document or paste a\nlink to start learning with AI\nassistance.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: _textGray, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 140,
            height: 46,
            child: ElevatedButton(
              onPressed: _pickAndReadPDF,
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Pick PDF',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
        // Row: Summarize + Generate Quiz
        Row(
          children: [
            // Summarize - Green
            Expanded(
              child: GestureDetector(
                onTap: _extractedText.isNotEmpty && !_isGeneratingSummary
                    ? _generateSummary
                    : _pickAndReadPDF,
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
            // Generate Quiz - Dark Navy
            Expanded(
              child: GestureDetector(
                onTap: _extractedText.isNotEmpty && !_isGeneratingQuiz
                    ? _generateQuiz
                    : _pickAndReadPDF,
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
        // Study Flashcards - Light gray
        GestureDetector(
          onTap: _extractedText.isNotEmpty
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FlashcardScreen(
                        documentText: _extractedText,
                        documentName: _selectedFileName,
                      ),
                    ),
                  );
                }
              : null,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFEDEDED),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.auto_stories_outlined,
                  color: _textDark.withOpacity(0.7),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Text(
                  'Study Flashcards',
                  style: TextStyle(
                    color: _textDark.withOpacity(0.85),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
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
                MaterialPageRoute(builder: (context) => const HistoryScreen()),
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
                  final percentage = session['total'] > 0
                      ? ((session['score'] / session['total']) * 100).round()
                      : 0;

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
                                '${_formatTimeAgo(session['date'])} • ${session['total']} Flashcards',
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
        // Action chips when doc loaded
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildLoadedActionButtons(),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildTextTab(),
              _buildSummaryTab(),
              _buildQuizTabView(),
              _buildChatTab(),
            ],
          ),
        ),
        _buildChatInputBar(),
      ],
    );
  }

  Widget _buildLoadedActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildSmallActionChip(
            Icons.summarize_outlined,
            'Summary',
            _green,
            _isGeneratingSummary ? null : _generateSummary,
            _isGeneratingSummary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSmallActionChip(
            Icons.quiz_outlined,
            'Quiz',
            _darkNavy,
            _isGeneratingQuiz ? null : _generateQuiz,
            _isGeneratingQuiz,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildSmallActionChip(
            Icons.auto_stories_outlined,
            'Cards',
            Colors.purple,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FlashcardScreen(
                    documentText: _extractedText,
                    documentName: _selectedFileName,
                  ),
                ),
              );
            },
            false,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallActionChip(
    IconData icon,
    String label,
    Color color,
    VoidCallback? onTap,
    bool loading,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardWhite,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _extractedText,
          style: const TextStyle(fontSize: 14, height: 1.6),
        ),
      ),
    );
  }

  Widget _buildSummaryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardWhite,
          borderRadius: BorderRadius.circular(16),
        ),
        child: _summary.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Text(
                    'Tap "Summary" above to generate a summary',
                    style: TextStyle(color: _textGray),
                  ),
                ),
              )
            : Text(_summary, style: const TextStyle(fontSize: 14, height: 1.6)),
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
              if (i == 0) {
                // Already on home
              } else if (i == 1) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HistoryScreen(),
                  ),
                );
              }
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
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              children: [
                Text(
                  'Quiz Complete!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You scored $_quizScore/${_quizQuestions.length}',
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _quizScore / _quizQuestions.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Colors.orange,
                  ),
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _resetQuiz,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _lastQuizId != null
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => QuizDetailsScreen(
                                    history: QuizHistory(
                                      id: _lastQuizId!,
                                      userId:
                                          FirebaseAuth
                                              .instance
                                              .currentUser
                                              ?.uid ??
                                          '',
                                      date: DateTime.now(),
                                      pdfName: _selectedFileName,
                                      score: _quizScore,
                                      totalQuestions: _quizQuestions.length,
                                      questions: _quizQuestions
                                          .map(
                                            (q) => {
                                              'question': q.question,
                                              'options': q.options,
                                              'userAnswer':
                                                  q.selectedAnswerIndex,
                                              'correctAnswer':
                                                  q.correctAnswerIndex,
                                              'isCorrect': q.isCorrect,
                                              'explanation': q.explanation,
                                            },
                                          )
                                          .toList(),
                                    ),
                                  ),
                                ),
                              );
                            }
                          : null,
                      icon: const Icon(Icons.visibility),
                      label: const Text('View Details'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
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
                                  child: Center(
                                    child: Text(
                                      String.fromCharCode(65 + optIndex),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    question.options[optIndex],
                                    style: TextStyle(
                                      color: textColor ?? Colors.black87,
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
                      if (_showQuizResults &&
                          question.explanation.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lightbulb,
                                size: 18,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  question.explanation,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
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
}

// Custom painter for dashed border
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
