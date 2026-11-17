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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(debugShowCheckedModeBanner: false, home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light, scaffoldBackgroundColor: const Color(0xFFF1F5F9)),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: const Color(0xFF090D16)),
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      home: HomePage(
        lang: _lang, isDark: _isDark, userName: _userName, needsOnboarding: !_onboarded, monthlyBudget: _monthlyBudget,
        onLangChanged: (l) async { await DBHelper.setSetting('lang', l); setState(() => _lang = l); },
        onThemeChanged: (d) async { await DBHelper.setSetting('theme', d ? 'dark' : 'light'); setState(() => _isDark = d); },
        onNameChanged: (n) async { await DBHelper.setSetting('userName', n); await DBHelper.setSetting('onboarded', '1'); setState(() { _userName = n; _onboarded = true; }); },
        onBudgetChanged: (b) async { await DBHelper.setSetting('budget', b.toString()); setState(() => _monthlyBudget = b); },
      ),
    );
  }
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

  const HomePage({super.key, required this.lang, required this.isDark, required this.userName, required this.needsOnboarding, required this.monthlyBudget, required this.onLangChanged, required this.onThemeChanged, required this.onNameChanged, required this.onBudgetChanged});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;
  List _expenses = [];
  List _reminders = [];

  bool get isBn => widget.lang == 'bn';
  String tr(String bn, String en) => isBn ? bn : en;

  @override
  void initState() {
    super.initState();
    _loadRecords();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.userName.isNotEmpty ? 'Hi, ${widget.userName}' : 'Smart Hishab')),
      body: Center(child: Text(tr('স্বাগতম', 'Welcome'))),
    );
  }
}
