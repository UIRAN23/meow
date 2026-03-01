// ════════════════════════════════════════════════════════════════════════════
//  SQL для Supabase (выполни один раз в SQL Editor):
//
//  create table messages (
//    id         bigint generated always as identity primary key,
//    created_at timestamptz default now(),
//    sender     text not null,
//    chat_key   text not null,
//    payload    text default '',
//    file_url   text,
//    file_type  text default 'text'
//  );
//  create index on messages(chat_key, id);
//  alter table messages disable row level security;
//
//  insert into storage.buckets (id, name, public)
//    values ('media', 'media', true);
//  create policy "media_all" on storage.objects for all
//    using (bucket_id = 'media') with check (bucket_id = 'media');
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

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
    final idx = s.indexOf('\x01');
    if (idx != -1) return ChatEntry(s.substring(0, idx), s.substring(idx + 1));
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
  int    _bubbleStyle  = 0;
  int    _chatBg       = 0;
  double _glassBlur    = 20;
  double _glassOpacity = 0.15;
  String _avatarUrl    = '';

  bool   get dark         => _dark;
  int    get accentIdx    => _accentIdx;
  double get fontSize     => _fontSize;
  int    get bubbleStyle  => _bubbleStyle;
  int    get chatBg       => _chatBg;
  double get glassBlur    => _glassBlur;
  double get glassOpacity => _glassOpacity;
  String get avatarUrl    => _avatarUrl;

  static const accents = [
    Color(0xFF6C63FF),
    Color(0xFF2090FF),
    Color(0xFF00C896),
    Color(0xFFFF5F7E),
    Color(0xFFFF9500),
    Color(0xFF34C759),
  ];
  Color get accent => accents[_accentIdx];

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _dark         = p.getBool('dark')          ?? true;
    _accentIdx    = p.getInt('accentIdx')      ?? 0;
    _fontSize     = p.getDouble('fontSize')    ?? 15;
    _bubbleStyle  = p.getInt('bubbleStyle')    ?? 0;
    _chatBg       = p.getInt('chatBg')         ?? 0;
    _glassBlur    = p.getDouble('glassBlur')   ?? 20;
    _glassOpacity = p.getDouble('glassOpacity') ?? 0.15;
    _avatarUrl    = p.getString('avatarUrl')   ?? '';
    notifyListeners();
  }

  Future<SharedPreferences> get _p => SharedPreferences.getInstance();
  Future<void> setDark(bool v)           async { _dark = v;         (await _p).setBool('dark', v);           notifyListeners(); }
  Future<void> setAccent(int v)          async { _accentIdx = v;    (await _p).setInt('accentIdx', v);       notifyListeners(); }
  Future<void> setFontSize(double v)     async { _fontSize = v;     (await _p).setDouble('fontSize', v);     notifyListeners(); }
  Future<void> setBubbleStyle(int v)     async { _bubbleStyle = v;  (await _p).setInt('bubbleStyle', v);     notifyListeners(); }
  Future<void> setChatBg(int v)          async { _chatBg = v;       (await _p).setInt('chatBg', v);          notifyListeners(); }
  Future<void> setGlassBlur(double v)    async { _glassBlur = v;    (await _p).setDouble('glassBlur', v);    notifyListeners(); }
  Future<void> setGlassOpacity(double v) async { _glassOpacity = v; (await _p).setDouble('glassOpacity', v); notifyListeners(); }
  Future<void> setAvatarUrl(String v)    async { _avatarUrl = v;    (await _p).setString('avatarUrl', v);    notifyListeners(); }
}

// ════════════════════════════════════════════════════════════════════════════
//  ШИФРОВАНИЕ — совместимо с itoryon/meow
// ════════════════════════════════════════════════════════════════════════════
String _encrypt(String text, String rawKey) {
  if (rawKey.isEmpty) return text;
  final key = enc.Key.fromUtf8(rawKey.padRight(32).substring(0, 32));
  return enc.Encrypter(enc.AES(key)).encrypt(text, iv: enc.IV.fromLength(16)).base64;
}

