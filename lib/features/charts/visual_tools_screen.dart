import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class MindMapNode {
  final String id;
  final String label;
  final String detail;
  final List<MindMapNode> children;
  final int depth;
  Offset position;

  MindMapNode({
    required this.id,
    required this.label,
    this.detail = '',
    this.children = const [],
    this.depth = 0,
    this.position = Offset.zero,
  });
}

class FlowNode {
  final String id;
  final String label;
  final String description;
  final FlowNodeType type;
  FlowNode({
    required this.id,
    required this.label,
    this.description = '',
    required this.type,
  });
}

enum FlowNodeType { start, step, decision, end }

class _ResourceLink {
  final String title;
  final String subtitle;
  final String url;
  final String source;
  const _ResourceLink({
    required this.title,
    required this.subtitle,
    required this.url,
    required this.source,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
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

  // Mind map
  MindMapNode? _mindMapRoot;
  bool _loadingMindMap = false;
  String? _mindMapError;
  final TransformationController _mindMapTransform = TransformationController();
  MindMapNode? _selectedNode;
  Size _canvasSize = const Size(1400, 1000);

  // Flowchart
  bool _loadingFlow = false;
  String? _flowError;

  // API
  static const _geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  static const _groqEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';
  static const _groqModel = 'llama-3.3-70b-versatile';

  static const double _rootR = 60.0;
  static const double _branchR = 48.0;
  static const double _leafR = 36.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );

    if (widget.documentText.trim().isEmpty) {
      setState(() {
        _mindMapError = 'No document loaded. Please select a PDF first.';
        _flowError = 'No document loaded. Please select a PDF first.';
        _loadingMindMap = false;
        _loadingFlow = false;
      });
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _generateMindMap();
      _generateFlowchart();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _mindMapTransform.dispose();
    super.dispose();
  }

  // ── AI caller ─────────────────────────────────────────────────────────────
  Future<String> _callAI(String prompt, {int maxTokens = 1000}) async {
    final geminiKey = widget.activeGeminiKey;
    if (geminiKey.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse('$_geminiEndpoint?key=$geminiKey'),
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
              "temperature": 0.2,
              "maxOutputTokens": maxTokens,
            },
          }),
        );
        if (res.statusCode == 200) {
          return jsonDecode(
            res.body,
          )['candidates'][0]['content']['parts'][0]['text'];
        }
        if (res.statusCode != 429) throw Exception('Gemini ${res.statusCode}');
      } catch (e) {
        if (!e.toString().contains('429')) rethrow;
      }
    }
    final groqKey = widget.activeGroqKey;
    if (groqKey.isEmpty) throw Exception('No API key available');
    final res = await http.post(
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
        "temperature": 0.2,
      }),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['choices'][0]['message']['content'];
    }
    throw Exception('All providers failed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MIND MAP
  // ─────────────────────────────────────────────────────────────────────────

  /// Sample from MIDDLE of document to skip intro/preface/TOC
  String _sampleText() {
    final full = widget.documentText;
    final len = full.length;
    if (len <= 6000) return full;
    final start = (len * 0.15).toInt(); // skip first 15%
    return full.substring(start, (start + 6000).clamp(0, len));
  }

  Future<void> _generateMindMap() async {
    setState(() {
      _loadingMindMap = true;
      _mindMapError = null;
    });
    try {
      final sample = _sampleText();
      final prompt =
          '''You are a JSON generator for a study mind map. Analyze the TEXT and extract KEY SUBJECT CONCEPTS.
Focus on the CORE CONTENT — main ideas, theories, methods, key terms.
Do NOT use document structure words like Introduction, Preface, Audience, Prerequisites, Overview, Contents.

Output ONLY this JSON (no markdown, no backticks, no explanation):
{"root":"SUBJECT","branches":[{"label":"CONCEPT","detail":"One sentence.","leaves":[{"label":"SUBTOPIC","detail":"Brief."},{"label":"SUBTOPIC","detail":"Brief."}]},{"label":"CONCEPT","detail":"One sentence.","leaves":[{"label":"SUBTOPIC","detail":"Brief."},{"label":"SUBTOPIC","detail":"Brief."}]},{"label":"CONCEPT","detail":"One sentence.","leaves":[{"label":"SUBTOPIC","detail":"Brief."},{"label":"SUBTOPIC","detail":"Brief."}]},{"label":"CONCEPT","detail":"One sentence.","leaves":[{"label":"SUBTOPIC","detail":"Brief."},{"label":"SUBTOPIC","detail":"Brief."}]},{"label":"CONCEPT","detail":"One sentence.","leaves":[{"label":"SUBTOPIC","detail":"Brief."},{"label":"SUBTOPIC","detail":"Brief."}]}]}

- root: actual subject name (1-3 words)
- 5 branches = 5 real concepts from the content
- each branch: exactly 2 leaves
- labels: 1-4 plain words, no brackets or special chars
- detail: max 1 sentence

TEXT:
$sample''';

      final response = await _callAI(prompt, maxTokens: 1400);

      String cleaned = response
          .replaceAll(RegExp(r'```json', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      final s = cleaned.indexOf('{');
      final e = cleaned.lastIndexOf('}');
      if (s == -1 || e == -1) throw Exception('No JSON in response');
      cleaned = _repairJson(cleaned.substring(s, e + 1));
      if (cleaned.isEmpty) throw Exception('JSON repair failed');

      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      final root = _parseMindMap(data);
      _layoutMindMap(root);

      setState(() {
        _mindMapRoot = root;
        _loadingMindMap = false;
      });
      _centerMindMap();
    } catch (e) {
      // Silently fall back to rule-based
      try {
        final fallback = _buildFallbackMindMap();
        _layoutMindMap(fallback);
        setState(() {
          _mindMapRoot = fallback;
          _loadingMindMap = false;
        });
        _centerMindMap();
      } catch (_) {
        setState(() {
          _mindMapError = 'Could not generate mind map. Please try again.';
          _loadingMindMap = false;
        });
      }
    }
  }

  MindMapNode _parseMindMap(Map<String, dynamic> data) {
    final branchList = data['branches'] as List<dynamic>? ?? [];
    final branches = branchList.map((b) {
      final leafList = b['leaves'] as List<dynamic>? ?? [];
      final leaves = leafList.map((l) {
        final label = l is Map ? (l['label'] ?? '').toString() : l.toString();
        final detail = l is Map ? (l['detail'] ?? '').toString() : '';
        return MindMapNode(
          id: UniqueKey().toString(),
          label: label,
          detail: detail,
          depth: 2,
        );
      }).toList();
      return MindMapNode(
        id: UniqueKey().toString(),
        label: (b['label'] ?? '').toString(),
        detail: (b['detail'] ?? '').toString(),
        children: leaves,
        depth: 1,
      );
    }).toList();

    return MindMapNode(
      id: 'root',
      label: (data['root'] ?? widget.documentName.replaceAll('.pdf', ''))
          .toString(),
      children: branches,
      depth: 0,
    );
  }

  void _layoutMindMap(MindMapNode root) {
    const double cx = 700, cy = 520;
    root.position = const Offset(cx, cy);

    final branches = root.children;
    for (int i = 0; i < branches.length; i++) {
      final angle = (i / branches.length) * 2 * math.pi - math.pi / 2;
      const dist = 240.0;
      final bx = cx + math.cos(angle) * dist;
      final by = cy + math.sin(angle) * dist;
      branches[i].position = Offset(bx, by);

      final leaves = branches[i].children;
      for (int j = 0; j < leaves.length; j++) {
        final leafAngle = angle + (j - (leaves.length - 1) / 2) * 0.42;
        const leafDist = 175.0;
        leaves[j].position = Offset(
          bx + math.cos(leafAngle) * leafDist,
          by + math.sin(leafAngle) * leafDist,
        );
      }
    }

    // Compute canvas bounds
    double minX = cx, maxX = cx, minY = cy, maxY = cy;
    void visit(MindMapNode n) {
      minX = math.min(minX, n.position.dx);
      maxX = math.max(maxX, n.position.dx);
      minY = math.min(minY, n.position.dy);
      maxY = math.max(maxY, n.position.dy);
      for (final c in n.children) visit(c);
    }

    visit(root);
    _canvasSize = Size(maxX + 140, maxY + 140);
  }

  void _centerMindMap() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final screen = MediaQuery.of(context).size;
      final scaleX = (screen.width * 0.92) / _canvasSize.width;
      final scaleY = (screen.height * 0.68) / _canvasSize.height;
      final scale = math.min(scaleX, scaleY).clamp(0.3, 1.0);
      _mindMapTransform.value = Matrix4.identity()..scale(scale);
    });
  }

  // localPosition from GestureDetector inside InteractiveViewer child
  // is already in canvas coordinates — no matrix transform needed
  MindMapNode? _hitTest(Offset pos) {
    if (_mindMapRoot == null) return null;
    MindMapNode? found;
    void visit(MindMapNode n) {
      final r = n.depth == 0
          ? _rootR
          : n.depth == 1
          ? _branchR
          : _leafR;
      if ((n.position - pos).distance <= r) {
        found = n;
        return;
      }
      for (final c in n.children) visit(c);
    }

    visit(_mindMapRoot!);
    return found;
  }

  // ── JSON repair ───────────────────────────────────────────────────────────
  String _repairJson(String json) {
    try {
      jsonDecode(json);
      return json;
    } catch (_) {}
    final buf = StringBuffer(json);
    int braces = 0, brackets = 0;
    bool inString = false, escaped = false;
    for (final ch in json.runes) {
      final c = String.fromCharCode(ch);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (c == '{') braces++;
      if (c == '}') braces--;
      if (c == '[') brackets++;
      if (c == ']') brackets--;
    }
    if (inString) buf.write('"');
    for (int i = 0; i < brackets; i++) buf.write(']');
    for (int i = 0; i < braces; i++) buf.write('}');
    final repaired = buf.toString();
    try {
      jsonDecode(repaired);
      return repaired;
    } catch (_) {
      return '';
    }
  }

  // ── Rule-based fallback ───────────────────────────────────────────────────
  MindMapNode _buildFallbackMindMap() {
    final text = widget.documentText;
    final conceptRegex = RegExp(r'\b([A-Z][a-z]+(?: [A-Z][a-z]+){1,3})\b');
    const noise = {
      'The',
      'This',
      'That',
      'These',
      'Those',
      'There',
      'Their',
      'They',
      'When',
      'Where',
      'What',
      'Which',
      'With',
      'From',
      'Into',
      'About',
    };
    final concepts = conceptRegex
        .allMatches(text)
        .map((m) => m.group(0)!)
        .where((m) => !noise.contains(m.split(' ').first))
        .toSet()
        .take(20)
        .toList();

    final rootLabel = widget.documentName
        .replaceAll('.pdf', '')
        .split(RegExp(r'[_\-\s]'))
        .take(3)
        .join(' ');

    final branches = <MindMapNode>[];
    for (int i = 0; i < 5 && i < concepts.length; i++) {
      final leaves = <MindMapNode>[];
      for (int j = 1; j <= 2; j++) {
        final idx = i * 2 + j;
        if (idx < concepts.length) {
          leaves.add(
            MindMapNode(
              id: UniqueKey().toString(),
              label: concepts[idx],
              depth: 2,
            ),
          );
        }
      }
      branches.add(
        MindMapNode(
          id: UniqueKey().toString(),
          label: concepts[i],
          children: leaves,
          depth: 1,
        ),
      );
    }
    return MindMapNode(
      id: 'root',
      label: rootLabel,
      children: branches,
      depth: 0,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FLOWCHART — AI with topic picker
  // ─────────────────────────────────────────────────────────────────────────

  List<_FlowChart> _availableCharts = [];
  int _selectedChartIndex = 0;

  List<FlowNode> get _flowNodes => _availableCharts.isEmpty
      ? []
      : _availableCharts[_selectedChartIndex].nodes;
  String get _flowTitle => _availableCharts.isEmpty
      ? ''
      : _availableCharts[_selectedChartIndex].title;

  Future<void> _generateFlowchart() async {
    setState(() {
      _loadingFlow = true;
      _flowError = null;
      _availableCharts = [];
    });
    try {
      final text = widget.documentText;
      final len = text.length;

      // Sample aggressively from the body — skip first 20% (always intro/TOC)
      final part1 = text.substring(
        (len * 0.20).toInt(),
        (len * 0.20 + 2500).clamp(0, len).toInt(),
      );
      final part2 = text.substring(
        (len * 0.45).toInt(),
        (len * 0.45 + 2500).clamp(0, len).toInt(),
      );
      final part3 = text.substring(
        (len * 0.70).toInt(),
        (len * 0.70 + 2000).clamp(0, len).toInt(),
      );
      final sample = '$part1\n\n$part2\n\n$part3';

      final prompt =
          '''You are an expert study tool. Read the TEXT from a document and create 3 DIFFERENT flowcharts.

CRITICAL RULES:
- Each flowchart must be about a REAL PROCESS or CONCEPT from the subject matter in the text
- Examples of good flowchart topics for a forex book: "How to Execute a Forex Trade", "How Bid-Ask Spread Works", "Currency Pair Selection Process"
- Examples of BAD topics (never use these): "Tutorial Overview", "Introduction", "Book Structure", "Prerequisites", "About the Author"
- If the text is about forex: make flowcharts about trading processes, analysis methods, risk management
- If the text is about programming: make flowcharts about algorithms, code flow, debugging process
- If the text is about biology: make flowcharts about biological processes, cell cycles, metabolic pathways
- Capture the ACTUAL SUBJECT from the text

Each node needs a real description explaining what happens at that step IN THE CONTEXT OF THE SUBJECT.

Output ONLY valid JSON (no markdown, no backticks):
{"charts":[{"title":"REAL PROCESS NAME","nodes":[{"id":1,"label":"SHORT LABEL","type":"start","description":"Explain what begins here in subject context."},{"id":2,"label":"SHORT LABEL","type":"step","description":"Explain this action in subject context."},{"id":3,"label":"SHORT LABEL?","type":"decision","description":"Explain this condition in subject context."},{"id":4,"label":"SHORT LABEL","type":"step","description":"Explain this step."},{"id":5,"label":"SHORT LABEL","type":"end","description":"Explain what is achieved."}]},{"title":"DIFFERENT REAL PROCESS","nodes":[...]},{"title":"ANOTHER REAL PROCESS","nodes":[...]}]}

Rules:
- 3 charts, each about a genuinely different process/concept from the subject
- 5-8 nodes per chart
- label: 2-5 words max
- description: 1-2 sentences, specific to the subject, actually useful for studying
- types: start(first), step(action), decision(condition ending in ?), end(last)

TEXT:
$sample''';

      final response = await _callAI(prompt, maxTokens: 2500);

      String cleaned = response
          .replaceAll(RegExp(r'```json', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();
      final s = cleaned.indexOf('{');
      final e = cleaned.lastIndexOf('}');
      if (s == -1 || e == -1) throw Exception('No JSON');
      cleaned = _repairJson(cleaned.substring(s, e + 1));
      if (cleaned.isEmpty) throw Exception('repair failed');

      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      final chartList = data['charts'] as List<dynamic>? ?? [];
      final charts = chartList
          .map((c) {
            final title = (c['title'] ?? '').toString();
            final nodes = _parseFlowNodes(c);
            return _FlowChart(title: title, nodes: nodes);
          })
          .where((c) => c.nodes.length >= 3)
          .toList();

      if (charts.isEmpty) throw Exception('no valid charts');

      setState(() {
        _availableCharts = charts;
        _selectedChartIndex = 0;
        _loadingFlow = false;
      });
    } catch (e) {
      try {
        final fallback = _buildFallbackCharts();
        setState(() {
          _availableCharts = fallback;
          _selectedChartIndex = 0;
          _loadingFlow = false;
        });
      } catch (_) {
        setState(() {
          _flowError = 'Could not generate flowchart. Please try again.';
          _loadingFlow = false;
        });
      }
    }
  }

  List<FlowNode> _parseFlowNodes(dynamic chartData) {
    int id = 0;
    final rawNodes = chartData['nodes'] as List<dynamic>? ?? [];
    return rawNodes
        .map((n) {
          final label = (n['label'] ?? '').toString().trim();
          final desc = (n['description'] ?? '').toString().trim();
          final typeStr = (n['type'] ?? 'step').toString().toLowerCase();
          FlowNodeType type;
          switch (typeStr) {
            case 'start':
              type = FlowNodeType.start;
              break;
            case 'decision':
              type = FlowNodeType.decision;
              break;
            case 'end':
              type = FlowNodeType.end;
              break;
            default:
              type = FlowNodeType.step;
          }
          return FlowNode(
            id: '${id++}',
            label: label,
            description: desc,
            type: type,
          );
        })
        .where((n) => n.label.isNotEmpty)
        .toList();
  }

  List<_FlowChart> _buildFallbackCharts() {
    // Extract headings from the document as a single fallback chart
    final text = widget.documentText;
    final lines = text.split('\n').map((l) => l.trim()).toList();
    final headings = lines
        .where((l) {
          if (l.length < 4 || l.length > 55) return false;
          if (l.endsWith('.') || l.endsWith(',') || l.endsWith(':'))
            return false;
          final words = l.split(' ');
          if (words.length > 7 || words.length < 2) return false;
          return words.first.isNotEmpty &&
              RegExp(r'^[A-Z]').hasMatch(words.first);
        })
        .toSet()
        .take(7)
        .toList();

    int id = 0;
    String nid() => '${id++}';
    final nodes = <FlowNode>[];

    if (headings.length >= 4) {
      nodes.add(
        FlowNode(id: nid(), label: headings[0], type: FlowNodeType.start),
      );
      for (final h in headings.skip(1).take(headings.length - 2)) {
        nodes.add(FlowNode(id: nid(), label: h, type: FlowNodeType.step));
      }
      nodes.add(
        FlowNode(id: nid(), label: headings.last, type: FlowNodeType.end),
      );
    } else {
      // Absolute fallback: sentences
      final mid = (text.length * 0.15).toInt();
      final sentences = text
          .substring(mid, (mid + 4000).clamp(0, text.length))
          .split(RegExp(r'(?<=[.!?])\s+'))
          .map((s) => s.trim())
          .where((s) => s.length > 25 && s.length < 100)
          .take(6)
          .toList();
      nodes.add(FlowNode(id: nid(), label: 'Begin', type: FlowNodeType.start));
      for (final s in sentences) {
        final w = s.split(' ');
        nodes.add(
          FlowNode(
            id: nid(),
            label: w.take(6).join(' ') + (w.length > 6 ? '...' : ''),
            type: FlowNodeType.step,
          ),
        );
      }
      nodes.add(FlowNode(id: nid(), label: 'Complete', type: FlowNodeType.end));
    }

    final title = widget.documentName.replaceAll('.pdf', '');
    return [_FlowChart(title: title, nodes: nodes)];
  }

  String _trim(String text) {
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
    return words.take(12).join(' ') + (words.length > 12 ? '...' : '');
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

  // ── Mind Map tab ──────────────────────────────────────────────────────────

  Widget _buildMindMapTab() {
    if (_loadingMindMap) {
      return _loader('Analyzing document concepts...', _green);
    }
    if (_mindMapError != null) {
      return _error(_mindMapError!, _generateMindMap);
    }
    if (_mindMapRoot == null) return _loader('Preparing...', _green);

    return Stack(
      children: [
        // Grid background
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),

        // InteractiveViewer handles ALL pan/zoom gestures freely.
        // GestureDetector is INSIDE as the child — so taps on the canvas
        // are detected AFTER InteractiveViewer decides it's not a pan.
        InteractiveViewer(
          transformationController: _mindMapTransform,
          boundaryMargin: const EdgeInsets.all(500),
          minScale: 0.25,
          maxScale: 3.0,
          child: GestureDetector(
            onTapUp: (d) {
              // d.localPosition is already in canvas space because
              // GestureDetector lives inside the InteractiveViewer child
              final hit = _hitTest(d.localPosition);
              setState(() => _selectedNode = hit);
              if (hit != null) _showNodeDetail(hit);
            },
            child: SizedBox(
              width: _canvasSize.width,
              height: _canvasSize.height,
              child: CustomPaint(
                painter: _MindMapPainter(
                  root: _mindMapRoot!,
                  selectedNode: _selectedNode,
                ),
              ),
            ),
          ),
        ),

        // Legend
        Positioned(top: 12, left: 16, child: _buildLegend()),

        // Controls
        Positioned(
          bottom: 60,
          right: 16,
          child: Column(
            children: [
              _iconBtn(
                Icons.refresh_rounded,
                _generateMindMap,
                tooltip: 'Regenerate',
              ),
              const SizedBox(height: 8),
              _iconBtn(
                Icons.fit_screen_rounded,
                _centerMindMap,
                tooltip: 'Fit to screen',
              ),
              const SizedBox(height: 8),
              _iconBtn(Icons.zoom_in_rounded, () {
                final m = _mindMapTransform.value.clone()..scale(1.3);
                _mindMapTransform.value = m;
              }),
              const SizedBox(height: 8),
              _iconBtn(Icons.zoom_out_rounded, () {
                final m = _mindMapTransform.value.clone()..scale(0.77);
                _mindMapTransform.value = m;
              }),
            ],
          ),
        ),

        // Hint
        Positioned(
          bottom: 16,
          left: 0,
          right: 80,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '✦ Tap any node for details  ·  Pinch to zoom',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _legendDot(_green, 'Core Topic'),
          const SizedBox(height: 4),
          _legendDot(const Color(0xFF6366F1), 'Main Concept'),
          const SizedBox(height: 4),
          _legendDot(const Color(0xFF10B981), 'Subtopic'),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _textDark,
        ),
      ),
    ],
  );

  // Cache: node id → fetched links (so we don't re-fetch on re-open)
  final Map<String, List<_ResourceLink>> _linkCache = {};

  /// Generates high-quality curated resource links for a topic.
  /// Uses DuckDuckGo as a first attempt, then falls back to smart curated links.
  Future<List<_ResourceLink>> _fetchLinks(String topic) async {
    if (_linkCache.containsKey(topic)) return _linkCache[topic]!;

    final links = <_ResourceLink>[];
    final encoded = Uri.encodeComponent(topic);

    // 1. Try DuckDuckGo instant answer for a real Wikipedia link
    try {
      final res = await http
          .get(
            Uri.parse(
              'https://api.duckduckgo.com/?q=${encoded}&format=json&no_html=1&skip_disambig=1',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final abstractUrl = data['AbstractURL']?.toString() ?? '';
        final abstractText = data['AbstractText']?.toString() ?? '';
        if (abstractUrl.isNotEmpty && abstractText.isNotEmpty) {
          final snippet = abstractText.length > 90
              ? '${abstractText.substring(0, 90)}…'
              : abstractText;
          links.add(
            _ResourceLink(
              title: snippet,
              subtitle: abstractUrl.replaceAll('https://', '').split('/').first,
              url: abstractUrl,
              source: 'Wikipedia',
            ),
          );
        }
      }
    } catch (_) {}

    // 2. Curated educational platforms — always high quality
    links.addAll([
      _ResourceLink(
        title: 'Read about "$topic"',
        subtitle: 'en.wikipedia.org',
        url: 'https://en.wikipedia.org/wiki/Special:Search?search=$encoded',
        source: 'Wikipedia',
      ),
      _ResourceLink(
        title: 'Watch "$topic" explained',
        subtitle: 'youtube.com',
        url:
            'https://www.youtube.com/results?search_query=${encoded}+explained',
        source: 'YouTube',
      ),
      _ResourceLink(
        title: 'Khan Academy — "$topic"',
        subtitle: 'khanacademy.org',
        url: 'https://www.khanacademy.org/search?page_search_query=$encoded',
        source: 'Khan Academy',
      ),
      _ResourceLink(
        title: 'Investopedia — "$topic"',
        subtitle: 'investopedia.com',
        url: 'https://www.investopedia.com/search#q=$encoded',
        source: 'Investopedia',
      ),
      _ResourceLink(
        title: 'Research papers on "$topic"',
        subtitle: 'scholar.google.com',
        url: 'https://scholar.google.com/scholar?q=$encoded',
        source: 'Google Scholar',
      ),
    ]);

    // Deduplicate by URL, keep Wikipedia API result first if present
    final seen = <String>{};
    final unique = links.where((l) => seen.add(l.url)).toList();

    _linkCache[topic] = unique;
    return unique;
  }

  void _showNodeDetail(MindMapNode node) {
    if (node.label.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NodeDetailSheet(
        node: node,
        fetchLinks: _fetchLinks,
        edgeColor: _edgeColor(node.depth),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {String? tooltip}) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
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
      ),
    );
  }

  // ── Flowchart tab ─────────────────────────────────────────────────────────

  Widget _buildFlowchartTab() {
    if (_loadingFlow) {
      return _loader('Generating flowcharts...', const Color(0xFF6366F1));
    }
    if (_flowError != null) return _error(_flowError!, _generateFlowchart);
    if (_availableCharts.isEmpty)
      return _loader('Preparing...', const Color(0xFF6366F1));

    final nodes = _flowNodes;

    return Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
        Column(
          children: [
            // Chart picker — horizontal scroll tabs
            if (_availableCharts.length > 1)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(_availableCharts.length, (i) {
                      final selected = i == _selectedChartIndex;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedChartIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF6366F1)
                                : const Color(0xFF6366F1).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _availableCharts[i].title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? Colors.white
                                  : const Color(0xFF6366F1),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),

            // Flow nodes
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
                child: Column(
                  children: [
                    for (int i = 0; i < nodes.length; i++) ...[
                      _flowWidget(nodes[i], i),
                      if (i < nodes.length - 1) _arrow(nodes[i], nodes[i + 1]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),

        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton.small(
            onPressed: _generateFlowchart,
            backgroundColor: const Color(0xFF6366F1),
            tooltip: 'Regenerate',
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

  Widget _flowWidget(FlowNode node, int index) {
    Widget card;
    switch (node.type) {
      case FlowNodeType.start:
      case FlowNodeType.end:
        card = _pillNode(node);
        break;
      case FlowNodeType.decision:
        card = _decisionNode(node, index);
        break;
      case FlowNodeType.step:
        card = _stepNode(node, index);
        break;
    }

    return GestureDetector(
      onTap: () => _showFlowNodeDetail(node, index),
      child: card,
    );
  }

  void _showFlowNodeDetail(FlowNode node, int index) {
    final isDecision = node.type == FlowNodeType.decision;
    final isStart = node.type == FlowNodeType.start;
    final isEnd = node.type == FlowNodeType.end;

    final Color color = isStart
        ? _green
        : isEnd
        ? const Color(0xFFEF4444)
        : isDecision
        ? const Color(0xFFF59E0B)
        : const Color(0xFF6366F1);

    final String typeLabel = isStart
        ? 'START'
        : isEnd
        ? 'END'
        : isDecision
        ? 'DECISION POINT'
        : 'STEP $index';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.42,
        minChildSize: 0.28,
        maxChildSize: 0.75,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 14),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Type badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      typeLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Node label
              Text(
                node.label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _textDark,
                  height: 1.2,
                ),
              ),

              const SizedBox(height: 20),

              // Description — front and center, this is the actual value
              if (node.description.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_rounded, color: color, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            'What this means',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        node.description,
                        style: const TextStyle(
                          fontSize: 15,
                          color: _textDark,
                          height: 1.7,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'No description available for this step.',
                  style: TextStyle(fontSize: 14, color: _textGray),
                ),

              // YES / NO outcome cards for decisions
              if (isDecision) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _outcomeCard(
                        'YES',
                        'Condition met — proceed to next step',
                        const Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _outcomeCard(
                        'NO',
                        'Condition not met — re-evaluate',
                        const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _outcomeCard(String label, String desc, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          desc,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: _textGray, height: 1.4),
        ),
      ],
    ),
  );

  Widget _pillNode(FlowNode node) {
    final isStart = node.type == FlowNodeType.start;
    final color = isStart ? _green : const Color(0xFFEF4444);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 28),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isStart ? Icons.play_arrow_rounded : Icons.stop_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            node.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepNode(FlowNode node, int index) {
    const color = Color(0xFF6366F1);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                if (node.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    node.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textGray,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _decisionNode(FlowNode node, int index) {
    const color = Color(0xFFF59E0B);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                '?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
                if (node.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    node.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _textGray,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _arrow(FlowNode from, FlowNode to) {
    final isDecision = from.type == FlowNodeType.decision;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        children: [
          if (isDecision)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _branchChip('YES', const Color(0xFF10B981)),
                  const SizedBox(width: 12),
                  _branchChip('NO', const Color(0xFFEF4444)),
                ],
              ),
            ),
          Container(width: 2, height: 12, color: Colors.grey.shade300),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Colors.grey.shade400,
            size: 22,
          ),
          Container(width: 2, height: 6, color: Colors.grey.shade300),
        ],
      ),
    );
  }

  Widget _branchChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: 0.5,
      ),
    ),
  );

  // ── Shared helpers ────────────────────────────────────────────────────────

  Color _edgeColor(int depth) {
    switch (depth) {
      case 0:
        return _green;
      case 1:
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF10B981);
    }
  }

  Widget _loader(String msg, Color color) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(color)),
        const SizedBox(height: 20),
        Text(
          msg,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'This may take a moment',
          style: TextStyle(color: _textGray, fontSize: 12),
        ),
      ],
    ),
  );

  Widget _error(String msg, VoidCallback retry) => Center(
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
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textGray, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try Again'),
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

// ─────────────────────────────────────────────────────────────────────────────
// Node detail bottom sheet with async resource links
// ─────────────────────────────────────────────────────────────────────────────

class _NodeDetailSheet extends StatefulWidget {
  final MindMapNode node;
  final Future<List<_ResourceLink>> Function(String topic) fetchLinks;
  final Color edgeColor;

  const _NodeDetailSheet({
    required this.node,
    required this.fetchLinks,
    required this.edgeColor,
  });

  @override
  State<_NodeDetailSheet> createState() => _NodeDetailSheetState();
}

class _NodeDetailSheetState extends State<_NodeDetailSheet> {
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);
  static const Color _green = Color(0xFF7ED957);

  List<_ResourceLink>? _links;
  bool _loadingLinks = true;

  static const Map<String, IconData> _sourceIcons = {
    'Wikipedia': Icons.menu_book_rounded,
    'YouTube': Icons.play_circle_fill_rounded,
    'Khan Academy': Icons.school_rounded,
    'Investopedia': Icons.trending_up_rounded,
    'Google Scholar': Icons.science_rounded,
    'DuckDuckGo': Icons.travel_explore_rounded,
  };
  static const Map<String, Color> _sourceColors = {
    'Wikipedia': Color(0xFF6366F1),
    'YouTube': Color(0xFFEF4444),
    'Khan Academy': Color(0xFF10B981),
    'Investopedia': Color(0xFF0EA5E9),
    'Google Scholar': Color(0xFF8B5CF6),
    'DuckDuckGo': Color(0xFFDE5833),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final links = await widget.fetchLinks(widget.node.label);
      if (mounted)
        setState(() {
          _links = links;
          _loadingLinks = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _links = [];
          _loadingLinks = false;
        });
    }
  }

  Future<void> _launch(String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // fallback — try platform default
      try {
        await launchUrl(Uri.parse(url));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Could not open link: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final color = widget.edgeColor;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),

            // Node header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: node.depth == 0 ? _green : color.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    node.depth == 0
                        ? Icons.hub_rounded
                        : node.depth == 1
                        ? Icons.circle_outlined
                        : Icons.fiber_manual_record,
                    color: node.depth == 0 ? Colors.white : color,
                    size: node.depth == 2 ? 14 : 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    node.label,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                ),
              ],
            ),

            // Detail text
            if (node.detail.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.15)),
                ),
                child: Text(
                  node.detail,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: _textGray,
                    height: 1.65,
                  ),
                ),
              ),
            ],

            // Subtopics chips
            if (node.children.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'SUBTOPICS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade400,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: node.children
                    .map(
                      (c) => GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          // slight delay so sheet closes first
                          Future.delayed(const Duration(milliseconds: 200));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            c.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],

            // Resources section
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'LEARN MORE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade400,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 8),
                if (_loadingLinks)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            if (_loadingLinks)
              ..._shimmerLinks()
            else if (_links == null || _links!.isEmpty)
              Text(
                'No links found.',
                style: TextStyle(color: _textGray, fontSize: 13),
              )
            else
              ..._links!.map((link) => _linkTile(link)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _linkTile(_ResourceLink link) {
    final icon = _sourceIcons[link.source] ?? Icons.link_rounded;
    final color = _sourceColors[link.source] ?? const Color(0xFF6366F1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _launch(link.url),
          borderRadius: BorderRadius.circular(14),
          splashColor: color.withOpacity(0.08),
          highlightColor: color.withOpacity(0.04),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textDark,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text(
                            link.source,
                            style: TextStyle(
                              fontSize: 11,
                              color: color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· ${link.subtitle}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Shimmer placeholder while loading
  List<Widget> _shimmerLinks() => List.generate(
    3,
    (i) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      height: 62,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  );
}

// Flow chart model

class _FlowChart {
  final String title;
  final List<FlowNode> nodes;
  const _FlowChart({required this.title, required this.nodes});
}

// Grid background

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.07)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
// Mind map painter

class _MindMapPainter extends CustomPainter {
  final MindMapNode root;
  final MindMapNode? selectedNode;

  static const double _rootR = 60.0;
  static const double _branchR = 48.0;
  static const double _leafR = 36.0;

  const _MindMapPainter({required this.root, this.selectedNode});

  @override
  void paint(Canvas canvas, Size size) {
    _drawEdges(canvas, root);
    _drawNodes(canvas, root);
  }

  void _drawEdges(Canvas canvas, MindMapNode node) {
    for (final child in node.children) {
      final paint = Paint()
        ..color = _edgeColor(node.depth).withOpacity(0.38)
        ..strokeWidth = node.depth == 0 ? 3.0 : 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      path.moveTo(node.position.dx, node.position.dy);
      final mx = (node.position.dx + child.position.dx) / 2;
      path.cubicTo(
        mx,
        node.position.dy,
        mx,
        child.position.dy,
        child.position.dx,
        child.position.dy,
      );
      canvas.drawPath(path, paint);
      _drawEdges(canvas, child);
    }
  }

  void _drawNodes(Canvas canvas, MindMapNode node) {
    final r = node.depth == 0
        ? _rootR
        : node.depth == 1
        ? _branchR
        : _leafR;
    final isSelected = selectedNode?.id == node.id;

    // Glow when selected
    if (isSelected) {
      canvas.drawCircle(
        node.position,
        r + 10,
        Paint()..color = _edgeColor(node.depth).withOpacity(0.18),
      );
    }

    // Shadow
    canvas.drawCircle(
      node.position + const Offset(0, 4),
      r,
      Paint()
        ..color = Colors.black.withOpacity(0.09)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Fill
    canvas.drawCircle(
      node.position,
      r,
      Paint()..color = _nodeColor(node.depth),
    );

    // Border
    canvas.drawCircle(
      node.position,
      r,
      Paint()
        ..color = _edgeColor(node.depth).withOpacity(isSelected ? 1.0 : 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3.5 : 2.0,
    );

    // Text
    _drawText(canvas, node.label, node.position, r, node.depth);

    for (final child in node.children) {
      _drawNodes(canvas, child);
    }
  }

  void _drawText(
    Canvas canvas,
    String label,
    Offset center,
    double radius,
    int depth,
  ) {
    final textColor = depth == 0 ? Colors.white : _edgeColor(depth);
    final fontSize = depth == 0
        ? 13.5
        : depth == 1
        ? 11.5
        : 10.0;
    final maxWidth = (radius * 1.55).clamp(55.0, 100.0);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: depth == 0 ? FontWeight.w800 : FontWeight.w700,
          height: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 4,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);

    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
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
  bool shouldRepaint(_MindMapPainter old) =>
      old.root != root || old.selectedNode?.id != selectedNode?.id;
}
