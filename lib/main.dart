// ════════════════════════════════════════════════════════════════════════════
//  SQL (Supabase SQL Editor — выполни один раз):
//
//  create table if not exists messages (
//    id           bigint generated always as identity primary key,
//    created_at   timestamptz default now(),
//    sender       text not null default '',
//    chat_key     text not null default '',
//    payload      text not null default '',
//    file_type    text not null default 'text',
//    reply_to_id  bigint,
//    reply_sender text not null default '',
//    reply_text   text not null default ''
//  );
//  create index if not exists idx_messages_chat on messages(chat_key, id desc);
//  alter table messages disable row level security;
//  -- Нужно для DELETE событий в Realtime:
//  alter table messages replica identity full;
// ════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
//  КОНФИГ
// ════════════════════════════════════════════════════════════════════════════
const _supabaseUrl = 'https://lyprkqxzvhgrjwqnaxtt.supabase.co';
const _supabaseKey = 'sb_publishable_mtensechlVIxkVmd1YCXNA_7QIczmZk';

final _sb     = Supabase.instance.client;
final _picker = ImagePicker();

// ════════════════════════════════════════════════════════════════════════════
//  МОДЕЛЬ ЧАТА
// ════════════════════════════════════════════════════════════════════════════
class ChatEntry {
  final String id;
  final String key;
  ChatEntry(this.id, this.key);
  String serialize() => '$id\x01$key';
  static ChatEntry from(String s) {
    final i = s.indexOf('\x01');
    if (i != -1) return ChatEntry(s.substring(0, i), s.substring(i + 1));
    final c = s.indexOf(':');
    if (c == -1) return ChatEntry(s, '');
    return ChatEntry(s.substring(0, c), s.substring(c + 1));
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ШИФРОВАНИЕ
//
//  Принцип работы:
//  • Пустой ключ → сообщение хранится открыто
//  • Ключ задан  → AES-256 CBC, IV=16 нулей
//  • _tryDecrypt возвращает null ТОЛЬКО если ключ неверный
//  • При неверном ключе — показываем заглушку "🔐 Зашифровано"
// ════════════════════════════════════════════════════════════════════════════
String _pad32(String k) => k.padRight(32).substring(0, 32);

String _encrypt(String text, String rawKey) {
  if (rawKey.isEmpty) return text;
  final k = enc.Key.fromUtf8(_pad32(rawKey));
  return enc.Encrypter(enc.AES(k))
      .encrypt(text, iv: enc.IV.fromLength(16))
      .base64;
}

/// null = неверный ключ; String = расшифровано (или исходный текст если ключ пустой)
String? _tryDecrypt(String payload, String rawKey) {
  if (rawKey.isEmpty) return payload; // Нет ключа — текст хранится открыто
  if (payload.isEmpty) return payload;
  try {
    final k = enc.Key.fromUtf8(_pad32(rawKey));
    return enc.Encrypter(enc.AES(k))
        .decrypt64(payload, iv: enc.IV.fromLength(16));
  } catch (_) {
    return null; // Неверный ключ
  }
}

/// Декодирует медиа-payload в байты с учётом шифрования
/// file_type 'image_enc'/'video_enc' → зашифровано; 'image'/'video' → нет
Uint8List? _decodeMedia(String payload, String fileType, String encKey) {
  try {
    final isEnc = fileType.endsWith('_enc');
    if (isEnc) {
      if (encKey.isEmpty) return null; // нет ключа — не показываем
      final dec = _tryDecrypt(payload, encKey);
      if (dec == null) return null; // неверный ключ
      return base64Decode(dec);
    } else {
      return base64Decode(payload);
    }
  } catch (_) {
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  НАСТРОЙКИ
// ════════════════════════════════════════════════════════════════════════════
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();

  bool   _dark      = true;
  int    _colorSeed = 0;
  double _fontSize  = 15;
  String _avatarB64 = '';

  bool   get dark      => _dark;
  int    get colorSeed => _colorSeed;
  double get fontSize  => _fontSize;
  String get avatarB64 => _avatarB64;

  static const seeds = [
    Color(0xFF6750A4),
    Color(0xFF006493),
    Color(0xFF006E2C),
    Color(0xFFBE0000),
    Color(0xFFA24900),
    Color(0xFF006A60),
  ];
  Color get seedColor => seeds[_colorSeed];

  Future<void> init() async {
    final p   = await SharedPreferences.getInstance();
    _dark      = p.getBool('dark')       ?? true;
    _colorSeed = p.getInt('colorSeed')   ?? 0;
    _fontSize  = p.getDouble('fontSize') ?? 15;
    _avatarB64 = p.getString('avatar')   ?? '';
    notifyListeners();
  }

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();
  Future<void> setDark(bool v)      async { _dark = v;      (await _p).setBool('dark', v);       notifyListeners(); }
  Future<void> setColor(int v)      async { _colorSeed = v; (await _p).setInt('colorSeed', v);   notifyListeners(); }
  Future<void> setFontSize(double v)async { _fontSize = v;  (await _p).setDouble('fontSize', v); notifyListeners(); }
  Future<void> setAvatar(String v)  async { _avatarB64 = v; (await _p).setString('avatar', v);   notifyListeners(); }
}

ColorScheme _cs(BuildContext ctx) => Theme.of(ctx).colorScheme;
TextTheme   _tt(BuildContext ctx) => Theme.of(ctx).textTheme;

// ════════════════════════════════════════════════════════════════════════════
//  MAIN
// ════════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await AppSettings.instance.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:                    Colors.transparent,
    systemNavigationBarColor:          Colors.transparent,
    statusBarIconBrightness:           Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseKey);
  runApp(const MeowApp());
}

// ════════════════════════════════════════════════════════════════════════════
//  APP
// ════════════════════════════════════════════════════════════════════════════
class MeowApp extends StatefulWidget {
  const MeowApp({super.key});
  @override State<MeowApp> createState() => _MeowAppState();
}

class _MeowAppState extends State<MeowApp> {
  final _s = AppSettings.instance;
  @override void initState()  { super.initState(); _s.addListener(_r); }
  @override void dispose()    { _s.removeListener(_r); super.dispose(); }
  void _r() => setState(() {});

