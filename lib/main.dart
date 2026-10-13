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
      }
    });
  }

  void _snack(String t) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), duration: const Duration(seconds: 2)));
  }

  // ---------- Yuborish ----------
  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty || _loading) return;
    if (_stt.isListening) await _stt.stop();
    _c.clear();
    setState(() {
      _msgs.removeWhere((m) => m.error);
      _msgs.add(Msg(true, t));
      _loading = true;
    });
    _scrollDown();
    try {
      final ans = await _ask();
      setState(() => _msgs.add(Msg(false, ans)));
      _saveChat();
    } on ApiError catch (e) {
      _fail(t, e.message);
    } on TimeoutException {
      _fail(t, "internetga ulanib bo'lmadi");
    } on IOException {
      _fail(t, "internetga ulanib bo'lmadi");
    } on http.ClientException {
      _fail(t, "internetga ulanib bo'lmadi");
    } catch (_) {
      _fail(t, "Xatolik yuz berdi. Qayta urinib ko'ring.");
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollDown();
    }
  }

  void _fail(String userText, String message) {
    if (!mounted) return;
    setState(() {
      if (_msgs.isNotEmpty && _msgs.last.user) _msgs.removeLast();
      _c.text = userText;
      _msgs.add(Msg(false, message, error: true));
    });
  }

  Future<String> _ask() async {
    var recent = _msgs.where((m) => !m.error).toList();
    if (recent.length > 30) recent = recent.sublist(recent.length - 30);
    while (recent.isNotEmpty && !recent.first.user) {
      recent.removeAt(0);
    }
    final contents = recent
        .map((m) => {
              'role': m.user ? 'user' : 'model',
              'parts': [
                {'text': m.text}
              ]
            })
        .toList();

    final r = await http
        .post(
          Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${widget.apiKey}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': _sys}
              ]
            },
            'contents': contents,
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (r.statusCode == 400 || r.statusCode == 401 || r.statusCode == 403) {
      throw ApiError("API key noto'g'ri yoki ruxsat yo'q. Tepadagi ⚙️ dan keyni tekshiring.");
    }
    if (r.statusCode == 429) {
      throw ApiError("So'rovlar limiti tugadi. Birozdan keyin urinib ko'ring.");
    }
    if (r.statusCode >= 500) {
      throw ApiError("Server band. Birozdan keyin urinib ko'ring.");
    }
    if (r.statusCode != 200) {
      throw ApiError('Xatolik (${r.statusCode}). Qayta urinib ko\'ring.');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final cands = j['candidates'] as List?;
    if (cands == null || cands.isEmpty) {
      throw ApiError("Javob olinmadi. Savolni boshqacha yozib ko'ring.");
    }
    final parts = cands[0]['content']?['parts'] as List?;
    final text = (parts ?? []).map((p) => p['text'] ?? '').join().trim();
    if (text.isEmpty) {
      throw ApiError("Javob olinmadi. Savolni boshqacha yozib ko'ring.");
    }
    return text;
  }

  // ---------- Mikrofon ----------
  Future<void> _mic() async {
    if (!_sttReady) {
      _sttReady = await _stt.initialize(
        onStatus: (s) {
          if (mounted) setState(() {});
        },
        onError: (e) {
          if (mounted) setState(() {});
        },
      );
      if (_sttReady) {
        final locs = await _stt.locales();
        for (final l in locs) {
          if (l.localeId.toLowerCase().startsWith('uz')) {
            _locale = l.localeId;
            break;
          }
        }
      }
    }
    if (!_sttReady) {
      _snack("Mikrofon ruxsati yo'q yoki ovoz xizmati topilmadi.");
      return;
    }
    if (_stt.isListening) {
      await _stt.stop();
      setState(() {});
      return;
    }
    final base = _c.text.trim();
    await _stt.listen(
      onResult: (r) {
        setState(() {
          _c.text = base.isEmpty ? r.recognizedWords : '$base ${r.recognizedWords}';
          _c.selection = TextSelection.collapsed(offset: _c.text.length);
        });
      },
      localeId: _locale,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(partialResults: true),
    );
    setState(() {});
  }

  // ---------- Sozlamalar / yangi suhbat ----------
  Future<void> _settings() async {
    final kc = TextEditingController(text: widget.apiKey);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sozlamalar'),
        content: TextField(
          controller: kc,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Gemini API key'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Bekor')),
          FilledButton(
            onPressed: () {
              if (kc.text.trim().isNotEmpty) widget.onKeyChanged(kc.text);
              Navigator.pop(ctx);
            },
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
  }

  Future<void> _newChat() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yangi suhbat'),
        content: const Text("Eski suhbat o'chiriladi. Davom etasizmi?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Yo'q")),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Ha')),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _msgs.clear());
      _saveChat();
    }
  }

  @override
  void dispose() {
    _stt.cancel();
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---------- UI ----------
  Widget _bubble(Msg m) {
    final cs = Theme.of(context).colorScheme;
    final bg = m.error
        ? cs.errorContainer
        : (m.user ? cs.primaryContainer : cs.surfaceContainerHighest);
    return Align(
      alignment: m.user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: m.text));
          _snack('Nusxalandi');
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Text(
            m.text,
            style: TextStyle(
                fontSize: 16, color: m.error ? cs.onErrorContainer : null),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _msgs.length + (_loading ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Revox AI'),
        actions: [
          IconButton(
              tooltip: 'Yangi suhbat',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _newChat),
          IconButton(
              tooltip: 'Sozlamalar',
              icon: const Icon(Icons.settings),
              onPressed: _settings),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _msgs.isEmpty && !_loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 64, color: cs.primary),
                          const SizedBox(height: 12),
                          const Text('Salom! Men Revox AI.',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          const Text('Nima haqida gaplashamiz?'),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: count,
                    itemBuilder: (_, i) {
                      if (i >= _msgs.length) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(16)),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 10),
                                Text("Revox AI o'ylamoqda..."),
                              ],
                            ),
                          ),
                        );
                      }
                      return _bubble(_msgs[i]);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _c,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Xabar yozing...',
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_stt.isListening ? Icons.mic : Icons.mic_none,
                        color: _stt.isListening ? Colors.redAccent : null),
                    onPressed: _mic,
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _loading ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
