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

// ==================== লোকাল ডাটাবেস ====================
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

// ==================== ক্যাটাগরি ও ভাষা ====================
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
  CatMeta(
    key: 'transport',
    bn: 'যাতায়াত',
    en: 'Transport',
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF6366F1),
  ),
  CatMeta(
    key: 'food',
    bn: 'খাবার',
    en: 'Food',
    icon: Icons.restaurant_rounded,
    color: Color(0xFFF59E0B),
  ),
  CatMeta(
    key: 'groceries',
    bn: 'বাজার',
    en: 'Groceries',
    icon: Icons.shopping_bag_rounded,
    color: Color(0xFF10B981),
  ),
  CatMeta(
    key: 'other',
    bn: 'অন্যান্য',
    en: 'Others',
    icon: Icons.receipt_long_rounded,
    color: Color(0xFFF43F5E),
  ),
];

CatMeta getCatMeta(String key) {
  return kCats.firstWhere((c) => c.key == key, orElse: () => kCats.last);
}

const List<String> _bnMonths = [
  'জানুয়ারি', 'ফেব্রুয়ারি', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
  'জুলাই', 'আগস্ট', 'সেপ্টেম্বর', 'অক্টোবর', 'নভেম্বর', 'ডিসেম্বর'
];
const List<String> _enMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
const List<String> _bnWeekdays = ['রবি', 'সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি'];
const List<String> _enWeekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

// ==================== মূল অ্যাপ ====================
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
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF0D9488)),
          ),
        ),
      );
    }

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0D9488),
        brightness: Brightness.light,
      ),
    );

    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF090D16),
      cardColor: const Color(0xFF131B2E),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2DD4BF),
        brightness: Brightness.dark,
        surface: const Color(0xFF131B2E),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'স্মার্ট হিসাব | Smart Hishab',
      theme: lightTheme,
      darkTheme: darkTheme,
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

// ==================== ডোনাট চার্ট পেইন্টার ====================
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
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate) => true;
}

