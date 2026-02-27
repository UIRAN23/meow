import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── КОНФИГ ──────────────────────────────────────────────────────────────────
const _kSupabaseUrl = 'https://ilszhdmqxsoixcefeoqa.supabase.co';
const _kSupabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlsc3poZG1xeHNvaXhjZWZlb3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2NjA4NDMsImV4cCI6MjA3NjIzNjg0M30.aJF9c3RaNvAk4_9nLYhQABH3pmYUcZ0q2udf2LoA6Sc'; // Замени на реальный ключ

// ─── ЦВЕТА ───────────────────────────────────────────────────────────────────
class AppColors {
  static const bg       = Color(0xFF0A0A0F);
  static const surface  = Color(0xFF141420);
  static const card     = Color(0xFF1C1C2E);
  static const accent   = Color(0xFF6C63FF);
  static const accent2  = Color(0xFF00D4AA);
  static const bubble   = Color(0xFF252540);
  static const myBubble = Color(0xFF3D3580);
  static const text     = Color(0xFFEEEEFF);
  static const hint     = Color(0xFF7070A0);
  static const divider  = Color(0xFF252535);
}

// ─── МОДЕЛЬ СООБЩЕНИЯ ────────────────────────────────────────────────────────
// Таблица messages: created_at | sender | chat_key | payload
class Message {
  final String   sender;
  final String   chatKey;
  final String   payload;   // текст сообщения
  final DateTime createdAt;

  const Message({
    required this.sender,
    required this.chatKey,
    required this.payload,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    sender:    json['sender']    as String,
    chatKey:   json['chat_key']  as String,
    payload:   json['payload']   as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
  );
}

// ─── SUPABASE СЕРВИС ─────────────────────────────────────────────────────────
class SupabaseService {
  static final _client = Supabase.instance.client;

  // Получить все уникальные chat_key (список чатов)
  static Future<List<String>> getChatKeys() async {
    final data = await _client
        .from('messages')
        .select('chat_key')
        .order('created_at', ascending: false);

    final seen = <String>{};
    final keys = <String>[];
    for (final row in data as List) {
      final key = row['chat_key'] as String;
      if (seen.add(key)) keys.add(key);
    }
    return keys;
  }

  // Получить последнее сообщение чата (для превью в списке)
  static Future<Message?> getLastMessage(String chatKey) async {
    final data = await _client
        .from('messages')
        .select()
        .eq('chat_key', chatKey)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return Message.fromJson(data);
  }

  // Получить все сообщения чата
  static Future<List<Message>> getMessages(String chatKey) async {
    final data = await _client
        .from('messages')
        .select()
        .eq('chat_key', chatKey)
        .order('created_at');
    return (data as List).map((e) => Message.fromJson(e)).toList();
  }

  // Отправить сообщение
  static Future<void> sendMessage({
    required String chatKey,
    required String sender,
    required String payload,
  }) async {
    await _client.from('messages').insert({
      'chat_key': chatKey,
      'sender':   sender,
      'payload':  payload,
    });
  }

  // Realtime — подписка на новые сообщения в чате
  static RealtimeChannel subscribeToMessages(
    String chatKey,
    void Function(Message) onMessage,
  ) {
    return _client
        .channel('chat:$chatKey')
        .onPostgresChanges(
          event:  PostgresChangeEvent.insert,
          schema: 'public',
          table:  'messages',
          filter: PostgresChangeFilter(
            type:   FilterType.eq,
            column: 'chat_key',
            value:  chatKey,
          ),
          callback: (payload) {
            final msg = Message.fromJson(payload.newRecord);
            onMessage(msg);
          },
        )
        .subscribe();
  }
}

// ─── ТОЧКА ВХОДА ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:           Colors.transparent,
    statusBarIconBrightness:  Brightness.light,
    systemNavigationBarColor: AppColors.bg,
  ));
  await Supabase.initialize(url: _kSupabaseUrl, anonKey: _kSupabaseKey);
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
        scaffoldBackgroundColor: AppColors.bg,
        primaryColor:            AppColors.accent,
        colorScheme: const ColorScheme.dark(
          primary:   AppColors.accent,
          secondary: AppColors.accent2,
          surface:   AppColors.surface,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          elevation:       0,
          centerTitle:     false,
          titleTextStyle: TextStyle(
            color:         AppColors.text,
            fontSize:      20,
            fontWeight:    FontWeight.w700,
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: AppColors.text),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled:    true,
          fillColor: AppColors.card,
          hintStyle: const TextStyle(color: AppColors.hint),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide:   BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical:   14,
          ),
        ),
      ),
      home: const NickScreen(),
    );
  }
}

