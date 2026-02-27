import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// ─── КОНФИГ ──────────────────────────────────────────────────────────────────
const supabaseUrl = 'https://ilszhdmqxsoixcefeoqa.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlsc3poZG1xeHNvaXhjZWZlb3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2NjA4NDMsImV4cCI6MjA3NjIzNjg0M30.aJF9c3RaNvAk4_9nLYhQABH3pmYUcZ0q2udf2LoA6Sc';

// ─── ЦВЕТА ───────────────────────────────────────────────────────────────────
class C {
  static const bg       = Color(0xFF0A0A0F);
  static const surface  = Color(0xFF141420);
  static const card     = Color(0xFF1C1C2E);
  static const accent   = Color(0xFF6C63FF);
  static const accent2  = Color(0xFF00D4AA);
  static const myMsg    = Color(0xFF3D3580);
  static const otherMsg = Color(0xFF252540);
  static const text     = Color(0xFFEEEEFF);
  static const hint     = Color(0xFF7070A0);
  static const divider  = Color(0xFF252535);
}

// ─── ШИФРОВАНИЕ (XOR + base64, без внешних пакетов) ─────────────────────────
String _encrypt(String text, String key) {
  if (key.isEmpty) return text;
  final textBytes = utf8.encode(text);
  final keyBytes  = utf8.encode(key);
  final result    = List<int>.generate(
    textBytes.length,
    (i) => textBytes[i] ^ keyBytes[i % keyBytes.length],
  );
  return base64.encode(result);
}

String _decrypt(String text, String key) {
  if (key.isEmpty) return text;
  try {
    final bytes    = base64.decode(text);
    final keyBytes = utf8.encode(key);
    final result   = List<int>.generate(
      bytes.length,
      (i) => bytes[i] ^ keyBytes[i % keyBytes.length],
    );
    return utf8.decode(result);
  } catch (_) {
    return text; // если не удалось — показываем как есть
  }
}

// ─── УТИЛИТЫ ─────────────────────────────────────────────────────────────────
Color _avatarColor(String name) =>
    Colors.primaries[name.hashCode.abs() % Colors.primaries.length];

// ─── ТОЧКА ВХОДА ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:           Colors.transparent,
    statusBarIconBrightness:  Brightness.light,
    systemNavigationBarColor: C.bg,
  ));
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const MeowApp());
}