  @override
  Widget build(BuildContext ctx) => MaterialApp(
    title: 'Meow', debugShowCheckedModeBanner: false,
    theme:     ThemeData(colorSchemeSeed: _s.seedColor, brightness: Brightness.light, useMaterial3: true),
    darkTheme: ThemeData(colorSchemeSeed: _s.seedColor, brightness: Brightness.dark,  useMaterial3: true),
    themeMode: _s.dark ? ThemeMode.dark : ThemeMode.light,
    home: const HomeScreen(),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  ГЛАВНЫЙ ЭКРАН (список чатов + настройки)
// ════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _s = AppSettings.instance;
  int             _tab  = 0;
  String          _nick = 'User';
  List<ChatEntry> _chats = [];
  late final TextEditingController _nickCtrl;

  @override
  void initState() {
    super.initState(); _nickCtrl = TextEditingController();
    _s.addListener(_r); _load();
  }

  @override
  void dispose() { _s.removeListener(_r); _nickCtrl.dispose(); super.dispose(); }
  void _r() => setState(() {});

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getString('nickname') ?? 'User';
    if (mounted) setState(() {
      _nick = n; _nickCtrl.text = n;
      _chats = (p.getStringList('chats') ?? []).map(ChatEntry.from).toList();
    });
  }

  Future<void> _saveChats() async =>
      (await SharedPreferences.getInstance())
          .setStringList('chats', _chats.map((e) => e.serialize()).toList());

  Future<void> _pickAvatar() async {
    final xf = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 300, maxHeight: 300);
    if (xf == null || !mounted) return;
    await _s.setAvatar(base64Encode(await xf.readAsBytes()));
  }

