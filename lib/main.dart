import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:encrypt/encrypt.dart' as enc;

// ════════════════════════════════════════════════════════════════════════════
//  КОНФИГ
// ════════════════════════════════════════════════════════════════════════════
const _supabaseUrl = 'https://ilszhdmqxsoixcefeoqa.supabase.co';
const _supabaseKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imlsc3poZG1xeHNvaXhjZWZlb3FhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2NjA4NDMsImV4cCI6MjA3NjIzNjg0M30.aJF9c3RaNvAk4_9nLYhQABH3pmYUcZ0q2udf2LoA6Sc';

// ════════════════════════════════════════════════════════════════════════════
//  НАСТРОЙКИ
// ════════════════════════════════════════════════════════════════════════════
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final instance = AppSettings._();

  bool   _dark        = true;
  int    _accentIdx   = 0;
  double _fontSize    = 15;
  int    _bubbleStyle = 0;
  int    _chatBg      = 0;

  bool   get dark        => _dark;
  int    get accentIdx   => _accentIdx;
  double get fontSize    => _fontSize;
  int    get bubbleStyle => _bubbleStyle;
  int    get chatBg      => _chatBg;

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
    final p    = await SharedPreferences.getInstance();
    _dark        = p.getBool('dark')       ?? true;
    _accentIdx   = p.getInt('accentIdx')   ?? 0;
    _fontSize    = p.getDouble('fontSize') ?? 15;
    _bubbleStyle = p.getInt('bubbleStyle') ?? 0;
    _chatBg      = p.getInt('chatBg')      ?? 0;
    notifyListeners();
  }

  Future<void> setDark(bool v)        async { _dark = v;        (await _p()).setBool('dark', v);           notifyListeners(); }
  Future<void> setAccent(int v)       async { _accentIdx = v;   (await _p()).setInt('accentIdx', v);       notifyListeners(); }
  Future<void> setFontSize(double v)  async { _fontSize = v;    (await _p()).setDouble('fontSize', v);     notifyListeners(); }
  Future<void> setBubbleStyle(int v)  async { _bubbleStyle = v; (await _p()).setInt('bubbleStyle', v);     notifyListeners(); }
  Future<void> setChatBg(int v)       async { _chatBg = v;      (await _p()).setInt('chatBg', v);          notifyListeners(); }
  Future<SharedPreferences> _p()     => SharedPreferences.getInstance();
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
  } catch (_) { return text; }
}

Color _avatarColor(String n) =>
    Colors.primaries[n.hashCode.abs() % Colors.primaries.length];

