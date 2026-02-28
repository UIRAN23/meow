import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:url_launcher/url_launcher.dart';

// ════════════════════════════════════════════════════════════════════════════
//  КОНФИГ
// ════════════════════════════════════════════════════════════════════════════
const _supabaseUrl = 'https://ilszhdmqxsoixcefeoqa.supabase.co';
const _supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlsc3poZG1xeHNvaXhjZWZlb3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2NjA4NDMsImV4cCI6MjA3NjIzNjg0M30.aJF9c3RaNvAk4_9nLYhQABH3pmYUcZ0q2udf2LoA6Sc';

// ════════════════════════════════════════════════════════════════════════════
//  МОДЕЛЬ ЧАТА
// ════════════════════════════════════════════════════════════════════════════
class ChatEntry {
  final String id;
  final String key;
  ChatEntry(this.id, this.key);

  // Разделитель \x01 — безопаснее чем ':', который может быть в ключе
  String serialize() => '$id\x01$key';

  static ChatEntry from(String s) {
    final idx = s.indexOf('\x01');
    if (idx != -1) return ChatEntry(s.substring(0, idx), s.substring(idx + 1));
    // Обратная совместимость со старым форматом "id:key"
    final ci = s.indexOf(':');
    if (ci == -1) return ChatEntry(s, '');
    return ChatEntry(s.substring(0, ci), s.substring(ci + 1));
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  НАСТРОЙКИ
// ════════════════════════════════════════════════════════════════════════════
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();

  bool   _dark         = true;
  int    _accentIdx    = 0;
  double _fontSize     = 15;
  int    _bubbleStyle  = 0;   // 0=скруглённые 1=острые 2=telegram
  int    _chatBg       = 0;   // 0=нет 1=точки 2=линии 3=сетка
  double _glassBlur    = 20;
  double _glassOpacity = 0.15;

  bool   get dark         => _dark;
  int    get accentIdx    => _accentIdx;
  double get fontSize     => _fontSize;
  int    get bubbleStyle  => _bubbleStyle;
  int    get chatBg       => _chatBg;
  double get glassBlur    => _glassBlur;
  double get glassOpacity => _glassOpacity;

  static const accents = [
    Color(0xFF6C63FF), // фиолетовый
    Color(0xFF2090FF), // синий
    Color(0xFF00C896), // мятный
    Color(0xFFFF5F7E), // розовый
    Color(0xFFFF9500), // оранжевый
    Color(0xFF34C759), // зелёный
  ];

  Color get accent => accents[_accentIdx];

  Future<void> init() async {
    final p      = await SharedPreferences.getInstance();
    _dark        = p.getBool('dark')          ?? true;
    _accentIdx   = p.getInt('accentIdx')      ?? 0;
    _fontSize    = p.getDouble('fontSize')    ?? 15;
    _bubbleStyle = p.getInt('bubbleStyle')    ?? 0;
    _chatBg      = p.getInt('chatBg')         ?? 0;
    _glassBlur   = p.getDouble('glassBlur')   ?? 20;
    _glassOpacity = p.getDouble('glassOpacity') ?? 0.15;
    notifyListeners();
  }

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  Future<void> setDark(bool v)           async { _dark = v;         (await _p).setBool('dark', v);            notifyListeners(); }
  Future<void> setAccent(int v)          async { _accentIdx = v;    (await _p).setInt('accentIdx', v);        notifyListeners(); }
  Future<void> setFontSize(double v)     async { _fontSize = v;     (await _p).setDouble('fontSize', v);      notifyListeners(); }
  Future<void> setBubbleStyle(int v)     async { _bubbleStyle = v;  (await _p).setInt('bubbleStyle', v);      notifyListeners(); }
  Future<void> setChatBg(int v)          async { _chatBg = v;       (await _p).setInt('chatBg', v);           notifyListeners(); }
  Future<void> setGlassBlur(double v)    async { _glassBlur = v;    (await _p).setDouble('glassBlur', v);     notifyListeners(); }
  Future<void> setGlassOpacity(double v) async { _glassOpacity = v; (await _p).setDouble('glassOpacity', v);  notifyListeners(); }
}

// ════════════════════════════════════════════════════════════════════════════
//  ШИФРОВАНИЕ — идентично itoryon/meow
// ════════════════════════════════════════════════════════════════════════════
String _encrypt(String text, String rawKey) {
  if (rawKey.isEmpty) return text;
  final key = enc.Key.fromUtf8(rawKey.padRight(32).substring(0, 32));
  final iv  = enc.IV.fromLength(16);
  return enc.Encrypter(enc.AES(key)).encrypt(text, iv: iv).base64;
}

String _decrypt(String text, String rawKey) {
  if (rawKey.isEmpty) return text;
  try {
    final key = enc.Key.fromUtf8(rawKey.padRight(32).substring(0, 32));
    final iv  = enc.IV.fromLength(16);
    return enc.Encrypter(enc.AES(key)).decrypt64(text, iv: iv);
  } catch (_) {
    return text; // не расшифровалось — показываем как есть
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  УТИЛИТЫ
// ════════════════════════════════════════════════════════════════════════════
Color _avatarColor(String n) =>
    Colors.primaries[n.hashCode.abs() % Colors.primaries.length];

// Читаем отправителя из обоих полей для совместимости с itoryon/meow
// Оригинал пишет в 'sender_', наш форк пишет в 'sender'
String _readSender(Map<String, dynamic> m) =>
    (m['sender'] as String?)?.isNotEmpty == true
        ? m['sender'] as String
        : (m['sender_'] as String?) ?? '?';

// Регулярка для URL
final _urlRegex = RegExp(
  r'(https?://[^\s]+|www\.[^\s]+\.[^\s]{2,})',
  caseSensitive: false,
);

Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ТОЧКА ВХОДА
// ════════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:                    Colors.transparent,
    statusBarIconBrightness:           Brightness.light,
    systemNavigationBarColor:          Colors.transparent,
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
  Widget build(BuildContext context) {
    final dark   = _s.dark;
    final accent = _s.accent;
    final bg     = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF2F2F7);
    final surf   = dark ? const Color(0xFF1C1C2E) : Colors.white;
    final hint   = dark ? const Color(0xFF7070A0) : const Color(0xFF999999);

    return MaterialApp(
      title: 'Meow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness:              dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bg,
        primaryColor:            accent,
        colorScheme: ColorScheme(
          brightness:  dark ? Brightness.dark : Brightness.light,
          primary:     accent, secondary: accent, surface: surf,
          error:       Colors.red, onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface:   dark ? Colors.white : Colors.black,
          onError:     Colors.white,
        ),
        hintColor:    hint,
        dividerColor: dark ? const Color(0xFF252535) : const Color(0xFFDDDDE8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0, scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white, fontSize: 18,
            fontWeight: FontWeight.w700, letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LIQUID GLASS ВИДЖЕТ
// ════════════════════════════════════════════════════════════════════════════
class Glass extends StatelessWidget {
  final Widget       child;
  final BorderRadius? radius;
  final EdgeInsets?   padding;
  final Color?        borderColor;
  final double?       blur;
  final double?       opacity;

  const Glass({
    super.key, required this.child,
    this.radius, this.padding, this.borderColor, this.blur, this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    final s    = AppSettings.instance;
    final b    = blur    ?? s.glassBlur;
    final op   = opacity ?? s.glassOpacity;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final br   = radius ?? BorderRadius.circular(20);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: b, sigmaY: b),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: br,
            color: (dark ? Colors.white : Colors.black).withOpacity(op),
            border: Border.all(
              color: borderColor ?? Colors.white.withOpacity(dark ? 0.12 : 0.5),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ГЛАВНЫЙ ЭКРАН
// ════════════════════════════════════════════════════════════════════════════
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _s        = AppSettings.instance;
  String          _nick  = 'User';
  List<ChatEntry> _chats = [];
  int             _tab   = 0;

  // FIX: контроллер ника живёт в State, не пересоздаётся при каждом build()
  late final TextEditingController _nickCtrl;

  @override
  void initState() {
    super.initState();
    _nickCtrl = TextEditingController(text: _nick);
    _s.addListener(_r);
    _load();
  }

  @override
  void dispose() {
    _s.removeListener(_r);
    _nickCtrl.dispose(); // правильно чистим
    super.dispose();
  }

  void _r() => setState(() {});

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final nick = p.getString('nickname') ?? 'User';
    setState(() {
      _nick  = nick;
      _nickCtrl.text = nick; // синхронизируем контроллер
      _chats = (p.getStringList('chats') ?? []).map(ChatEntry.from).toList();
    });
  }

  Future<void> _saveChats() async =>
      (await SharedPreferences.getInstance())
          .setStringList('chats', _chats.map((e) => e.serialize()).toList());

  // ── Добавить / редактировать чат ─────────────────────────────────────────
  void _showChatSheet({ChatEntry? existing, int? index}) {
    final idCtrl  = TextEditingController(text: existing?.id  ?? '');
    final keyCtrl = TextEditingController(text: existing?.key ?? '');
    final isEdit  = existing != null;

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ручка
            Center(child: Container(
              width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isEdit ? 'Редактировать' : 'Новый чат',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                if (isEdit)
                  GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      _chats.removeAt(index!);
                      await _saveChats();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('ID и ключ должны совпадать у обоих',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 18),
            _GlassField(
              controller: idCtrl, hint: 'ID чата (chat_key)',
              icon: Icons.tag,
              readOnly: isEdit, // нельзя менять ID существующего чата
            ),
            const SizedBox(height: 10),
            _GlassField(
              controller: keyCtrl,
              hint: 'Ключ шифрования (необязательно)',
              icon: Icons.key_outlined,
            ),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.info_outline, size: 14, color: _s.accent.withOpacity(0.7)),
              const SizedBox(width: 6),
              Expanded(child: Text(
                isEdit
                    ? 'Изменяешь ключ — старые сообщения не расшифруются'
                    : 'Ключ нужен для шифрования. Без него сообщения хранятся открыто',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.4)),
              )),
            ]),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity, height: 50,
              child: _GlassButton(
                color: _s.accent,
                onTap: () async {
                  final id = idCtrl.text.trim();
                  if (id.isEmpty) return;
                  final entry = ChatEntry(id, keyCtrl.text.trim());
                  if (isEdit) {
                    _chats[index!] = entry;
                  } else {
                    if (!_chats.any((e) => e.id == id)) _chats.add(entry);
                  }
                  await _saveChats();
                  setState(() {});
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(
                  isEdit ? 'Сохранить' : 'Добавить',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _s.dark;
    final bg   = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bg,
      extendBody: true,
      body: Stack(children: [
        _BgGlow(color: _s.accent),
        _tab == 0 ? _buildChats() : _buildSettings(),
      ]),

      // ── Liquid Glass Bottom Bar ──────────────────────────────────────────
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 12),
        child: Glass(
          blur: _s.glassBlur, opacity: dark ? 0.2 : 0.5,
          radius: BorderRadius.circular(28),
          borderColor: Colors.white.withOpacity(0.15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.forum_outlined,    label: 'Чаты',      selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
                // FAB по центру
                GestureDetector(
                  onTap: _showChatSheet,
                  child: Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_s.accent, _s.accent.withOpacity(0.7)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color: _s.accent.withOpacity(0.4),
                        blurRadius: 16, offset: const Offset(0, 4),
                      )],
                    ),
                    child: const Icon(Icons.edit_outlined, color: Colors.white, size: 22),
                  ),
                ),
                _NavItem(icon: Icons.settings_outlined,  label: 'Настройки', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Список чатов ─────────────────────────────────────────────────────────
  Widget _buildChats() {
    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true, floating: false,
        expandedHeight: 100, collapsedHeight: 60,
        backgroundColor: Colors.transparent,
        flexibleSpace: FlexibleSpaceBar(
          titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
          title: Text('Meow', style: TextStyle(
            fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white,
            shadows: [Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
          )),
          background: ClipRect(child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _s.glassBlur, sigmaY: _s.glassBlur),
            child: Container(color: Colors.transparent),
          )),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8),
            child: Glass(
              radius: BorderRadius.circular(20), blur: 15,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(_nick,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
            ),
          ),
        ],
      ),

      if (_chats.isEmpty)
        SliverFillRemaining(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined, size: 72, color: Colors.white.withOpacity(0.15)),
          const SizedBox(height: 16),
          Text('Нет чатов', style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Нажми + чтобы добавить', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.25))),
        ])))
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          sliver: SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) {
              final chat = _chats[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Glass(
                  blur: _s.glassBlur, opacity: 0.12,
                  radius: BorderRadius.circular(20),
                  child: ListTile(
                    onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ChatScreen(roomName: chat.id, encryptionKey: chat.key, myNick: _nick),
                    )),
                    onLongPress: () => _showChatSheet(existing: chat, index: i),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: _avatarColor(chat.id).withOpacity(0.25),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(chat.id[0].toUpperCase(),
                          style: TextStyle(color: _avatarColor(chat.id), fontWeight: FontWeight.w800, fontSize: 18))),
                    ),
                    title: Text(chat.id,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white)),
                    subtitle: Text(
                      chat.key.isNotEmpty ? '🔒 Зашифрован' : '🔓 Без шифрования',
                      style: TextStyle(fontSize: 12,
                          color: chat.key.isNotEmpty ? _s.accent : Colors.white.withOpacity(0.4)),
                    ),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      GestureDetector(
                        onTap: () => _showChatSheet(existing: chat, index: i),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.edit_outlined, color: Colors.white.withOpacity(0.3), size: 18),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.3)),
                    ]),
                  ),
                ),
              );
            },
            childCount: _chats.length,
          )),
        ),
    ]);
  }

  // ── Настройки ─────────────────────────────────────────────────────────────
  Widget _buildSettings() {
    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true, backgroundColor: Colors.transparent,
        collapsedHeight: 60, expandedHeight: 100,
        flexibleSpace: FlexibleSpaceBar(
          titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
          title: const Text('Настройки',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
          background: ClipRect(child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _s.glassBlur, sigmaY: _s.glassBlur),
            child: Container(color: Colors.transparent),
          )),
        ),
      ),

      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        sliver: SliverList(delegate: SliverChildListDelegate([

          // ── Профиль ────────────────────────────────────────────────────
          _Section('ПРОФИЛЬ', [
            Padding(padding: const EdgeInsets.all(16), child: Row(children: [
              // FIX: используем _nickCtrl из State, не создаём новый каждый раз
              Expanded(child: _GlassField(controller: _nickCtrl, hint: 'Твоё имя', icon: Icons.person_outline)),
              const SizedBox(width: 10),
              _GlassButton(
                color: _s.accent,
                onTap: () async {
                  final n = _nickCtrl.text.trim();
                  if (n.isEmpty) return;
                  (await SharedPreferences.getInstance()).setString('nickname', n);
                  setState(() => _nick = n);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Имя сохранено'),
                      duration: Duration(seconds: 2),
                    ));
                  }
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ])),
          ]),

          const SizedBox(height: 16),

          // ── Тема ───────────────────────────────────────────────────────
          _Section('ТЕМА', [
            _GlassSwitch(
              label: 'Тёмная тема',
              icon:  _s.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              value: _s.dark, onChanged: _s.setDark,
            ),
          ]),

          const SizedBox(height: 16),

          // ── Цвет акцента ───────────────────────────────────────────────
          _Section('ЦВЕТ АКЦЕНТА', [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: StatefulBuilder(builder: (_, ss) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(AppSettings.accents.length, (i) {
                  final sel = _s.accentIdx == i;
                  return GestureDetector(
                    onTap: () { _s.setAccent(i); ss(() {}); },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppSettings.accents[i], shape: BoxShape.circle,
                        border: sel ? Border.all(color: Colors.white, width: 3) : null,
                        boxShadow: sel ? [BoxShadow(
                          color: AppSettings.accents[i].withOpacity(0.6),
                          blurRadius: 12, spreadRadius: 1,
                        )] : null,
                      ),
                      child: sel ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  );
                }),
              )),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Liquid Glass ───────────────────────────────────────────────
          _Section('LIQUID GLASS', [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: StatefulBuilder(builder: (_, ss) => Column(children: [

                // Blur
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Размытие', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                  Glass(radius: BorderRadius.circular(16), blur: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      child: Text('${_s.glassBlur.round()}px',
                          style: TextStyle(color: _s.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                ]),
                _StyledSlider(
                  value: _s.glassBlur, min: 0, max: 40, divisions: 40,
                  onChanged: (v) { _s.setGlassBlur(v); ss(() {}); },
                ),

                const SizedBox(height: 8),

                // Opacity
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Прозрачность', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
                  Glass(radius: BorderRadius.circular(16), blur: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      child: Text('${(_s.glassOpacity * 100).round()}%',
                          style: TextStyle(color: _s.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                ]),
                _StyledSlider(
                  value: _s.glassOpacity, min: 0.03, max: 0.5, divisions: 47,
                  onChanged: (v) { _s.setGlassOpacity(v); ss(() {}); },
                ),

                const SizedBox(height: 8),
                // Превью
                Glass(
                  blur: _s.glassBlur, opacity: _s.glassOpacity,
                  radius: BorderRadius.circular(14),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Center(child: Text('Превью стекла 🪟',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500))),
                  ),
                ),
                const SizedBox(height: 8),
              ])),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Размер шрифта ──────────────────────────────────────────────
          _Section('РАЗМЕР ТЕКСТА', [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: StatefulBuilder(builder: (_, ss) => Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Аа', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  Glass(radius: BorderRadius.circular(16), blur: 8,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      child: Text('${_s.fontSize.round()} px',
                          style: TextStyle(color: _s.accent, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ),
                  Text('Аа', style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.5))),
                ]),
                _StyledSlider(
                  value: _s.fontSize, min: 11, max: 22, divisions: 11,
                  onChanged: (v) { _s.setFontSize(v); ss(() {}); },
                ),
                Glass(
                  radius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Center(child: Text('Привет! Это пример текста.',
                        style: TextStyle(fontSize: _s.fontSize, color: Colors.white))),
                  ),
                ),
                const SizedBox(height: 8),
              ])),
            ),
          ]),

          const SizedBox(height: 16),

          // ── Форма пузырей ──────────────────────────────────────────────
          _Section('ФОРМА ПУЗЫРЕЙ', [
            _Radio('Скруглённые', 0, _s.bubbleStyle, _s.setBubbleStyle),
            _Radio('Острые',      1, _s.bubbleStyle, _s.setBubbleStyle),
            _Radio('Telegram',    2, _s.bubbleStyle, _s.setBubbleStyle),
          ]),

          const SizedBox(height: 16),

          // ── Фон чата ───────────────────────────────────────────────────
          _Section('ФОН ЧАТА', [
            _Radio('Без фона', 0, _s.chatBg, _s.setChatBg),
            _Radio('Точки',    1, _s.chatBg, _s.setChatBg),
            _Radio('Линии',    2, _s.chatBg, _s.setChatBg),
            _Radio('Сетка',    3, _s.chatBg, _s.setChatBg),
          ]),

          const SizedBox(height: 16),

          // ── Опасная зона ───────────────────────────────────────────────
          GestureDetector(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1C1C2E),
                  title: const Text('Очистить все чаты?', style: TextStyle(color: Colors.white)),
                  content: const Text('Это действие нельзя отменить.',
                      style: TextStyle(color: Colors.white54)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Удалить', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                (await SharedPreferences.getInstance()).remove('chats');
                setState(() { _chats = []; _tab = 0; });
              }
            },
            child: Glass(
              radius: BorderRadius.circular(16),
              borderColor: Colors.red.withOpacity(0.3),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Очистить все чаты',
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ])),
              ),
            ),
          ),
        ])),
      ),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ЭКРАН ЧАТА