// ─── ЭКРАН ВВОДА НИКА ────────────────────────────────────────────────────────
class NickScreen extends StatefulWidget {
  const NickScreen({super.key});

  @override
  State<NickScreen> createState() => _NickScreenState();
}

class _NickScreenState extends State<NickScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _enter() {
    final nick = _ctrl.text.trim();
    if (nick.isEmpty) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainScreen(myNick: nick)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment:  MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width:  64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.accent, AppColors.accent2],
                    begin:  Alignment.topLeft,
                    end:    Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.pets, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 32),
              const Text(
                'Meow',
                style: TextStyle(
                  fontSize:      48,
                  fontWeight:    FontWeight.w800,
                  color:         AppColors.text,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Введи своё имя чтобы начать',
                style: TextStyle(color: AppColors.hint, fontSize: 16),
              ),
              const SizedBox(height: 40),
              TextField(
                controller:      _ctrl,
                autofocus:       true,
                textInputAction: TextInputAction.done,
                onSubmitted:     (_) => _enter(),
                style:           const TextStyle(color: AppColors.text),
                decoration:      const InputDecoration(hintText: 'Твоё имя'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width:  double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _enter,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Войти',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── ГЛАВНЫЙ ЭКРАН (список чатов) ────────────────────────────────────────────
class MainScreen extends StatefulWidget {
  final String myNick;
  const MainScreen({super.key, required this.myNick});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final Map<String, Message?> _chats   = {};
  List<String>                _keys    = [];
  bool                        _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final keys = await SupabaseService.getChatKeys();
      final map  = <String, Message?>{};
      for (final key in keys) {
        map[key] = await SupabaseService.getLastMessage(key);
      }
      if (mounted) {
        setState(() {
          _keys    = keys;
          _chats   = map;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showNewChat() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context:            context,
      backgroundColor:    AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 24, 24,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Открыть чат',
              style: TextStyle(
                fontSize:   20,
                fontWeight: FontWeight.w700,
                color:      AppColors.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Введи ключ чата — он должен совпадать у обоих собеседников',
              style: TextStyle(color: AppColors.hint, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus:  true,
              style:      const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                hintText: 'Ключ чата (chat_key)',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width:  double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final key = ctrl.text.trim();
                  if (key.isEmpty) return;
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        chatKey: key,
                        myNick:  widget.myNick,
                      ),
                    ),
                  ).then((_) => _load());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: const Text(
                  'Открыть',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color:      Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meow'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              radius:          18,
              backgroundColor: AppColors.accent.withOpacity(0.2),
              child: Text(
                widget.myNick[0].toUpperCase(),
                style: const TextStyle(
                  color:      AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : _keys.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size:  64,
                        color: AppColors.hint.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Нет чатов',
                        style: TextStyle(color: AppColors.hint, fontSize: 18),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Нажми + и введи ключ чата',
                        style: TextStyle(color: AppColors.hint, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color:     AppColors.accent,
                  child: ListView.separated(
                    padding:     const EdgeInsets.symmetric(vertical: 8),
                    itemCount:   _keys.length,
                    separatorBuilder: (_, __) => const Divider(
                      color:  AppColors.divider,
                      height: 1,
                      indent: 72,
                    ),
                    itemBuilder: (_, i) {
                      final key  = _keys[i];
                      final last = _chats[key];
                      return ListTile(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              chatKey: key,
                              myNick:  widget.myNick,
                            ),
                          ),
                        ).then((_) => _load()),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical:   4,
                        ),
                        leading: CircleAvatar(
                          radius:          26,
                          backgroundColor: AppColors.accent.withOpacity(0.15),
                          child: Text(
                            key[0].toUpperCase(),
                            style: const TextStyle(
                              color:      AppColors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize:   18,
                            ),
                          ),
                        ),
                        title: Text(
                          key,
                          style: const TextStyle(
                            color:      AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: last != null
                            ? Text(
                                '${last.sender}: ${last.payload}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color:    AppColors.hint,
                                  fontSize: 13,
                                ),
                              )
                            : null,
                        trailing: last != null
                            ? Text(
                                _formatTime(last.createdAt),
                                style: const TextStyle(
                                  color:    AppColors.hint,
                                  fontSize: 12,
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed:       _showNewChat,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

// ─── ЭКРАН ЧАТА ──────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String chatKey;
  final String myNick;

  const ChatScreen({
    super.key,
    required this.chatKey,
    required this.myNick,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Message>    _messages = [];
  bool             _loading  = true;
  bool             _sending  = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await SupabaseService.getMessages(widget.chatKey);
      if (mounted) {
        setState(() {
          _messages = msgs;
          _loading  = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeRealtime() {
    _channel = SupabaseService.subscribeToMessages(widget.chatKey, (msg) {
      if (mounted) {
        setState(() => _messages.add(msg));
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve:    Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    _msgCtrl.clear();
    setState(() => _sending = true);

    try {
      await SupabaseService.sendMessage(
        chatKey: widget.chatKey,
        sender:  widget.myNick,
        payload: text,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:         Text('Ошибка отправки'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chatKey),
            const Text(
              'онлайн',
              style: TextStyle(
                color:      AppColors.accent2,
                fontSize:   12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  )
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Напиши первое сообщение',
                          style: TextStyle(color: AppColors.hint),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical:   16,
                        ),
                        itemCount:   _messages.length,
                        itemBuilder: (_, i) {
                          final msg      = _messages[i];
                          final isMe     = msg.sender == widget.myNick;
                          final showNick = i == 0 ||
                              _messages[i - 1].sender != msg.sender;
                          return _MessageBubble(
                            message:  msg,
                            isMe:     isMe,
                            showNick: showNick && !isMe,
                          );
                        },
                      ),
          ),
          _InputBar(
            controller: _msgCtrl,
            sending:    _sending,
            onSend:     _send,
          ),
        ],
      ),
    );
  }
}

// ─── ПУЗЫРЬ СООБЩЕНИЯ ────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool    isMe;
  final bool    showNick;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showNick,
  });

  @override
  Widget build(BuildContext context) {
    final time =
        '${message.createdAt.hour.toString().padLeft(2, '0')}:'
        '${message.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top:    showNick ? 12 : 2,
          bottom: 2,
          left:   isMe ? 60 : 0,
          right:  isMe ? 0  : 60,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppColors.myBubble : AppColors.bubble,
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
                  message.sender,
                  style: const TextStyle(
                    color:      AppColors.accent2,
                    fontSize:   12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            // payload = текст сообщения
            Text(
              message.payload,
              style: const TextStyle(color: AppColors.text, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                time,
                style: TextStyle(
                  color:    AppColors.hint.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── ПОЛЕ ВВОДА ──────────────────────────────────────────────────────────────
class _InputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool                  sending;
  final VoidCallback          onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final has = widget.controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12, 8, 12,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color:  AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller:      widget.controller,
              maxLines:        5,
              minLines:        1,
              textInputAction: TextInputAction.newline,
              style:           const TextStyle(color: AppColors.text),
              decoration: const InputDecoration(
                hintText:       'Сообщение...',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical:   10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _hasText
                ? GestureDetector(
                    key:   const ValueKey('send'),
                    onTap: widget.sending ? null : widget.onSend,
                    child: Container(
                      width:  44,
                      height: 44,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.accent, AppColors.accent2],
                          begin:  Alignment.topLeft,
                          end:    Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: widget.sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color:       Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size:  20,
                            ),
                    ),
                  )
                : const SizedBox(key: ValueKey('empty'), width: 44),
          ),
        ],
      ),
    );
  }
}
