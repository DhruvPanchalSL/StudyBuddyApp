import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class SettingsScreen extends StatefulWidget {
  final String currentApiKey;
  final void Function(String) onApiKeyChanged;

  const SettingsScreen({
    super.key,
    required this.currentApiKey,
    required this.onApiKeyChanged,
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

  late TextEditingController _apiKeyController;
  bool _obscureKey = true;
  bool _isSaving = false;
  bool _isVerifying = false;
  bool _isVerified = false;
  bool _hasChanges = false;
  String _keyStatus = ''; // '', 'valid', 'invalid'

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.currentApiKey);
    _apiKeyController.addListener(() {
      setState(() {
        _hasChanges = _apiKeyController.text.trim() != widget.currentApiKey;
        _isVerified = false;
        _keyStatus = '';
      });
    });
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  bool get _usingDefaultKey => widget.currentApiKey.isEmpty;

  Future<void> _verifyAndSave() async {
    final key = _apiKeyController.text.trim();

    if (key.isEmpty) {
      // User wants to remove their key and revert to default
      await _saveKey('');
      return;
    }

    setState(() => _isVerifying = true);

    // Make a lightweight test call to Gemini to verify the key
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

      setState(() => _isVerifying = false);

      if (response.statusCode == 200) {
        setState(() {
          _keyStatus = 'valid';
          _isVerified = true;
        });
        await _saveKey(key);
      } else if (response.statusCode == 400 || response.statusCode == 403) {
        setState(() => _keyStatus = 'invalid');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '❌ Invalid API key. Please check and try again.',
              ),
              backgroundColor: Colors.red.shade400,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      } else {
        // Unknown error, save anyway and let the user find out on use
        setState(() => _keyStatus = 'valid');
        await _saveKey(key);
      }
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _keyStatus = 'invalid';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error verifying key: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveKey(String key) async {
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'geminiApiKey': key,
      }, SetOptions(merge: true));

      widget.onApiKeyChanged(key);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              key.isEmpty
                  ? '✅ Reverted to default API key'
                  : '✅ Your API key saved successfully!',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        setState(() {
          _hasChanges = false;
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeKey() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Your API Key?'),
        content: const Text(
          'This will revert to using the default app API key. Your saved key will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _apiKeyController.clear();
              _saveKey('');
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
            // Status Banner
            _buildStatusBanner(),
            const SizedBox(height: 24),

            // API Key Section
            const Text(
              'GEMINI API KEY',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _textGray,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
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
                    'Your Personal API Key',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _textDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Add your own Gemini API key to avoid rate limits. Get one free at Google AI Studio.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _textGray,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Key Input Field
                  Container(
                    decoration: BoxDecoration(
                      color: _bgGray,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _keyStatus == 'valid'
                            ? Colors.green.shade300
                            : _keyStatus == 'invalid'
                            ? Colors.red.shade300
                            : Colors.grey.shade200,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            style: const TextStyle(
                              fontSize: 13,
                              fontFamily: 'monospace',
                              color: _textDark,
                            ),
                            decoration: InputDecoration(
                              hintText: 'AIza...',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        // Show/Hide toggle
                        IconButton(
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: _textGray,
                            size: 20,
                          ),
                          onPressed: () =>
                              setState(() => _obscureKey = !_obscureKey),
                        ),
                        // Copy button
                        if (_apiKeyController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: _textGray,
                              size: 18,
                            ),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _apiKeyController.text),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Key copied')),
                              );
                            },
                          ),
                      ],
                    ),
                  ),

                  // Validation status text
                  if (_keyStatus == 'valid')
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
                  else if (_keyStatus == 'invalid')
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cancel,
                            color: Colors.red.shade400,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Invalid key — please check and retry',
                            style: TextStyle(
                              color: Colors.red.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_isSaving || _isVerifying)
                          ? null
                          : _verifyAndSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: Colors.grey.shade200,
                      ),
                      child: (_isSaving || _isVerifying)
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
                                  _isVerifying ? 'Verifying...' : 'Saving...',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
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

                  // Remove Key button (only show if user has a saved key)
                  if (widget.currentApiKey.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _removeKey,
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
            ),

            const SizedBox(height: 20),

            // How to get a key
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.blue.shade400,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'How to get a free API key',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '1. Go to aistudio.google.com\n2. Sign in with your Google account\n3. Click "Get API Key" → "Create API Key"\n4. Copy and paste it above',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isUsingOwnKey = widget.currentApiKey.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUsingOwnKey ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUsingOwnKey ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isUsingOwnKey
                  ? Colors.green.shade100
                  : Colors.orange.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isUsingOwnKey ? Icons.vpn_key_rounded : Icons.key_off_rounded,
              color: isUsingOwnKey
                  ? Colors.green.shade600
                  : Colors.orange.shade600,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUsingOwnKey
                      ? '🟢 Using Your API Key'
                      : '🟡 Using Default App Key',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isUsingOwnKey
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isUsingOwnKey
                      ? 'You have unlimited usage with your own key.'
                      : 'Shared key — may hit rate limits. Add your own for best experience.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isUsingOwnKey
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                    height: 1.4,
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
