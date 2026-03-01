// ════════════════════════════════════════════════════════════════════════════
//  SQL (Supabase SQL Editor — выполни один раз):
//
//  create table if not exists messages (
//    id         bigint generated always as identity primary key,
//    created_at timestamptz default now(),
//    sender     text not null default '',
//    chat_key   text not null default '',
//    payload    text not null default '',
//    file_type  text not null default 'text'
//  );
//  create index if not exists idx_messages_chat
//    on messages (chat_key, id desc);
//  alter table messages disable row level security;
// ════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

// ════════════════════════════════════════════════════════════════════════════
//  КОНФИГ
// ════════════════════════════════════════════════════════════════════════════
const _supabaseUrl = 'https://lyprkqxzvhgrjwqnaxtt.supabase.co';
const _supabaseKey = 'sb_publishable_mtensechlVIxkVmd1YCXNA_7QIczmZk';

final _sb     = Supabase.instance.client;
final _picker = ImagePicker();

// ════════════════════════════════════════════════════════════════════════════
//  МОДЕЛЬ ЧАТА
//  id  = имя комнаты (chat_key в БД)
//  key = ключ шифрования (только у тебя, не передаётся в БД)
// ════════════════════════════════════════════════════════════════════════════
class ChatEntry {
  final String id;   // публичный ID чата
  final String key;  // приватный ключ шифрования
  ChatEntry(this.id, this.key);