// ════════════════════════════════════════════════════════════════════════════
class ChatScreen extends StatefulWidget {
  final String roomName;
  final String encryptionKey;
  final String myNick;
  const ChatScreen({super.key, required this.roomName, required this.encryptionKey, required this.myNick});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _s      = AppSettings.instance;
  final _ctrl   = TextEditingController();
  final _sb     = Supabase.instance.client;
  final _scroll = ScrollController();
  bool  _hasTxt = false;

  @override
  void initState() {
    super.initState();
    _s.addListener(_r);
    _ctrl.addListener(() {
      final has = _ctrl.text.isNotEmpty;
      if (has != _hasTxt) setState(() => _hasTxt = has);
    });
  }

  @override
  void dispose() {
    _s.removeListener(_r);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _r() => setState(() {});

  void _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      // 'sender' — правильное имя колонки в реальной БД
      await _sb.from('messages').insert({
        'sender':   widget.myNick,
        'payload':  _encrypt(text, widget.encryptionKey),
        'chat_key': widget.roomName,
      });
    } catch (e) {
      _ctrl.text = text;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка отправки: $e'),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // stream() — совместимо с itoryon/meow
    final stream = _sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_key', widget.roomName)
        .order('id', ascending: false);

    final dark = _s.dark;
    final bg   = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF2F2F7);

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _s.glassBlur, sigmaY: _s.glassBlur),
            child: AppBar(
              backgroundColor: Colors.black.withOpacity(_s.glassOpacity * 2),
              title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.roomName),
                Text(
                  widget.encryptionKey.isNotEmpty ? '🔒 E2EE' : '🔓 Без шифрования',
                  style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6), fontWeight: FontWeight.w400),
                ),
              ]),
            ),
          ),
        ),
      ),
      body: Stack(children: [
        _BgGlow(color: _s.accent, intensity: 0.3),
        CustomPaint(
          painter: _BgPainter(_s.chatBg, _s.accent.withOpacity(0.05)),
          child: const SizedBox.expand(),
        ),
        Column(children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (ctx, snap) {
                if (snap.hasError) return Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ошибка: ${snap.error}', textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.5))),
                ));
                if (!snap.hasData) return Center(child: CircularProgressIndicator(color: _s.accent));

                final msgs = snap.data!;
                if (msgs.isEmpty) return Center(child: Text('Напиши первое сообщение 👋',
                    style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15)));

                return ListView.builder(
                  controller: _scroll, reverse: true,
                  padding: EdgeInsets.fromLTRB(10, MediaQuery.of(ctx).padding.top + 70, 10, 100),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m      = msgs[i];
                    // FIX: читаем оба поля — 'sender' и 'sender_' для совместимости
                    final sender = _readSender(m);
                    final isMe   = sender == widget.myNick;
                    final raw    = (m['payload'] as String?) ?? '';
                    final text   = _decrypt(raw, widget.encryptionKey);
                    final showNick = !isMe && (
                      i == msgs.length - 1 ||
                      _readSender(msgs[i + 1]) != sender
                    );
                    String time = '';
                    if (m['created_at'] != null) {
                      time = DateTime.parse(m['created_at']).toLocal().toString().substring(11, 16);
                    }
                    return _Bubble(
                      text: text, sender: sender, time: time,
                      isMe: isMe, showNick: showNick,
                      style: _s.bubbleStyle, fontSize: _s.fontSize,
                      accent: _s.accent, dark: dark,
                      glassBlur: _s.glassBlur,
                    );
                  },
                );
              },
            ),
          ),

          // ── Liquid glass поле ввода ─────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 12),
            child: Glass(
              blur: _s.glassBlur, opacity: _s.glassOpacity * 1.5,
              radius: BorderRadius.circular(28),
              borderColor: Colors.white.withOpacity(0.15),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: TextField(
                      controller: _ctrl, maxLines: 5, minLines: 1,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Сообщение...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
                        border: InputBorder.none, focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none, fillColor: Colors.transparent,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                      ),
                    )),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: _hasTxt
                          ? GestureDetector(
                              key: const ValueKey('send'), onTap: _send,
                              child: Container(
                                width: 40, height: 40,
                                margin: const EdgeInsets.only(bottom: 2),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [_s.accent, _s.accent.withOpacity(0.7)],
                                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: _s.accent.withOpacity(0.4), blurRadius: 10)],
                                ),
                                child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                              ),
                            )
                          : const SizedBox(key: ValueKey('empty'), width: 40),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ПУЗЫРЬ СООБЩЕНИЯ — с копированием и ссылками
