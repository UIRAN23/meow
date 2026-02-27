import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://ilszhdmqxsoixcefeoqa.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...'; // Твой ключ

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  runApp(const SignalApp());
}

class SignalApp extends StatelessWidget {
  const SignalApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF2090FF),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String myNick = "User";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Signal'),
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
      ),
      // ТОТ САМЫЙ БУРГЕР
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              currentAccountPicture: const CircleAvatar(backgroundColor: Colors.blueAccent),
              accountName: Text(myNick),
              accountEmail: const Text("Supabase Protected"),
              decoration: const BoxDecoration(color: Color(0xFF1C1C1C)),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text("Профиль"),
              onTap: () {
                // Здесь можно добавить диалог смены ника
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text("Настройки"),
              subtitle: const Text("В разработке", style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () {},
            ),
          ],
        ),
      ),
      body: const Center(child: Text("Нет активных чатов")),
      // КНОПКА ПЛЮС
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Логика добавления чата
        },
        backgroundColor: const Color(0xFF2090FF),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String roomName;
  const ChatScreen({super.key, required this.roomName});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _msgController = TextEditingController();
  bool _showSend = false;

  @override
  void initState() {
    super.initState();
    _msgController.addListener(() {
      setState(() {
        _showSend = _msgController.text.isNotEmpty;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomName),
        backgroundColor: const Color(0xFF121212),
        // Бургера здесь автоматически НЕ будет, будет кнопка "Назад"
      ),
      body: Column(
        children: [
          const Expanded(child: Center(child: Text("Сообщений нет"))),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: InputDecoration(
                      hintText: "Сообщение",
                      fillColor: const Color(0xFF2D2D2D),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                // ТРЕУГОЛЬНИК ПОЯВЛЯЕТСЯ ТОЛЬКО КОГДА ЕСТЬ ТЕКСТ
                if (_showSend)
                  IconButton(
                    icon: const Icon(Icons.send, color: Color(0xFF2090FF)),
                    onPressed: () {
                      _msgController.clear();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