// ════════════════════════════════════════════════════════════════════════════
//  ТОЧКА ВХОДА
// ════════════════════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.init();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:                   Colors.transparent,
    statusBarIconBrightness:          Brightness.light,
    systemNavigationBarColor:         Colors.transparent,
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
  @override void initState() { super.initState(); _s.addListener(_r); }
  @override void dispose()   { _s.removeListener(_r); super.dispose(); }
  void _r() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final dark   = _s.dark;
    final accent = _s.accent;
    final bg     = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF2F2F7);
    final surf   = dark ? const Color(0xFF1C1C2E) : Colors.white;
    final hint   = dark ? const Color(0xFF7070A0) : const Color(0xFF999999);

    return MaterialApp(
      title:                      'Meow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness:              dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bg,
        primaryColor:            accent,
        colorScheme: ColorScheme(
          brightness:  dark ? Brightness.dark : Brightness.light,
          primary:     accent, secondary: accent, surface: surf,
          error:       Colors.red, onPrimary: Colors.white,
          onSecondary: Colors.white, onSurface: dark ? Colors.white : Colors.black,
          onError:     Colors.white,
        ),
        hintColor:    hint,
        dividerColor: dark ? const Color(0xFF252535) : const Color(0xFFDDDDE8),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0, scrolledUnderElevation: 0,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
          titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 18,
            fontWeight: FontWeight.w700, letterSpacing: -0.3,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true, fillColor: surf.withOpacity(0.5),
          hintStyle: TextStyle(color: hint),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: accent, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  LIQUID GLASS — переиспользуемый виджет
// ════════════════════════════════════════════════════════════════════════════
class GlassBox extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? radius;
  final EdgeInsets? padding;
  final Color? borderColor;

  const GlassBox({
    super.key,
    required this.child,
    this.blur       = 20,
    this.opacity    = 0.15,
    this.radius,
    this.padding,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final br = radius ?? BorderRadius.circular(20);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: br,
            color: (dark ? Colors.white : Colors.black).withOpacity(opacity),
            border: Border.all(
              color: borderColor ??
                  (dark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.white.withOpacity(0.6)),
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
//  ГЛАВНЫЙ ЭКРАН — с bottom nav bar
// ════════════════════════════════════════════════════════════════════════════
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _s     = AppSettings.instance;
  String       _nick  = 'User';
  List<String> _chats = [];
  int          _tab   = 0; // 0=чаты 1=настройки

  @override
  void initState() {
    super.initState();
    _s.addListener(_r);
    _load();
  }

  @override
  void dispose() { _s.removeListener(_r); super.dispose(); }
  void _r() => setState(() {});

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _nick  = p.getString('nickname') ?? 'User';
      _chats = p.getStringList('chats') ?? [];
    });
  }

  Future<void> _saveChats() async =>
      (await SharedPreferences.getInstance()).setStringList('chats', _chats);

  void _showAddChat() {
    final idCtrl  = TextEditingController();
    final keyCtrl = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _GlassSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 36, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const Text('Новый чат',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 6),
            Text('ID и ключ должны совпадать у обоих',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 18),
            _GlassField(controller: idCtrl, hint: 'ID чата (chat_key)', icon: Icons.tag),
            const SizedBox(height: 10),
            _GlassField(controller: keyCtrl, hint: 'Ключ шифрования (необязательно)', icon: Icons.key_outlined),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity, height: 50,
              child: _GlassButton(
                color: _s.accent,
                onTap: () async {
                  final id = idCtrl.text.trim();
                  if (id.isEmpty) return;
                  final entry = '$id:${keyCtrl.text.trim()}';
                  if (!_chats.contains(entry)) {
                    _chats.add(entry);
                    await _saveChats();
                    setState(() {});
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Добавить',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
            SizedBox(height: MediaQuery.of(ctx).viewInsets.bottom),
          ],
        ),
      ),
    );
  }

  void _deleteChat(int i) async {
    _chats.removeAt(i);
    await _saveChats();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = _s.dark;
    final bg   = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF2F2F7);

    return Scaffold(
      backgroundColor: bg,
      extendBody: true, // контент уходит под bottom bar
      body: Stack(
        children: [
          // Фоновые градиентные пятна
          _BgGlow(color: _s.accent),

          // Контент
          _tab == 0 ? _buildChats() : _buildSettings(),
        ],
      ),

      // ── Liquid Glass Bottom Bar ────────────────────────────────────────
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).padding.bottom + 12,
        ),
        child: GlassBox(
          blur: 30, opacity: dark ? 0.2 : 0.5,
          radius: BorderRadius.circular(28),
          borderColor: Colors.white.withOpacity(0.15),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.forum_outlined,  label: 'Чаты',       selected: _tab == 0, onTap: () => setState(() => _tab = 0), accent: _s.accent),
                // FAB в центре
                GestureDetector(
                  onTap: _showAddChat,
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
                _NavItem(icon: Icons.settings_outlined, label: 'Настройки', selected: _tab == 1, onTap: () => setState(() => _tab = 1), accent: _s.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Экран чатов ──────────────────────────────────────────────────────────
  Widget _buildChats() {
    return CustomScrollView(
      slivers: [
        // Glass AppBar
        SliverAppBar(
          pinned: true, floating: false,
          expandedHeight: 100, collapsedHeight: 60,
          backgroundColor: Colors.transparent,
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
            title: Text('Meow',
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white,
                  shadows: [Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)],
                )),
            background: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 8),
              child: GlassBox(
                radius: BorderRadius.circular(20), blur: 15, opacity: 0.2,
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
          SliverFillRemaining(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.forum_outlined, size: 72,
                    color: Colors.white.withOpacity(0.15)),
                const SizedBox(height: 16),
                Text('Нет чатов',
                    style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.4),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Нажми + чтобы добавить',
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.25))),
              ]),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final parts  = _chats[i].split(':');
                  final chatId = parts[0];
                  final encKey = parts.length > 1 ? parts[1] : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Dismissible(
                      key: Key(_chats[i]),
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
                      onDismissed: (_) => _deleteChat(i),
                      child: GlassBox(
                        blur: 15, opacity: 0.12, radius: BorderRadius.circular(20),
                        child: ListTile(
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => ChatScreen(
                                roomName: chatId, encryptionKey: encKey, myNick: _nick),
                          )),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: _avatarColor(chatId).withOpacity(0.25),
                              shape: BoxShape.circle,
                            ),
                            child: Center(child: Text(chatId[0].toUpperCase(),
                                style: TextStyle(color: _avatarColor(chatId),
                                    fontWeight: FontWeight.w800, fontSize: 18))),
                          ),
                          title: Text(chatId,
                              style: const TextStyle(fontWeight: FontWeight.w600,
                                  fontSize: 16, color: Colors.white)),
                          subtitle: Text(
                            encKey.isNotEmpty ? '🔒 Зашифрован' : '🔓 Без шифрования',
                            style: TextStyle(
                                fontSize: 12,
                                color: encKey.isNotEmpty
                                    ? _s.accent
                                    : Colors.white.withOpacity(0.4)),
                          ),
                          trailing: Icon(Icons.chevron_right,
                              color: Colors.white.withOpacity(0.3)),
                        ),
                      ),
                    ),
                  );
                },
                childCount: _chats.length,
              ),
            ),
          ),
      ],
    );
  }

  // ── Экран настроек ───────────────────────────────────────────────────────
  Widget _buildSettings() {
    final nickCtrl = TextEditingController(text: _nick);
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true, backgroundColor: Colors.transparent,
          collapsedHeight: 60, expandedHeight: 100,
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
            title: const Text('Настройки',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
            background: ClipRect(child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(color: Colors.transparent),
            )),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          sliver: SliverList(delegate: SliverChildListDelegate([

            // Профиль
            _GlassSection(title: 'ПРОФИЛЬ', children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(child: _GlassField(controller: nickCtrl, hint: 'Твоё имя', icon: Icons.person_outline)),
                  const SizedBox(width: 10),
                  _GlassButton(
                    color: _s.accent,
                    onTap: () async {
                      final n = nickCtrl.text.trim();
                      if (n.isEmpty) return;
                      (await SharedPreferences.getInstance()).setString('nickname', n);
                      setState(() => _nick = n);
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ]),
              ),
            ]),

            const SizedBox(height: 16),

            // Тема
            _GlassSection(title: 'ТЕМА', children: [
              _GlassSwitch(
                label: 'Тёмная тема',
                icon:  _s.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                value: _s.dark,
                onChanged: _s.setDark,
                accent: _s.accent,
              ),
            ]),

            const SizedBox(height: 16),

            // Цвет акцента
            _GlassSection(title: 'ЦВЕТ АКЦЕНТА', children: [
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
                          color: AppSettings.accents[i],
                          shape: BoxShape.circle,
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

            // Размер шрифта
            _GlassSection(title: 'РАЗМЕР ТЕКСТА', children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: StatefulBuilder(builder: (_, ss) => Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Аа', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                    GlassBox(
                      radius: BorderRadius.circular(20), blur: 10, opacity: 0.2,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Text('${_s.fontSize.round()} px',
                            style: TextStyle(color: _s.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                    Text('Аа', style: TextStyle(fontSize: 20, color: Colors.white.withOpacity(0.5))),
                  ]),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _s.accent,
                      thumbColor:       _s.accent,
                      inactiveTrackColor: _s.accent.withOpacity(0.2),
                      overlayColor: _s.accent.withOpacity(0.15),
                    ),
                    child: Slider(
                      value: _s.fontSize, min: 11, max: 22, divisions: 11,
                      onChanged: (v) { _s.setFontSize(v); ss(() {}); },
                    ),
                  ),
                  GlassBox(
                    radius: BorderRadius.circular(14), blur: 10, opacity: 0.1,
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

            // Форма пузырей
            _GlassSection(title: 'ФОРМА ПУЗЫРЕЙ', children: [
              _GlassRadio('Скруглённые', 0, _s.bubbleStyle, _s.setBubbleStyle, _s.accent),
              _GlassRadio('Острые',      1, _s.bubbleStyle, _s.setBubbleStyle, _s.accent),
              _GlassRadio('Telegram',    2, _s.bubbleStyle, _s.setBubbleStyle, _s.accent),
            ]),

            const SizedBox(height: 16),

            // Фон чата
            _GlassSection(title: 'ФОН ЧАТА', children: [
              _GlassRadio('Без фона', 0, _s.chatBg, _s.setChatBg, _s.accent),
              _GlassRadio('Точки',    1, _s.chatBg, _s.setChatBg, _s.accent),
              _GlassRadio('Линии',    2, _s.chatBg, _s.setChatBg, _s.accent),
              _GlassRadio('Сетка',    3, _s.chatBg, _s.setChatBg, _s.accent),
            ]),

            const SizedBox(height: 16),

            // Очистить чаты
            GestureDetector(
              onTap: () async {
                (await SharedPreferences.getInstance()).remove('chats');
                setState(() { _chats = []; _tab = 0; });
              },
              child: GlassBox(
                radius: BorderRadius.circular(16), blur: 15,
                borderColor: Colors.red.withOpacity(0.3),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Очистить все чаты',
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                    ],
                  )),
                ),
              ),
            ),
          ])),
        ),
      ],
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
  void dispose() { _s.removeListener(_r); _ctrl.dispose(); _scroll.dispose(); super.dispose(); }
  void _r() => setState(() {});

  void _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    try {
      // ← ИСПРАВЛЕНО: 'sender' без подчёркивания — реальная колонка в БД
      await _sb.from('messages').insert({
        'sender':   widget.myNick,
        'payload':  _encrypt(text, widget.encryptionKey),
        'chat_key': widget.roomName,
      });
    } catch (e) {
      _ctrl.text = text;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Ошибка: $e'),
        backgroundColor: Colors.red.shade800,
        duration: const Duration(seconds: 6),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = _sb
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_key', widget.roomName)
        .order('id', ascending: false);

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      backgroundColor: _s.dark ? const Color(0xFF0A0A0F) : const Color(0xFFF2F2F7),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: AppBar(
              backgroundColor: Colors.black.withOpacity(0.3),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.roomName),
                  Text(
                    widget.encryptionKey.isNotEmpty ? '🔒 E2EE' : '🔓 Без шифрования',
                    style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6),
                        fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          _BgGlow(color: _s.accent, intensity: 0.3),
          CustomPaint(
            painter: _BgPainter(_s.chatBg, _s.accent.withOpacity(0.05)),
            child: const SizedBox.expand(),
          ),
          Column(
            children: [
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: stream,
                  builder: (ctx, snap) {
                    if (snap.hasError) return Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Ошибка: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.5))),
                    ));
                    if (!snap.hasData) return Center(
                        child: CircularProgressIndicator(color: _s.accent));
                    final msgs = snap.data!;
                    if (msgs.isEmpty) return Center(
                      child: Text('Напиши первое сообщение 👋',
                          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15)),
                    );
                    return ListView.builder(
                      controller: _scroll, reverse: true,
                      padding: EdgeInsets.fromLTRB(
                          10, MediaQuery.of(ctx).padding.top + 70, 10, 100),
                      itemCount: msgs.length,
                      itemBuilder: (_, i) {
                        final m      = msgs[i];
                        // ← читаем 'sender' — правильное имя колонки
                        final sender = (m['sender'] as String?) ?? '?';
                        final isMe   = sender == widget.myNick;
                        final text   = _decrypt((m['payload'] as String?) ?? '', widget.encryptionKey);
                        final showNick = !isMe && (
                          i == msgs.length - 1 || msgs[i + 1]['sender'] != sender
                        );
                        String time = '';
                        if (m['created_at'] != null) {
                          time = DateTime.parse(m['created_at']).toLocal().toString().substring(11, 16);
                        }
                        return _Bubble(
                          text: text, sender: sender, time: time,
                          isMe: isMe, showNick: showNick,
                          style: _s.bubbleStyle, fontSize: _s.fontSize,
                          accent: _s.accent, dark: _s.dark,
                        );
                      },
                    );
                  },
                ),
              ),

              // ── Liquid glass поле ввода ───────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(
                    12, 8, 12, MediaQuery.of(context).padding.bottom + 12),
                child: GlassBox(
                  blur: 25, opacity: 0.2, radius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ctrl,
                            maxLines: 5, minLines: 1,
                            textInputAction: TextInputAction.newline,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Сообщение...',
                              hintStyle: TextStyle(color: Colors.white38),
                              border: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              fillColor: Colors.transparent,
                              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                          child: _hasTxt
                              ? GestureDetector(
                                  key: const ValueKey('send'),
                                  onTap: _send,
                                  child: Container(
                                    width: 40, height: 40,
                                    margin: const EdgeInsets.only(bottom: 2),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [_s.accent, _s.accent.withOpacity(0.7)],
                                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(
                                        color: _s.accent.withOpacity(0.4),
                                        blurRadius: 10,
                                      )],
                                    ),
                                    child: const Icon(Icons.arrow_upward_rounded,
                                        color: Colors.white, size: 20),
                                  ),
                                )
                              : const SizedBox(key: ValueKey('empty'), width: 40),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  ПУЗЫРЬ СООБЩЕНИЯ