// ════════════════════════════════════════════════════════════════════════════
class _Bubble extends StatelessWidget {
  final String  text;
  final String  sender;
  final String  time;
  final bool    isMe;
  final bool    showNick;
  final int     style;
  final double  fontSize;
  final Color   accent;
  final bool    dark;
  final double  glassBlur;

  const _Bubble({
    super.key,
    required this.text, required this.sender, required this.time,
    required this.isMe, required this.showNick, required this.style,
    required this.fontSize, required this.accent, required this.dark,
    required this.glassBlur,
  });

  BorderRadius _radius() {
    switch (style) {
      case 1: return BorderRadius.only(
        topLeft:     Radius.circular(isMe ? 18 : 4),
        topRight:    Radius.circular(isMe ? 4 : 18),
        bottomLeft:  const Radius.circular(18),
        bottomRight: const Radius.circular(18));
      case 2: return BorderRadius.only(
        topLeft:     const Radius.circular(18),
        topRight:    const Radius.circular(18),
        bottomLeft:  Radius.circular(isMe ? 18 : 4),
        bottomRight: Radius.circular(isMe ? 4 : 18));
      default: return BorderRadius.only(
        topLeft:     Radius.circular(isMe ? 18 : (showNick ? 4 : 18)),
        topRight:    Radius.circular(isMe ? (showNick ? 4 : 18) : 18),
        bottomLeft:  const Radius.circular(18),
        bottomRight: const Radius.circular(18));
    }
  }

