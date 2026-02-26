import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'auth_screen.dart';
import 'history_screen.dart';
import 'models/chat_message.dart';
import 'models/quiz_history.dart';
import 'models/quiz_question.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color kLimeGreen = Color(0xFFAAFF00);
  static const Color kDarkBg = Color(0xFF1C1C2E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Study Buddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFAAFF00),
          primary: const Color(0xFF1C1C2E),
          secondary: const Color(0xFFAAFF00),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1C1C2E),
          titleTextStyle: TextStyle(
            color: Color(0xFF1C1C2E),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
            return HomeScreen();
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

  // Quiz related variables
  List<QuizQuestion> _quizQuestions = [];
  bool _isGeneratingQuiz = false;
  bool _showQuizResults = false;
  int _quizScore = 0;
  int _currentQuizIndex = 0; // One-at-a-time question index

  // Chat related variables
  List<ChatMessage> _chatMessages = [];
  final TextEditingController _chatController = TextEditingController();
  bool _isSendingMessage = false;
  final ScrollController _chatScrollController = ScrollController();

  bool _isLoading = false;
  bool _isGeneratingSummary = false;

  late TabController _tabController;
  int _currentTabIndex = 0;

  // Gemini API endpoint - Using Flash for better free tier quotas
  final String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // Changed to 4 tabs
    _tabController.addListener(() {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    });

    // Add welcome message
    _chatMessages.add(
      ChatMessage(
        text:
            "👋 Hi! I'm your AI study assistant. Ask me anything about your document!",
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
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
          _tabController.animateTo(0);
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

      if (apiKey.isEmpty) {
        throw Exception('API key not found. Check your .env file');
      }

      final url = Uri.parse('$_geminiEndpoint?key=$apiKey');

      String textToSummarize = _extractedText;
      if (textToSummarize.length > 30000) {
        textToSummarize =
            textToSummarize.substring(0, 30000) +
            "\n\n[Note: Text truncated due to length...]";
      }

      String prompt =
          '''
Please provide a clear and concise summary of the following text. 
Focus on the main points and key ideas:

$textToSummarize

Summary:
''';

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

      if (apiKey.isEmpty) {
        throw Exception('API key not found. Check your .env file');
      }

      final url = Uri.parse('$_geminiEndpoint?key=$apiKey');

      String textForQuiz = _extractedText;
      if (textForQuiz.length > 25000) {
        textForQuiz =
            textForQuiz.substring(0, 25000) +
            "\n\n[Note: Text truncated for quiz generation...]";
      }

      String prompt =
          '''
Based on the following text, generate 5 multiple choice quiz questions.
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
- correctAnswerIndex must be 0, 1, 2, or 3 (0 = first option, 1 = second, etc.)
- Make questions challenging but fair
- Base questions strictly on the provided text

TEXT:
$textForQuiz

JSON RESPONSE:
''';

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

            _tabController.animateTo(2);

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '✅ Quiz generated with ${questions.length} questions',
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          } else {
            throw Exception('No questions in response');
          }
        } else {
          throw Exception('Could not parse quiz JSON');
        }
      } else if (response.statusCode == 429) {
        setState(() {
          _isGeneratingQuiz = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
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
      setState(() {
        _isGeneratingQuiz = false;
      });

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

  // NEW: Send message to AI chat
  Future<void> _sendMessage() async {
    if (_chatController.text.trim().isEmpty) return;

    String userMessage = _chatController.text.trim();

    // Add user message to chat
    setState(() {
      _chatMessages.add(
        ChatMessage(text: userMessage, isUser: true, timestamp: DateTime.now()),
      );
      _chatController.clear();
      _isSendingMessage = true;
    });

    // Scroll to bottom
    _scrollToBottom();

    try {
      String apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

      if (apiKey.isEmpty) {
        throw Exception('API key not found');
      }

      final url = Uri.parse('$_geminiEndpoint?key=$apiKey');

      // Use summary as context if available, otherwise use extracted text
      String context = _summary.isNotEmpty ? _summary : _extractedText;

      if (context.isEmpty) {
        // No document loaded
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

      // Truncate context if too long
      if (context.length > 20000) {
        context = context.substring(0, 20000) + "...";
      }

      String prompt =
          '''
You are a helpful study assistant. Answer the user's question based ONLY on the following context.
If the answer cannot be found in the context, say "I don't have enough information about that in the document."

CONTEXT:
$context

USER QUESTION: $userMessage

ANSWER (be concise but helpful):
''';

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

  // Add this import at the top

  // Replace your existing _saveQuizToHistory with this:
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

      // Show saving indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saving quiz to history...'),
          duration: Duration(seconds: 1),
        ),
      );

      // Create list of question details
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

      // Create history object
      final history = QuizHistory(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: user.uid,
        date: DateTime.now(),
        pdfName: _selectedFileName,
        score: _quizScore,
        totalQuestions: _quizQuestions.length,
        questions: questionDetails,
      );

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('quiz_history')
          .doc(history.id)
          .set(history.toMap());

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Quiz saved to history!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      print('Error saving quiz history: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving quiz: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _submitQuiz() {
    int score = 0;
    for (var question in _quizQuestions) {
      if (question.isCorrect) {
        score++;
      }
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
      _currentQuizIndex = 0;
    });
  }

  static const Color kLimeGreen = Color(0xFFAAFF00);
  static const Color kDarkBg = Color(0xFF1C1C2E);

  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.email?.split('@').first ?? 'Student';
    final capitalizedName = displayName[0].toUpperCase() + displayName.substring(1);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: SafeArea(
        child: _buildBody(capitalizedName),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: (i) {
          if (i == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            );
          } else if (i == 3) {
            FirebaseAuth.instance.signOut();
          } else {
            setState(() => _navIndex = i);
          }
        },
        selectedItemColor: kDarkBg,
        unselectedItemColor: Colors.grey.shade400,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_rounded), label: 'Library'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded), label: 'AI Tools'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
        ],
      ),
    );
  }

  Widget _buildBody(String userName) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: kDarkBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome back,',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: kDarkBg,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(Icons.notifications_outlined, color: kDarkBg, size: 20),
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),

        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                const Text(
                  'Study Buddy AI',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: kDarkBg,
                    letterSpacing: -0.5,
                  ),
                ),

                // Mode selector
                if (_extractedText.isNotEmpty && !_isLoading) ...[
                  const SizedBox(height: 14),
                  _buildModeSelector(),
                ],

                const SizedBox(height: 20),

                // PDF Picker card (always show when no text or still in text tab)
                if (_extractedText.isEmpty || _isLoading)
                  _buildPickerCard()
                else
                  _buildContentArea(),

                // Loading
                if (_isLoading) ...[
                  const SizedBox(height: 20),
                  _buildLoadingCard(),
                ],

                // Action buttons — only show when text loaded & no tab content showing
                if (_extractedText.isNotEmpty && !_isLoading) ...[
                  const SizedBox(height: 20),
                  _buildActionButtons(),
                ],

                const SizedBox(height: 28),

                // Recent sessions header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'RECENT SESSIONS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.grey.shade500,
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
                          color: kDarkBg,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (_selectedFileName != 'No file selected') ...[
                  _buildRecentItem(_selectedFileName),
                ] else
                  _buildEmptyRecentSessions(),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),

        // Chat input bar
        _buildChatInputBar(),
      ],
    );
  }

  Widget _buildModeSelector() {
    final tabs = ['Text', 'Summary', 'Quiz'];
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final tabIndex = i;
            final selected = _currentTabIndex == tabIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  _tabController.animateTo(tabIndex);
                  setState(() => _currentTabIndex = tabIndex);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected ? kDarkBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    child: Text(
                      tabs[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.grey.shade500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildPickerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: const Color(0xFFF0FFF0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: kLimeGreen, size: 36),
          ),
          const SizedBox(height: 18),
          const Text(
            'Pick your Study Material',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: kDarkBg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a PDF document or paste a\nlink to start learning with AI assistance.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 140,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _pickAndReadPDF,
              style: ElevatedButton.styleFrom(
                backgroundColor: kLimeGreen,
                foregroundColor: kDarkBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Pick PDF',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: kLimeGreen),
          ),
          const SizedBox(width: 16),
          Text('Extracting text from PDF...', style: TextStyle(color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    return SizedBox(
      height: 280,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildContentTab(
                content: _extractedText,
                icon: Icons.text_snippet,
                color: kDarkBg,
                emptyMessage: 'No text extracted yet',
              ),
              _summary.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.auto_awesome,
                      message: 'Click Summarize to generate AI summary',
                      color: kLimeGreen,
                    )
                  : _buildContentTab(
                      content: _summary,
                      icon: Icons.auto_awesome,
                      color: kDarkBg,
                      emptyMessage: '',
                    ),
              _quizQuestions.isEmpty
                  ? _buildEmptyState(
                      icon: Icons.quiz,
                      message: 'Click Generate Quiz to create questions',
                      color: kDarkBg,
                    )
                  : _buildQuizTab(),
              _buildChatTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _isGeneratingSummary ? null : _generateSummary,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: kDarkBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isGeneratingSummary
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2, color: kLimeGreen),
                          )
                        : const Icon(Icons.summarize_rounded, color: kLimeGreen, size: 22),
                  ),
                  const SizedBox(height: 14),
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
            onTap: _isGeneratingQuiz ? null : _generateQuiz,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: kDarkBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isGeneratingQuiz
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(strokeWidth: 2, color: kLimeGreen),
                          )
                        : const Icon(Icons.quiz_rounded, color: kLimeGreen, size: 22),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Generate\nQuiz',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentItem(String fileName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
              color: kLimeGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.picture_as_pdf_rounded, color: kLimeGreen, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kDarkBg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  _quizQuestions.isNotEmpty
                      ? '${_quizQuestions.length} Questions Generated'
                      : 'Just now',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  Widget _buildEmptyRecentSessions() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          'No recent sessions yet.\nPick a PDF to get started!',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade400, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildChatInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _chatController,
                decoration: InputDecoration(
                  hintText: 'Ask your Study Buddy anything...',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _extractedText.isNotEmpty ? _sendMessage() : null,
                enabled: _extractedText.isNotEmpty && !_isSendingMessage,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: kLimeGreen,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSendingMessage
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: kDarkBg, strokeWidth: 2),
                    )
                  : const Icon(Icons.north_east_rounded, color: kDarkBg, size: 22),
              onPressed: _extractedText.isNotEmpty && !_isSendingMessage ? _sendMessage : null,
            ),
          ),
        ],
      ),
    );
  }




  Widget _buildContentTab({
    required String content,
    required IconData icon,
    required Color color,
    required String emptyMessage,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: kLimeGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: kDarkBg),
                ),
                const SizedBox(width: 8),
                Text(
                  icon == Icons.auto_awesome ? 'AI Summary' : 'Extracted Text',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kDarkBg,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String message,
    required Color color,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: kLimeGreen.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: kDarkBg.withOpacity(0.4)),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }




  Widget _buildQuizTab() {
    if (_showQuizResults) {
      return _buildQuizResults();
    }

    int answeredCount = _quizQuestions.where((q) => q.selectedAnswerIndex != null).length;

    return Column(
      children: [
        // Progress header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'QUIZ PROGRESS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  Text(
                    '$answeredCount / ${_quizQuestions.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: kDarkBg,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _quizQuestions.isEmpty ? 0 : answeredCount / _quizQuestions.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(kLimeGreen),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        // Quiz questions list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _quizQuestions.length,
            itemBuilder: (context, index) {
              final question = _quizQuestions[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: kLimeGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: kDarkBg,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            question.question,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: kDarkBg,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...question.options.asMap().entries.map((entry) {
                      int optionIndex = entry.key;
                      String option = entry.value;
                      bool isSelected = question.selectedAnswerIndex == optionIndex;
                      final letter = String.fromCharCode(65 + optionIndex);

                      return GestureDetector(
                        onTap: () => _selectAnswer(index, optionIndex),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? kLimeGreen.withOpacity(0.12) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? kLimeGreen : Colors.grey.shade200,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: isSelected ? kLimeGreen : Colors.white,
                                  border: Border.all(
                                    color: isSelected ? kLimeGreen : Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Center(
                                  child: isSelected
                                      ? const Icon(Icons.check, size: 14, color: kDarkBg)
                                      : Text(
                                          letter,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  option,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: isSelected ? kDarkBg : Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            },
          ),
        ),
        // Submit button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _showQuizResults ? null : _submitQuiz,
              style: ElevatedButton.styleFrom(
                backgroundColor: kLimeGreen,
                foregroundColor: kDarkBg,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _showQuizResults ? 'Submitted' : 'Submit Answer',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  if (!_showQuizResults) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuizResults() {
    final percentage = (_quizScore / _quizQuestions.length * 100).round();
    String label = percentage >= 80
        ? 'Mastery Achieved'
        : percentage >= 50
            ? 'Good Progress'
            : 'Keep Practicing';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 8),
          // Score ring
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 140,
                height: 140,
                child: CircularProgressIndicator(
                  value: _quizScore / _quizQuestions.length,
                  strokeWidth: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(kLimeGreen),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$percentage',
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                      color: kDarkBg,
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF22C55E),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You scored $_quizScore out of ${_quizQuestions.length} questions.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          // Stats row
          Row(
            children: [
              Expanded(
                child: _buildResultChip(
                  Icons.check_circle_outline,
                  '$_quizScore Correct',
                  const Color(0xFFDCFCE7),
                  const Color(0xFF22C55E),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildResultChip(
                  Icons.percent_rounded,
                  '$percentage% Accuracy',
                  const Color(0xFFDCFCE7),
                  const Color(0xFF22C55E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Difficulty breakdown
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
                    color: kDarkBg,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDifficultyRow('Easy', Colors.green, _quizQuestions.where((q) => _quizQuestions.indexOf(q) % 3 == 0 && q.isCorrect).length, (_quizQuestions.length / 3).ceil()),
                _buildDifficultyRow('Intermediate', Colors.orange, _quizQuestions.where((q) => _quizQuestions.indexOf(q) % 3 == 1 && q.isCorrect).length, (_quizQuestions.length / 3).ceil()),
                _buildDifficultyRow('Advanced', Colors.red, _quizQuestions.where((q) => _quizQuestions.indexOf(q) % 3 == 2 && q.isCorrect).length, _quizQuestions.length - (_quizQuestions.length ~/ 3 * 2)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Review button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: kLimeGreen,
                foregroundColor: kDarkBg,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                'Review Detailed Answers',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _resetQuiz,
            child: const Text(
              'Retake Quiz',
              style: TextStyle(color: kDarkBg, fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultChip(IconData icon, String text, Color bg, Color iconColor) {
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

  Widget _buildDifficultyRow(String label, Color color, int correct, int total) {
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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kDarkBg),
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


  Widget _buildChatTab() {
    return Column(
      children: [
        // Chat messages
        Expanded(
          child: _chatMessages.isEmpty
              ? _buildEmptyState(
                  icon: Icons.chat_bubble_outline_rounded,
                  message: 'Ask questions about your document',
                  color: kDarkBg,
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _chatMessages.length,
                  itemBuilder: (context, index) {
                    final message = _chatMessages[index];
                    return _buildChatBubble(message);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildChatBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: kLimeGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: kDarkBg, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: message.isUser ? kDarkBg : Colors.white,
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomLeft: message.isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: message.isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
                border: message.isUser
                    ? null
                    : Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: message.isUser ? Colors.white : Colors.grey.shade800,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: kDarkBg.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_rounded, color: kDarkBg, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}