// ════════════════════════════════════════════════════════════════════════════
class _Bubble extends StatelessWidget {
  final String text; final String sender; final String time;
  final bool isMe; final bool showNick;
  final int style; final double fontSize; final Color accent; final bool dark;

  const _Bubble({
    required this.text, required this.sender, required this.time,
    required this.isMe, required this.showNick,
    required this.style, required this.fontSize, required this.accent, required this.dark,
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: showNick ? 10 : 2, bottom: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 2),
            child: showNick
                ? CircleAvatar(radius: 14,
                    backgroundColor: _avatarColor(sender).withOpacity(0.25),
                    child: Text(sender[0].toUpperCase(),
                        style: TextStyle(fontSize: 11, color: _avatarColor(sender), fontWeight: FontWeight.w800)))
                : const SizedBox(width: 28),
          ),
          Flexible(
            child: ClipRRect(
              borderRadius: _r(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.73),
                  margin: EdgeInsets.only(left: isMe ? 56 : 0, right: isMe ? 0 : 56),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: _r(),
                    color: isMe
                        ? accent.withOpacity(0.75)
                        : Colors.white.withOpacity(dark ? 0.1 : 0.6),
                    border: Border.all(
                      color: isMe
                          ? accent.withOpacity(0.4)
                          : Colors.white.withOpacity(0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showNick) Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(sender,
                            style: TextStyle(color: _avatarColor(sender),
                                fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      Text(text,
                          style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.35)),
                      const SizedBox(height: 3),
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(time,
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 10)),
                      ),
                    ],
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
  final Color color;
  final double intensity;
  const _BgGlow({required this.color, this.intensity = 0.15});

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(top: -100, right: -80,
        child: Container(width: 300, height: 300,
          decoration: BoxDecoration(shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(intensity), blurRadius: 120, spreadRadius: 40)]))),
      Positioned(bottom: 50, left: -60,
        child: Container(width: 250, height: 250,
          decoration: BoxDecoration(shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color.withOpacity(intensity * 0.6), blurRadius: 100, spreadRadius: 30)]))),
    ]);
  }
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
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
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
  final String hint;
  final IconData icon;
  const _GlassField({required this.controller, required this.hint, required this.icon});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 0.8),
          ),
          child: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.35)),
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
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
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
}