  void _showChatDialog({ChatEntry? existing, int? index}) {
    final idCtrl  = TextEditingController(text: existing?.id  ?? '');
    final keyCtrl = TextEditingController(text: existing?.key ?? '');
    final isEdit  = existing != null;
    bool keyVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
        icon: Icon(isEdit ? Icons.edit_outlined : Icons.add_comment_outlined),
        title: Text(isEdit ? 'Редактировать чат' : 'Новый чат'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'ID — публичный, одинаковый у всех. '
            'Ключ — приватный: только те у кого такой же ключ увидят сообщения.',
            style: _tt(ctx).bodySmall?.copyWith(color: _cs(ctx).onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: idCtrl, readOnly: isEdit,
            decoration: InputDecoration(
              labelText: 'ID чата', prefixIcon: const Icon(Icons.tag),
              border: const OutlineInputBorder(), filled: true,
              helperText: isEdit ? 'ID нельзя менять' : 'Например: family, work, dev',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: keyCtrl,
            obscureText: !keyVisible,
            decoration: InputDecoration(
              labelText: 'Ключ шифрования',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(keyVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => ss(() => keyVisible = !keyVisible),
              ),
              border: const OutlineInputBorder(), filled: true,
              helperText: 'Пусто = без шифрования',
            ),
          ),
        ])),
        actions: [
          if (isEdit) TextButton(
            style: TextButton.styleFrom(foregroundColor: _cs(ctx).error),
            onPressed: () async {
              Navigator.pop(ctx); _chats.removeAt(index!);
              await _saveChats(); setState(() {});
            },
            child: const Text('Удалить'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final id = idCtrl.text.trim();
              if (id.isEmpty) return;
              final entry = ChatEntry(id, keyCtrl.text.trim());
              if (isEdit) { _chats[index!] = entry; }
              else if (!_chats.any((e) => e.id == id)) _chats.add(entry);
              await _saveChats(); setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(isEdit ? 'Сохранить' : 'Добавить'),
          ),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
    body: _tab == 0 ? _buildChats(ctx) : _buildSettings(ctx),
    floatingActionButton: _tab == 0
        ? FloatingActionButton(
            onPressed: _showChatDialog, tooltip: 'Новый чат',
            child: const Icon(Icons.edit_outlined),
          )
        : null,
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Чаты'),
        NavigationDestination(icon: Icon(Icons.settings_outlined),   selectedIcon: Icon(Icons.settings),   label: 'Настройки'),
      ],
    ),
  );

  // ── Список чатов ─────────────────────────────────────────────────────────
  Widget _buildChats(BuildContext ctx) {
    final cs = _cs(ctx);
    return CustomScrollView(slivers: [
      SliverAppBar.large(
        title: const Text('Meow'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => setState(() => _tab = 1),
              child: _Avatar(nick: _nick, b64: _s.avatarB64, radius: 18),
            ),
          ),
        ],
      ),
      if (_chats.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline, size: 72, color: cs.outlineVariant),
          const SizedBox(height: 16),
          Text('Нет чатов', style: _tt(ctx).titleLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('Нажми + чтобы создать', style: _tt(ctx).bodyMedium?.copyWith(color: cs.outline)),
        ])))
      else
        SliverList.separated(
          itemCount: _chats.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (_, i) {
            final chat = _chats[i];
            return Dismissible(
              key: Key(chat.serialize()),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                color: cs.errorContainer,
                child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
              ),
              confirmDismiss: (_) => showDialog<bool>(context: ctx,
                builder: (d) => AlertDialog(
                  icon: Icon(Icons.warning_outlined, color: cs.error),
                  title: Text('Удалить "${chat.id}"?'),
                  content: const Text('Только из списка. Сообщения в базе сохранятся.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: cs.error),
                      onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                  ],
                ),
              ),
              onDismissed: (_) async { _chats.removeAt(i); await _saveChats(); setState(() {}); },
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: _Avatar(nick: chat.id, radius: 24),
                title: Text(chat.id, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  chat.key.isNotEmpty ? '🔒 Зашифрован' : '🔓 Открытый',
                  style: TextStyle(fontSize: 12, color: chat.key.isNotEmpty ? cs.primary : cs.outline),
                ),
                trailing: IconButton(icon: const Icon(Icons.more_vert),
                    onPressed: () => _showChatDialog(existing: chat, index: i)),
                onTap: () => Navigator.push(ctx, MaterialPageRoute(
                  builder: (_) => ChatScreen(
                      roomName: chat.id, encKey: chat.key, myNick: _nick),
                )),
                onLongPress: () => _showChatDialog(existing: chat, index: i),
              ),
            );
          },
        ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
    ]);
  }

  // ── Настройки ─────────────────────────────────────────────────────────────
  Widget _buildSettings(BuildContext ctx) {
    final cs = _cs(ctx);
    return CustomScrollView(slivers: [
      const SliverAppBar.large(title: Text('Настройки')),
      SliverList(delegate: SliverChildListDelegate([

        // ── Профиль ─────────────────────────────────────────────────────
        _SectionHeader('ПРОФИЛЬ'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.filled(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(alignment: Alignment.bottomRight, children: [
                  _Avatar(nick: _nick, b64: _s.avatarB64, radius: 40),
                  CircleAvatar(
                    radius: 14, backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.camera_alt_outlined, size: 16, color: cs.onPrimaryContainer),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(
                  controller: _nickCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Имя', prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(), filled: true,
                  ),
                )),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final n = _nickCtrl.text.trim();
                    if (n.isEmpty) return;
                    (await SharedPreferences.getInstance()).setString('nickname', n);
                    setState(() => _nick = n);
                    if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Имя сохранено')));
                  },
                  child: const Text('OK'),
                ),
              ]),
            ]),
          )),
        ),
        const SizedBox(height: 16),

        // ── Внешний вид ─────────────────────────────────────────────────
        _SectionHeader('ВНЕШНИЙ ВИД'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.outlined(child: Column(children: [
            SwitchListTile(
              secondary: Icon(_s.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
              title: const Text('Тёмная тема'),
              value: _s.dark, onChanged: _s.setDark,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Цвет акцента', style: _tt(ctx).labelLarge),
                const SizedBox(height: 12),
                StatefulBuilder(builder: (_, ss) => Wrap(spacing: 10, runSpacing: 10,
                  children: List.generate(AppSettings.seeds.length, (i) {
                    final sel = _s.colorSeed == i;
                    return GestureDetector(
                      onTap: () { _s.setColor(i); ss(() {}); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppSettings.seeds[i], shape: BoxShape.circle,
                          border: sel ? Border.all(color: cs.outline, width: 3) : null,
                          boxShadow: sel ? [BoxShadow(color: AppSettings.seeds[i].withOpacity(0.5), blurRadius: 8)] : null,
                        ),
                        child: sel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                      ),
                    );
                  }),
                )),
              ]),
            ),
          ])),
        ),
        const SizedBox(height: 16),

        // ── Текст ────────────────────────────────────────────────────────
        _SectionHeader('ТЕКСТ'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.outlined(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: StatefulBuilder(builder: (_, ss) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Размер текста', style: _tt(ctx).labelLarge),
                  Chip(label: Text('${_s.fontSize.round()} px'), padding: const EdgeInsets.symmetric(horizontal: 4)),
                ]),
                Slider(
                  value: _s.fontSize, min: 12, max: 22, divisions: 10,
                  onChanged: (v) { _s.setFontSize(v); ss(() {}); },
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                  child: Text('Пример текста сообщения', style: TextStyle(fontSize: _s.fontSize)),
                ),
              ],
            )),
          )),
        ),
        const SizedBox(height: 16),

        // ── Опасная зона ─────────────────────────────────────────────────
        _SectionHeader('ДАННЫЕ'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.outlined(child: ListTile(
            leading: Icon(Icons.delete_sweep_outlined, color: cs.error),
            title: Text('Очистить список чатов', style: TextStyle(color: cs.error)),
            subtitle: const Text('Сообщения в базе сохранятся'),
            onTap: () async {
              final ok = await showDialog<bool>(context: ctx,
                builder: (d) => AlertDialog(
                  icon: Icon(Icons.warning_outlined, color: cs.error),
                  title: const Text('Очистить?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                      onPressed: () => Navigator.pop(d, true), child: const Text('Да')),
                  ],
                ),
              );
              if (ok == true) {
                (await SharedPreferences.getInstance()).remove('chats');
                setState(() { _chats = []; _tab = 0; });
              }
            },
          )),
        ),
        const SizedBox(height: 100),
      ])),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ЭКРАН ЧАТА