String _decrypt(String text, String rawKey) {
  if (rawKey.isEmpty) return text;
  try {
    final key = enc.Key.fromUtf8(rawKey.padRight(32).substring(0, 32));
    return enc.Encrypter(enc.AES(key)).decrypt64(text, iv: enc.IV.fromLength(16));
  } catch (_) {
    return text;
  }
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

String _uid() => DateTime.now().millisecondsSinceEpoch.toString();

// ════════════════════════════════════════════════════════════════════════════
//  ТОЧКА ВХОДА
// ════════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
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
    final bg     = dark ? const Color(0xFF080810) : const Color(0xFFF0F0F7);
    final surf   = dark ? const Color(0xFF18182A) : Colors.white;
    return MaterialApp(
      title: 'Meow', debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bg, primaryColor: accent,
        colorScheme: ColorScheme(
          brightness: dark ? Brightness.dark : Brightness.light,
          primary: accent, secondary: accent, surface: surf,
          error: Colors.red, onPrimary: Colors.white, onSecondary: Colors.white,
          onSurface: dark ? Colors.white : Colors.black, onError: Colors.white,
        ),
        hintColor: dark ? const Color(0xFF6060A0) : const Color(0xFF999999),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          iconTheme: IconThemeData(color: Colors.white),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LIQUID GLASS — настоящий с бликами
// ════════════════════════════════════════════════════════════════════════════
class LiquidGlass extends StatelessWidget {
  final Widget        child;
  final BorderRadius? radius;
  final EdgeInsets?   padding;
  final double?       blur;
  final double?       opacity;
  final Color?        tint;

  const LiquidGlass({
    super.key, required this.child,
    this.radius, this.padding, this.blur, this.opacity, this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final s    = AppSettings.instance;
    final b    = blur    ?? s.glassBlur;
    final op   = opacity ?? s.glassOpacity;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final br   = radius ?? BorderRadius.circular(20);
    final base = tint ?? (dark ? Colors.white : Colors.black);

    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: b, sigmaY: b),
          inner: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        ),
        child: CustomPaint(
          painter: _LiquidPainter(br, op, base, dark),
          child: padding != null
              ? Padding(padding: padding!, child: child)
              : child,
        ),
      ),
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final BorderRadius br;
  final double opacity;
  final Color  base;
  final bool   dark;
  const _LiquidPainter(this.br, this.opacity, this.base, this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = br.toRRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // 1. Базовый заливка
    canvas.drawRRect(rrect, Paint()..color = base.withOpacity(opacity));

    // 2. Бликовая рамка — сверху/слева светло, снизу/справа темно
    canvas.drawRRect(rrect, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(dark ? 0.45 : 0.8),
          Colors.white.withOpacity(dark ? 0.15 : 0.4),
          Colors.black.withOpacity(dark ? 0.15 : 0.05),
          Colors.black.withOpacity(dark ? 0.25 : 0.1),
        ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)));

    // 3. Яркий блик сверху — имитация преломления стекла
    final specWidth  = size.width * 0.55;
    final specHeight = size.height * 0.35;
    final specRect   = Rect.fromLTWH((size.width - specWidth) / 2, 0, specWidth, specHeight);
    canvas.drawRect(specRect, Paint()
      ..shader = RadialGradient(
        center: Alignment.topCenter, radius: 1.0,
        colors: [
          Colors.white.withOpacity(dark ? 0.18 : 0.25),
          Colors.white.withOpacity(0),
        ],
      ).createShader(specRect));

    // 4. Внутренняя тень снизу
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3),
        const Radius.circular(4),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0), Colors.black.withOpacity(dark ? 0.12 : 0.06)],
        ).createShader(Rect.fromLTWH(0, size.height * 0.7, size.width, size.height * 0.3)),
    );
  }

  @override bool shouldRepaint(_LiquidPainter o) =>
      o.opacity != opacity || o.dark != dark;
}