class _GlassSection extends StatelessWidget {
  final String title; final List<Widget> children;
  const _GlassSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          letterSpacing: 1.2, color: AppSettings.instance.accent,
        )),
      ),
      GlassBox(
        blur: 15, opacity: 0.12, radius: BorderRadius.circular(20),
        child: Column(children: children),
      ),
    ]);
  }
}

class _GlassSwitch extends StatelessWidget {
  final String label; final IconData icon; final bool value;
  final Future<void> Function(bool) onChanged; final Color accent;
  const _GlassSwitch({required this.label, required this.icon, required this.value, required this.onChanged, required this.accent});
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value, onChanged: onChanged,
      secondary: Icon(icon, color: Colors.white.withOpacity(0.6)),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      activeColor: accent, activeTrackColor: accent.withOpacity(0.4),
    );
  }
}

class _GlassRadio extends StatelessWidget {
  final String label; final int value; final int groupValue;
  final Future<void> Function(int) onChanged; final Color accent;
  const _GlassRadio(this.label, this.value, this.groupValue, this.onChanged, this.accent);
  @override
  Widget build(BuildContext context) {
    return RadioListTile<int>(
      value: value, groupValue: groupValue,
      onChanged: (v) => onChanged(v!),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      activeColor: accent, dense: true,
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon; final String label;
  final bool selected; final VoidCallback onTap; final Color accent;
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap, required this.accent});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