  void _onLongPress(BuildContext context) {
    final urls = _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _GlassSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            // Копировать текст
            ListTile(
              leading: const Icon(Icons.copy_outlined, color: Colors.white70),
              title: const Text('Копировать', style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Скопировано'),
                  duration: Duration(seconds: 2),
                ));
              },
            ),
            // Ссылки
            ...urls.map((url) => ListTile(
              leading: const Icon(Icons.open_in_new, color: Colors.lightBlueAccent),
              title: Text(url,
                  style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 13),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(context);
                _openUrl(url);
              },
            )),
          ],
        ),
      ),
    );
  }

  // Текст с подсветкой ссылок
  Widget _buildText() {
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.35));
    }

    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () => _openUrl(url),
          child: Text(url, style: TextStyle(
            fontSize: fontSize, height: 1.35,
            color: Colors.lightBlueAccent,
            decoration: TextDecoration.underline,
            decorationColor: Colors.lightBlueAccent,
          )),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return RichText(text: TextSpan(
      style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.35),
      children: spans,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final br = _radius();

    return Padding(
      padding: EdgeInsets.only(top: showNick ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment:  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Аватар
          if (!isMe) Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: showNick
                ? CircleAvatar(
                    radius: 14,
                    backgroundColor: _avatarColor(sender).withOpacity(0.25),
                    child: Text(sender[0].toUpperCase(),
                        style: TextStyle(fontSize: 11, color: _avatarColor(sender), fontWeight: FontWeight.w800)),
                  )
                : const SizedBox(width: 28),
          ),

          // Пузырь
          Flexible(
            child: GestureDetector(
              onLongPress: () => _onLongPress(context),
              child: ClipRRect(
                borderRadius: br,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
                  child: Container(
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.73),
                    margin: EdgeInsets.only(left: isMe ? 56 : 0, right: isMe ? 0 : 56),
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    decoration: BoxDecoration(
                      borderRadius: br,
                      color: isMe
                          ? accent.withOpacity(0.75)
                          : Colors.white.withOpacity(dark ? 0.1 : 0.6),
                      border: Border.all(
                        color: isMe ? accent.withOpacity(0.4) : Colors.white.withOpacity(0.15),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showNick) Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(sender, style: TextStyle(
                              color: _avatarColor(sender), fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        _buildText(),
                        const SizedBox(height: 3),
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Text(time, style: TextStyle(
                              color: Colors.white.withOpacity(0.5), fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
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
//  ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ
// ════════════════════════════════════════════════════════════════════════════
class _BgGlow extends StatelessWidget {
  final Color  color;
  final double intensity;
  const _BgGlow({required this.color, this.intensity = 0.15});
  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned(top: -100, right: -80, child: Container(width: 300, height: 300,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(
          color: color.withOpacity(intensity), blurRadius: 120, spreadRadius: 40)]))),
    Positioned(bottom: 50, left: -60, child: Container(width: 250, height: 250,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(
          color: color.withOpacity(intensity * 0.6), blurRadius: 100, spreadRadius: 30)]))),
  ]);
}

class _BgPainter extends CustomPainter {
  final int type; final Color color;
  const _BgPainter(this.type, this.color);
  @override void paint(Canvas canvas, Size size) {
    if (type == 0) return;
    final p = Paint()..color = color..strokeWidth = 1;
    switch (type) {
      case 1:
        for (double x = 16; x < size.width; x += 24)
          for (double y = 16; y < size.height; y += 24)
            canvas.drawCircle(Offset(x, y), 1.5, p);
        break;
      case 2:
        for (double y = 0; y < size.height; y += 28)
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        break;
      case 3:
        for (double x = 0; x < size.width; x += 28)
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
        for (double y = 0; y < size.height; y += 28)
          canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
        break;
    }
  }
  @override bool shouldRepaint(_BgPainter o) => o.type != type;
}

class _GlassSheet extends StatelessWidget {
  final Widget child;
  const _GlassSheet({required this.child});
  @override Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: s.glassBlur, sigmaY: s.glassBlur),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(s.glassOpacity),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15), width: 0.8)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  final TextEditingController controller;
  final String hint; final IconData icon; final bool readOnly;
  const _GlassField({required this.controller, required this.hint, required this.icon, this.readOnly = false});
  @override Widget build(BuildContext context) {
    final s = AppSettings.instance;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: s.glassBlur, sigmaY: s.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(readOnly ? 0.05 : s.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8),
          ),
          child: TextField(
            controller: controller, readOnly: readOnly,
            style: TextStyle(color: readOnly ? Colors.white.withOpacity(0.5) : Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
              prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.4), size: 20),
              border: InputBorder.none, focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none, fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final Widget child; final Color color; final VoidCallback onTap;
  const _GlassButton({required this.child, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    ),
  );
}

class _Section extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Section(this.title, this.children);
  @override Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          letterSpacing: 1.2, color: AppSettings.instance.accent,
        )),
      ),
      Glass(radius: BorderRadius.circular(20), child: Column(children: children)),
    ],
  );
}

