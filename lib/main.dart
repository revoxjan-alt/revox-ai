import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() => runApp(const RevoxApp());

class RevoxApp extends StatelessWidget {
  const RevoxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Revox AI',
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const Root(),
      );
}

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
}

class Msg {
  final bool user;
  final String text;
  final bool error;
  Msg(this.user, this.text, {this.error = false});
  Map<String, dynamic> toJson() => {'u': user, 't': text};
}

// ---------------- Root ----------------
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  String _key = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _key = p.getString('gemini_key') ?? '';
      _ready = true;
    });
  }

  Future<void> _saveKey(String k) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('gemini_key', k.trim());
    setState(() => _key = k.trim());
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_key.isEmpty) return KeyScreen(onSave: _saveKey);
    return ChatScreen(apiKey: _key, onKeyChanged: _saveKey);
  }
}

// ---------------- API key ekrani ----------------
class KeyScreen extends StatefulWidget {
  final Future<void> Function(String) onSave;
  const KeyScreen({super.key, required this.onSave});
  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends State<KeyScreen> {
  final _c = TextEditingController();
  bool _empty = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome,
                    size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 12),
                const Text('Revox AI',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text(
                  'Boshlash uchun Gemini API key kiriting.\n'
                  'Uni aistudio.google.com/apikey saytidan bepul olasiz.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _c,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Gemini API key',
                    border: const OutlineInputBorder(),
                    errorText: _empty ? 'API key kiriting' : null,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (_c.text.trim().isEmpty) {
                        setState(() => _empty = true);
                        return;
                      }
                      widget.onSave(_c.text);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Boshlash', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Chat ekrani ----------------
class ChatScreen extends StatefulWidget {
  final String apiKey;
  final Future<void> Function(String) onKeyChanged;
  const ChatScreen({super.key, required this.apiKey, required this.onKeyChanged});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const _sys =
      "Sening isming Revox AI. Sen aqlli, samimiy va foydali sun'iy intellekt yordamchisan. "
      "Foydalanuvchi qaysi tilda va qaysi yozuvda (lotin yoki kirill) yozsa, shu tilda va shu yozuvda javob ber; "
      "odatda o'zbek tilida (lotin yozuvida) gapir. Aniq, tushunarli va to'g'ri javob ber. "
      "Qisqa savolga qisqa, murakkab savolga batafsil javob ber. Kod so'ralsa, kodni to'liq yoz. "
      "Markdown belgilarini (**, ##, ``` kabi) ishlatma, oddiy matn yoz; ro'yxat kerak bo'lsa 1., 2., 3. deb raqamla. "
      "Bilmasang, bilmayman deb ayt, to'qima.";

  final _c = TextEditingController();
  final _scroll = ScrollController();
  final _stt = SpeechToText();
  final List<Msg> _msgs = [];
  bool _loading = false;
  bool _sttReady = false;
  String? _locale;

  @override
  void initState() {
    super.initState();
    _loadChat();
  }

  Future<void> _loadChat() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('chat');
    if (s != null) {
      try {
        final l = jsonDecode(s) as List;
        setState(() {
          for (final e in l) {
            _msgs.add(Msg(e['u'] as bool, e['t'] as String));
          }
        });
        _scrollDown();
      } catch (_) {}
    }
  }

  Future<void> _saveChat() async {
    final p = await SharedPreferences.getInstance();
    final l = _msgs.where((m) => !m.error).toList();
    final keep = l.length > 100 ? l.sublist(l.length - 100) : l;
    await p.setString('chat', jsonEncode(keep.map((m) => m.toJson()).toList()));
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
