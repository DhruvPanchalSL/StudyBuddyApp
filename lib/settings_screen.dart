import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class SettingsScreen extends StatefulWidget {
  final String currentGeminiKey;
  final String currentGroqKey;
  final void Function(String) onGeminiKeyChanged;
  final void Function(String) onGroqKeyChanged;

  const SettingsScreen({
    super.key,
    required this.currentGeminiKey,
    required this.currentGroqKey,
    required this.onGeminiKeyChanged,
    required this.onGroqKeyChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const Color _green = Color(0xFF7ED957);
  static const Color _textDark = Color(0xFF1A1A2E);
  static const Color _textGray = Color(0xFF8E8E93);
  static const Color _bgGray = Color(0xFFF5F5F7);
  static const Color _cardWhite = Colors.white;

  // ── Gemini key state ───────────────────────────────────────────────────────
  late TextEditingController _geminiController;
  bool _obscureGemini = true;
  bool _isSavingGemini = false;
  bool _isVerifyingGemini = false;
  String _geminiStatus = ''; // '', 'valid', 'invalid'

  // ── Groq key state ─────────────────────────────────────────────────────────
  late TextEditingController _groqController;
  bool _obscureGroq = true;
  bool _isSavingGroq = false;
  bool _isVerifyingGroq = false;
  String _groqStatus = ''; // '', 'valid', 'invalid'

  @override
  void initState() {
    super.initState();
    _geminiController = TextEditingController(text: widget.currentGeminiKey);
    _geminiController.addListener(() {
      setState(() => _geminiStatus = '');
    });

    _groqController = TextEditingController(text: widget.currentGroqKey);
    _groqController.addListener(() {
      setState(() => _groqStatus = '');
    });
  }

  @override
  void dispose() {
    _geminiController.dispose();
    _groqController.dispose();
    super.dispose();
  }

  // ── Gemini verify & save ───────────────────────────────────────────────────
  Future<void> _verifyAndSaveGemini() async {
    final key = _geminiController.text.trim();
    if (key.isEmpty) {
      await _saveGeminiKey('');
      return;
    }

    setState(() => _isVerifyingGemini = true);
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$key',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": "Say OK"},
              ],
            },
          ],
          "generationConfig": {"maxOutputTokens": 5},
        }),
      );

      setState(() => _isVerifyingGemini = false);

      if (response.statusCode == 200) {
        setState(() => _geminiStatus = 'valid');
        await _saveGeminiKey(key);
      } else if (response.statusCode == 400 || response.statusCode == 403) {
        setState(() => _geminiStatus = 'invalid');
        if (mounted) {
          _showSnackBar(
            '❌ Invalid Gemini key. Please check and try again.',
            Colors.red.shade400,
          );
        }
      } else {
        setState(() => _geminiStatus = 'valid');
        await _saveGeminiKey(key);
      }
    } catch (e) {
      setState(() {
        _isVerifyingGemini = false;
        _geminiStatus = 'invalid';
      });
      if (mounted) _showSnackBar('Error verifying Gemini key: $e', Colors.red);
    }
  }

  Future<void> _saveGeminiKey(String key) async {
    setState(() => _isSavingGemini = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'geminiApiKey': key,
      }, SetOptions(merge: true));
      widget.onGeminiKeyChanged(key);
      if (mounted) {
        _showSnackBar(
          key.isEmpty
              ? '✅ Gemini key removed — using app default'
              : '✅ Gemini key saved!',
          Colors.green,
        );
        setState(() => _isSavingGemini = false);
      }
    } catch (e) {
      setState(() => _isSavingGemini = false);
      if (mounted) _showSnackBar('Error saving: $e', Colors.red);
    }
  }

  // ── Groq verify & save ─────────────────────────────────────────────────────
  Future<void> _verifyAndSaveGroq() async {
    final key = _groqController.text.trim();
    if (key.isEmpty) {
      await _saveGroqKey('');
      return;
    }

    setState(() => _isVerifyingGroq = true);
    try {
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $key',
        },
        body: jsonEncode({
          "model": "llama-3.3-70b-versatile",
          "messages": [
            {"role": "user", "content": "Say OK"},
          ],
          "max_tokens": 5,
        }),
      );

      setState(() => _isVerifyingGroq = false);

      if (response.statusCode == 200) {
        setState(() => _groqStatus = 'valid');
        await _saveGroqKey(key);
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        setState(() => _groqStatus = 'invalid');
        if (mounted) {
          _showSnackBar(
            '❌ Invalid Groq key. Please check and try again.',
            Colors.red.shade400,
          );
        }
      } else {
        // save anyway on unknown errors
        setState(() => _groqStatus = 'valid');
        await _saveGroqKey(key);
      }
    } catch (e) {
      setState(() {
        _isVerifyingGroq = false;
        _groqStatus = 'invalid';
      });
      if (mounted) _showSnackBar('Error verifying Groq key: $e', Colors.red);
    }
  }

  Future<void> _saveGroqKey(String key) async {
    setState(() => _isSavingGroq = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'groqApiKey': key,
      }, SetOptions(merge: true));
      widget.onGroqKeyChanged(key);
      if (mounted) {
        _showSnackBar(
          key.isEmpty
              ? '✅ Groq key removed — using app default'
              : '✅ Groq key saved!',
          Colors.green,
        );
        setState(() => _isSavingGroq = false);
      }
    } catch (e) {
      setState(() => _isSavingGroq = false);
      if (mounted) _showSnackBar('Error saving: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _removeGeminiKey() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Gemini Key?'),
        content: const Text(
          'This will revert to using the default app Gemini key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _geminiController.clear();
              _saveGeminiKey('');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _removeGroqKey() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Groq Key?'),
        content: const Text(
          'This will revert to using the default app Groq fallback key.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _groqController.clear();
              _saveGroqKey('');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_rounded,
            color: _textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: _textDark,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status Banner ──────────────────────────────────────────────
            _buildStatusBanner(),
            const SizedBox(height: 24),

            // ── How the fallback works ─────────────────────────────────────
            _buildFallbackInfoCard(),
            const SizedBox(height: 24),

            // ── Gemini Key Section ─────────────────────────────────────────
            const Text(
              'GEMINI API KEY  (Primary)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _textGray,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildKeyCard(
              icon: Icons.auto_awesome_rounded,
              iconColor: const Color(0xFF6366F1),
              title: 'Your Gemini Key',
              subtitle:
                  'Add your own Gemini key to use it first. Get one free at aistudio.google.com.',
              controller: _geminiController,
              obscure: _obscureGemini,
              onObscureToggle: () =>
                  setState(() => _obscureGemini = !_obscureGemini),
              status: _geminiStatus,
              isSaving: _isSavingGemini,
              isVerifying: _isVerifyingGemini,
              onSave: _verifyAndSaveGemini,
              onRemove: widget.currentGeminiKey.isNotEmpty
                  ? _removeGeminiKey
                  : null,
              hintText: 'AIza...',
            ),
            const SizedBox(height: 8),
            _buildHowToCard(
              title: 'How to get a free Gemini key',
              steps:
                  '1. Go to aistudio.google.com\n2. Sign in with Google\n3. Click "Get API Key" → "Create API Key"\n4. Copy and paste it above',
              color: Colors.blue,
            ),
            const SizedBox(height: 24),

            // ── Groq Key Section ───────────────────────────────────────────
            const Text(
              'GROQ API KEY  (Fallback)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _textGray,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _buildKeyCard(
              icon: Icons.flash_on_rounded,
              iconColor: Colors.orange.shade600,
              title: 'Your Groq Key',
              subtitle:
                  'Used automatically when Gemini hits rate limits. Get one free at console.groq.com.',
              controller: _groqController,
              obscure: _obscureGroq,
              onObscureToggle: () =>
                  setState(() => _obscureGroq = !_obscureGroq),
              status: _groqStatus,
              isSaving: _isSavingGroq,
              isVerifying: _isVerifyingGroq,
              onSave: _verifyAndSaveGroq,
              onRemove: widget.currentGroqKey.isNotEmpty
                  ? _removeGroqKey
                  : null,
              hintText: 'gsk_...',
            ),
            const SizedBox(height: 8),
            _buildHowToCard(
              title: 'How to get a free Groq key',
              steps:
                  '1. Go to console.groq.com\n2. Sign up / Sign in\n3. Click "API Keys" → "Create API Key"\n4. Copy and paste it above',
              color: Colors.orange,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final hasGemini = widget.currentGeminiKey.isNotEmpty;
    final hasGroq = widget.currentGroqKey.isNotEmpty;

    String statusText;
    Color bannerColor;
    Color borderColor;
    Color iconColor;
    IconData bannerIcon;

    if (hasGemini && hasGroq) {
      statusText = '🟢 Fully configured — Gemini primary, Groq fallback';
      bannerColor = Colors.green.shade50;
      borderColor = Colors.green.shade200;
      iconColor = Colors.green.shade600;
      bannerIcon = Icons.verified_rounded;
    } else if (hasGemini) {
      statusText = '🟡 Gemini key set. Add a Groq key for fallback protection.';
      bannerColor = Colors.blue.shade50;
      borderColor = Colors.blue.shade200;
      iconColor = Colors.blue.shade600;
      bannerIcon = Icons.vpn_key_rounded;
    } else if (hasGroq) {
      statusText = '🟡 Groq key set. Add a Gemini key to use it as primary.';
      bannerColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      iconColor = Colors.orange.shade600;
      bannerIcon = Icons.flash_on_rounded;
    } else {
      statusText =
          '🔴 Using app default keys only — may hit rate limits faster.';
      bannerColor = Colors.red.shade50;
      borderColor = Colors.red.shade200;
      iconColor = Colors.red.shade600;
      bannerIcon = Icons.key_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(bannerIcon, color: iconColor, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              statusText,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: _textDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.purple.shade400,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How AI fallback works',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.purple.shade700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '1️⃣  Your Gemini key is tried first\n'
                  '2️⃣  If not set, the app\'s Gemini key is used\n'
                  '3️⃣  If Gemini hits a rate limit (429), Groq kicks in automatically\n'
                  '4️⃣  Your Groq key is tried first, then the app\'s Groq key',
                  style: TextStyle(
                    color: Colors.purple.shade700,
                    fontSize: 12,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onObscureToggle,
    required String status,
    required bool isSaving,
    required bool isVerifying,
    required VoidCallback onSave,
    required VoidCallback? onRemove,
    required String hintText,
  }) {
    return Container(
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, color: _textGray, height: 1.5),
          ),
          const SizedBox(height: 16),

          // Input field
          Container(
            decoration: BoxDecoration(
              color: _bgGray,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: status == 'valid'
                    ? Colors.green.shade300
                    : status == 'invalid'
                    ? Colors.red.shade300
                    : Colors.grey.shade200,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    obscureText: obscure,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: _textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _textGray,
                    size: 20,
                  ),
                  onPressed: onObscureToggle,
                ),
                if (controller.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.copy_rounded,
                      color: _textGray,
                      size: 18,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: controller.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Key copied'),
                          backgroundColor: Colors.grey.shade600,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // Status text
          if (status == 'valid')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade500,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Key verified successfully',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            )
          else if (status == 'invalid')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.cancel, color: Colors.red.shade400, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Invalid key — please check and retry',
                    style: TextStyle(color: Colors.red.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Save button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isSaving || isVerifying) ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                disabledBackgroundColor: Colors.grey.shade200,
              ),
              child: (isSaving || isVerifying)
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isVerifying ? 'Verifying...' : 'Saving...',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  : const Text(
                      'Verify & Save Key',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),

          // Remove button
          if (onRemove != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onRemove,
                child: Text(
                  'Remove My Key (use default)',
                  style: TextStyle(
                    color: Colors.red.shade400,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHowToCard({
    required String title,
    required String steps,
    required MaterialColor color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color.shade400, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color.shade700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  steps,
                  style: TextStyle(
                    color: color.shade700,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