// ════════════════════════════════════════════════════════════════════════════
//  ГЛАВНЫЙ ЭКРАН
// ════════════════════════════════════════════════════════════════════════════
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _s    = AppSettings.instance;
  String          _nick  = 'User';
  List<ChatEntry> _chats = [];
  int             _tab   = 0;
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
    setState(() {
      _nick = n;
      _nickCtrl.text = n;
      _chats = (p.getStringList('chats') ?? []).map(ChatEntry.from).toList();
    });
  }

  Future<void> _saveChats() async =>
      (await SharedPreferences.getInstance())
          .setStringList('chats', _chats.map((e) => e.serialize()).toList());

  // ── Аватар ───────────────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final xf = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (xf == null) return;
    if (!mounted) return;
    _showUploadingSnack('Загружаем аватар...');
    try {
      final bytes = await xf.readAsBytes();
      final ext   = xf.path.split('.').last.toLowerCase();
      final path  = 'avatars/$_nick.$ext';
      await _sb.storage.from('media').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(contentType: 'image/$ext', upsert: true),
      );
      final url = _sb.storage.from('media').getPublicUrl(path);
      await _s.setAvatarUrl(url);
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (e) {
      if (mounted) _showErrSnack('Ошибка загрузки: $e');
    }
  }

  void _showUploadingSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        const SizedBox(width: 12),
        Text(msg),
      ]),
      duration: const Duration(seconds: 30),
    ));
  }

  void _showErrSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: Colors.red.shade800,
      duration: const Duration(seconds: 5),
    ));
  }

  // ── Добавить / редактировать чат ─────────────────────────────────────────
  void _showChatSheet({ChatEntry? existing, int? index}) {
    final idCtrl  = TextEditingController(text: existing?.id  ?? '');
    final keyCtrl = TextEditingController(text: existing?.key ?? '');
    final isEdit  = existing != null;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetHandle(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(isEdit ? 'Редактировать' : 'Новый чат',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          if (isEdit) GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              _chats.removeAt(index!);
              await _saveChats(); setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.withOpacity(0.4)),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text('ID и ключ должны совпадать у всех участников',
            style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.45))),
        const SizedBox(height: 18),
        _GlassField(controller: idCtrl, hint: 'ID чата', icon: Icons.tag, readOnly: isEdit),
        const SizedBox(height: 10),
        _GlassField(controller: keyCtrl, hint: 'Ключ шифрования (необязательно)', icon: Icons.key_outlined),
        const SizedBox(height: 18),
        SizedBox(width: double.infinity, height: 50,
          child: _GlassBtn(color: _s.accent, onTap: () async {
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
          child: Text(isEdit ? 'Сохранить' : 'Добавить',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
        ),
        SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _s.dark;
    final bg   = dark ? const Color(0xFF080810) : const Color(0xFFF0F0F7);
    return Scaffold(
      backgroundColor: bg, extendBody: true,
      body: Stack(children: [
        _BgGlow(color: _s.accent),
        _tab == 0 ? _buildChats() : _buildSettings(),
      ]),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 12),
        child: LiquidGlass(
          blur: _s.glassBlur, opacity: dark ? 0.22 : 0.55,
          radius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _NavItem(icon: Icons.forum_outlined,    label: 'Чаты',      selected: _tab == 0, onTap: () => setState(() => _tab = 0)),
              GestureDetector(
                onTap: _showChatSheet,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_s.accent, _s.accent.withOpacity(0.65)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: _s.accent.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 4))],
                  ),
                  child: const Icon(Icons.edit_outlined, color: Colors.white, size: 22),
                ),
              ),
              _NavItem(icon: Icons.settings_outlined,  label: 'Настройки', selected: _tab == 1, onTap: () => setState(() => _tab = 1)),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Список чатов ─────────────────────────────────────────────────────────
  Widget _buildChats() {
    return CustomScrollView(slivers: [
      _glassAppBar('Meow', actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14, top: 6),
          child: GestureDetector(
            onTap: () => setState(() => _tab = 1),
            child: _AvatarWidget(nick: _nick, url: _s.avatarUrl, radius: 18),
          ),
        ),
      ]),
      if (_chats.isEmpty)
        SliverFillRemaining(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.forum_outlined, size: 72, color: Colors.white.withOpacity(0.12)),
          const SizedBox(height: 16),
          Text('Нет чатов', style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Нажми + чтобы добавить', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.2))),
        ])))
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          sliver: SliverList(delegate: SliverChildBuilderDelegate(
            (_, i) {
              final chat = _chats[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Dismissible(
                  key: Key(chat.serialize()),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    _chats.removeAt(i);
                    await _saveChats(); setState(() {});
                  },
                  child: LiquidGlass(
                    blur: _s.glassBlur, opacity: 0.1,
                    radius: BorderRadius.circular(20),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => ChatScreen(roomName: chat.id, encryptionKey: chat.key, myNick: _nick),
                      )),
                      onLongPress: () => _showChatSheet(existing: chat, index: i),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: _AvatarWidget(nick: chat.id, radius: 22),
                      title: Text(chat.id, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: Colors.white)),
                      subtitle: Text(
                        chat.key.isNotEmpty ? '🔒 Зашифрован' : '🔓 Без шифрования',
                        style: TextStyle(fontSize: 12, color: chat.key.isNotEmpty ? _s.accent : Colors.white.withOpacity(0.35)),
                      ),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(
                          onTap: () => _showChatSheet(existing: chat, index: i),
                          child: Padding(padding: const EdgeInsets.all(8),
                              child: Icon(Icons.edit_outlined, color: Colors.white.withOpacity(0.25), size: 18)),
                        ),
                        Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.25)),
                      ]),
                    ),
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
      _glassAppBar('Настройки'),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        sliver: SliverList(delegate: SliverChildListDelegate([

          // Профиль + аватар
          _Sect('ПРОФИЛЬ', [
            Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              // Аватар
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(alignment: Alignment.bottomRight, children: [
                  _AvatarWidget(nick: _nick, url: _s.avatarUrl, radius: 38),
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _s.accent, shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26, width: 1.5),
                    ),
                    child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 14),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: _GlassField(controller: _nickCtrl, hint: 'Твоё имя', icon: Icons.person_outline)),
                const SizedBox(width: 10),
                _GlassBtn(
                  color: _s.accent,
                  onTap: () async {
                    final n = _nickCtrl.text.trim();
                    if (n.isEmpty) return;
                    (await SharedPreferences.getInstance()).setString('nickname', n);
                    setState(() => _nick = n);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Сохранено'), duration: Duration(seconds: 2)));
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ])),
          ]),

          const SizedBox(height: 16),

          // Тема
          _Sect('ТЕМА', [
            _GlassSwitch(
              label: 'Тёмная тема',
              icon: _s.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              value: _s.dark, onChanged: _s.setDark,
            ),
          ]),

          const SizedBox(height: 16),

          // Акцент
          _Sect('ЦВЕТ АКЦЕНТА', [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                        boxShadow: sel ? [BoxShadow(color: AppSettings.accents[i].withOpacity(0.6), blurRadius: 12)] : null,
                      ),
                      child: sel ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                    ),
                  );
                }),
              )),
            ),
          ]),

          const SizedBox(height: 16),

          // Liquid Glass
          _Sect('LIQUID GLASS', [
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: StatefulBuilder(builder: (_, ss) => Column(children: [
                _SliderRow('Размытие', '${_s.glassBlur.round()}px', _s.glassBlur, 0, 40, 40,
                    (v) { _s.setGlassBlur(v); ss(() {}); }),
                _SliderRow('Прозрачность', '${(_s.glassOpacity * 100).round()}%', _s.glassOpacity, 0.03, 0.5, 47,
                    (v) { _s.setGlassOpacity(v); ss(() {}); }),
                const SizedBox(height: 6),
                LiquidGlass(radius: BorderRadius.circular(14),
                  child: const Padding(padding: EdgeInsets.all(14),
                    child: Center(child: Text('Превью стекла 🪟',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500))))),
                const SizedBox(height: 8),
              ])),
            ),
          ]),

          const SizedBox(height: 16),

          // Размер шрифта
          _Sect('РАЗМЕР ТЕКСТА', [
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: StatefulBuilder(builder: (_, ss) => Column(children: [
                _SliderRow('Размер', '${_s.fontSize.round()} px', _s.fontSize, 11, 22, 11,
                    (v) { _s.setFontSize(v); ss(() {}); }),
                const SizedBox(height: 4),
                LiquidGlass(radius: BorderRadius.circular(14),
                  child: Padding(padding: const EdgeInsets.all(14),
                    child: Center(child: Text('Пример текста сообщения',
                        style: TextStyle(fontSize: _s.fontSize, color: Colors.white))))),
                const SizedBox(height: 8),
              ])),
            ),
          ]),

          const SizedBox(height: 16),

          _Sect('ФОРМА ПУЗЫРЕЙ', [
            _Radio('Скруглённые', 0, _s.bubbleStyle, _s.setBubbleStyle),
            _Radio('Острые',      1, _s.bubbleStyle, _s.setBubbleStyle),
            _Radio('Telegram',    2, _s.bubbleStyle, _s.setBubbleStyle),
          ]),

          const SizedBox(height: 16),

          _Sect('ФОН ЧАТА', [
            _Radio('Без фона', 0, _s.chatBg, _s.setChatBg),
            _Radio('Точки',    1, _s.chatBg, _s.setChatBg),
            _Radio('Линии',    2, _s.chatBg, _s.setChatBg),
            _Radio('Сетка',    3, _s.chatBg, _s.setChatBg),
          ]),

          const SizedBox(height: 16),

          GestureDetector(
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1C1C2E),
                  title: const Text('Очистить все чаты?', style: TextStyle(color: Colors.white)),
                  content: const Text('Нельзя отменить.', style: TextStyle(color: Colors.white54)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Удалить', style: TextStyle(color: Colors.red))),
                  ],
                ),
              );
              if (ok == true) {
                (await SharedPreferences.getInstance()).remove('chats');
                setState(() { _chats = []; _tab = 0; });
              }
            },
            child: LiquidGlass(radius: BorderRadius.circular(16), tint: Colors.red, opacity: 0.08,
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Очистить все чаты', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                ])))),
          ),
        ])),
      ),
    ]);
  }

  Widget _glassAppBar(String title, {List<Widget>? actions}) {
    return SliverAppBar(
      pinned: true, floating: false, expandedHeight: 100, collapsedHeight: 60,
      backgroundColor: Colors.transparent,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
        title: Text(title, style: TextStyle(
          fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white,
          shadows: [Shadow(color: Colors.black.withOpacity(0.35), blurRadius: 10)],
        )),
        background: ClipRect(child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _s.glassBlur, sigmaY: _s.glassBlur),
          child: Container(color: Colors.transparent),
        )),
      ),
      actions: actions,
    );
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
  final _scroll = ScrollController();
  bool  _hasTxt    = false;
  bool  _uploading = false;

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
  void dispose() { _s.removeListener(_r); _ctrl.dispose(); _scroll.dispose(); super.dispose(); }
  void _r() => setState(() {});

  // ── Отправить текст ───────────────────────────────────────────────────────
  Future<void> _sendText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      await _sb.from('messages').insert({
        'sender':    widget.myNick,
        'chat_key':  widget.roomName,
        'payload':   _encrypt(text, widget.encryptionKey),
        'file_type': 'text',
      });
    } catch (e) {
      _ctrl.text = text;
      _showErr('Ошибка: $e');
    }
  }

  // ── Отправить медиа ───────────────────────────────────────────────────────
  Future<void> _pickAndSend(bool isVideo) async {
    final xf = isVideo
        ? await _picker.pickVideo(source: ImageSource.gallery)
        : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xf == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await xf.readAsBytes();
      final ext   = xf.path.split('.').last.toLowerCase();
      final path  = 'chat_media/${widget.roomName}/${_uid()}.$ext';
      await _sb.storage.from('media').uploadBinary(
        path, bytes,
        fileOptions: FileOptions(
          contentType: isVideo ? 'video/$ext' : 'image/$ext', upsert: false),
      );
      final url = _sb.storage.from('media').getPublicUrl(path);
      await _sb.from('messages').insert({
        'sender':    widget.myNick,
        'chat_key':  widget.roomName,
        'payload':   '',
        'file_url':  url,
        'file_type': isVideo ? 'video' : 'image',
      });
    } catch (e) {
      _showErr('Ошибка загрузки: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ── Прикрепить (показать выбор фото/видео) ────────────────────────────────
  void _showAttach() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => _GlassSheet(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetHandle(),
        const Text('Прикрепить', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _AttachBtn(icon: Icons.image_outlined, label: 'Фото', onTap: () { Navigator.pop(context); _pickAndSend(false); }),
          _AttachBtn(icon: Icons.videocam_outlined, label: 'Видео', onTap: () { Navigator.pop(context); _pickAndSend(true); }),
          _AttachBtn(icon: Icons.camera_alt_outlined, label: 'Камера', onTap: () async {
            Navigator.pop(context);
            final xf = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
            if (xf != null) {
              // upload как image
              setState(() => _uploading = true);
              try {
                final bytes = await xf.readAsBytes();
                final ext = xf.path.split('.').last.toLowerCase();
                final path = 'chat_media/${widget.roomName}/${_uid()}.$ext';
                await _sb.storage.from('media').uploadBinary(path, bytes,
                    fileOptions: FileOptions(contentType: 'image/$ext', upsert: false));
                final url = _sb.storage.from('media').getPublicUrl(path);
                await _sb.from('messages').insert({
                  'sender': widget.myNick, 'chat_key': widget.roomName,
                  'payload': '', 'file_url': url, 'file_type': 'image',
                });
              } catch (e) { _showErr('Ошибка: $e'); }
              finally { if (mounted) setState(() => _uploading = false); }
            }
          }),
        ]),
        const SizedBox(height: 8),
      ])),
    );
  }

  void _showErr(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: Colors.red.shade800, duration: const Duration(seconds: 5)));
  }

  @override
  Widget build(BuildContext context) {
    final stream = _sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_key', widget.roomName)
        .order('id', ascending: false);

    final dark = _s.dark;
    final bg   = dark ? const Color(0xFF080810) : const Color(0xFFF0F0F7);

    return Scaffold(
      extendBodyBehindAppBar: true, extendBody: true,
      backgroundColor: bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _s.glassBlur, sigmaY: _s.glassBlur),
            child: AppBar(
              backgroundColor: Colors.black.withOpacity(_s.glassOpacity * 1.8),
              title: Row(children: [
                _AvatarWidget(nick: widget.roomName, radius: 18),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.roomName),
                  Text(widget.encryptionKey.isNotEmpty ? '🔒 E2EE' : '🔓 Открыто',
                      style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w400)),
                ]),
              ]),
            ),
          ),
        ),
      ),
      body: Stack(children: [
        _BgGlow(color: _s.accent, intensity: 0.25),
        _BgPainter2(_s.chatBg, _s.accent),
        Column(children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: stream,
              builder: (ctx, snap) {
                if (snap.hasError) return Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Ошибка: ${snap.error}',
                      style: TextStyle(color: Colors.white.withOpacity(0.45)), textAlign: TextAlign.center),
                ));
                if (!snap.hasData) return Center(child: CircularProgressIndicator(color: _s.accent));
                final msgs = snap.data!;
                if (msgs.isEmpty) return Center(child: Text('Напиши первое сообщение 👋',
                    style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 15)));

                return ListView.builder(
                  controller: _scroll, reverse: true,
                  padding: EdgeInsets.fromLTRB(10, MediaQuery.of(ctx).padding.top + 70, 10, 90),
                  itemCount: msgs.length,
                  itemBuilder: (_, i) {
                    final m      = msgs[i];
                    final sender = (m['sender'] as String?) ?? '?';
                    final isMe   = sender == widget.myNick;
                    final ftype  = (m['file_type'] as String?) ?? 'text';
                    final payload = (m['payload'] as String?) ?? '';
                    final fileUrl = (m['file_url'] as String?) ?? '';
                    final text   = ftype == 'text' ? _decrypt(payload, widget.encryptionKey) : payload;
                    final showNick = !isMe && (i == msgs.length - 1 || msgs[i + 1]['sender'] != sender);
                    String time = '';
                    if (m['created_at'] != null) {
                      time = DateTime.parse(m['created_at']).toLocal().toString().substring(11, 16);
                    }
                    return _Bubble(
                      text: text, sender: sender, time: time, fileUrl: fileUrl, fileType: ftype,
                      isMe: isMe, showNick: showNick,
                      style: _s.bubbleStyle, fontSize: _s.fontSize,
                      accent: _s.accent, dark: dark, glassBlur: _s.glassBlur,
                    );
                  },
                );
              },
            ),
          ),

          // ── Liquid glass поле ввода ───────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(10, 6, 10, MediaQuery.of(context).padding.bottom + 10),
            child: LiquidGlass(
              blur: _s.glassBlur, opacity: _s.glassOpacity * 1.6,
              radius: BorderRadius.circular(28),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  // Кнопка прикрепить
                  GestureDetector(
                    onTap: _showAttach,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8, right: 4),
                      child: Icon(_uploading ? Icons.hourglass_bottom : Icons.add_circle_outline,
                          color: _uploading ? _s.accent : Colors.white.withOpacity(0.45), size: 24),
                    ),
                  ),
                  Expanded(child: TextField(
                    controller: _ctrl, maxLines: 5, minLines: 1,
                    textInputAction: TextInputAction.newline,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Сообщение...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      border: InputBorder.none, focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none, fillColor: Colors.transparent,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    ),
                  )),
                  const SizedBox(width: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: _hasTxt
                        ? GestureDetector(
                            key: const ValueKey('send'), onTap: _sendText,
                            child: Container(
                              width: 40, height: 40,
                              margin: const EdgeInsets.only(bottom: 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [_s.accent, _s.accent.withOpacity(0.65)],
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
                ]),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ПУЗЫРЬ
// ════════════════════════════════════════════════════════════════════════════
class _Bubble extends StatelessWidget {
  final String text, sender, time, fileUrl, fileType;
  final bool isMe, showNick, dark;
  final int style;
  final double fontSize, glassBlur;
  final Color accent;

  const _Bubble({
    required this.text, required this.sender, required this.time,
    required this.fileUrl, required this.fileType,
    required this.isMe, required this.showNick, required this.style,
    required this.fontSize, required this.accent, required this.dark, required this.glassBlur,
  });

  BorderRadius _r() {
    switch (style) {
      case 1: return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 18 : 4), topRight: Radius.circular(isMe ? 4 : 18),
        bottomLeft: const Radius.circular(18), bottomRight: const Radius.circular(18));
      case 2: return BorderRadius.only(
        topLeft: const Radius.circular(18), topRight: const Radius.circular(18),
        bottomLeft: Radius.circular(isMe ? 18 : 4), bottomRight: Radius.circular(isMe ? 4 : 18));
      default: return BorderRadius.only(
        topLeft: Radius.circular(isMe ? 18 : (showNick ? 4 : 18)),
        topRight: Radius.circular(isMe ? (showNick ? 4 : 18) : 18),
        bottomLeft: const Radius.circular(18), bottomRight: const Radius.circular(18));
    }
  }

  void _onLongPress(BuildContext ctx) {
    final urls = _urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
    showModalBottomSheet(
      context: ctx, backgroundColor: Colors.transparent,
      builder: (_) => _GlassSheet(child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sheetHandle(),
        if (text.isNotEmpty) ListTile(
          leading: const Icon(Icons.copy_outlined, color: Colors.white70),
          title: const Text('Копировать', style: TextStyle(color: Colors.white)),
          onTap: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('Скопировано'), duration: Duration(seconds: 2)));
          },
        ),
        ...urls.map((url) => ListTile(
          leading: const Icon(Icons.open_in_new, color: Colors.lightBlueAccent),
          title: Text(url, style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () { Navigator.pop(ctx); _openUrl(url); },
        )),
      ])),
    );
  }

  Widget _buildContent(BuildContext ctx) {
    if (fileType == 'image' && fileUrl.isNotEmpty) {
      return GestureDetector(
        onTap: () => Navigator.push(ctx, MaterialPageRoute(
          builder: (_) => _FullImageScreen(url: fileUrl),
        )),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: fileUrl,
            width: 220, fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 220, height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 220, height: 60,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image_outlined, color: Colors.white38),
            ),
          ),
        ),
      );
    }

    if (fileType == 'video' && fileUrl.isNotEmpty) {
      return _VideoMessage(url: fileUrl);
    }

    // Текст с ссылками
    final matches = _urlRegex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.35));
    }
    final spans = <InlineSpan>[];
    int last = 0;
    for (final m in matches) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final url = m.group(0)!;
      spans.add(WidgetSpan(child: GestureDetector(
        onTap: () => _openUrl(url),
        child: Text(url, style: TextStyle(
          fontSize: fontSize, height: 1.35,
          color: Colors.lightBlueAccent,
          decoration: TextDecoration.underline,
          decorationColor: Colors.lightBlueAccent,
        )),
      )));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(text: TextSpan(
      style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.35),
      children: spans,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final br = _r();
    final isMedia = fileType == 'image' || fileType == 'video';

    return Padding(
      padding: EdgeInsets.only(top: showNick ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment:  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: showNick
                ? _AvatarWidget(nick: sender, radius: 14)
                : const SizedBox(width: 28),
          ),
          Flexible(
            child: GestureDetector(
              onLongPress: () => _onLongPress(context),
              child: ClipRRect(
                borderRadius: br,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
                  child: CustomPaint(
                    painter: _LiquidPainter(br,
                      isMe ? 0.0 : (dark ? 0.1 : 0.55),
                      isMe ? accent : (dark ? Colors.white : Colors.black),
                      dark),
                    child: Container(
                      constraints: BoxConstraints(maxWidth: isMedia ? 240 : MediaQuery.of(context).size.width * 0.72),
                      margin: EdgeInsets.only(left: isMe ? 52 : 0, right: isMe ? 0 : 52),
                      padding: EdgeInsets.all(isMedia ? 6 : 10),
                      decoration: isMe ? BoxDecoration(
                        borderRadius: br,
                        color: accent.withOpacity(0.7),
                      ) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (showNick) Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(sender, style: TextStyle(
                                color: _avatarColor(sender), fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          _buildContent(context),
                          if (!isMedia) ...[
                            const SizedBox(height: 3),
                            Align(alignment: Alignment.bottomRight,
                              child: Text(time, style: TextStyle(
                                  color: Colors.white.withOpacity(0.5), fontSize: 10))),
                          ] else
                            Padding(
                              padding: const EdgeInsets.only(top: 4, right: 4),
                              child: Align(alignment: Alignment.bottomRight,
                                child: Text(time, style: TextStyle(
                                    color: Colors.white.withOpacity(0.7), fontSize: 10,
                                    shadows: [const Shadow(color: Colors.black54, blurRadius: 4)]))),
                            ),
                        ],
                      ),
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
//  ВИДЕО СООБЩЕНИЕ
// ════════════════════════════════════════════════════════════════════════════
class _VideoMessage extends StatefulWidget {
  final String url;
  const _VideoMessage({required this.url});
  @override State<_VideoMessage> createState() => _VideoMessageState();
}

class _VideoMessageState extends State<_VideoMessage> {
  late final VideoPlayerController _vc;
  bool _init = false;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) { if (mounted) setState(() => _init = true); });
  }

  @override
  void dispose() { _vc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!_init) return Container(
      width: 220, height: 130,
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
      child: const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
    );

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => _FullVideoScreen(url: widget.url),
      )),
      child: Stack(alignment: Alignment.center, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: _vc.value.aspectRatio.clamp(0.5, 2.0),
            child: VideoPlayer(_vc),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
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
  final String url;
  const _FullImageScreen({required this.url});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Center(child: Hero(
        tag: url,
        child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
      )),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  ПОЛНОЭКРАННОЕ ВИДЕО
// ════════════════════════════════════════════════════════════════════════════
class _FullVideoScreen extends StatefulWidget {
  final String url;
  const _FullVideoScreen({required this.url});
  @override State<_FullVideoScreen> createState() => _FullVideoScreenState();
}

class _FullVideoScreenState extends State<_FullVideoScreen> {
  late final VideoPlayerController _vc;
  bool _init = false;

  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) { setState(() => _init = true); _vc.play(); }
      });
  }

  @override void dispose() { _vc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      onTap: () { if (_vc.value.isPlaying) { _vc.pause(); } else { _vc.play(); } },
      child: Stack(children: [
        if (_init) Center(child: AspectRatio(aspectRatio: _vc.value.aspectRatio, child: VideoPlayer(_vc)))
        else const Center(child: CircularProgressIndicator(color: Colors.white)),
        SafeArea(child: Padding(
          padding: const EdgeInsets.all(8),
          child: IconButton(icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context)),
        )),
        if (_init) Positioned(bottom: 40, left: 0, right: 0,
          child: Center(child: VideoProgressIndicator(_vc,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: AppSettings.instance.accent,
                bufferedColor: Colors.white30, backgroundColor: Colors.white12)))),
      ]),
    ),
  );
}

