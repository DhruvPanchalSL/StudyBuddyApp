import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class MindMapNode {
  final String id;
  final String label;
  final List<MindMapNode> children;
  final int depth; // 0 = root, 1 = branch, 2 = leaf
  Offset position;

  MindMapNode({
    required this.id,
    required this.label,
    this.children = const [],
    this.depth = 0,
    this.position = Offset.zero,
  });
}

class FlowNode {
  final String id;
  final String label;
  final FlowNodeType type;

  FlowNode({required this.id, required this.label, required this.type});
}

enum FlowNodeType { start, step, decision, end }

// ─────────────────────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────────────────────

class VisualToolsScreen extends StatefulWidget {
  final String documentText;
  final String documentName;
  final String activeGeminiKey;
  final String activeGroqKey;
  final int initialTab;

  const VisualToolsScreen({
    Key? key,
    required this.documentText,
    required this.documentName,
    required this.activeGeminiKey,
    required this.activeGroqKey,
    this.initialTab = 0,
  }) : super(key: key);

  @override
  State<VisualToolsScreen> createState() => _VisualToolsScreenState();
}

class _VisualToolsScreenState extends State<VisualToolsScreen>
    with SingleTickerProviderStateMixin {
  static const Color _green = Color(0xFF7ED957);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);

  late TabController _tabController;

  // Mind Map state
  MindMapNode? _mindMapRoot;
  bool _loadingMindMap = false;
  String? _mindMapError;
  final TransformationController _mindMapTransform = TransformationController();

  // Flowchart state
  List<FlowNode> _flowNodes = [];
  bool _loadingFlow = false;
  String? _flowError;
  final ScrollController _flowScroll = ScrollController();

  // API
  final String _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  final String _groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  final String _groqModel = 'llama-3.3-70b-versatile';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    // Auto-generate both on open only if we have content
    if (widget.documentText.trim().isEmpty) {
      setState(() {
        _mindMapError = 'No document loaded. Please select a PDF first.';
        _flowError = 'No document loaded. Please select a PDF first.';
        _loadingMindMap = false;
        _loadingFlow = false;
      });
      return;
    }
    // Auto-generate both on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateMindMap();
      _generateFlowchart();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mindMapTransform.dispose();
    _flowScroll.dispose();
    super.dispose();
  }

  // ── AI caller (Gemini → Groq fallback)
  Future<String> _callAI(String prompt, {int maxTokens = 600}) async {
    // Try Gemini first
    try {
      final url = Uri.parse('$_geminiEndpoint?key=${widget.activeGeminiKey}');
      final res = await http.post(
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
            "temperature": 0.3,
            "maxOutputTokens": maxTokens,
          },
        }),
      );
      if (res.statusCode == 429) throw Exception('rate_limit');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['candidates'][0]['content']['parts'][0]['text'];
      }
      throw Exception('Gemini ${res.statusCode}');
    } catch (e) {
      if (!e.toString().contains('rate_limit') && !e.toString().contains('429'))
        rethrow;
    }
    // Fallback to Groq
    final res = await http.post(
      Uri.parse(_groqEndpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${widget.activeGroqKey}',
      },
      body: jsonEncode({
        "model": _groqModel,
        "messages": [
          {"role": "user", "content": prompt},
        ],
        "max_tokens": maxTokens,
        "temperature": 0.3,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['choices'][0]['message']['content'];
    }
    throw Exception('Both providers failed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MIND MAP — small AI call to extract semantic structure
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _generateMindMap() async {
    setState(() {
      _loadingMindMap = true;
      _mindMapError = null;
    });
    try {
      final text = widget.documentText.length > 8000
          ? widget.documentText.substring(0, 8000)
          : widget.documentText;

      final prompt =
          '''
Analyze this text and extract a mind map structure. 
Return ONLY valid JSON, no explanation, no markdown, no backticks.
Format:
{
  "root": "Central Topic",
  "branches": [
    {
      "label": "Branch 1",
      "leaves": ["Leaf A", "Leaf B", "Leaf C"]
    }
  ]
}
Rules:
- root: the single most central topic (max 4 words)
- branches: 4-6 major concepts (max 4 words each)
- leaves: 2-3 subtopics per branch (max 5 words each)
- No square brackets in text values

Text: $text
''';

      final response = await _callAI(prompt, maxTokens: 600);

      // Strip any accidental markdown fences
      final cleaned = response.replaceAll(RegExp(r'```json|```'), '').trim();

      final Map<String, dynamic> data = jsonDecode(cleaned);
      final root = _buildMindMapTree(data);
      _layoutMindMap(root);

      setState(() {
        _mindMapRoot = root;
        _loadingMindMap = false;
      });

      // Reset view to center
      _mindMapTransform.value = Matrix4.identity();
    } catch (e) {
      setState(() {
        _mindMapError = 'Could not generate mind map: $e';
        _loadingMindMap = false;
      });
    }
  }

  MindMapNode _buildMindMapTree(Map<String, dynamic> data) {
    final branches = (data['branches'] as List<dynamic>? ?? []).map((b) {
      final leaves = (b['leaves'] as List<dynamic>? ?? [])
          .map(
            (l) => MindMapNode(
              id: UniqueKey().toString(),
              label: l.toString(),
              depth: 2,
            ),
          )
          .toList();
      return MindMapNode(
        id: UniqueKey().toString(),
        label: b['label']?.toString() ?? '',
        children: leaves,
        depth: 1,
      );
    }).toList();

    return MindMapNode(
      id: 'root',
      label: data['root']?.toString() ?? 'Main Topic',
      children: branches,
      depth: 0,
    );
  }

  void _layoutMindMap(MindMapNode root) {
    const double cx = 600, cy = 500;
    root.position = const Offset(cx, cy);

    final branches = root.children;
    if (branches.isEmpty) return;

    for (int i = 0; i < branches.length; i++) {
      final angle = (i / branches.length) * 2 * math.pi - math.pi / 2;
      final bx = cx + math.cos(angle) * 220;
      final by = cy + math.sin(angle) * 180;
      branches[i].position = Offset(bx, by);

      final leaves = branches[i].children;
      for (int j = 0; j < leaves.length; j++) {
        final spread = 0.35;
        final leafAngle = angle + (j - (leaves.length - 1) / 2) * spread;
        final lx = bx + math.cos(leafAngle) * 160;
        final ly = by + math.sin(leafAngle) * 120;
        leaves[j].position = Offset(lx, ly);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLOWCHART — rule-based keyword extraction, zero AI
  // ─────────────────────────────────────────────────────────────────────────

  void _generateFlowchart() {
    setState(() {
      _loadingFlow = true;
      _flowError = null;
    });
    try {
      final nodes = _extractFlowNodes(widget.documentText);
      setState(() {
        _flowNodes = nodes;
        _loadingFlow = false;
      });
    } catch (e) {
      setState(() {
        _flowError = 'Could not generate flowchart: $e';
        _loadingFlow = false;
      });
    }
  }

  List<FlowNode> _extractFlowNodes(String text) {
    final List<FlowNode> nodes = [];
    int idCounter = 0;
    String nextId() => (idCounter++).toString();

    // Sentence splitter
    final sentences = text
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((s) => s.trim())
        .where((s) => s.length > 20 && s.length < 200)
        .toList();

    // Step keywords
    final stepPatterns = [
      RegExp(
        r'^(first|firstly|to begin|initially|start by)',
        caseSensitive: false,
      ),
      RegExp(
        r'^(second|secondly|next|then|after that|subsequently)',
        caseSensitive: false,
      ),
      RegExp(
        r'^(third|thirdly|following this|afterwards)',
        caseSensitive: false,
      ),
      RegExp(
        r'^(finally|lastly|in conclusion|as a result|therefore)',
        caseSensitive: false,
      ),
      RegExp(r'^step\s*\d+', caseSensitive: false),
      RegExp(r'^\d+[\.\)]\s+\w'),
    ];

    // Decision keywords
    final decisionPatterns = [
      RegExp(
        r'\b(if|whether|when|depending on|in case|provided that)\b',
        caseSensitive: false,
      ),
      RegExp(r'\b(alternatively|or|otherwise|instead)\b', caseSensitive: false),
    ];

    // Numbered list detection
    final numberedLine = RegExp(r'^(\d+)[\.\)]\s+(.+)');

    bool hasStart = false;

    for (final sentence in sentences) {
      if (nodes.length >= 12) break; // Cap at 12 nodes for readability

      final numbered = numberedLine.firstMatch(sentence.trim());
      if (numbered != null) {
        final label = _truncateLabel(numbered.group(2) ?? sentence);
        if (!hasStart) {
          nodes.add(
            FlowNode(id: nextId(), label: 'Start', type: FlowNodeType.start),
          );
          hasStart = true;
        }
        nodes.add(
          FlowNode(id: nextId(), label: label, type: FlowNodeType.step),
        );
        continue;
      }

      bool isStep = stepPatterns.any((p) => p.hasMatch(sentence));
      bool isDecision = decisionPatterns.any((p) => p.hasMatch(sentence));

      if (isStep || isDecision) {
        if (!hasStart) {
          nodes.add(
            FlowNode(id: nextId(), label: 'Start', type: FlowNodeType.start),
          );
          hasStart = true;
        }
        final label = _truncateLabel(sentence);
        nodes.add(
          FlowNode(
            id: nextId(),
            label: label,
            type: isDecision ? FlowNodeType.decision : FlowNodeType.step,
          ),
        );
      }
    }

    if (nodes.isEmpty) {
      // Fallback: take first 6 sentences as steps
      nodes.add(
        FlowNode(id: nextId(), label: 'Start', type: FlowNodeType.start),
      );
      for (final s in sentences.take(6)) {
        nodes.add(
          FlowNode(
            id: nextId(),
            label: _truncateLabel(s),
            type: FlowNodeType.step,
          ),
        );
      }
    }

    if (nodes.isNotEmpty && nodes.last.type != FlowNodeType.end) {
      nodes.add(FlowNode(id: nextId(), label: 'End', type: FlowNodeType.end));
    }

    return nodes;
  }

  String _truncateLabel(String text) {
    final cleaned = text
        .replaceAll(
          RegExp(
            r'^(first|second|third|next|then|finally|step\s*\d+[:\.]?\s*)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    final words = cleaned.split(' ');
    return words.take(10).join(' ') + (words.length > 10 ? '...' : '');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Visual Tools',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: _textDark,
              ),
            ),
            Text(
              widget.documentName.replaceAll('.pdf', ''),
              style: const TextStyle(fontSize: 11, color: _textGray),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _textDark),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _green,
          unselectedLabelColor: _textGray,
          indicatorColor: _green,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          tabs: const [
            Tab(icon: Icon(Icons.hub_rounded, size: 18), text: 'Mind Map'),
            Tab(
              icon: Icon(Icons.account_tree_rounded, size: 18),
              text: 'Flowchart',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildMindMapTab(), _buildFlowchartTab()],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MIND MAP TAB
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMindMapTab() {
    if (_loadingMindMap) return _buildLoader('Generating mind map...', _green);
    if (_mindMapError != null)
      return _buildError(_mindMapError!, _generateMindMap);
    if (_mindMapRoot == null) return _buildLoader('Preparing...', _green);

    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _mindMapTransform,
          boundaryMargin: const EdgeInsets.all(400),
          minScale: 0.3,
          maxScale: 2.5,
          child: SizedBox(
            width: 1200,
            height: 1000,
            child: CustomPaint(
              painter: _MindMapPainter(root: _mindMapRoot!),
              child: _buildMindMapLabels(_mindMapRoot!),
            ),
          ),
        ),
        // Controls
        Positioned(
          bottom: 20,
          right: 20,
          child: Column(
            children: [
              _mapButton(Icons.refresh_rounded, _generateMindMap),
              const SizedBox(height: 8),
              _mapButton(Icons.center_focus_strong_rounded, () {
                _mindMapTransform.value = Matrix4.identity();
              }),
              const SizedBox(height: 8),
              _mapButton(Icons.zoom_in_rounded, () {
                final m = _mindMapTransform.value.clone();
                m.scale(1.3);
                _mindMapTransform.value = m;
              }),
              const SizedBox(height: 8),
              _mapButton(Icons.zoom_out_rounded, () {
                final m = _mindMapTransform.value.clone();
                m.scale(0.77);
                _mindMapTransform.value = m;
              }),
            ],
          ),
        ),
        // Hint
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Pinch to zoom · Drag to pan',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMindMapLabels(MindMapNode root) {
    final List<Widget> labels = [];

    void addLabel(MindMapNode node) {
      final color = node.depth == 0
          ? _green
          : node.depth == 1
          ? const Color(0xFF6366F1)
          : const Color(0xFF10B981);
      final fontSize = node.depth == 0
          ? 13.0
          : node.depth == 1
          ? 11.0
          : 10.0;
      final maxW = node.depth == 0
          ? 100.0
          : node.depth == 1
          ? 90.0
          : 80.0;

      labels.add(
        Positioned(
          left: node.position.dx - maxW / 2,
          top: node.position.dy - 20,
          child: SizedBox(
            width: maxW,
            child: Text(
              node.label,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: node.depth == 0 ? FontWeight.w800 : FontWeight.w600,
                color: node.depth == 0 ? Colors.white : color,
                height: 1.2,
              ),
            ),
          ),
        ),
      );
      for (final child in node.children) {
        addLabel(child);
      }
    }

    addLabel(root);
    return Stack(children: labels);
  }

  Widget _mapButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: _textDark),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLOWCHART TAB
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFlowchartTab() {
    if (_loadingFlow) {
      return _buildLoader('Extracting flow...', const Color(0xFF6366F1));
    }
    if (_flowError != null) {
      return _buildError(_flowError!, _generateFlowchart);
    }
    if (_flowNodes.isEmpty) {
      return _buildLoader('Preparing...', const Color(0xFF6366F1));
    }

    return Stack(
      children: [
        SingleChildScrollView(
          controller: _flowScroll,
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
          child: Column(
            children: [
              for (int i = 0; i < _flowNodes.length; i++) ...[
                _buildFlowNode(_flowNodes[i]),
                if (i < _flowNodes.length - 1) _buildFlowArrow(),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
        // Regenerate button
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.small(
            onPressed: _generateFlowchart,
            backgroundColor: const Color(0xFF6366F1),
            child: const Icon(
              Icons.refresh_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlowNode(FlowNode node) {
    switch (node.type) {
      case FlowNodeType.start:
      case FlowNodeType.end:
        return _buildPillNode(node);
      case FlowNodeType.decision:
        return _buildDiamondNode(node);
      case FlowNodeType.step:
        return _buildRectNode(node);
    }
  }

  Widget _buildPillNode(FlowNode node) {
    final isStart = node.type == FlowNodeType.start;
    final color = isStart ? _green : const Color(0xFFEF4444);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        node.label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 15,
        ),
      ),
    );
  }

  Widget _buildRectNode(FlowNode node) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.circle, size: 10, color: Color(0xFF6366F1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              node.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiamondNode(FlowNode node) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              size: 18,
              color: Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              node.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowArrow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Container(width: 2, height: 12, color: Colors.grey.shade300),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.grey.shade400,
            size: 20,
          ),
          Container(width: 2, height: 4, color: Colors.grey.shade300),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoader(String message, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          const SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: _textGray, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mind Map CustomPainter — draws edges and node circles
// ─────────────────────────────────────────────────────────────────────────────

class _MindMapPainter extends CustomPainter {
  final MindMapNode root;

  const _MindMapPainter({required this.root});

  @override
  void paint(Canvas canvas, Size size) {
    _drawNode(canvas, root);
  }

  void _drawNode(Canvas canvas, MindMapNode node) {
    for (final child in node.children) {
      // Draw curved edge
      final paint = Paint()
        ..color = _edgeColor(node.depth).withOpacity(0.5)
        ..strokeWidth = node.depth == 0 ? 2.5 : 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(node.position.dx, node.position.dy);
      final cx = (node.position.dx + child.position.dx) / 2;
      path.cubicTo(
        cx,
        node.position.dy,
        cx,
        child.position.dy,
        child.position.dx,
        child.position.dy,
      );
      canvas.drawPath(path, paint);

      _drawNode(canvas, child);
    }

    // Draw node circle
    final radius = node.depth == 0
        ? 52.0
        : node.depth == 1
        ? 42.0
        : 36.0;

    // Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(node.position + const Offset(0, 3), radius, shadowPaint);

    // Fill
    final fillPaint = Paint()..color = _nodeColor(node.depth);
    canvas.drawCircle(node.position, radius, fillPaint);

    // Border
    final borderPaint = Paint()
      ..color = _edgeColor(node.depth).withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(node.position, radius, borderPaint);
  }

  Color _nodeColor(int depth) {
    switch (depth) {
      case 0:
        return const Color(0xFF7ED957);
      case 1:
        return const Color(0xFFEEF2FF);
      default:
        return const Color(0xFFECFDF5);
    }
  }

  Color _edgeColor(int depth) {
    switch (depth) {
      case 0:
        return const Color(0xFF7ED957);
      case 1:
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF10B981);
    }
  }

  @override
  bool shouldRepaint(_MindMapPainter old) => old.root != root;
}
