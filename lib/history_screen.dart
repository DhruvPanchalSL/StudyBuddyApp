import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'models/quiz_history.dart';
import 'quiz_details_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with TickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  late TabController _tabController;
  int _selectedTabIndex = 0;

  // Brand colors
  static const Color _green = Color(0xFF7ED957);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);
  static const Color _bgWhite = Colors.white;
  static const Color _bgGray = Color(0xFFF7F7F7);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() => _selectedTabIndex = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return 'Today at ${DateFormat('h:mm a').format(date)}';
      }
      return 'Today at ${DateFormat('h:mm a').format(date)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday at ${DateFormat('h:mm a').format(date)}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago · ${DateFormat('h:mm a').format(date)}';
    } else {
      return DateFormat('MMM d').format(date) +
          ' at ${DateFormat('h:mm a').format(date)}';
    }
  }

  Color _getScoreColor(int score, int total) {
    double percentage = score / total;
    if (percentage >= 0.8) return _green;
    if (percentage >= 0.6) return Colors.orange;
    return Colors.red;
  }

  void _viewQuizDetails(QuizHistory history) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizDetailsScreen(history: history),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        backgroundColor: _bgWhite,
        appBar: AppBar(
          title: const Text('Study History'),
          backgroundColor: _bgWhite,
          foregroundColor: _textDark,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Please login to view history',
                style: TextStyle(fontSize: 16, color: _textGray),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _bgWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: _textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Study History',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: _textDark,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded, color: _textDark, size: 24),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tab bar (All Archive / Quizzes / Summaries)
          Container(
            color: _bgWhite,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Row(
              children: [
                _buildTabPill('All Archive', 0),
                const SizedBox(width: 8),
                _buildTabPill('Quizzes', 1),
                const SizedBox(width: 8),
                _buildTabPill('Summaries', 2),
              ],
            ),
          ),

          // "RECENT SESSIONS" label
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Text(
              'RECENT SESSIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _textGray,
                letterSpacing: 1.3,
              ),
            ),
          ),

          // Sessions list
          Expanded(
            child: _selectedTabIndex == 2
                ? _buildSummariesTab()
                : _buildQuizzesTab(),
          ),
        ],
      ),
      // Green FAB
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.pop(context),
        backgroundColor: _green,
        elevation: 4,
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTabPill(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        _tabController.animateTo(index);
        setState(() => _selectedTabIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _green.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? _green : _textGray,
          ),
        ),
      ),
    );
  }

  Widget _buildQuizzesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('quiz_history')
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF7ED957)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading history',
              style: TextStyle(color: _textGray),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: _green.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    size: 56,
                    color: _green.withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No quiz history yet',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Take a quiz to see your history here!',
                  style: TextStyle(fontSize: 13, color: _textGray),
                ),
              ],
            ),
          );
        }

        List<QuizHistory> histories = snapshot.data!.docs.map((doc) {
          return QuizHistory.fromMap(doc.data() as Map<String, dynamic>);
        }).toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          itemCount: histories.length,
          itemBuilder: (context, index) {
            final history = histories[index];
            final percentage = ((history.score / history.totalQuestions) * 100)
                .round();
            final scoreColor = _getScoreColor(
              history.score,
              history.totalQuestions,
            );

            // Alternating icon styles for visual variety
            final iconData = _getDocIcon(history.pdfName, index);
            final iconBg = _getIconBg(index);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: _bgWhite,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: iconBg,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(iconData, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        // Title + date
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                history.pdfName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _textDark,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatDate(history.date),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _textGray,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Three-dot menu
                        PopupMenuButton(
                          icon: Icon(
                            Icons.more_vert,
                            color: _textGray,
                            size: 20,
                          ),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'details',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.visibility,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                  SizedBox(width: 8),
                                  Text('View Details'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete,
                                    size: 18,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'delete') {
                              _deleteQuiz(history.id);
                            } else if (value == 'details') {
                              _viewQuizDetails(history);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Divider
                    Container(height: 1, color: Colors.grey.shade100),
                    const SizedBox(height: 10),
                    // Score + Review Details row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Score: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _textGray,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                              TextSpan(
                                text: '$percentage%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scoreColor,
                                  fontFamily: 'Roboto',
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _viewQuizDetails(history),
                          child: Row(
                            children: [
                              Text(
                                'Review Details',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _green,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: _green,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSummariesTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome,
              size: 56,
              color: _green.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Summary history coming soon!',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: _textDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Generate summaries to see them here',
            style: TextStyle(fontSize: 13, color: _textGray),
          ),
        ],
      ),
    );
  }

  IconData _getDocIcon(String name, int index) {
    final lower = name.toLowerCase();
    if (lower.contains('neural') ||
        lower.contains('ai') ||
        lower.contains('machine')) {
      return Icons.hub_rounded;
    } else if (lower.contains('chem') ||
        lower.contains('bio') ||
        lower.contains('science')) {
      return Icons.science_rounded;
    } else if (lower.contains('quantum') || lower.contains('physics')) {
      return Icons.bolt_rounded;
    } else if (lower.contains('history') || lower.contains('art')) {
      return Icons.history_edu_rounded;
    } else if (lower.contains('math') ||
        lower.contains('macro') ||
        lower.contains('econ')) {
      return Icons.calculate_rounded;
    }
    final icons = [
      Icons.menu_book_rounded,
      Icons.calculate_rounded,
      Icons.bolt_rounded,
      Icons.history_edu_rounded,
      Icons.hub_rounded,
    ];
    return icons[index % icons.length];
  }

  Color _getIconBg(int index) {
    final colors = [
      const Color(0xFF5BBF35),
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
      const Color(0xFFEF4444),
      const Color(0xFF0891B2),
    ];
    return colors[index % colors.length];
  }

  Widget _buildBottomNav() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: _bgWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_rounded, 'Home', false),
          _buildNavItem(Icons.library_books_rounded, 'Library', true),
          const SizedBox(width: 56), // Space for FAB
          _buildNavItem(Icons.auto_fix_high_rounded, 'Flashcards', false),
          _buildNavItem(Icons.person_rounded, 'Profile', false),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: isActive ? _green : _textGray, size: 24),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? _green : _textGray,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Future<void> _deleteQuiz(String quizId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('quiz_history')
          .doc(quizId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quiz deleted'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error deleting quiz: $e');
    }
  }

  Future<void> _showDeleteAllDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Clear History',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to delete all quiz history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: _textGray)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final batch = FirebaseFirestore.instance.batch();
                final snapshot = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user!.uid)
                    .collection('quiz_history')
                    .get();
                for (var doc in snapshot.docs) {
                  batch.delete(doc.reference);
                }
                await batch.commit();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All history deleted'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error deleting all: $e');
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}