// ════════════════════════════════════════════════════════════════════════════
//  ВИДЖЕТ АВАТАРА
// ════════════════════════════════════════════════════════════════════════════
class _AvatarWidget extends StatelessWidget {
  final String  nick;
  final double  radius;
  final String? url;
  const _AvatarWidget({required this.nick, required this.radius, this.url});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: CachedNetworkImageProvider(url!),
        backgroundColor: _avatarColor(nick).withOpacity(0.25),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _avatarColor(nick).withOpacity(0.25),
      child: Text(nick.isNotEmpty ? nick[0].toUpperCase() : '?',
          style: TextStyle(color: _avatarColor(nick), fontWeight: FontWeight.w800,
              fontSize: radius * 0.7)),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ВСПОМОГАТЕЛЬНЫЕ ВИДЖЕТЫ
// ════════════════════════════════════════════════════════════════════════════
Widget _sheetHandle() => Center(child: Container(
  width: 36, height: 4, margin: const EdgeInsets.only(bottom: 18),
  decoration: BoxDecoration(color: Colors.white.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
));

class _BgGlow extends StatelessWidget {
  final Color color; final double intensity;
  const _BgGlow({required this.color, this.intensity = 0.14});
  @override Widget build(BuildContext context) => Stack(children: [
    Positioned(top: -120, right: -100, child: Container(width: 320, height: 320,
        decoration: BoxDecoration(shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(intensity), blurRadius: 130, spreadRadius: 50)]))),
    Positioned(bottom: 80, left: -80, child: Container(width: 260, height: 260,
        decoration: BoxDecoration(shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(intensity * 0.55), blurRadius: 110, spreadRadius: 35)]))),
  ]);
}