//  - Начальная загрузка через HTTP (надёжно)
//  - Обновления через Realtime (с авто-переподключением)
//  - БЕЗ StreamBuilder → нет мерцания при вводе текста
// ════════════════════════════════════════════════════════════════════════════
class ChatScreen extends StatefulWidget {
  final String roomName;
  final String encKey;
  final String myNick;
  const ChatScreen({super.key, required this.roomName, required this.encKey, required this.myNick});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _s      = AppSettings.instance;
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _focus  = FocusNode();

  // Состояние сообщений
  final List<Map<String, dynamic>> _msgs = [];
  bool    _loading   = true;
  bool    _connected = false;
  String? _error;
  RealtimeChannel? _channel;

  // Ответ на сообщение
  Map<String, dynamic>? _replyTo;
  String                _replyPreview = '';

  // Загрузка медиа
  bool _uploading = false;

  // Кэш расшифрованных текстов {id: decrypted}
  final Map<int, String> _decCache = {};

  @override
  void initState() {
    super.initState();
    _init();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _ctrl.dispose(); _scroll.dispose(); _focus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    await _fetchMessages();
    if (mounted) _setupRealtime();
  }

  // ── Начальная загрузка ────────────────────────────────────────────────────
  Future<void> _fetchMessages() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _sb
          .from('messages')
          .select()
          .eq('chat_key', widget.roomName)
          .order('id', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _msgs.clear();
        _msgs.addAll(List<Map<String, dynamic>>.from(data));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Realtime подписка с авто-переподключением ─────────────────────────────
  void _setupRealtime() {
    _channel?.unsubscribe();
    _channel = _sb
      .channel('chat:${widget.roomName}:${DateTime.now().millisecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public', table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'chat_key', value: widget.roomName,
        ),
        callback: (payload) {
          if (!mounted) return;
          final msg = Map<String, dynamic>.from(payload.newRecord);
          if (_msgs.any((m) => m['id'] == msg['id'])) return;
          setState(() => _msgs.insert(0, msg));
        },
      )
      .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public', table: 'messages',
        callback: (payload) {
          if (!mounted) return;
          final id = payload.oldRecord['id'];
          if (id == null) return;
          setState(() {
            _msgs.removeWhere((m) => m['id'] == id);
            _decCache.remove(id);
          });
        },
      )
      .subscribe((status, error) {
        if (!mounted) return;
        setState(() => _connected = status == RealtimeSubscribeStatus.subscribed);
        if (status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.channelError) {
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) _setupRealtime();
          });
        }
      });
  }

  // ── Расшифровка с кэшем (не пересчитываем на каждый rebuild) ─────────────
  String _getDecrypted(int id, String payload) {
    if (_decCache.containsKey(id)) return _decCache[id]!;
    final dec = _tryDecrypt(payload, widget.encKey);
    final result = dec ?? '🔐 Зашифровано';
    _decCache[id] = result;
    return result;
  }

  // ── Отправить текст ───────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    _focus.requestFocus();

    final Map<String, dynamic> row = {
      'sender':    widget.myNick,
      'chat_key':  widget.roomName,
      'payload':   _encrypt(text, widget.encKey),
      'file_type': 'text',
    };
    if (_replyTo != null) {
      row['reply_to_id']  = _replyTo!['id'];
      row['reply_sender'] = (_replyTo!['sender'] as String?) ?? '';
      row['reply_text']   = _replyPreview;
    }
    setState(() => _replyTo = null);

    try {
      await _sb.from('messages').insert(row);
    } catch (e) {
      _ctrl.text = text;
      _showErr('Ошибка: $e');
    }
  }

  // ── Отправить фото ────────────────────────────────────────────────────────
  Future<void> _sendImage({ImageSource src = ImageSource.gallery}) async {
    final xf = await _picker.pickImage(
        source: src, imageQuality: 75, maxWidth: 1024, maxHeight: 1024);
    if (xf == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xf.readAsBytes();
      if (bytes.length > 800 * 1024) { _showErr('Фото слишком большое (макс ~800KB)'); return; }
      final b64  = base64Encode(bytes);
      final enc  = widget.encKey.isNotEmpty;
      await _sb.from('messages').insert({
        'sender':    widget.myNick,
        'chat_key':  widget.roomName,
        'payload':   enc ? _encrypt(b64, widget.encKey) : b64,
        'file_type': enc ? 'image_enc' : 'image',
      });
    } catch (e) { _showErr('Ошибка: $e'); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  // ── Отправить видео ───────────────────────────────────────────────────────
  Future<void> _sendVideo() async {
    final xf = await _picker.pickVideo(
        source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
    if (xf == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xf.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) { _showErr('Видео слишком большое (макс 10MB)'); return; }
      final b64 = base64Encode(bytes);
      final enc = widget.encKey.isNotEmpty;
      await _sb.from('messages').insert({
        'sender':    widget.myNick,
        'chat_key':  widget.roomName,
        'payload':   enc ? _encrypt(b64, widget.encKey) : b64,
        'file_type': enc ? 'video_enc' : 'video',
      });
    } catch (e) { _showErr('Ошибка: $e'); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  // ── Удалить сообщение ─────────────────────────────────────────────────────
  Future<void> _deleteMessage(int id) async {
    try {
      await _sb.from('messages').delete().eq('id', id);
      setState(() {
        _msgs.removeWhere((m) => m['id'] == id);
        _decCache.remove(id);
      });
    } catch (e) { _showErr('Ошибка: $e'); }
  }

  // ── Сохранить медиа ───────────────────────────────────────────────────────
  Future<void> _saveMedia(String payload, String fileType) async {
    final bytes = _decodeMedia(payload, fileType, widget.encKey);
    if (bytes == null) { _showErr('Невозможно сохранить: неверный ключ или ошибка'); return; }
    try {
      final dir  = await getApplicationDocumentsDirectory();
      final ext  = fileType.contains('video') ? 'mp4' : 'jpg';
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/meow_$ts.$ext');
      await file.writeAsBytes(bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Сохранено: ${file.path}'),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) { _showErr('Ошибка сохранения: $e'); }
  }

  // ── Меню действий с сообщением (MD3 bottom sheet) ────────────────────────
  void _showActions(Map<String, dynamic> msg, String displayText, bool isMe) {
    final cs       = _cs(context);
    final id       = msg['id'] as int;
    final ftype    = (msg['file_type'] as String?) ?? 'text';
    final payload  = (msg['payload']   as String?) ?? '';
    final isMedia  = ftype != 'text';
    final encFail  = displayText == '🔐 Зашифровано';
    final sender   = (msg['sender'] as String?) ?? '?';

    showModalBottomSheet(
      context: context, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (ctx) => _M3Sheet(cs: cs, child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Предпросмотр
        if (!isMedia && !encFail)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            child: Text(displayText,
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: _tt(ctx).bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),

        // Ответить
        if (!encFail) ListTile(
          leading: const Icon(Icons.reply_outlined),
          title: const Text('Ответить'),
          onTap: () {
            Navigator.pop(ctx);
            String preview;
            if (isMedia) {
              preview = ftype.contains('image') ? '📷 Фото' : '🎥 Видео';
            } else {
              preview = displayText.length > 60 ? '${displayText.substring(0, 60)}…' : displayText;
            }
            setState(() { _replyTo = msg; _replyPreview = preview; });
            _focus.requestFocus();
          },
        ),

        // Копировать (только текст)
        if (!isMedia && !encFail) ListTile(
          leading: const Icon(Icons.copy_outlined),
          title: const Text('Копировать'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: displayText));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Скопировано'), duration: Duration(seconds: 2)));
          },
        ),

        // Скачать медиа
        if (isMedia) ListTile(
          leading: Icon(ftype.contains('image') ? Icons.download_outlined : Icons.video_file_outlined),
          title: Text(ftype.contains('image') ? 'Скачать фото' : 'Скачать видео'),
          onTap: () { Navigator.pop(ctx); _saveMedia(payload, ftype); },
        ),

        // Открыть ссылки
        ..._urlRegex.allMatches(displayText).map((m) => ListTile(
          leading: const Icon(Icons.open_in_new),
          title: Text(m.group(0)!, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: cs.primary)),
          onTap: () { Navigator.pop(ctx); _openUrl(m.group(0)!); },
        )),

        if (isMe) const Divider(),

        // Удалить (только свои)
        if (isMe) ListTile(
          leading: Icon(Icons.delete_outlined, color: cs.error),
          title: Text('Удалить', style: TextStyle(color: cs.error)),
          subtitle: const Text('Удалится у всех'),
          onTap: () async {
            Navigator.pop(ctx);
            final ok = await showDialog<bool>(context: context,
              builder: (d) => AlertDialog(
                icon: Icon(Icons.delete_outlined, color: cs.error),
                title: const Text('Удалить сообщение?'),
                content: const Text('Сообщение удалится у всех участников.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: cs.error),
                    onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                ],
              ),
            );
            if (ok == true) await _deleteMessage(id);
          },
        ),
      ])),
    );
  }

  void _showAttach() {
    final cs = _cs(context);
    showModalBottomSheet(
      context: context, useSafeArea: true, backgroundColor: Colors.transparent,
      builder: (_) => _M3Sheet(cs: cs, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('Прикрепить', style: _tt(context).titleMedium),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _AttachBtn(icon: Icons.image_outlined,      label: 'Фото',   cs: cs,
              onTap: () { Navigator.pop(context); _sendImage(); }),
          _AttachBtn(icon: Icons.videocam_outlined,   label: 'Видео',  cs: cs,
              onTap: () { Navigator.pop(context); _sendVideo(); }),
          _AttachBtn(icon: Icons.camera_alt_outlined, label: 'Камера', cs: cs,
              onTap: () { Navigator.pop(context); _sendImage(src: ImageSource.camera); }),
        ]),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: _cs(context).error));
  }

  @override
  Widget build(BuildContext context) {
    final cs       = _cs(context);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          _Avatar(nick: widget.roomName, radius: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text(widget.roomName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Row(children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _connected ? Icons.circle : Icons.circle_outlined,
                  key: ValueKey(_connected),
                  size: 8,
                  color: _connected ? Colors.green : cs.outline,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _connected ? (_error == null ? 'В сети' : 'Переподключение...') : 'Подключение...',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w400),
              ),
              const SizedBox(width: 8),
              Text(
                widget.encKey.isNotEmpty ? '🔒' : '🔓',
                style: const TextStyle(fontSize: 11),
              ),
            ]),
          ])),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(
              icon: const Icon(Icons.info_outline),
              title: Text(widget.roomName),
              content: Text(widget.encKey.isNotEmpty
                  ? '🔒 Зашифрованный чат.\n\nТолько те у кого такой же ключ — видят сообщения и медиа. '
                    'Остальные видят "🔐 Зашифровано".'
                  : '🔓 Открытый чат.\n\nСообщения видны всем у кого есть этот ID.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            )),
          ),
        ],
      ),
      body: Column(children: [

        // ── Баннер ошибки ───────────────────────────────────────────────
        if (_error != null && !_loading)
          MaterialBanner(
            backgroundColor: cs.errorContainer,
            content: Text('Ошибка подключения', style: TextStyle(color: cs.onErrorContainer)),
            leading: Icon(Icons.wifi_off, color: cs.onErrorContainer),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: cs.onErrorContainer),
                onPressed: _init, child: const Text('Повторить'),
              ),
            ],
          ),

        // ── Список сообщений ────────────────────────────────────────────
        Expanded(child: _buildMessageList(cs)),

        // ── Панель ответа ────────────────────────────────────────────────
        if (_replyTo != null) _buildReplyBar(cs),

        // ── Поле ввода ───────────────────────────────────────────────────
        _buildInputBar(cs, isDesktop),
      ]),
    );
  }

  Widget _buildMessageList(ColorScheme cs) {
    if (_loading) return Center(child: CircularProgressIndicator(color: cs.primary));
    if (_msgs.isEmpty && _error == null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.chat_bubble_outline, size: 64, color: cs.outlineVariant),
      const SizedBox(height: 12),
      Text('Напиши первое сообщение 👋',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
    ]));
    if (_msgs.isEmpty && _error != null) return const SizedBox();

    return ListView.builder(
      controller: _scroll, reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount: _msgs.length,
      itemBuilder: (_, i) {
        final m       = _msgs[i];
        final id      = m['id'] as int;
        final sender  = (m['sender']    as String?) ?? '?';
        final ftype   = (m['file_type'] as String?) ?? 'text';
        final payload = (m['payload']   as String?) ?? '';
        final isMe    = sender == widget.myNick;
        final showNick = !isMe && (i == _msgs.length - 1 || _msgs[i + 1]['sender'] != sender);

        String time = '';
        if (m['created_at'] != null) {
          time = DateTime.parse(m['created_at']).toLocal().toString().substring(11, 16);
        }

        String displayText = payload;
        bool   encFail     = false;
        if (ftype == 'text') {
          final dec = _getDecrypted(id, payload);
          if (dec == '🔐 Зашифровано') encFail = true;
          displayText = dec;
        }

        final replyToId  = m['reply_to_id']  as int?;
        final replySender = (m['reply_sender'] as String?) ?? '';
        final replyText   = (m['reply_text']   as String?) ?? '';

        return _BubbleWidget(
          key: ValueKey(id),
          msg: m, text: displayText, sender: sender, time: time,
          fileType: ftype, payload: payload, encKey: widget.encKey,
          isMe: isMe, showNick: showNick, encFail: encFail,
          fontSize: AppSettings.instance.fontSize, cs: cs,
          replyToId: replyToId, replySender: replySender, replyText: replyText,
          onLongPress: () => _showActions(m, displayText, isMe),
        );
      },
    );
  }

  Widget _buildReplyBar(ColorScheme cs) {
    final replySender = (_replyTo!['sender'] as String?) ?? '?';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.surfaceContainerLow,
      child: Row(children: [
        Container(width: 3, height: 36, color: cs.primary,
            margin: const EdgeInsets.only(right: 10)),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(replySender, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
          Text(_replyPreview, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
        ])),
        IconButton(icon: const Icon(Icons.close), iconSize: 18,
            onPressed: () => setState(() => _replyTo = null)),
      ]),
    );
  }

  Widget _buildInputBar(ColorScheme cs, bool isDesktop) {
    return Material(
      elevation: 2, color: cs.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [

            // Прикрепить
            IconButton(
              onPressed: _uploading ? null : _showAttach,
              icon: _uploading
                  ? SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                  : const Icon(Icons.attach_file),
            ),

            // Поле ввода
            Expanded(
              child: KeyboardListener(
                focusNode: FocusNode(),
                onKeyEvent: (e) {
                  if (!isDesktop) return;
                  if (e is KeyDownEvent &&
                      e.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    _send();
                  }
                },
                child: TextField(
                  controller: _ctrl, focusNode: _focus,
                  minLines: 1, maxLines: isDesktop ? 4 : 6,
                  textInputAction: TextInputAction.newline,
                  style: TextStyle(fontSize: AppSettings.instance.fontSize),
                  decoration: InputDecoration(
                    hintText: isDesktop ? 'Сообщение... (Enter — отправить)' : 'Сообщение...',
                    hintStyle: TextStyle(color: cs.outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    isDense: true, filled: true,
                    fillColor: cs.surfaceContainerHighest,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 6),

            // Кнопка отправить
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: _ctrl.text.isNotEmpty
                  ? FloatingActionButton.small(
                      key: const ValueKey('send'),
                      onPressed: _send, elevation: 0,
                      child: const Icon(Icons.send_rounded),
                    )
                  : const SizedBox(key: ValueKey('empty'), width: 40),
            ),
          ]),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ПУЗЫРЬ СООБЩЕНИЯ
// ════════════════════════════════════════════════════════════════════════════
class _BubbleWidget extends StatelessWidget {
  final Map<String, dynamic> msg;
  final String text, sender, time, fileType, payload, encKey;
  final bool   isMe, showNick, encFail;
  final double fontSize;
  final ColorScheme cs;
  final int?   replyToId;
  final String replySender, replyText;
  final VoidCallback onLongPress;

  const _BubbleWidget({
    super.key,
    required this.msg, required this.text, required this.sender, required this.time,
    required this.fileType, required this.payload, required this.encKey,
    required this.isMe, required this.showNick, required this.encFail,
    required this.fontSize, required this.cs,
    required this.replyToId, required this.replySender, required this.replyText,
    required this.onLongPress,
  });

  // MD3: свои — primaryContainer, чужие — surfaceContainerHigh
  Color get _bgColor => isMe ? cs.primaryContainer : cs.surfaceContainerHigh;
  Color get _txtColor => isMe ? cs.onPrimaryContainer : cs.onSurface;

  Widget _buildReplyPreview() {
    if (replyToId == null || replyText.isEmpty) return const SizedBox();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: (isMe ? cs.primary : cs.primary).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: cs.primary, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(replySender,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary)),
        Text(replyText, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _txtColor.withOpacity(0.7))),
      ]),
    );
  }

  Widget _buildContent(BuildContext ctx) {
    final isMedia = fileType != 'text';

    if (fileType == 'image' || fileType == 'image_enc') {
      final bytes = _decodeMedia(payload, fileType, encKey);
      if (bytes == null) {
        return Container(
          width: 200, height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline, color: cs.outline, size: 18),
            const SizedBox(width: 6),
            Text('Зашифровано 📷', style: TextStyle(color: cs.outline, fontSize: 12)),
          ]),
        );
      }
      return GestureDetector(
        onTap: () => Navigator.push(ctx, MaterialPageRoute(
            builder: (_) => _FullImageScreen(bytes: bytes))),
        child: Hero(
          tag: '${msg['id']}_img',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: 220, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _ErrWidget(icon: Icons.broken_image_outlined, label: 'Ошибка', cs: cs)),
          ),
        ),
      );
    }

    if (fileType == 'video' || fileType == 'video_enc') {
      final bytes = _decodeMedia(payload, fileType, encKey);
      if (bytes == null) return Container(
        width: 200, height: 60, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_outline, color: cs.outline, size: 18),
          const SizedBox(width: 6),
          Text('Зашифровано 🎥', style: TextStyle(color: cs.outline, fontSize: 12)),
        ]),
      );
      return _VideoB64(bytes: bytes);
    }

    // Текст
    if (encFail) return Text(text,
        style: TextStyle(fontSize: fontSize, fontStyle: FontStyle.italic,
            color: _txtColor.withOpacity(0.55)));

    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) return Text(text,
        style: TextStyle(fontSize: fontSize, color: _txtColor));

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in matches) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final url = m.group(0)!;
      spans.add(WidgetSpan(child: GestureDetector(
        onTap: () => _openUrl(url),
        child: Text(url, style: TextStyle(
          fontSize: fontSize, color: isMe ? cs.onPrimaryContainer : cs.primary,
          decoration: TextDecoration.underline,
          decorationColor: isMe ? cs.onPrimaryContainer : cs.primary,
        )),
      )));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(text: TextSpan(
        style: TextStyle(fontSize: fontSize, color: _txtColor), children: spans));
  }

  @override
  Widget build(BuildContext ctx) {
    final isMedia = fileType != 'text';
    final br = BorderRadius.only(
      topLeft:    Radius.circular(isMe ? 18 : (showNick ? 4 : 18)),
      topRight:   Radius.circular(isMe ? (showNick ? 4 : 18) : 18),
      bottomLeft: const Radius.circular(18),
      bottomRight: const Radius.circular(18),
    );

    return Padding(
      padding: EdgeInsets.only(top: showNick ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Аватар
          if (!isMe) Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: showNick ? _Avatar(nick: sender, radius: 14) : const SizedBox(width: 28),
          ),

          // Пузырь
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: isMedia ? 240 : MediaQuery.of(ctx).size.width * 0.72),
                margin: EdgeInsets.only(left: isMe ? 56 : 0, right: isMe ? 0 : 56),
                padding: EdgeInsets.all(isMedia && replyToId == null ? 4 : 10),
                decoration: BoxDecoration(color: _bgColor, borderRadius: br),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Ник отправителя
                    if (showNick) Padding(
                      padding: EdgeInsets.only(bottom: 2, left: isMedia ? 6 : 0),
                      child: Text(sender, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: _avatarColor(sender),
                      )),
                    ),
                    // Превью ответа
                    if (replyToId != null && replyText.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(left: isMedia ? 6 : 0, right: isMedia ? 6 : 0),
                        child: _buildReplyPreview(),
                      ),
                    // Контент
                    isMedia
                        ? Padding(padding: const EdgeInsets.all(2), child: _buildContent(ctx))
                        : _buildContent(ctx),
                    // Время
                    Padding(
                      padding: EdgeInsets.only(
                        top: 3, left: isMedia ? 6 : 0, right: isMedia ? 6 : 0),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Text(time, style: TextStyle(
                          fontSize: 10,
                          color: isMe ? cs.onPrimaryContainer.withOpacity(0.6) : cs.outline,
                        )),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ВИДЕО ИЗ БАЙТ (media_kit)
// ════════════════════════════════════════════════════════════════════════════
class _VideoB64 extends StatefulWidget {
  final Uint8List bytes;
  const _VideoB64({required this.bytes});
  @override State<_VideoB64> createState() => _VideoB64State();
}

class _VideoB64State extends State<_VideoB64> {
  late final Player          _player;
  late final VideoController _ctrl;
  bool    _init = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _ctrl   = VideoController(_player);
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final path = '${Directory.systemTemp.path}/meow_v_${widget.bytes.hashCode}.mp4';
      final file = File(path);
      if (!await file.exists()) await file.writeAsBytes(widget.bytes);
      await _player.open(Media('file:///$path'), play: false);
      if (mounted) setState(() => _init = true);
    } catch (e) {
      if (mounted) setState(() => _err = 'Ошибка видео');
    }
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext ctx) {
    final cs = _cs(ctx);
    if (_err != null) return _ErrWidget(icon: Icons.videocam_off_outlined, label: _err!, cs: cs);
    if (!_init) return Container(
      width: 200, height: 120,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
    return GestureDetector(
      onTap: () => Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => _FullVideoScreen(player: _player, ctrl: _ctrl))),
      child: Stack(alignment: Alignment.center, children: [
        ClipRRect(borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 220, height: 140, child: Video(controller: _ctrl, fit: BoxFit.cover))),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ПОЛНОЭКРАННОЕ ФОТО
// ════════════════════════════════════════════════════════════════════════════
class _FullImageScreen extends StatelessWidget {
  final Uint8List bytes;
  const _FullImageScreen({required this.bytes});
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: Colors.black,
    extendBodyBehindAppBar: true,
    appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
    body: GestureDetector(
      onVerticalDragEnd: (d) { if (d.primaryVelocity != null && d.primaryVelocity! > 400) Navigator.pop(ctx); },
      child: Center(child: InteractiveViewer(
        maxScale: 5, child: Image.memory(bytes, fit: BoxFit.contain),
      )),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  ПОЛНОЭКРАННОЕ ВИДЕО
// ════════════════════════════════════════════════════════════════════════════
class _FullVideoScreen extends StatelessWidget {
  final Player          player;
  final VideoController ctrl;
  const _FullVideoScreen({required this.player, required this.ctrl});
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.transparent, foregroundColor: Colors.white,
      actions: [
        IconButton(
          icon: StreamBuilder<bool>(
            stream: player.stream.playing,
            builder: (_, s) => Icon(s.data == true ? Icons.pause : Icons.play_arrow),
          ),
          onPressed: () => player.state.playing ? player.pause() : player.play(),
        ),
      ],
    ),
    body: Center(child: Video(controller: ctrl, fit: BoxFit.contain)),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  АВАТАР
// ════════════════════════════════════════════════════════════════════════════
class _Avatar extends StatelessWidget {
  final String  nick;
  final double  radius;
  final String? b64;
  const _Avatar({required this.nick, required this.radius, this.b64});

  @override
  Widget build(BuildContext ctx) {
    final cs = _cs(ctx);
    if (b64 != null && b64!.isNotEmpty) {
      try {
        return CircleAvatar(radius: radius, backgroundImage: MemoryImage(base64Decode(b64!)));
      } catch (_) {}
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _avatarColor(nick).withOpacity(0.2),
      child: Text(
        nick.isNotEmpty ? nick[0].toUpperCase() : '?',
        style: TextStyle(color: _avatarColor(nick),
            fontWeight: FontWeight.w700, fontSize: radius * 0.8),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ
// ════════════════════════════════════════════════════════════════════════════
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(28, 16, 0, 8),
    child: Text(text, style: TextStyle(
      fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2,
      color: _cs(ctx).primary,
    )),
  );
}

class _M3Sheet extends StatelessWidget {
  final Widget child; final ColorScheme cs;
  const _M3Sheet({required this.child, required this.cs});
  @override
  Widget build(BuildContext ctx) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 32, height: 4, margin: const EdgeInsets.only(top: 14, bottom: 12),
          decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
      child,
      const SizedBox(height: 12),
    ]),
  );
}

class _AttachBtn extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap; final ColorScheme cs;
  const _AttachBtn({required this.icon, required this.label, required this.onTap, required this.cs});
  @override
  Widget build(BuildContext ctx) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(children: [
        CircleAvatar(radius: 28, backgroundColor: cs.primaryContainer,
            child: Icon(icon, color: cs.onPrimaryContainer, size: 24)),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface)),
      ]),
    ),
  );
}

class _ErrWidget extends StatelessWidget {
  final IconData icon; final String label; final ColorScheme cs;
  const _ErrWidget({required this.icon, required this.label, required this.cs});
  @override
  Widget build(BuildContext ctx) => Container(
    width: 180, height: 50, alignment: Alignment.center,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: cs.outline, size: 18),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: cs.outline, fontSize: 12)),
    ]),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  УТИЛИТЫ
// ════════════════════════════════════════════════════════════════════════════
Color _avatarColor(String n) =>
    Colors.primaries[n.hashCode.abs() % Colors.primaries.length];

final _urlRegex = RegExp(r'(https?://[^\s]+|www\.[^\s]+\.[^\s]{2,})', caseSensitive: false);

Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
  if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
}