  String serialize() => '$id\x01$key';
  static ChatEntry from(String s) {
    final idx = s.indexOf('\x01');
    if (idx != -1) return ChatEntry(s.substring(0, idx), s.substring(idx + 1));
    final ci = s.indexOf(':');
    if (ci == -1) return ChatEntry(s, '');
    return ChatEntry(s.substring(0, ci), s.substring(ci + 1));
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ШИФРОВАНИЕ
//
//  Логика:
//  • Ключ пустой  → сообщение хранится открыто, все читают
//  • Ключ задан   → шифруем AES-256 CBC.
//                   Только у кого такой же ключ — расшифрует.
//                   Остальные увидят placeholder "🔐 Зашифровано"
// ════════════════════════════════════════════════════════════════════════════
String _pad32(String k) => k.padRight(32).substring(0, 32);

String _encrypt(String text, String rawKey) {
  if (rawKey.isEmpty) return text;
  final k = enc.Key.fromUtf8(_pad32(rawKey));
  return enc.Encrypter(enc.AES(k))
      .encrypt(text, iv: enc.IV.fromLength(16))
      .base64;
}

/// Возвращает расшифрованный текст, или null если ключ неверный / не подходит
String? _tryDecrypt(String payload, String rawKey) {
  // Нет ключа → показываем как есть (незашифровано)
  if (rawKey.isEmpty) return payload;

  // Проверяем, похоже ли на base64-зашифрованное
  final b64 = RegExp(r'^[A-Za-z0-9+/]+=*$');
  if (!b64.hasMatch(payload) || payload.length < 16) {
    // Скорее всего незашифрованное сообщение из другого клиента
    return payload;
  }

  try {
    final k      = enc.Key.fromUtf8(_pad32(rawKey));
    final result = enc.Encrypter(enc.AES(k))
        .decrypt64(payload, iv: enc.IV.fromLength(16));
    // Лёгкая проверка что расшифрованный текст — валидный UTF-8
    utf8.encode(result);
    return result;
  } catch (_) {
    return null; // Неверный ключ
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

  // Цвета в стиле Material You
  static const seeds = [
    Color(0xFF6750A4), // фиолетовый (дефолт Pixel)
    Color(0xFF006493), // синий
    Color(0xFF006E2C), // зелёный
    Color(0xFFBE0000), // красный
    Color(0xFFA24900), // оранжевый
    Color(0xFF006A60), // бирюзовый
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
  Future<void> setDark(bool v)      async { _dark = v;      (await _p).setBool('dark', v);         notifyListeners(); }
  Future<void> setColor(int v)      async { _colorSeed = v; (await _p).setInt('colorSeed', v);     notifyListeners(); }
  Future<void> setFontSize(double v)async { _fontSize = v;  (await _p).setDouble('fontSize', v);   notifyListeners(); }
  Future<void> setAvatar(String v)  async { _avatarB64 = v; (await _p).setString('avatar', v);     notifyListeners(); }
}

ColorScheme _scheme(BuildContext ctx) => Theme.of(ctx).colorScheme;

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
//  APP — Material You
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'Meow',
    debugShowCheckedModeBanner: false,
    theme:     ThemeData(colorSchemeSeed: _s.seedColor, brightness: Brightness.light, useMaterial3: true),
    darkTheme: ThemeData(colorSchemeSeed: _s.seedColor, brightness: Brightness.dark,  useMaterial3: true),
    themeMode: _s.dark ? ThemeMode.dark : ThemeMode.light,
    home: const HomeScreen(),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  ГЛАВНЫЙ ЭКРАН
// ════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _s    = AppSettings.instance;
  int             _tab   = 0;
  String          _nick  = 'User';
  List<ChatEntry> _chats = [];
  late final TextEditingController _nickCtrl;

  @override
  void initState() {
    super.initState();
    _nickCtrl = TextEditingController();
    _s.addListener(_r);
    _load();
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

  // ── Аватар ───────────────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final xf = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 70, maxWidth: 300, maxHeight: 300);
    if (xf == null || !mounted) return;
    final b64 = base64Encode(await xf.readAsBytes());
    await _s.setAvatar(b64);
  }

  // ── Диалог добавления/редактирования чата ────────────────────────────────
  void _showChatDialog({ChatEntry? existing, int? index}) {
    final idCtrl  = TextEditingController(text: existing?.id  ?? '');
    final keyCtrl = TextEditingController(text: existing?.key ?? '');
    final isEdit  = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Редактировать чат' : 'Новый чат'),
        icon: Icon(isEdit ? Icons.edit_outlined : Icons.add_comment_outlined),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'ID чата — публичный (все с одинаковым ID попадают в одну комнату).\n'
            'Ключ — приватный. Только те у кого такой же ключ, увидят сообщения.',
            style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: idCtrl,
            readOnly: isEdit,
            decoration: InputDecoration(
              labelText: 'ID чата',
              prefixIcon: const Icon(Icons.tag),
              border: const OutlineInputBorder(),
              filled: true,
              helperText: isEdit ? 'ID нельзя менять' : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: keyCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Ключ шифрования',
              prefixIcon: Icon(Icons.key_outlined),
              border: OutlineInputBorder(),
              filled: true,
              helperText: 'Оставь пустым — сообщения без шифрования',
            ),
          ),
        ]),
        actions: [
          if (isEdit) TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              _chats.removeAt(index!);
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
              if (isEdit) {
                _chats[index!] = entry;
              } else {
                if (!_chats.any((e) => e.id == id)) _chats.add(entry);
              }
              await _saveChats(); setState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(isEdit ? 'Сохранить' : 'Добавить'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = _scheme(context);
    return Scaffold(
      body: _tab == 0 ? _buildChatList(cs) : _buildSettings(cs),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              onPressed: _showChatDialog,
              tooltip: 'Новый чат',
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
  }

  // ── Список чатов ─────────────────────────────────────────────────────────
  Widget _buildChatList(ColorScheme cs) {
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
        SliverFillRemaining(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: cs.outline),
          const SizedBox(height: 16),
          Text('Нет чатов', style: TextStyle(fontSize: 18, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('Нажми + чтобы создать', style: TextStyle(fontSize: 14, color: cs.outline)),
        ])))
      else
        SliverList.builder(
          itemCount: _chats.length,
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
              confirmDismiss: (_) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Удалить чат?'),
                    content: Text('Удалить "${chat.id}" из списка?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
                    ],
                  ),
                );
              },
              onDismissed: (_) async { _chats.removeAt(i); await _saveChats(); setState(() {}); },
              child: ListTile(
                leading: _Avatar(nick: chat.id, radius: 22),
                title: Text(chat.id, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  chat.key.isNotEmpty ? '🔒 Зашифрован' : '🔓 Открытый',
                  style: TextStyle(
                    fontSize: 12,
                    color: chat.key.isNotEmpty ? cs.primary : cs.outline,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _showChatDialog(existing: chat, index: i),
                ),
                onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ChatScreen(roomName: chat.id, encKey: chat.key, myNick: _nick),
                )),
                onLongPress: () => _showChatDialog(existing: chat, index: i),
              ),
            );
          },
        ),
      const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
    ]);
  }

  // ── Настройки ─────────────────────────────────────────────────────────────
  Widget _buildSettings(ColorScheme cs) {
    return CustomScrollView(slivers: [
      const SliverAppBar.large(title: Text('Настройки')),
      SliverList(delegate: SliverChildListDelegate([

        // Профиль
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              const SizedBox(height: 12),
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
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Имя сохранено')));
                  },
                  child: const Text('OK'),
                ),
              ]),
            ]),
          )),
        ),

        // Тема
        const Padding(
          padding: EdgeInsets.fromLTRB(28, 8, 0, 4),
          child: Text('ВНЕШНИЙ ВИД', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.outlined(child: Column(children: [
            SwitchListTile(
              secondary: Icon(_s.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
              title: const Text('Тёмная тема'),
              value: _s.dark,
              onChanged: _s.setDark,
            ),
          ])),
        ),

        const SizedBox(height: 12),

        // Цвет
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.outlined(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Цвет акцента', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              StatefulBuilder(builder: (_, ss) => Wrap(
                spacing: 10, runSpacing: 10,
                children: List.generate(AppSettings.seeds.length, (i) {
                  final sel = _s.colorSeed == i;
                  return InkWell(
                    onTap: () { _s.setColor(i); ss(() {}); },
                    borderRadius: BorderRadius.circular(50),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppSettings.seeds[i],
                        shape: BoxShape.circle,
                        border: sel ? Border.all(color: cs.outline, width: 3) : null,
                        boxShadow: sel ? [BoxShadow(color: AppSettings.seeds[i].withOpacity(0.5), blurRadius: 8)] : null,
                      ),
                      child: sel ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                }),
              )),
            ]),
          )),
        ),

        const SizedBox(height: 12),

        // Размер шрифта
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.outlined(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: StatefulBuilder(builder: (_, ss) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Размер текста', style: Theme.of(context).textTheme.titleSmall),
                  Text('${_s.fontSize.round()} px',
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                ]),
                Slider(
                  value: _s.fontSize, min: 12, max: 22, divisions: 10,
                  label: '${_s.fontSize.round()}',
                  onChanged: (v) { _s.setFontSize(v); ss(() {}); },
                ),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('Привет! Это пример текста сообщения.',
                      style: TextStyle(fontSize: _s.fontSize)),
                ),
                const SizedBox(height: 4),
              ],
            )),
          )),
        ),

        const SizedBox(height: 12),

        // Очистить чаты
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card.outlined(
            child: ListTile(
              leading: Icon(Icons.delete_sweep_outlined, color: cs.error),
              title: Text('Очистить все чаты', style: TextStyle(color: cs.error)),
              onTap: () async {
                final ok = await showDialog<bool>(context: context,
                  builder: (ctx) => AlertDialog(
                    icon: Icon(Icons.warning_outlined, color: cs.error),
                    title: const Text('Очистить все чаты?'),
                    content: const Text('Это удалит список чатов на этом устройстве. Сообщения в БД сохранятся.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
                        onPressed: () => Navigator.pop(ctx, true), child: const Text('Очистить')),
                    ],
                  ),
                );
                if (ok == true) {
                  (await SharedPreferences.getInstance()).remove('chats');
                  setState(() { _chats = []; _tab = 0; });
                }
              },
            ),
          ),
        ),

        const SizedBox(height: 100),
      ])),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ЭКРАН ЧАТА