class _BgPainter2 extends StatelessWidget {
  final int type; final Color color;
  const _BgPainter2(this.type, this.color);
  @override Widget build(BuildContext context) => type == 0
      ? const SizedBox.expand()
      : CustomPaint(painter: _BgCP(type, color.withOpacity(0.05)), child: const SizedBox.expand());
}

class _BgCP extends CustomPainter {
  final int t; final Color c;
  const _BgCP(this.t, this.c);
  @override void paint(Canvas canvas, Size s) {
    final p = Paint()..color = c..strokeWidth = 1;
    if (t == 1) { for (double x = 16; x < s.width; x += 24) for (double y = 16; y < s.height; y += 24) canvas.drawCircle(Offset(x, y), 1.5, p); }
    else if (t == 2) { for (double y = 0; y < s.height; y += 28) canvas.drawLine(Offset(0, y), Offset(s.width, y), p); }
    else if (t == 3) { for (double x = 0; x < s.width; x += 28) canvas.drawLine(Offset(x, 0), Offset(x, s.height), p); for (double y = 0; y < s.height; y += 28) canvas.drawLine(Offset(0, y), Offset(s.width, y), p); }
  }
  @override bool shouldRepaint(_BgCP o) => o.t != t;
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
            color: Colors.white.withOpacity(s.glassOpacity * 1.2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.2), width: 0.8)),
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
        filter: ImageFilter.blur(sigmaX: s.glassBlur * 0.6, sigmaY: s.glassBlur * 0.6),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(readOnly ? 0.05 : s.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.8),
          ),
          child: TextField(
            controller: controller, readOnly: readOnly,
            style: TextStyle(color: readOnly ? Colors.white.withOpacity(0.45) : Colors.white),
            decoration: InputDecoration(
              hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.35), size: 20),
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