class _GlassSwitch extends StatelessWidget {
  final String label; final IconData icon; final bool value;
  final Future<void> Function(bool) onChanged;
  const _GlassSwitch({required this.label, required this.icon, required this.value, required this.onChanged});
  @override Widget build(BuildContext context) => SwitchListTile(
    value: value, onChanged: onChanged,
    secondary: Icon(icon, color: Colors.white.withOpacity(0.6)),
    title: Text(label, style: const TextStyle(color: Colors.white)),
    activeColor: AppSettings.instance.accent,
    activeTrackColor: AppSettings.instance.accent.withOpacity(0.4),
  );
}

class _Radio extends StatelessWidget {
  final String label; final int value; final int groupValue;
  final Future<void> Function(int) onChanged;
  const _Radio(this.label, this.value, this.groupValue, this.onChanged);
  @override Widget build(BuildContext context) => RadioListTile<int>(
    value: value, groupValue: groupValue,
    onChanged: (v) => onChanged(v!),
    title: Text(label, style: const TextStyle(color: Colors.white)),
    activeColor: AppSettings.instance.accent, dense: true,
  );
}

class _StyledSlider extends StatelessWidget {
  final double value, min, max;
  final int    divisions;
  final void Function(double) onChanged;
  const _StyledSlider({required this.value, required this.min, required this.max, required this.divisions, required this.onChanged});
  @override Widget build(BuildContext context) {
    final accent = AppSettings.instance.accent;
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor:   accent,
        thumbColor:         accent,
        inactiveTrackColor: accent.withOpacity(0.2),
        overlayColor:       accent.withOpacity(0.15),
        trackHeight:        3,
      ),
      child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon; final String label;
  final bool selected; final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});
  @override Widget build(BuildContext context) {
    final accent = AppSettings.instance.accent;
    return GestureDetector(
      onTap: onTap, behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? accent.withOpacity(0.2) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: selected ? accent : Colors.white.withOpacity(0.4), size: 22),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: selected ? accent : Colors.white.withOpacity(0.35),
          )),
        ]),
      ),
    );
  }
}
