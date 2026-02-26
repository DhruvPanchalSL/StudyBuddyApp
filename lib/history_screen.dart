import 'package:StudyBuddy/quiz_details_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'models/quiz_history.dart';

const Color _kLime = Color(0xFFAAFF00);
const Color _kDark = Color(0xFF1C1C2E);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  final user = FirebaseAuth.instance.currentUser;
  late TabController _filterTabController;

  @override
  void initState() {
    super.initState();
    _filterTabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _filterTabController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      final h = date.hour;
      final m = date.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return 'Today at $displayH:$m $period';
    } else if (difference.inDays == 1) {
      final h = date.hour;
      final m = date.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'PM' : 'AM';
      final displayH = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return 'Yesterday at $displayH:$m $period';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Color _getScoreColor(int score, int total) {
    double percentage = score / total;
    if (percentage >= 0.8) return const Color(0xFF22C55E);
    if (percentage >= 0.5) return Colors.orange;
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
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(
          title: const Text('Study History'),
          backgroundColor: Colors.white,
          foregroundColor: _kDark,
          elevation: 0,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline, size: 50, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 16),
              Text(
                'Please login to view history',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kDark,
        elevation: 0,
        title: const Text(
          'Study History',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: _kDark),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: Colors.red.shade400),
            onPressed: _showDeleteAllDialog,
            tooltip: 'Clear history',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter tabs
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _filterTabController,
                tabs: const [
                  Tab(text: 'All Archive'),
                  Tab(text: 'Quizzes'),
                  Tab(text: 'Summaries'),
                ],
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                labelColor: _kDark,
                unselectedLabelColor: Colors.grey,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
              ),
            ),
          ),
          // Content
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user!.uid)
                  .collection('quiz_history')
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: _kLime, strokeWidth: 3),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading history',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: _kLime.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.history_rounded, size: 50, color: _kDark.withOpacity(0.3)),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No quiz history yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _kDark,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Take a quiz to see your history here!',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                List<QuizHistory> histories = snapshot.data!.docs.map((doc) {
                  return QuizHistory.fromMap(doc.data() as Map<String, dynamic>);
                }).toList();

                return TabBarView(
                  controller: _filterTabController,
                  children: [
                    _buildHistoryList(histories),
                    _buildHistoryList(histories), // Quizzes (all quizzes)
                    _buildEmptyTab(), // Summaries (no summaries in history yet)
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(List<QuizHistory> histories) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: histories.length,
      itemBuilder: (context, index) {
        final history = histories[index];
        final pct = (history.score / history.totalQuestions * 100).round();
        final scoreColor = _getScoreColor(history.score, history.totalQuestions);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: InkWell(
            onTap: () => _viewQuizDetails(history),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _kLime.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: _kLime, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          history.pdfName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _kDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              'Score: $pct%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scoreColor,
                              ),
                            ),
                            Text(
                              '  •  ${_formatDate(history.date)}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _viewQuizDetails(history),
                        child: Text(
                          'Review Details',
                          style: TextStyle(
                            fontSize: 11,
                            color: _kDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.chevron_right_rounded, size: 16, color: Colors.grey.shade400),
                    ],
                  ),
                  PopupMenuButton(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade400, size: 18),
                    padding: EdgeInsets.zero,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('View Details'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
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
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.article_outlined, size: 50, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'No summaries saved yet.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
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
            content: const Text('Quiz deleted from history'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        title: const Text('Clear History', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to delete all quiz history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
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
                    SnackBar(
                      content: const Text('All history deleted'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Error deleting all: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }
}
