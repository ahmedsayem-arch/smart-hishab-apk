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

  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _reminders = [];

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

  String _greeting() {
    final hr = DateTime.now().hour;
    if (hr >= 5 && hr < 12) return tr('শুভ সকাল', 'Good Morning');
    if (hr >= 12 && hr < 17) return tr('শুভ দুপুর', 'Good Afternoon');
    if (hr >= 17 && hr < 21) return tr('শুভ সন্ধ্যা', 'Good Evening');
    return tr('শুভ রাত্রি', 'Good Night');
  }

  String _formatMonthYear(int year, int month) {
    final mName = isBn ? _bnMonths[month - 1] : _enMonths[month - 1];
    return '$mName $year';
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
        title: Text(tr('স্মার্ট হিসাবে স্বাগতম!', 'Welcome to Smart Hishab!')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ChoiceChip(
                  label: const Text('বাংলা'),
                  selected: isBn,
                  onSelected: (_) {
                    widget.onLangChanged('bn');
                    Navigator.pop(ctx);
                    _welcomeShown = false;
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('English'),
                  selected: !isBn,
                  onSelected: (_) {
                    widget.onLangChanged('en');
                    Navigator.pop(ctx);
                    _welcomeShown = false;
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(tr(
              'আপনার প্রতিদিনের খরচ সহজে গুছিয়ে রাখতে আপনার নাম লিখুন:',
              'Enter your name to personalize your daily expenses:',
            )),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              widget.onNameChanged('');
              Navigator.pop(ctx);
            },
            child: Text(tr('এখন নয়', 'Skip')),
          ),
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
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('নতুন খরচ যোগ করুন', 'Add New Expense'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                Text(tr('ক্যাটাগরি', 'Category'), style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 8),
                Row(
                  children: kCats.map((c) {
                    final sel = selectedCat == c.key;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setSheet(() => selectedCat = c.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: sel ? c.color.withOpacity(0.18) : Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                              border: Border.all(color: sel ? c.color : Colors.transparent, width: 1.5),
                            ),
                            child: Column(
                              children: [
                                Icon(c.icon, color: c.color, size: 22),
                                const SizedBox(height: 4),
                                Text(isBn ? c.bn : c.en, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: itemCtrl,
                  decoration: InputDecoration(
                    labelText: tr('খরচের বিবরণ', 'Description'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('টাকার পরিমাণ (৳)', 'Amount (৳)'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [10, 20, 50, 100, 500].map((v) {
                    return ActionChip(
                      label: Text('+৳$v'),
                      onPressed: () {
                        final cur = double.tryParse(amtCtrl.text.trim()) ?? 0;
                        amtCtrl.text = (cur + v).toStringAsFixed(0);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () async {
                      final item = itemCtrl.text.trim();
                      final amt = double.tryParse(amtCtrl.text.trim());
                      if (item.isEmpty || amt == null || amt <= 0) {
                        _toast(tr('বিবরণ ও সঠিক টাকা লিখুন', 'Enter description and valid amount'));
                        return;
                      }
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
                      _toast(tr('খরচ সেভ হয়েছে', 'Expense saved'));
                    },
                    child: Text(tr('সেভ করুন', 'Save')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== নোট যোগ (রিমাইন্ডার পরিবর্তন করে নোট করা হয়েছে) ====================
  Future<void> _openAddReminderSheet() async {
    final titleCtrl = TextEditingController();
    final amtCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('নতুন নোট যোগ করুন', 'Add New Note'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: titleCtrl,
                decoration: InputDecoration(
                  labelText: tr('নোটের বিবরণ', 'Note Details'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('টাকা (ঐচ্ছিক)', 'Amount (Optional)'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: () async {
                    final title = titleCtrl.text.trim();
                    if (title.isEmpty) {
                      _toast(tr('নোটের বিবরণ লিখুন', 'Please enter note details'));
                      return;
                    }
                    final est = double.tryParse(amtCtrl.text.trim()) ?? 0;
                    final db = await DBHelper.db;
                    await db.insert('reminders', {
                      'title': title,
                      'amount': est,
                      'remindAt': DateTime.now().toIso8601String(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    await _loadRecords();
                    _toast(tr('নোট সেভ হয়েছে', 'Note saved'));
                  },
                  child: Text(tr('নোট সেভ করুন', 'Save Note')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openBudgetSheet() async {
    final ctrl = TextEditingController(text: widget.monthlyBudget > 0 ? widget.monthlyBudget.toStringAsFixed(0) : '');
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('মাসিক বাজেট সেট করুন', 'Set Monthly Budget'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('বাজেটের পরিমাণ (৳)', 'Budget Amount (৳)'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () {
                  final v = double.tryParse(ctrl.text.trim()) ?? 0;
                  widget.onBudgetChanged(v > 0 ? v : 0);
                  Navigator.pop(ctx);
                  _toast(tr('বাজেট আপডেট হয়েছে', 'Budget updated'));
                },
                child: Text(tr('সেভ করুন', 'Save')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteExpense(int id) async {
    final db = await DBHelper.db;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    await _loadRecords();
    _toast(tr('মুছে ফেলা হয়েছে', 'Deleted'));
  }

  Future<void> _deleteReminder(int id) async {
    final db = await DBHelper.db;
    await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
    await _loadRecords();
    _toast(tr('মুছে ফেলা হয়েছে', 'Deleted'));
  }

  Widget _buildExpenseCard(Map<String, dynamic> e) {
    final meta = getCatMeta(e['category'] as String);
    final ts = (e['ts'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
    final timeStr = DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts));

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.18)),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: meta.color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(meta.icon, color: meta.color),
        ),
        title: Text(e['item'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${isBn ? meta.bn : meta.en} • ${e['date']} ($timeStr)'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('৳${(e['amount'] as num).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
              onPressed: () => _deleteExpense(e['id'] as int),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpensesView() {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final monthPrefix = todayStr.substring(0, 7);

    double monthSum = 0;
    double todaySum = 0;
    final Map<String, double> catSums = {'transport': 0, 'food': 0, 'groceries': 0, 'other': 0};

    for (final e in _expenses) {
      final d = e['date'] as String;
      if (d.startsWith(monthPrefix)) {
        final amt = (e['amount'] as num).toDouble();
        monthSum += amt;
        if (d == todayStr) todaySum += amt;
        final k = e['category'] as String;
        catSums[k] = (catSums[k] ?? 0) + amt;
      }
    }

    final dailyAvg = monthSum / (now.day > 0 ? now.day : 1);
    final segments = kCats.map((c) => MapEntry(c, catSums[c.key] ?? 0)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final q = _searchQuery.trim().toLowerCase();
    final filtered = _expenses.where((e) {
      final catOk = _activeCat == 'all' || e['category'] == _activeCat;
      final meta = getCatMeta(e['category'] as String);
      final qOk = q.isEmpty || (e['item'] as String).toLowerCase().contains(q) || meta.bn.toLowerCase().contains(q) || meta.en.toLowerCase().contains(q);
      return catOk && qOk;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF0284C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('চলতি মাসের মোট খরচ', 'This Month Total'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(_formatMonthYear(now.year, now.month), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 6),
              Text('৳ ${monthSum.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              InkWell(
                onTap: _openBudgetSheet,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.monthlyBudget > 0 ? '${tr('বাজেট', 'Budget')}: ৳${widget.monthlyBudget.toStringAsFixed(0)}' : tr('মাসিক বাজেট সেট করতে ট্যাপ করুন', 'Tap to set monthly budget'),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      if (widget.monthlyBudget > 0)
                        Text('${((monthSum / widget.monthlyBudget) * 100).round()}%', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: tr('যেকোনো খরচ খুঁজুন...', 'Search expenses...'),
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(tr('সব', 'All')), selected: _activeCat == 'all', onSelected: (_) => setState(() => _activeCat = 'all')),
              ),
              ...kCats.map((c) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(c.icon, size: 16, color: c.color),
                      label: Text(isBn ? c.bn : c.en),
                      selected: _activeCat == c.key,
                      onSelected: (_) => setState(() => _activeCat = c.key),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(tr('কোনো খরচের তথ্য নেই।', 'No expenses found.'))),
          )
        else
          ...filtered.map((e) => _buildExpenseCard(e)),
      ],
    );
  }

  Widget _buildCalendarView() {
    final monthPrefix = '$_calYear-${_calMonth.toString().padLeft(2, '0')}';
    final Map<String, double> dayTotals = {};
    double monthSum = 0;

    for (final e in _expenses) {
      final d = e['date'] as String;
      if (d.startsWith(monthPrefix)) {
        final amt = (e['amount'] as num).toDouble();
        dayTotals[d] = (dayTotals[d] ?? 0) + amt;
        monthSum += amt;
      }
    }

    final firstDay = DateTime(_calYear, _calMonth, 1);
    final leadingEmpty = firstDay.weekday % 7;
    final totalDays = DateTime(_calYear, _calMonth + 1, 0).day;
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final dayExps = _expenses.where((e) => e['date'] == _selectedCalDate).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.18)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: () => setState(() {
                        _calMonth--;
                        if (_calMonth < 1) { _calMonth = 12; _calYear--; }
                        _selectedCalDate = '$_calYear-${_calMonth.toString().padLeft(2, '0')}-01';
                      }),
                    ),
                    Text(_formatMonthYear(_calYear, _calMonth), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () => setState(() {
                        _calMonth++;
                        if (_calMonth > 12) { _calMonth = 1; _calYear++; }
                        _selectedCalDate = '$_calYear-${_calMonth.toString().padLeft(2, '0')}-01';
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: (isBn ? _bnWeekdays : _enWeekdays)
                      .map((w) => Expanded(child: Center(child: Text(w, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)))))
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5, childAspectRatio: 0.9),
                  itemCount: leadingEmpty + totalDays,
                  itemBuilder: (ctx, idx) {
                    if (idx < leadingEmpty) return const SizedBox.shrink();
                    final day = idx - leadingEmpty + 1;
                    final dStr = '$monthPrefix-${day.toString().padLeft(2, '0')}';
                    final amt = dayTotals[dStr] ?? 0;
                    final isSel = dStr == _selectedCalDate;

                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _selectedCalDate = dStr),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: isSel ? Theme.of(ctx).colorScheme.primary : (amt > 0 ? Theme.of(ctx).colorScheme.primary.withOpacity(0.14) : Colors.transparent),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('$day', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSel ? Colors.white : null)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(_selectedCalDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),
        if (dayExps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text(tr('এই তারিখে কোনো খরচ নেই', 'No expenses on this date'))),
          )
        else
          ...dayExps.map((e) => _buildExpenseCard(e)),
      ],
    );
  }

  // ==================== নোটস ভিউ ====================
  Widget _buildRemindersView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        if (_reminders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: Center(child: Text(tr('কোনো নোট নেই', 'No notes found'))),
          )
        else
          ..._reminders.map((r) {
            final amt = (r['amount'] as num).toDouble();
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.18)),
              ),
              child: ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.16), borderRadius: BorderRadius.circular(13)),
                  child: const Icon(Icons.note_alt_rounded, color: Colors.amber),
                ),
                title: Text(r['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: amt > 0 ? Text('৳${amt.toStringAsFixed(0)}') : null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  onPressed: () => _deleteReminder(r['id'] as int),
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0284C7)]),
              ),
              child: const Center(
                child: Text('৳', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.userName.isNotEmpty ? '${tr('হ্যালো, ', 'Hi, ')}${widget.userName}!' : tr('স্মার্ট হিসাব', 'Smart Hishab'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(widget.userName.isNotEmpty ? '${_greeting()} • ${tr('স্মার্ট হিসাব', 'Smart Hishab')}' : tr('দৈনিক খরচ ও নোট', 'Daily Expense & Notes'), style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildExpensesView(),
          _buildCalendarView(),
          _buildRemindersView(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tabIndex == 2 ? _openAddReminderSheet : _openAddExpenseSheet,
        icon: const Icon(Icons.add_rounded),
        label: Text(_tabIndex == 2 ? tr('নোট দিন', 'Add Note') : tr('খরচ লিখুন', 'Add Expense')),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_rounded), label: tr('খরচ ও সার্চ', 'Expenses')),
          NavigationDestination(icon: const Icon(Icons.calendar_month_rounded), label: tr('ক্যালেন্ডার', 'Calendar')),
          NavigationDestination(icon: const Icon(Icons.note_rounded), label: tr('নোট', 'Notes')),
        ],
      ),
    );
  }
}