// ==================== হোম স্ক্রিন ====================
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== ওয়েলকাম ডায়ালগ ====================
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
              'আপনার প্রতিদিনের খরচ ও রিমাইন্ডার সহজে গুছিয়ে রাখতে আপনার নাম লিখুন:',
              'Enter your name to personalize your daily expenses and reminders:',
            )),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText: tr('আপনার নাম (যেমন: সায়েম)', 'Your name (e.g. Sayem)'),
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
              _toast(tr('প্রোফাইল সেভ হয়েছে', 'Profile saved'));
            },
            child: Text(tr('শুরু করুন', 'Get Started')),
          ),
        ],
      ),
    );
  }

  // ==================== খরচ যোগ ====================
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
          padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('নতুন খরচ যোগ করুন', 'Add New Expense'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
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
                              color: sel
                                  ? c.color.withOpacity(0.18)
                                  : Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                              border: Border.all(
                                color: sel ? c.color : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(c.icon, color: c.color, size: 22),
                                const SizedBox(height: 4),
                                Text(
                                  isBn ? c.bn : c.en,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
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
                    hintText: tr('যেমন: রিকশা ভাড়া, ফুচকা', 'e.g. Rickshaw fare, Snacks'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('টাকার পরিমাণ (৳)', 'Amount (৳)'),
                    hintText: '20',
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
                      final dateStr = _tabIndex == 1
                          ? _selectedCalDate
                          : DateFormat('yyyy-MM-dd').format(DateTime.now());
                      final db = await DBHelper.db;
                      await db.insert('expenses', {
                        'category': selectedCat,
                        'item': item,
                        'amount': amt,
                        'date': dateStr,
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

  // ==================== রিমাইন্ডার যোগ ====================
  Future<void> _openAddReminderSheet() async {
    final titleCtrl = TextEditingController();
    final amtCtrl = TextEditingController();
    DateTime pickedDate = DateTime.now();
    TimeOfDay pickedTime = TimeOfDay.fromDateTime(
      DateTime.now().add(const Duration(minutes: 5)),
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('নতুন রিমাইন্ডার সেট করুন', 'Set New Reminder'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    labelText: tr('কাজের বা বাজারের বিবরণ', 'Task or Shopping Note'),
                    hintText: tr('যেমন: বিকেলে কাঁচাবাজার', 'e.g. Evening groceries'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amtCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: tr('সম্ভাব্য খরচ (ঐচ্ছিক)', 'Estimated Cost (Optional)'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today_rounded, size: 18),
                        label: Text(DateFormat('dd/MM/yyyy').format(pickedDate)),
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate: pickedDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2035),
                          );
                          if (d != null) setSheet(() => pickedDate = d);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.access_time_rounded, size: 18),
                        label: Text(pickedTime.format(ctx)),
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: ctx,
                            initialTime: pickedTime,
                          );
                          if (t != null) setSheet(() => pickedTime = t);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () async {
                      final title = titleCtrl.text.trim();
                      if (title.isEmpty) {
                        _toast(tr('কাজের বিবরণ লিখুন', 'Please enter a title'));
                        return;
                      }
                      final scheduled = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                      if (scheduled.isBefore(DateTime.now())) {
                        _toast(tr('দয়া করে ভবিষ্যতের সময় দিন', 'Please choose a future time'));
                        return;
                      }

                      final est = double.tryParse(amtCtrl.text.trim()) ?? 0;
                      final db = await DBHelper.db;
                      final id = await db.insert('reminders', {
                        'title': title,
                        'amount': est,
                        'remindAt': scheduled.toIso8601String(),
                      });

                      await notificationsPlugin.zonedSchedule(
                        id,
                        tr('রিমাইন্ডার অ্যালার্ট!', 'Reminder Alert!'),
                        est > 0 ? '$title (${tr('সম্ভাব্য', 'Est.')} ৳${est.toStringAsFixed(0)})' : title,
                        tz.TZDateTime.from(scheduled, tz.local),
                        const NotificationDetails(
                          android: AndroidNotificationDetails(
                            'reminder_channel',
                            'Expense Reminders',
                            channelDescription: 'Scheduled expense and task alarms',
                            importance: Importance.max,
                            priority: Priority.high,
                            playSound: true,
                            enableVibration: true,
                          ),
                        ),
                        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
                        uiLocalNotificationDateInterpretation:
                            UILocalNotificationDateInterpretation.absoluteTime,
                      );

                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadRecords();
                      _toast(tr('অ্যালার্ম সেট হয়েছে', 'Alarm scheduled'));
                    },
                    child: Text(tr('অ্যালার্ম সেট করুন', 'Set Alarm')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== বাজেট ও সেটিংস ====================
  Future<void> _openBudgetSheet() async {
    final ctrl = TextEditingController(
      text: widget.monthlyBudget > 0 ? widget.monthlyBudget.toStringAsFixed(0) : '',
    );
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20, 4, 20, MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('মাসিক বাজেট সেট করুন', 'Set Monthly Budget'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('বাজেটের পরিমাণ (৳)', 'Budget Amount (৳)'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [3000, 5000, 10000, 20000, 0].map((v) {
                return ActionChip(
                  label: Text(v == 0 ? tr('রিসেট (0)', 'Reset (0)') : '৳$v'),
                  onPressed: () => ctrl.text = v.toString(),
                );
              }).toList(),
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

  Future<void> _openEditNameDialog() async {
    final ctrl = TextEditingController(text: widget.userName);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('প্রোফাইল নাম পরিবর্তন', 'Edit Profile Name')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: tr('আপনার নাম', 'Your Name'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('বাতিল', 'Cancel'))),
          FilledButton(
            onPressed: () {
              widget.onNameChanged(ctrl.text.trim());
              Navigator.pop(ctx);
              _toast(tr('নাম সেভ হয়েছে', 'Name saved'));
            },
            child: Text(tr('সেভ করুন', 'Save')),
          ),
        ],
      ),
    );
  }

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: Theme.of(ctx).colorScheme.primary,
                foregroundColor: Colors.white,
                child: Text(
                  widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '৳',
                ),
              ),
              title: Text(
                widget.userName.isNotEmpty ? widget.userName : tr('গেস্ট ব্যবহারকারী', 'Guest User'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(tr('অফলাইন প্রোফাইল', 'Offline Profile')),
              trailing: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _openEditNameDialog();
                },
                child: Text(tr('পরিবর্তন', 'Edit')),
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.language_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(tr('ভাষা / Language', 'Language')),
                  ],
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'bn', label: Text('বাংলা')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {widget.lang},
                  onSelectionChanged: (s) {
                    widget.onLangChanged(s.first);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.dark_mode_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(tr('থিম মোড', 'Theme Mode')),
                  ],
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Light')),
                    ButtonSegment(value: true, label: Text('Dark')),
                  ],
                  selected: {widget.isDark},
                  onSelectionChanged: (s) {
                    widget.onThemeChanged(s.first);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.track_changes_rounded),
                label: Text(tr('মাসিক বাজেট সেট করুন', 'Set Monthly Budget')),
                onPressed: () {
                  Navigator.pop(ctx);
                  _openBudgetSheet();
                },
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_forever_rounded, color: Colors.red),
                label: Text(
                  tr('সব ডেটা মুছুন', 'Clear All Data'),
                  style: const TextStyle(color: Colors.red),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _confirmClearAll();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearAll() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('সব ডেটা মুছবেন?', 'Delete All Data?')),
        content: Text(tr(
          'মুছে ফেললে আপনার সব হিসাব ও রিমাইন্ডার চিরতরে চলে যাবে।',
          'All saved expenses and reminders will be permanently erased.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('বাতিল', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final db = await DBHelper.db;
              await db.delete('expenses');
              await db.delete('reminders');
              await notificationsPlugin.cancelAll();
              widget.onBudgetChanged(0);
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadRecords();
              _toast(tr('সব ডেটা মুছে ফেলা হয়েছে', 'All data cleared'));
            },
            child: Text(tr('মুছে ফেলুন', 'Delete All')),
          ),
        ],
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
    await notificationsPlugin.cancel(id);
    await _loadRecords();
    _toast(tr('মুছে ফেলা হয়েছে', 'Deleted'));
  }

  Future<void> _testNotification() async {
    await notificationsPlugin.show(
      99999,
      tr('রিমাইন্ডার অ্যালার্ট!', 'Reminder Alert!'),
      tr('নোটিফিকেশন ও শব্দ ঠিকমতো কাজ করছে!', 'Notification and sound are working properly!'),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          'Expense Reminders',
          channelDescription: 'Scheduled expense and task alarms',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
      ),
    );
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
            Text(
              '৳${(e['amount'] as num).toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
              onPressed: () => _deleteExpense(e['id'] as int),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== ট্যাব ১: খরচ ও সার্চ ====================
  Widget _buildExpensesView() {
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final monthPrefix = todayStr.substring(0, 7);

    double monthSum = 0;
    double todaySum = 0;
    final Map<String, double> catSums = {
      'transport': 0, 'food': 0, 'groceries': 0, 'other': 0,
    };

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
      final qOk = q.isEmpty ||
          (e['item'] as String).toLowerCase().contains(q) ||
          meta.bn.toLowerCase().contains(q) ||
          meta.en.toLowerCase().contains(q);
      return catOk && qOk;
    }).toList();

    final filteredSum = filtered.fold<double>(0, (s, e) => s + (e['amount'] as num).toDouble());

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        // হিরো কার্ড
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF0284C7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0D9488).withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr('চলতি মাসের মোট খরচ', 'This Month Total'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _formatMonthYear(now.year, now.month),
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '৳ ${monthSum.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _openBudgetSheet,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.track_changes_rounded, color: Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                widget.monthlyBudget > 0
                                    ? '${tr('বাজেট', 'Budget')}: ৳${widget.monthlyBudget.toStringAsFixed(0)}'
                                    : tr('মাসিক বাজেট সেট করতে ট্যাপ করুন', 'Tap to set monthly budget'),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                          if (widget.monthlyBudget > 0)
                            Text(
                              '${((monthSum / widget.monthlyBudget) * 100).round()}%',
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: widget.monthlyBudget > 0
                              ? (monthSum / widget.monthlyBudget).clamp(0.0, 1.0)
                              : 0,
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            widget.monthlyBudget > 0 && monthSum > widget.monthlyBudget
                                ? Colors.redAccent.shade100
                                : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('আজকের খরচ', 'Today'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          Text('৳ ${todaySum.toStringAsFixed(0)}',
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr('দৈনিক গড় খরচ', 'Daily Average'), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          Text('৳ ${dailyAvg.toStringAsFixed(1)}',
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ডোনাট চার্ট বিশ্লেষণ
        if (monthSum > 0) ...[
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(tr('মাসিক খরচের বিশ্লেষণ', 'Monthly Breakdown'),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${tr('সর্বোচ্চ', 'Top')}: ${segments.isNotEmpty ? (isBn ? segments.first.key.bn : segments.first.key.en) : ""}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: CustomPaint(
                          painter: DonutPainter(segments: segments, total: monthSum),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(tr('মোট', 'Total'), style: const TextStyle(fontSize: 10)),
                                Text('৳${monthSum.toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          children: segments.map((entry) {
                            final pct = monthSum > 0 ? ((entry.value / monthSum) * 100).round() : 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(entry.key.icon, size: 14, color: entry.key.color),
                                          const SizedBox(width: 5),
                                          Text(isBn ? entry.key.bn : entry.key.en,
                                              style: const TextStyle(fontSize: 12)),
                                        ],
                                      ),
                                      Text('৳${entry.value.toStringAsFixed(0)} ($pct%)',
                                          style: const TextStyle(fontSize: 11.5)),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      minHeight: 5,
                                      value: monthSum > 0 ? entry.value / monthSum : 0,
                                      valueColor: AlwaysStoppedAnimation(entry.key.color),
                                      backgroundColor: entry.key.color.withOpacity(0.15),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 14),
        // সার্চ বার
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            hintText: tr('যেকোনো খরচ খুঁজুন (যেমন: রিকশা, ফুচকা)...', 'Search expenses...'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _searchQuery = '');
                    },
                  )
                : null,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // ক্যাটাগরি চিপস
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(tr('সব', 'All')),
                  selected: _activeCat == 'all',
                  onSelected: (_) => setState(() => _activeCat = 'all'),
                ),
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
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${filtered.length}${tr('টি এন্ট্রি', ' entries')}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            Text('${tr('ফিল্টার মোট', 'Filtered')}: ৳ ${filteredSum.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          ],
        ),
        const SizedBox(height: 10),

        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                tr('কোনো খরচের তথ্য নেই। নিচের বাটনে চাপ দিয়ে যোগ করুন।', 'No expenses found. Tap + below to add.'),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...filtered.map((e) => _buildExpenseCard(e)),
      ],
    );
  }

  // ==================== ট্যাব ২: ক্যালেন্ডার ====================
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
    final daySum = dayExps.fold<double>(0, (s, e) => s + (e['amount'] as num).toDouble());

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
                      onPressed: () {
                        setState(() {
                          _calMonth--;
                          if (_calMonth < 1) { _calMonth = 12; _calYear--; }
                          _selectedCalDate = '$_calYear-${_calMonth.toString().padLeft(2, '0')}-01';
                        });
                      },
                    ),
                    Text(_formatMonthYear(_calYear, _calMonth),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: () {
                        setState(() {
                          _calMonth++;
                          if (_calMonth > 12) { _calMonth = 1; _calYear++; }
                          _selectedCalDate = '$_calYear-${_calMonth.toString().padLeft(2, '0')}-01';
                        });
                      },
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${tr('মাসের মোট', 'Month Total')}: ৳${monthSum.toStringAsFixed(0)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('${tr('খরচের দিন', 'Active Days')}: ${dayTotals.length}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: (isBn ? _bnWeekdays : _enWeekdays)
                      .map((w) => Expanded(
                            child: Center(
                              child: Text(w, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 5,
                    crossAxisSpacing: 5,
                    childAspectRatio: 0.9,
                  ),
                  itemCount: leadingEmpty + totalDays,
                  itemBuilder: (ctx, idx) {
                    if (idx < leadingEmpty) return const SizedBox.shrink();
                    final day = idx - leadingEmpty + 1;
                    final dStr = '$monthPrefix-${day.toString().padLeft(2, '0')}';
                    final amt = dayTotals[dStr] ?? 0;
                    final isSel = dStr == _selectedCalDate;
                    final isToday = dStr == todayStr;

                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _selectedCalDate = dStr),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: isSel
                              ? const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0284C7)])
                              : null,
                          color: isSel
                              ? null
                              : (amt > 0
                                  ? Theme.of(ctx).colorScheme.primary.withOpacity(0.14)
                                  : Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.35)),
                          border: isToday && !isSel
                              ? Border.all(color: Theme.of(ctx).colorScheme.primary, width: 1.5)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isSel ? Colors.white : null,
                              ),
                            ),
                            if (amt > 0)
                              Text(
                                amt >= 1000
                                    ? '৳${(amt / 1000).toStringAsFixed(1)}k'
                                    : '৳${amt.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: isSel ? Colors.white70 : Theme.of(ctx).colorScheme.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_selectedCalDate, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${dayExps.length}${tr('টি খরচ', ' expenses')}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
              ],
            ),
            Chip(label: Text('${tr('মোট', 'Total')}: ৳${daySum.toStringAsFixed(0)}')),
          ],
        ),
        const SizedBox(height: 8),
        if (dayExps.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text(tr('এই তারিখে কোনো খরচ লেখা হয়নি', 'No expenses on this date'))),
          )
        else
          ...dayExps.map((e) => _buildExpenseCard(e)),
      ],
    );
  }

  // ==================== ট্যাব ৩: রিমাইন্ডার ====================
  Widget _buildRemindersView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.18)),
          ),
          child: ListTile(
            title: Text(tr('অ্যালার্ম ও নোটিফিকেশন', 'Alarm & Notification'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr('অ্যাপ বন্ধ থাকলেও ঠিক সময়ে বাজবে', 'Rings on time even when closed')),
            trailing: FilledButton.icon(
              icon: const Icon(Icons.volume_up_rounded, size: 18),
              label: Text(tr('পরীক্ষা', 'Test')),
              onPressed: _testNotification,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_reminders.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: Center(
              child: Text(
                tr('কোনো রিমাইন্ডার সেট করা নেই', 'No reminders set'),
              ),
            ),
          )
        else
          ..._reminders.map((r) {
            final dt = DateTime.parse(r['remindAt'] as String);
            final isPast = dt.isBefore(DateTime.now());
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
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.notifications_active_rounded, color: Colors.amber),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(r['title'] as String,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isPast ? Colors.green : Colors.orange).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isPast ? tr('সম্পন্ন', 'Done') : tr('অপেক্ষমাণ', 'Pending'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isPast ? Colors.green : Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(dt) +
                      (amt > 0 ? ' • ${tr('সম্ভাব্য', 'Est.')} ৳${amt.toStringAsFixed(0)}' : ''),
                ),
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
    final titleText = widget.userName.isNotEmpty
        ? '${tr('হ্যালো, ', 'Hi, ')}${widget.userName}!'
        : tr('স্মার্ট হিসাব', 'Smart Hishab');
    final subText = widget.userName.isNotEmpty
        ? '${_greeting()} • ${tr('স্মার্ট হিসাব', 'Smart Hishab')}'
        : tr('দৈনিক খরচ ও রিমাইন্ডার', 'Daily Expense & Reminders');

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
              child: Center(
                child: Text(
                  widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '৳',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(subText, style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: _openSettingsSheet,
          ),
        ],
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
        label: Text(
          _tabIndex == 2 ? tr('রিমাইন্ডার দিন', 'Add Reminder') : tr('খরচ লিখুন', 'Add Expense'),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.account_balance_wallet_rounded),
            label: tr('খরচ ও সার্চ', 'Expenses'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_rounded),
            label: tr('ক্যালেন্ডার', 'Calendar'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_rounded),
            label: tr('রিমাইন্ডার', 'Reminders'),
          ),
        ],
      ),
    );
  }
}