// ─── APP ─────────────────────────────────────────────────────────────────────
class MeowApp extends StatelessWidget {
  const MeowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                      'Meow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: C.bg,
        primaryColor:            C.accent,
        colorScheme: const ColorScheme.dark(
          primary:   C.accent,
          secondary: C.accent2,
          surface:   C.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: C.bg,
          elevation:       0,
          titleTextStyle: TextStyle(
            color:         C.text,
            fontSize:      20,
            fontWeight:    FontWeight.w700,
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: C.text),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled:    true,
          fillColor: C.card,
          hintStyle: const TextStyle(color: C.hint),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide:   BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14,
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ─── ГЛАВНЫЙ ЭКРАН ───────────────────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String       _nick  = 'User';
  List<String> _chats = []; // формат: "chatId:encKey"

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nick  = prefs.getString('nickname') ?? 'User';
      _chats = prefs.getStringList('chats') ?? [];
    });
  }

  Future<void> _saveChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('chats', _chats);
  }

  Future<void> _saveNick(String nick) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nickname', nick);
  }

  void _showNickDialog() {
    final ctrl = TextEditingController(text: _nick);
    showModalBottomSheet(
      context:            context,
      backgroundColor:    C.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Изменить имя', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: C.text,
            )),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus:  true,
              style:      const TextStyle(color: C.text),
              decoration: const InputDecoration(hintText: 'Твоё имя'),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  final nick = ctrl.text.trim();
                  if (nick.isEmpty) return;
                  await _saveNick(nick);
                  setState(() => _nick = nick);
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text('Сохранить', style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white,
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddChat() {
    final idCtrl  = TextEditingController();
    final keyCtrl = TextEditingController();
    showModalBottomSheet(
      context:            context,
      backgroundColor:    C.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Новый чат', style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: C.text,
            )),
            const SizedBox(height: 8),
            const Text(
              'ID чата должен совпадать у обоих собеседников',
              style: TextStyle(color: C.hint, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: idCtrl,
              autofocus:  true,
              style:      const TextStyle(color: C.text),
              decoration: const InputDecoration(hintText: 'ID чата (chat_key)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: keyCtrl,
              style:      const TextStyle(color: C.text),
              decoration: const InputDecoration(
                hintText: 'Ключ шифрования (необязательно)',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  final id = idCtrl.text.trim();
                  if (id.isEmpty) return;
                  final entry = '$id:${keyCtrl.text.trim()}';
                  if (!_chats.contains(entry)) {
                    _chats.add(entry);
                    await _saveChats();
                    setState(() {});
                  }
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: C.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text('Добавить', style: TextStyle(
                  fontWeight: FontWeight.w700, color: Colors.white,
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteChat(int index) async {
    _chats.removeAt(index);
    await _saveChats();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meow'),
        actions: [
          GestureDetector(
            onTap: _showNickDialog,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius:          18,
                backgroundColor: _avatarColor(_nick).withOpacity(0.25),
                child: Text(
                  _nick[0].toUpperCase(),
                  style: TextStyle(
                    color:      _avatarColor(_nick),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: C.surface,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              currentAccountPicture: CircleAvatar(
                backgroundColor: _avatarColor(_nick),
                child: Text(
                  _nick[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 24, color: Colors.white, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              accountName:  Text(_nick, style: const TextStyle(fontWeight: FontWeight.w700)),
              accountEmail: const Text(
                '🔒 Шифрование E2EE активно',
                style: TextStyle(color: C.accent2, fontSize: 12),
              ),
              decoration: const BoxDecoration(color: C.card),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: C.accent),
              title:   const Text('Изменить имя', style: TextStyle(color: C.text)),
              onTap: () {
                Navigator.pop(context);
                _showNickDialog();
              },
            ),
            const Divider(color: C.divider, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title:   const Text('Очистить все чаты',
                style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('chats');
                setState(() => _chats = []);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: _chats.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline,
                    size: 64, color: C.hint.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  const Text('Нет чатов',
                    style: TextStyle(color: C.hint, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text('Нажми + чтобы добавить чат по ID',
                    style: TextStyle(color: C.hint, fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              padding:     const EdgeInsets.symmetric(vertical: 8),
              itemCount:   _chats.length,
              separatorBuilder: (_, __) => const Divider(
                color: C.divider, height: 1, indent: 72,
              ),
              itemBuilder: (_, i) {
                final parts  = _chats[i].split(':');
                final chatId = parts[0];
                final encKey = parts.length > 1 ? parts[1] : '';
                return Dismissible(
                  key:       Key(_chats[i]),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) => _deleteChat(i),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding:   const EdgeInsets.only(right: 20),
                    color:     Colors.red.withOpacity(0.8),
                    child:     const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: chatId,
                          encKey: encKey,
                          myNick: _nick,
                        ),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4,
                    ),
                    leading: CircleAvatar(
                      radius:          26,
                      backgroundColor: _avatarColor(chatId).withOpacity(0.2),
                      child: Text(
                        chatId[0].toUpperCase(),
                        style: TextStyle(
                          color:      _avatarColor(chatId),
                          fontWeight: FontWeight.w700,
                          fontSize:   18,
                        ),
                      ),
                    ),
                    title: Text(chatId, style: const TextStyle(
                      color: C.text, fontWeight: FontWeight.w600,
                    )),
                    subtitle: Text(
                      encKey.isNotEmpty ? '🔒 Зашифрован' : '🔓 Без шифрования',
                      style: TextStyle(
                        color:    encKey.isNotEmpty ? C.accent2 : C.hint,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: C.hint),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed:       _showAddChat,
        backgroundColor: C.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ─── ЭКРАН ЧАТА ──────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String encKey;
  final String myNick;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.encKey,
    required this.myNick,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl      = TextEditingController();
  final _supabase  = Supabase.instance.client;
  final _scroll    = ScrollController();
  bool  _showSend  = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final has = _ctrl.text.isNotEmpty;
      if (has != _showSend) setState(() => _showSend = has);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    await _supabase.from('messages').insert({
      'sender':   widget.myNick,
      'payload':  _encrypt(text, widget.encKey),
      'chat_key': widget.chatId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final stream = _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_key', widget.chatId)
        .order('created_at', ascending: false);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatId),
            Text(
              widget.encKey.isNotEmpty ? '🔒 E2EE шифрование' : '🔓 Без шифрования',
              style: TextStyle(
                fontSize:   12,
                fontWeight: FontWeight.w400,
                color:      widget.encKey.isNotEmpty ? C.accent2 : C.hint,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Ошибка: ${snap.error}\n\nПроверь RLS в Supabase.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: C.hint),
                      ),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: C.accent),
                  );
                }
                final msgs = snap.data!;
                if (msgs.isEmpty) {
                  return const Center(
                    child: Text('Напиши первое сообщение',
                      style: TextStyle(color: C.hint)),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse:    true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 16,
                  ),
                  itemCount:   msgs.length,
                  itemBuilder: (_, i) {
                    final m      = msgs[i];
                    final isMe   = m['sender'] == widget.myNick;
                    final sender = (m['sender'] as String?) ?? '?';
                    final raw    = (m['payload'] as String?) ?? '';
                    // Расшифровываем payload
                    final text   = _decrypt(raw, widget.encKey);
                    final showNick = i == msgs.length - 1 ||
                        msgs[i + 1]['sender'] != sender;
                    String time = '';
                    if (m['created_at'] != null) {
                      time = DateTime.parse(m['created_at'])
                          .toLocal()
                          .toString()
                          .substring(11, 16);
                    }
                    return _Bubble(
                      text:     text,
                      sender:   sender,
                      time:     time,
                      isMe:     isMe,
                      showNick: showNick && !isMe,
                    );
                  },
                );
              },
            ),
          ),
          // ── Поле ввода ────────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
              12, 8, 12, MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: const BoxDecoration(
              color:  C.surface,
              border: Border(top: BorderSide(color: C.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:      _ctrl,
                    maxLines:        5,
                    minLines:        1,
                    textInputAction: TextInputAction.newline,
                    style:           const TextStyle(color: C.text),
                    decoration: const InputDecoration(
                      hintText:       'Сообщение...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _showSend
                      ? GestureDetector(
                          key:   const ValueKey('send'),
                          onTap: _send,
                          child: Container(
                            width:  44,
                            height: 44,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [C.accent, C.accent2],
                                begin:  Alignment.topLeft,
                                end:    Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.send_rounded,
                              color: Colors.white, size: 20,
                            ),
                          ),
                        )
                      : const SizedBox(key: ValueKey('empty'), width: 44),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ПУЗЫРЬ СООБЩЕНИЯ ────────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final String text;
  final String sender;
  final String time;
  final bool   isMe;
  final bool   showNick;

  const _Bubble({
    required this.text,
    required this.sender,
    required this.time,
    required this.isMe,
    required this.showNick,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: showNick ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: showNick
                  ? CircleAvatar(
                      radius:          14,
                      backgroundColor: _avatarColor(sender).withOpacity(0.25),
                      child: Text(
                        sender[0].toUpperCase(),
                        style: TextStyle(
                          fontSize:   11,
                          color:      _avatarColor(sender),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : const SizedBox(width: 28),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              margin: EdgeInsets.only(
                left:  isMe ? 60 : 0,
                right: isMe ? 0  : 60,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? C.myMsg : C.otherMsg,
                borderRadius: BorderRadius.only(
                  topLeft:     Radius.circular(isMe ? 18 : (showNick ? 4 : 18)),
                  topRight:    Radius.circular(isMe ? (showNick ? 4 : 18) : 18),
                  bottomLeft:  const Radius.circular(18),
                  bottomRight: const Radius.circular(18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize:       MainAxisSize.min,
                children: [
                  if (showNick)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        sender,
                        style: TextStyle(
                          color:      _avatarColor(sender),
                          fontSize:   12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Text(text, style: const TextStyle(color: C.text, fontSize: 15)),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      time,
                      style: TextStyle(
                        color: C.hint.withOpacity(0.7), fontSize: 11,
                      ),
                    ),
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
