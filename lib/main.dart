import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() async {
  await dotenv.load();
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
        appBarTheme: const AppBarTheme(elevation: 2, centerTitle: true),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  String _selectedFileName = "No file selected";
  String _extractedText = "";
  String _summary = "";

  // Quiz related variables
  List<QuizQuestion> _quizQuestions = [];
  bool _isGeneratingQuiz = false;
  bool _showQuizResults = false;
  int _quizScore = 0;

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
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentTabIndex = _tabController.index;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      print("Error: $e");
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

  void _selectAnswer(int questionIndex, int answerIndex) {
    setState(() {
      _quizQuestions[questionIndex].selectedAnswerIndex = answerIndex;
    });
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
    });
    _tabController.animateTo(0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Study Buddy AI',
          style: TextStyle(fontWeight: FontWeight.w500, letterSpacing: 0.5),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: _extractedText.isNotEmpty && !_isLoading
            ? TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(icon: Icon(Icons.text_snippet), text: 'Text'),
                  Tab(icon: Icon(Icons.auto_awesome), text: 'Summary'),
                  Tab(icon: Icon(Icons.quiz), text: 'Quiz'),
                ],
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
              )
            : null,
        actions: [
          if (_extractedText.isNotEmpty ||
              _summary.isNotEmpty ||
              _quizQuestions.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearAll,
              tooltip: 'Clear all',
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // File selection section - Enhanced design
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.picture_as_pdf,
                          color: Colors.blue.shade700,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PDF File',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              _selectedFileName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _pickAndReadPDF,
                        icon: const Icon(Icons.upload_file, size: 18),
                        label: const Text('Pick PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Loading indicator for PDF
              if (_isLoading)
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.blue.shade700,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Extracting text from PDF...',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),

              // Action buttons (only show when text is extracted)
              if (_extractedText.isNotEmpty && !_isLoading) ...[
                // Action buttons with improved styling
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            onPressed: _isGeneratingSummary
                                ? null
                                : _generateSummary,
                            isLoading: _isGeneratingSummary,
                            icon: Icons.summarize,
                            label: 'Summarize',
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            onPressed: _isGeneratingQuiz ? null : _generateQuiz,
                            isLoading: _isGeneratingQuiz,
                            icon: Icons.quiz,
                            label: 'Generate Quiz',
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Tab content
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // Text Tab - Improved
                          _buildContentTab(
                            content: _extractedText,
                            icon: Icons.text_snippet,
                            color: Colors.blue,
                            emptyMessage: 'No text extracted yet',
                          ),

                          // Summary Tab - Improved
                          _summary.isEmpty
                              ? _buildEmptyState(
                                  icon: Icons.auto_awesome,
                                  message:
                                      'Click Summarize to generate AI summary',
                                  color: Colors.green,
                                )
                              : _buildContentTab(
                                  content: _summary,
                                  icon: Icons.auto_awesome,
                                  color: Colors.green,
                                  emptyMessage: '',
                                ),

                          // Quiz Tab - Improved
                          _quizQuestions.isEmpty
                              ? _buildEmptyState(
                                  icon: Icons.quiz,
                                  message:
                                      'Click Generate Quiz to create questions',
                                  color: Colors.orange,
                                )
                              : _buildQuizTab(),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Stats at bottom - Enhanced
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade200,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        icon: Icons.text_snippet,
                        label: '${_extractedText.length} chars',
                        color: Colors.blue,
                      ),
                      if (_summary.isNotEmpty)
                        _buildStatItem(
                          icon: Icons.auto_awesome,
                          label: '${_summary.length} chars',
                          color: Colors.green,
                        ),
                      if (_quizQuestions.isNotEmpty)
                        _buildStatItem(
                          icon: Icons.quiz,
                          label: '${_quizQuestions.length} questions',
                          color: Colors.orange,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Helper method for action buttons
  Widget _buildActionButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(icon, size: 18),
      label: Text(isLoading ? 'Generating...' : label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
      ),
    );
  }

  // Helper method for content tabs
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
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 8),
                Text(
                  'Extracted Text',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(content, style: const TextStyle(fontSize: 14, height: 1.5)),
          ],
        ),
      ),
    );
  }

  // Helper method for empty state
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
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 50, color: color.withOpacity(0.5)),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  // Helper method for stat items
  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
      ],
    );
  }

  // Enhanced Quiz Tab
  Widget _buildQuizTab() {
    return Column(
      children: [
        // Quiz header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border(bottom: BorderSide(color: Colors.orange.shade200)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${_quizQuestions.length}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Questions',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (_showQuizResults)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Score: $_quizScore/${_quizQuestions.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Quiz questions list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _quizQuestions.length,
            itemBuilder: (context, index) {
              final question = _quizQuestions[index];
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
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              question.question,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...question.options.asMap().entries.map((entry) {
                        int optionIndex = entry.key;
                        String option = entry.value;
                        bool isSelected =
                            question.selectedAnswerIndex == optionIndex;
                        bool isCorrect =
                            question.correctAnswerIndex == optionIndex;

                        Color tileColor = Colors.transparent;
                        Color borderColor = Colors.grey.shade300;
                        double borderWidth = 1;

                        if (_showQuizResults) {
                          if (isCorrect) {
                            tileColor = Colors.green.shade50;
                            borderColor = Colors.green;
                            borderWidth = 2;
                          } else if (isSelected && !isCorrect) {
                            tileColor = Colors.red.shade50;
                            borderColor = Colors.red;
                            borderWidth = 2;
                          }
                        } else if (isSelected) {
                          tileColor = Colors.blue.shade50;
                          borderColor = Colors.blue;
                          borderWidth = 2;
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: tileColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: borderColor,
                              width: borderWidth,
                            ),
                          ),
                          child: RadioListTile<int>(
                            title: Text(
                              '${String.fromCharCode(65 + optionIndex)}. $option',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            value: optionIndex,
                            groupValue: question.selectedAnswerIndex,
                            onChanged: _showQuizResults
                                ? null
                                : (value) => _selectAnswer(index, value!),
                            activeColor: Colors.blue,
                            dense: true,
                          ),
                        );
                      }).toList(),

                      // Show explanation after quiz is submitted
                      if (_showQuizResults &&
                          question.explanation.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.lightbulb,
                                    size: 18,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Explanation',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(question.explanation),
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
        // Quiz action buttons
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _resetQuiz,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade700,
                    side: BorderSide(color: Colors.orange.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _showQuizResults ? null : _submitQuiz,
                  icon: const Icon(Icons.check_circle),
                  label: Text(
                    _showQuizResults ? 'Submitted' : 'Submit Answers',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