class _GlassBtn extends StatelessWidget {
  final Widget child; final Color color; final VoidCallback onTap;
  const _GlassBtn({required this.child, required this.color, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [color, color.withOpacity(0.65)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: color.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
    ),
  );
}

class _AttachBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _AttachBtn({required this.icon, required this.label, required this.onTap});
  @override Widget build(BuildContext context) {
    final accent = AppSettings.instance.accent;
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(width: 60, height: 60,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [accent, accent.withOpacity(0.65)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: accent.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }
}

class _Sect extends StatelessWidget {
  final String title; final List<Widget> children;
  const _Sect(this.title, this.children);
  @override Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            letterSpacing: 1.2, color: AppSettings.instance.accent))),
      LiquidGlass(radius: BorderRadius.circular(20), child: Column(children: children)),
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
  final String label; final int value, groupValue;
  final Future<void> Function(int) onChanged;
  const _Radio(this.label, this.value, this.groupValue, this.onChanged);
  @override Widget build(BuildContext context) => RadioListTile<int>(
    value: value, groupValue: groupValue, onChanged: (v) => onChanged(v!),
    title: Text(label, style: const TextStyle(color: Colors.white)),
    activeColor: AppSettings.instance.accent, dense: true,
  );
}

class _SliderRow extends StatelessWidget {
  final String label, valLabel;
  final double value, min, max;
  final int divisions;
  final void Function(double) onChanged;
  const _SliderRow(this.label, this.valLabel, this.value, this.min, this.max, this.divisions, this.onChanged);
  @override Widget build(BuildContext context) {
    final accent = AppSettings.instance.accent;
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(valLabel, style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: accent, thumbColor: accent,
          inactiveTrackColor: accent.withOpacity(0.2),
          overlayColor: accent.withOpacity(0.15), trackHeight: 3,
        ),
        child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ),
    ]);
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
            child: Icon(icon, color: selected ? accent : Colors.white.withOpacity(0.35), size: 22),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: selected ? accent : Colors.white.withOpacity(0.3))),
        ]),
      ),
    );
  }
}