// ════════════════════════════════════════════════════════════════════════════
class ChatScreen extends StatefulWidget {
  final String roomName;
  final String encKey;   // ключ шифрования (приватный, только на устройстве)
  final String myNick;
  const ChatScreen({super.key, required this.roomName, required this.encKey, required this.myNick});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  final _focus  = FocusNode();
  bool  _hasTxt    = false;
  bool  _uploading = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final h = _ctrl.text.isNotEmpty;
      if (h != _hasTxt) setState(() => _hasTxt = h);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); _scroll.dispose(); _focus.dispose(); super.dispose(); }

  // ── Отправить текст ───────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    _focus.requestFocus();
    try {
      await _sb.from('messages').insert({
        'sender':    widget.myNick,
        'chat_key':  widget.roomName,
        'payload':   _encrypt(text, widget.encKey),
        'file_type': 'text',
      });
    } catch (e) {
      _ctrl.text = text;
      _err('Ошибка: $e');
    }
  }

  // ── Отправить изображение ─────────────────────────────────────────────────
  Future<void> _sendImage({ImageSource src = ImageSource.gallery}) async {
    final xf = await _picker.pickImage(source: src, imageQuality: 75, maxWidth: 1024, maxHeight: 1024);
    if (xf == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xf.readAsBytes();
      if (bytes.length > 700 * 1024) { _err('Фото слишком большое (макс ~700KB)'); return; }
      await _sb.from('messages').insert({
        'sender':    widget.myNick,
        'chat_key':  widget.roomName,
        'payload':   base64Encode(bytes),
        'file_type': 'image',
      });
    } catch (e) { _err('Ошибка: $e'); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  // ── Отправить видео ───────────────────────────────────────────────────────
  Future<void> _sendVideo() async {
    final xf = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 20));
    if (xf == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xf.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) { _err('Видео слишком большое (макс 8MB, 20 сек)'); return; }
      await _sb.from('messages').insert({
        'sender':    widget.myNick,
        'chat_key':  widget.roomName,
        'payload':   base64Encode(bytes),
        'file_type': 'video',
      });
    } catch (e) { _err('Ошибка: $e'); }
    finally { if (mounted) setState(() => _uploading = false); }
  }

  void _err(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Theme.of(context).colorScheme.error));
  }

  void _showAttach() {
    final cs = _scheme(context);
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 32, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
          const Text('Прикрепить', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _AttachChip(icon: Icons.image_outlined,     label: 'Фото',   cs: cs,
                onTap: () { Navigator.pop(context); _sendImage(); }),
            _AttachChip(icon: Icons.videocam_outlined,  label: 'Видео',  cs: cs,
                onTap: () { Navigator.pop(context); _sendVideo(); }),
            _AttachChip(icon: Icons.camera_alt_outlined, label: 'Камера', cs: cs,
                onTap: () { Navigator.pop(context); _sendImage(src: ImageSource.camera); }),
          ]),
          const SizedBox(height: 24),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = _scheme(context);
    final stream = _sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_key', widget.roomName)
        .order('id', ascending: false);

    // На ПК Enter отправляет
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          _Avatar(nick: widget.roomName, radius: 18),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(widget.roomName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(
              widget.encKey.isNotEmpty ? '🔒 Зашифрован' : '🔓 Открытый',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w400),
            ),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog(context: context, builder: (_) => AlertDialog(
              title: Text(widget.roomName),
              content: Text(
                widget.encKey.isNotEmpty
                    ? '🔒 Зашифрованный чат.\n\nСообщения шифруются ключом на вашем устройстве. Только те у кого такой же ключ — видят текст. Остальные видят зашифрованные данные.'
                    : '🔓 Открытый чат.\n\nСообщения хранятся без шифрования. Все кто знает ID чата могут читать сообщения.',
              ),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('ОК'))],
            )),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (ctx, snap) {
              if (snap.hasError) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.error_outline, size: 48, color: cs.error),
                const SizedBox(height: 8),
                Text('Ошибка подключения', style: TextStyle(color: cs.error)),
                const SizedBox(height: 4),
                Text('${snap.error}', style: TextStyle(fontSize: 12, color: cs.outline), textAlign: TextAlign.center),
              ]));
              if (!snap.hasData) return Center(child: CircularProgressIndicator(color: cs.primary));
              final msgs = snap.data!;
              if (msgs.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chat_bubble_outline, size: 56, color: cs.outline),
                const SizedBox(height: 12),
                Text('Напиши первое сообщение 👋',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15)),
              ]));

              return ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: msgs.length,
                itemBuilder: (_, i) {
                  final m      = msgs[i];
                  final sender = (m['sender']    as String?) ?? '?';
                  final ftype  = (m['file_type'] as String?) ?? 'text';
                  final payload= (m['payload']   as String?) ?? '';
                  final isMe   = sender == widget.myNick;
                  final showNick = !isMe && (
                      i == msgs.length - 1 || msgs[i + 1]['sender'] != sender);

                  String time = '';
                  if (m['created_at'] != null) {
                    time = DateTime.parse(m['created_at']).toLocal().toString().substring(11, 16);
                  }

                  // Расшифровка (только для текста)
                  String displayText  = payload;
                  bool   encFail      = false;
                  if (ftype == 'text') {
                    final dec = _tryDecrypt(payload, widget.encKey);
                    if (dec == null) {
                      displayText = '🔐 Зашифровано';
                      encFail     = true;
                    } else {
                      displayText = dec;
                    }
                  }

                  return _BubbleWidget(
                    text: displayText, sender: sender, time: time,
                    fileType: ftype, b64: ftype != 'text' ? payload : '',
                    isMe: isMe, showNick: showNick, encFail: encFail,
                    fontSize: AppSettings.instance.fontSize,
                    cs: cs,
                  );
                },
              );
            },
          ),
        ),

        // ── Поле ввода ──────────────────────────────────────────────────────
        Material(
          elevation: 4,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                // Кнопка прикрепить
                IconButton(
                  onPressed: _uploading ? null : _showAttach,
                  icon: _uploading
                      ? SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                      : const Icon(Icons.attach_file),
                  tooltip: 'Прикрепить',
                ),
                // Поле текста
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
                      controller: _ctrl,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: isDesktop ? 4 : 6,
                      textInputAction: TextInputAction.newline,
                      onSubmitted: isDesktop ? (_) => _send() : null,
                      style: TextStyle(fontSize: AppSettings.instance.fontSize),
                      decoration: InputDecoration(
                        hintText: isDesktop
                            ? 'Сообщение...  (Enter — отправить)'
                            : 'Сообщение...',
                        hintStyle: TextStyle(color: cs.outline, fontSize: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                        filled: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Кнопка отправить
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: _hasTxt
                      ? FloatingActionButton.small(
                          key: const ValueKey('send'),
                          onPressed: _send,
                          elevation: 0,
                          child: const Icon(Icons.send_rounded),
                        )
                      : const SizedBox(key: ValueKey('empty'), width: 40),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ВИДЖЕТ ПУЗЫРЯ
// ════════════════════════════════════════════════════════════════════════════
class _BubbleWidget extends StatelessWidget {
  final String text, sender, time, fileType, b64;
  final bool   isMe, showNick, encFail;
  final double fontSize;
  final ColorScheme cs;

  const _BubbleWidget({
    required this.text, required this.sender, required this.time,
    required this.fileType, required this.b64,
    required this.isMe, required this.showNick, required this.encFail,
    required this.fontSize, required this.cs,
  });

  void _onLongPress(BuildContext ctx) {
    if (fileType != 'text' || encFail) return;
    showModalBottomSheet(
      context: ctx, backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(28)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 32, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Копировать'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Скопировано')));
            },
          ),
          // Ссылки
          ..._urlRegex.allMatches(text).map((m) => ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(m.group(0)!, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () { Navigator.pop(ctx); _openUrl(m.group(0)!); },
          )),
          const SizedBox(height: 8),
        ]),
      )),
    );
  }

  Widget _content(BuildContext ctx) {
    if (fileType == 'image' && b64.isNotEmpty) {
      try {
        final bytes = base64Decode(b64);
        return GestureDetector(
          onTap: () => Navigator.push(ctx, MaterialPageRoute(
              builder: (_) => _FullImageScreen(bytes: bytes))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: 220, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _MediaErr(icon: Icons.broken_image_outlined, label: 'Ошибка фото')),
          ),
        );
      } catch (_) {
        return const _MediaErr(icon: Icons.broken_image_outlined, label: 'Ошибка фото');
      }
    }
    if (fileType == 'video' && b64.isNotEmpty) return _VideoB64(b64: b64);

    // Текст
    if (encFail) return Text(text,
        style: TextStyle(fontSize: fontSize, fontStyle: FontStyle.italic,
            color: isMe ? cs.onPrimary.withOpacity(0.6) : cs.onSurfaceVariant));

    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: TextStyle(fontSize: fontSize,
          color: isMe ? cs.onPrimary : cs.onSurface));
    }
    // Текст со ссылками
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in matches) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final url = m.group(0)!;
      spans.add(WidgetSpan(child: GestureDetector(
        onTap: () => _openUrl(url),
        child: Text(url, style: TextStyle(
          fontSize: fontSize, color: isMe ? cs.onPrimary : cs.primary,
          decoration: TextDecoration.underline,
          decorationColor: isMe ? cs.onPrimary : cs.primary,
        )),
      )));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(text: TextSpan(
      style: TextStyle(fontSize: fontSize, color: isMe ? cs.onPrimary : cs.onSurface),
      children: spans,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isMedia = fileType == 'image' || fileType == 'video';

    return Padding(
      padding: EdgeInsets.only(top: showNick ? 8 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Аватар слева (не мои сообщения)
          if (!isMe) Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: showNick
                ? _Avatar(nick: sender, radius: 14)
                : const SizedBox(width: 28),
          ),
          // Пузырь
          Flexible(
            child: GestureDetector(
              onLongPress: () => _onLongPress(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isMedia ? 240 : MediaQuery.of(context).size.width * 0.72),
                margin: EdgeInsets.only(left: isMe ? 56 : 0, right: isMe ? 0 : 56),
                decoration: BoxDecoration(
                  color: isMe ? cs.primary : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.only(
                    topLeft:     Radius.circular(isMe ? 18 : (showNick ? 4 : 18)),
                    topRight:    Radius.circular(isMe ? (showNick ? 4 : 18) : 18),
                    bottomLeft:  const Radius.circular(18),
                    bottomRight: const Radius.circular(18),
                  ),
                ),
                padding: EdgeInsets.all(isMedia ? 4 : 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showNick) Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(sender, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: _avatarColor(sender),
                      )),
                    ),
                    _content(context),
                    SizedBox(height: isMedia ? 0 : 2),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: isMedia ? const EdgeInsets.only(top: 2, right: 2) : EdgeInsets.zero,
                        child: Text(time, style: TextStyle(
                          fontSize: 10,
                          color: isMe ? cs.onPrimary.withOpacity(0.7) : cs.outline,
                          shadows: isMedia ? [const Shadow(color: Colors.black54, blurRadius: 4)] : null,
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
//  ВИДЕО ИЗ BASE64
// ════════════════════════════════════════════════════════════════════════════
class _VideoB64 extends StatefulWidget {
  final String b64;
  const _VideoB64({required this.b64});
  @override State<_VideoB64> createState() => _VideoB64State();
}

class _VideoB64State extends State<_VideoB64> {
  late final Player            _player;
  late final VideoController   _ctrl;
  bool   _init = false;
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
      final bytes = base64Decode(widget.b64);
      final path  = '${Directory.systemTemp.path}/mv_${widget.b64.hashCode}.mp4';
      final file  = File(path);
      if (!await file.exists()) await file.writeAsBytes(bytes);
      await _player.open(Media('file:///$path'), play: false);
      if (mounted) setState(() => _init = true);
    } catch (e) {
      if (mounted) setState(() => _err = 'Ошибка видео');
    }
  }

  @override
  void dispose() { _player.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_err != null) return _MediaErr(icon: Icons.videocam_off_outlined, label: _err!);
    if (!_init) return Container(
      width: 200, height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => _FullVideoScreen(player: _player, ctrl: _ctrl))),
      child: Stack(alignment: Alignment.center, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 220, height: 140, child: Video(controller: _ctrl, fit: BoxFit.cover)),
        ),
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
    body: Center(child: InteractiveViewer(
      child: Image.memory(bytes, fit: BoxFit.contain),
    )),
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white),
      body: GestureDetector(
        onTap: () { player.state.playing ? player.pause() : player.play(); },
        child: Center(
          child: Video(controller: ctrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
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
        style: TextStyle(color: _avatarColor(nick), fontWeight: FontWeight.w700, fontSize: radius * 0.8),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  МЕЛКИЕ ВИДЖЕТЫ
// ════════════════════════════════════════════════════════════════════════════
class _AttachChip extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap; final ColorScheme cs;
  const _AttachChip({required this.icon, required this.label, required this.onTap, required this.cs});
  @override Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(children: [
        CircleAvatar(
          radius: 28, backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.onPrimaryContainer, size: 24),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface)),
      ]),
    ),
  );
}

class _MediaErr extends StatelessWidget {
  final IconData icon; final String label;
  const _MediaErr({required this.icon, required this.label});
  @override Widget build(BuildContext context) => Container(
    width: 180, height: 60, alignment: Alignment.center,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Theme.of(context).colorScheme.outline, size: 20),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
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
