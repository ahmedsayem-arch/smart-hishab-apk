import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await notificationsPlugin.initialize(initSettings);

  final androidImpl = notificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.requestNotificationsPermission();
  await androidImpl?.requestExactAlarmsPermission();

  runApp(const SmartHishabApp());
}

class DBHelper {
  static Database? _db;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'smart_hishab.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            category TEXT,
            item TEXT,
            amount REAL,
            date TEXT,
            ts INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            amount REAL,
            remindAt TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            k TEXT PRIMARY KEY,
            v TEXT
          )
        ''');
      },
    );
    return _db!;
  }

  static Future<String> getSetting(String key, [String def = '']) async {
    try {
      final database = await db;
      final res = await database.query('settings', where: 'k = ?', whereArgs: [key]);
      if (res.isNotEmpty) return (res.first['v'] as String?) ?? def;
    } catch (_) {}
    return def;
  }

  static Future<void> setSetting(String key, String value) async {
    try {
      final database = await db;
      await database.insert(
        'settings',
        {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }
}

class CatMeta {
  final String key;
  final String bn;
  final String en;
  final IconData icon;
  final Color color;

  const CatMeta({
    required this.key,
    required this.bn,
    required this.en,
    required this.icon,
    required this.color,
  });
}

const List<CatMeta> kCats = [
  CatMeta(key: 'transport', bn: 'যাতায়াত', en: 'Transport', icon: Icons.directions_bus_rounded, color: Color(0xFF6366F1)),
  CatMeta(key: 'food', bn: 'খাবার', en: 'Food', icon: Icons.restaurant_rounded, color: Color(0xFFF59E0B)),
  CatMeta(key: 'groceries', bn: 'বাজার', en: 'Groceries', icon: Icons.shopping_bag_rounded, color: Color(0xFF10B981)),
  CatMeta(key: 'other', bn: 'অন্যান্য', en: 'Others', icon: Icons.receipt_long_rounded, color: Color(0xFFF43F5E)),
];

CatMeta getCatMeta(String key) {
  return kCats.firstWhere((c) => c.key == key, orElse: () => kCats.last);
}

const List<String> _bnMonths = ['জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন', 'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'];
const List<String> _enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const List<String> _bnWeekdays = ['রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি'];
const List<String> _enWeekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

class SmartHishabApp extends StatefulWidget {
  const SmartHishabApp({super.key});

  @override
  State<SmartHishabApp> createState() => _SmartHishabAppState();
}

class _SmartHishabAppState extends State<SmartHishabApp> {
  String _lang = 'bn';
  bool _isDark = false;
  String _userName = '';
  bool _onboarded = true;
  double _monthlyBudget = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final l = await DBHelper.getSetting('lang', 'bn');
    final th = await DBHelper.getSetting('theme', 'light');
    final u = await DBHelper.getSetting('userName', '');
    final ob = await DBHelper.getSetting('onboarded', '0');
    final b = double.tryParse(await DBHelper.getSetting('budget', '0')) ?? 0;

    if (!mounted) return;
    setState(() {
      _lang = l;
      _isDark = th == 'dark';
      _userName = u;
      _onboarded = ob == '1' || u.isNotEmpty;
      _monthlyBudget = b;
      _isLoading = false;
    });
  }

  Future<void> _updateLang(String l) async {
    await DBHelper.setSetting('lang', l);
    setState(() => _lang = l);
  }

  Future<void> _updateTheme(bool dark) async {
    await DBHelper.setSetting('theme', dark ? 'dark' : 'light');
    setState(() => _isDark = dark);
  }

  Future<void> _updateUserName(String name) async {
    await DBHelper.setSetting('userName', name);
    await DBHelper.setSetting('onboarded', '1');
    setState(() {
      _userName = name;
      _onboarded = true;
    });
  }

  Future<void> _updateBudget(double val) async {
    await DBHelper.setSetting('budget', val.toString());
    setState(() => _monthlyBudget = val);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF0D9488)))),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'স্মার্ট হিসাব',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light, scaffoldBackgroundColor: const Color(0xFFF1F5F9)),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF090D16)),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: HomePage(
        lang: _lang,
        isDark: _isDark,
        userName: _userName,
        needsOnboarding: !_onboarded,
        monthlyBudget: _monthlyBudget,
        onLangChanged: _updateLang,
        onThemeChanged: _updateTheme,
        onNameChanged: _updateUserName,
        onBudgetChanged: _updateBudget,
      ),
    );
  }
}

class DonutPainter extends CustomPainter {
  final List<MapEntry<CatMeta, double>> segments;
  final double total;

  DonutPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 8;
    const strokeWidth = 14.0;
    double startAngle = -math.pi / 2;

    for (final entry in segments) {
      if (entry.value <= 0) continue;
      final sweepAngle = (entry.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = entry.key.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) => true;
}

class HomePage extends StatefulWidget {
  final String lang;
  final bool isDark;
  final String userName;
  final bool needsOnboarding;
  final double monthlyBudget;
  final ValueChanged<String> onLangChanged;
  final ValueChanged<bool> onThemeChanged;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<double> onBudgetChanged;

  const HomePage({
    super.key,
    required this.lang,
    required this.isDark,
    required this.userName,
    required this.needsOnboarding,
    required this.monthlyBudget,
    required this.onLangChanged,
    required this.onThemeChanged,
    required this.onNameChanged,
    required this.onBudgetChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;
  String _activeCat = 'all';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  List> _expenses = [];
  List> _reminders = [];

  late int _calYear;
  late int _calMonth;
  late String _selectedCalDate;
  bool _welcomeShown = false;

  bool get isBn => widget.lang == 'bn';
  String tr(String bn, String en) => isBn ? bn : en;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calYear = now.year;
    _calMonth = now.month;
    _selectedCalDate = DateFormat('yyyy-MM-dd').format(now);
    _loadRecords();

    if (widget.needsOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWelcomeDialog());
    }
  }

  Future<void> _loadRecords() async {
    try {
      final db = await DBHelper.db;
      final exp = await db.query('expenses', orderBy: 'date DESC, id DESC');
      final rem = await db.query('reminders', orderBy: 'remindAt ASC');
      if (!mounted) return;
      setState(() {
        _expenses = exp;
        _reminders = rem;
      });
    } catch (_) {}
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _showWelcomeDialog() async {
    if (_welcomeShown) return;
    _welcomeShown = true;
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('স্মার্ট হিসাবে স্বাগতম!', 'Welcome!')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: tr('আপনার নাম লিখুন', 'Enter your name')),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              widget.onNameChanged(name);
              Navigator.pop(ctx);
            },
            child: Text(tr('শুরু করুন', 'Get Started')),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddExpenseSheet() async {
    String selectedCat = 'transport';
    final itemCtrl = TextEditingController();
    final amtCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('নতুন খরচ যোগ করুন', 'Add Expense'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              TextField(controller: itemCtrl, decoration: InputDecoration(labelText: tr('বিবরণ', 'Description'))),
              const SizedBox(height: 10),
              TextField(controller: amtCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('টাকা', 'Amount'))),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final item = itemCtrl.text.trim();
                    final amt = double.tryParse(amtCtrl.text.trim());
                    if (item.isEmpty || amt == null || amt <= 0) return;
                    final db = await DBHelper.db;
                    await db.insert('expenses', {
                      'category': selectedCat,
                      'item': item,
                      'amount': amt,
                      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                      'ts': DateTime.now().millisecondsSinceEpoch,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadRecords();
                  },
                  child: Text(tr('সেভ করুন', 'Save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpensesView() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        if (_expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(tr('কোনো খরচ নেই', 'No expenses found'))),
          )
        else
          ..._expenses.map((e) => Card(
                child: ListTile(
                  title: Text(e['item']),
                  trailing: Text('৳${e['amount']}'),
                ),
              )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.userName.isNotEmpty ? 'Hi, ${widget.userName}' : 'Smart Hishab')),
      body: _buildExpensesView(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddExpenseSheet,
        child: const Icon(Icons.add),
      ),
    );
  }
}
