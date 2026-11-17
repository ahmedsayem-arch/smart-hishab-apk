import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  // Bangladesh uses UTC+6 and currently has no daylight-saving changes.
  tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await notifications.initialize(const InitializationSettings(android: android, iOS: ios));
  await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
  await notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
    const AndroidNotificationChannel('smart_hishab_reminders_v2', 'Smart Hishab Reminders', description: 'Expense and note reminders', importance: Importance.max, playSound: true),
  );
  runApp(const SmartHishabApp());
}

Future<bool> scheduleNoteReminder(int id, String title, DateTime when) async {
  if (!when.isAfter(DateTime.now())) return false;

  try {
    final androidImpl = notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Android 12+ exact alarm permission. If not granted, use inexact mode.
    final exactAllowed =
        await androidImpl?.requestExactAlarmsPermission() ?? false;

    await notifications.zonedSchedule(
      id,
      'Smart Hishab',
      title,
      tz.TZDateTime.from(when, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'smart_hishab_reminders_v2',
          'Smart Hishab Reminders',
          channelDescription: 'Expense and note reminders',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: exactAllowed
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );

    return true;
  } catch (_) {
    return false;
  }
}


class DB {
  static Database? _db;
  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'smart_hishab.db'),
      version: 3,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE expenses (id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL, item TEXT NOT NULL, amount REAL NOT NULL, date TEXT NOT NULL, ts INTEGER NOT NULL)');
        await db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, amount REAL NOT NULL, createdAt TEXT NOT NULL, reminderAt INTEGER)');
        await db.execute('CREATE TABLE settings (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
        await indexes(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, amount REAL NOT NULL, createdAt TEXT NOT NULL, reminderAt INTEGER)');
          // Version 1 used a table named reminders. Preserve those saved notes.
          final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='reminders'");
          if (tables.isNotEmpty) {
            await db.execute("INSERT OR IGNORE INTO notes (id,title,amount,createdAt) SELECT id,title,amount,remindAt FROM reminders");
          }
          await indexes(db);
        }
        if (oldVersion < 3) {
          final cols = await db.rawQuery('PRAGMA table_info(notes)');
          if (!cols.any((c) => c['name'] == 'reminderAt')) {
            await db.execute('ALTER TABLE notes ADD COLUMN reminderAt INTEGER');
          }
        }
      },
    );
    return _db!;
  }

  static Future<void> indexes(Database db) async {
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_created ON notes(createdAt)');
  }

  static Future<String> setting(String key, [String fallback = '']) async {
    final rows = await (await instance).query('settings', where: 'k=?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? fallback : (rows.first['v'] as String? ?? fallback);
  }

  static Future<void> saveSetting(String key, String value) async {
    await (await instance).insert('settings', {'k': key, 'v': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

class Category {
  final String id, bn, en;
  final IconData icon;
  final Color color;
  const Category(this.id, this.bn, this.en, this.icon, this.color);
}
const cats = <Category>[
  Category('transport','যাতায়াত','Transport',Icons.directions_bus_rounded,Color(0xFF6366F1)),
  Category('food','খাবার','Food',Icons.restaurant_rounded,Color(0xFFF59E0B)),
  Category('groceries','বাজার','Groceries',Icons.shopping_bag_rounded,Color(0xFF10B981)),
  Category('other','অন্যান্য','Others',Icons.receipt_long_rounded,Color(0xFFF43F5E)),
];
Category catOf(String id) => cats.firstWhere((c) => c.id == id, orElse: () => cats.last);
const bnMonths = ['জানুয়ারি','ফেব্রুয়ারি','মার্চ','এপ্রিল','মে','জুন','জুলাই','আগস্ট','সেপ্টেম্বর','অক্টোবর','নভেম্বর','ডিসেম্বর'];
const enMonths = ['January','February','March','April','May','June','July','August','September','October','November','December'];

class SmartHishabApp extends StatefulWidget {
  const SmartHishabApp({super.key});
  @override
  State<SmartHishabApp> createState() => _SmartHishabAppState();
}
class _SmartHishabAppState extends State<SmartHishabApp> {
  String lang = 'bn', name = '';
  bool dark = false, loading = true;
  double budget = 0;

  @override
  void initState() {
    super.initState();
    load();
  }
  Future<void> load() async {
    final l = await DB.setting('lang','bn');
    final d = await DB.setting('theme','light');
    final n = await DB.setting('userName','');
    final b = double.tryParse(await DB.setting('budget','0')) ?? 0;
    if (!mounted) return;
    setState(() { lang=l; dark=d=='dark'; name=n; budget=b; loading=false; });
  }
  Future<void> setLang(String v) async { await DB.saveSetting('lang',v); if(mounted)setState(()=>lang=v); }
  Future<void> setDark(bool v) async { await DB.saveSetting('theme',v?'dark':'light'); if(mounted)setState(()=>dark=v); }
  Future<void> setName(String v) async { await DB.saveSetting('userName',v); if(mounted)setState(()=>name=v); }
  Future<void> setBudget(double v) async { await DB.saveSetting('budget',v.toString()); if(mounted)setState(()=>budget=v); }

  @override
  Widget build(BuildContext context) {
    if (loading) return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    return MaterialApp(
      debugShowCheckedModeBanner:false,
      title:'Smart Hishab',
      themeMode:dark?ThemeMode.dark:ThemeMode.light,
      theme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF0D9488),brightness:Brightness.light,scaffoldBackgroundColor:const Color(0xFFF1F5F9)),
      darkTheme:ThemeData(useMaterial3:true,colorSchemeSeed:const Color(0xFF0D9488),brightness:Brightness.dark,scaffoldBackgroundColor:const Color(0xFF090D16)),
      home:HomePage(lang:lang,dark:dark,name:name,budget:budget,onLang:setLang,onDark:setDark,onName:setName,onBudget:setBudget),
    );
  }
}

class DonutPainter extends CustomPainter {
  final Map<String,double> values;
  final double total;
  DonutPainter(this.values,this.total);
  @override
  void paint(Canvas canvas, Size size) {
    if(total<=0)return;
    final rect=Rect.fromCircle(center:Offset(size.width/2,size.height/2),radius:math.min(size.width,size.height)/2-7);
    double start=-math.pi/2;
    for(final c in cats){
      final amount=values[c.id]??0;
      if(amount<=0)continue;
      final sweep=amount/total*math.pi*2;
      canvas.drawArc(rect,start,sweep,false,Paint()..color=c.color..style=PaintingStyle.stroke..strokeWidth=13..strokeCap=StrokeCap.round);
      start+=sweep;
    }
  }
  @override
  bool shouldRepaint(covariant DonutPainter oldDelegate)=>true;
}

class HomePage extends StatefulWidget {
  final String lang,name;
  final bool dark;
  final double budget;
  final ValueChanged<String> onLang,onName;
  final ValueChanged<bool> onDark;
  final ValueChanged<double> onBudget;
  const HomePage({super.key,required this.lang,required this.dark,required this.name,required this.budget,required this.onLang,required this.onDark,required this.onName,required this.onBudget});
  @override
  State<HomePage> createState()=>_HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab=0, year=DateTime.now().year, month=DateTime.now().month;
  String selectedDate=DateFormat('yyyy-MM-dd').format(DateTime.now()), filter='all', search='';
  final searchCtrl=TextEditingController();
  List<Map<String,dynamic>> expenses=[], notes=[];
  bool get bn=>widget.lang=='bn';
  String tr(String b,String e)=>bn?b:e;

  @override
  void initState(){super.initState();loadRecords();}
  @override
  void dispose(){searchCtrl.dispose();super.dispose();}
  Future<void> loadRecords() async {
    final db=await DB.instance;
    final e=await db.query('expenses',orderBy:'date DESC,id DESC');
    final n=await db.query('notes',orderBy:'createdAt DESC');
    if(!mounted)return;
    setState(() { expenses = e; notes = n; });
  }
  void toast(String s){if(!mounted)return;ScaffoldMessenger.of(context)..clearSnackBars()..showSnackBar(SnackBar(content:Text(s),behavior:SnackBarBehavior.floating));}
  String monthTitle()=> '${(bn?bnMonths:enMonths)[month-1]} $year';

  Future<void> addExpense() async {
    String category='transport';
    final item=TextEditingController(), amount=TextEditingController();
    await showModalBottomSheet(context:context,isScrollControlled:true,showDragHandle:true,builder:(sheet)=>StatefulBuilder(builder:(ctx,setSheet)=>Padding(
      padding:EdgeInsets.fromLTRB(18,8,18,MediaQuery.of(ctx).viewInsets.bottom+20),
      child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(tr('নতুন খরচ যোগ করুন','Add Expense'),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
        const SizedBox(height:14),
        Wrap(spacing:7,runSpacing:7,children:cats.map((c)=>ChoiceChip(avatar:Icon(c.icon,color:c.color,size:17),label:Text(bn?c.bn:c.en),selected:category==c.id,onSelected:(_)=>setSheet(()=>category=c.id))).toList()),
        const SizedBox(height:12),
        TextField(controller:item,decoration:InputDecoration(labelText:tr('খরচের বিবরণ','Description'),border:const OutlineInputBorder())),
        const SizedBox(height:12),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('টাকার পরিমাণ (৳)','Amount (৳)'),border:const OutlineInputBorder())),
        const SizedBox(height:16),
        SizedBox(width:double.infinity,child:FilledButton(onPressed:()async{
          final value=double.tryParse(amount.text.trim()), title=item.text.trim();
          if(title.isEmpty||value==null||value<=0){toast(tr('বিবরণ ও সঠিক টাকা লিখুন','Enter description and valid amount'));return;}
          final now=DateTime.now();
          await (await DB.instance).insert('expenses',{'category':category,'item':title,'amount':value,'date':DateFormat('yyyy-MM-dd').format(now),'ts':now.millisecondsSinceEpoch});
          if(sheet.mounted)Navigator.pop(sheet);
          await loadRecords();toast(tr('খরচ সেভ হয়েছে','Expense saved'));
        },child:Text(tr('সেভ করুন','Save')))),
      ])),
    )));
    item.dispose();amount.dispose();
  }

  Future<void> addNote() async {
    final title=TextEditingController(), amount=TextEditingController();
    DateTime? reminder;
    await showModalBottomSheet(context:context,isScrollControlled:true,showDragHandle:true,builder:(sheet)=>StatefulBuilder(builder:(ctx,setSheet)=>Padding(
      padding:EdgeInsets.fromLTRB(18,8,18,MediaQuery.of(ctx).viewInsets.bottom+20),
      child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(tr('নতুন নোট / রিমাইন্ডার','New Note / Reminder'),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
        const SizedBox(height:14),
        TextField(controller:title,decoration:InputDecoration(labelText:tr('নোটের বিবরণ','Note details'),border:const OutlineInputBorder())),
        const SizedBox(height:12),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:tr('টাকা (ঐচ্ছিক)','Amount (optional)'),border:const OutlineInputBorder())),
        const SizedBox(height:10),
        Card(elevation:0,child:ListTile(
          leading:const Icon(Icons.notifications_active_outlined),
          title:Text(reminder==null?tr('রিমাইন্ডারের সময় দিন','Set reminder time'):DateFormat('dd MMM yyyy, hh:mm a').format(reminder!)),
          subtitle:Text(tr('ঐচ্ছিক — সময় দিলে নোটিফিকেশন আসবে','Optional — a notification will appear at this time')),
          trailing:reminder==null?const Icon(Icons.chevron_right):IconButton(icon:const Icon(Icons.close),onPressed:()=>setSheet(()=>reminder=null)),
          onTap:()async{
            final pickedDate=await showDatePicker(context:ctx,initialDate:DateTime.now().add(const Duration(days:1)),firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:365*5)));
            if(pickedDate==null)return;
            if(!ctx.mounted)return;
            final pickedTime=await showTimePicker(context:ctx,initialTime:TimeOfDay.now());
            if(pickedTime==null)return;
            final chosen=DateTime(pickedDate.year,pickedDate.month,pickedDate.day,pickedTime.hour,pickedTime.minute);
            if(!chosen.isAfter(DateTime.now())){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(tr('ভবিষ্যতের সময় নির্বাচন করুন','Choose a future time'))));return;}
            setSheet(()=>reminder=chosen);
          },
        )),
        const SizedBox(height:14),
        SizedBox(width:double.infinity,child:FilledButton(onPressed:()async{
          final t=title.text.trim(), a=double.tryParse(amount.text.trim())??0;
          if(t.isEmpty||a<0){toast(tr('নোটের বিবরণ লিখুন','Enter note details'));return;}
          final id=await (await DB.instance).insert('notes',{'title':t,'amount':a,'createdAt':DateTime.now().toIso8601String(),'reminderAt':reminder?.millisecondsSinceEpoch});
          bool reminderSet = true;
          if(reminder!=null){
            reminderSet = await scheduleNoteReminder(id,t,reminder!);
          }
          if(sheet.mounted)Navigator.pop(sheet);
          await loadRecords();
          if(reminder==null){
            toast(tr('নোট সেভ হয়েছে','Note saved'));
          }else if(reminderSet){
            toast(tr('নোট ও রিমাইন্ডার সেভ হয়েছে','Note and reminder saved'));
          }else{
             toast(tr('নোট সেভ হয়েছে, তবে রিমাইন্ডার সেট করা যায়নি', 'Note saved, but reminder could not be set',));
          }
          }
        },child:Text(tr('সেভ করুন','Save')))),
      ])),
    )));
    title.dispose();amount.dispose();
  }
  Future<void> setBudgetDialog() async {
    final c=TextEditingController(text:widget.budget>0?widget.budget.toStringAsFixed(0):'');
    await showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:Text(tr('মাসিক বাজেট','Monthly Budget')),
      content:TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'৳',border:OutlineInputBorder())),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tr('বাতিল','Cancel'))),
        FilledButton(onPressed:(){final v=double.tryParse(c.text.trim())??0;if(v<0){toast(tr('সঠিক বাজেট লিখুন','Enter a valid budget'));return;}widget.onBudget(v);Navigator.pop(ctx);toast(tr('বাজেট আপডেট হয়েছে','Budget updated'));},child:Text(tr('সেভ','Save'))),
      ],
    ));
    c.dispose();
  }

  Future<void> deleteRow(String table,int id) async {
    try {
      final deleted = await (await DB.instance).delete(
        table,
        where:'id=?',
        whereArgs:[id],
      );
      await loadRecords();
      toast(deleted > 0
          ? tr('মুছে ফেলা হয়েছে','Deleted')
          : tr('আইটেমটি পাওয়া যায়নি','Item not found'));
    } catch (e) {
      debugPrint('Delete error: $e');
      toast(tr('ডিলেট করা যায়নি','Could not delete item'));
    }
  }

  Future<void> confirmDelete(
      String title, Future<void> Function() action) async {
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(tr('মুছে ফেলবেন?','Delete this item?')),content:Text(title),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(tr('বাতিল','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(tr('মুছুন','Delete')))],
    ));
    if(yes==true) await action();
  }

  Widget expenseTile(Map<String,dynamic> e){
    final c=catOf(e['category'] as String);
    final ts=(e['ts'] as int?) ?? 0;
    final time=ts>0?DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts)):'';
    return Card(elevation:0,margin:const EdgeInsets.only(bottom:8),child:ListTile(
      leading:CircleAvatar(backgroundColor:c.color.withOpacity(.15),child:Icon(c.icon,color:c.color)),
      title:Text(e['item'] as String,style:const TextStyle(fontWeight:FontWeight.w600)),
      subtitle:Text('${bn?c.bn:c.en} • ${e['date']} $time'),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        Text('৳${(e['amount'] as num).toStringAsFixed(0)}',style:const TextStyle(fontWeight:FontWeight.bold)),
        IconButton(icon:const Icon(Icons.delete_outline,color:Colors.redAccent),onPressed:()=>confirmDelete(e['item'] as String,()=>deleteRow('expenses',e['id'] as int))),
      ]),
    ));
  }

  Widget summaryBox(String label,String value)=>Expanded(child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.black.withOpacity(.13),borderRadius:BorderRadius.circular(12)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:Colors.white70,fontSize:11)),const SizedBox(height:4),Text(value,style:const TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.bold))])));

  Widget expensePage(){
    final now=DateTime.now(), today=DateFormat('yyyy-MM-dd').format(now), prefix=today.substring(0,7);
    double total=0,todayTotal=0;
    final sums=<String,double>{for(final c in cats)c.id:0};
    for(final e in expenses){final d=e['date'] as String;if(d.startsWith(prefix)){final a=(e['amount'] as num).toDouble();total+=a;if(d==today)todayTotal+=a;final k=e['category'] as String;sums[k]=(sums[k]??0)+a;}}
    final average=total/now.day, q=search.trim().toLowerCase();
    final filtered=expenses.where((e){final c=catOf(e['category'] as String);final ok=filter=='all'||filter==e['category'];final text=(e['item'] as String).toLowerCase();return ok&&(q.isEmpty||text.contains(q)||c.bn.toLowerCase().contains(q)||c.en.toLowerCase().contains(q));}).toList();
    final ranked=cats.toList()..sort((a,b)=>(sums[b.id]??0).compareTo(sums[a.id]??0));
    final progress=widget.budget>0?(total/widget.budget).clamp(0.0,1.0):0.0;
    return ListView(padding:const EdgeInsets.fromLTRB(14,14,14,100),children:[
      Container(padding:const EdgeInsets.all(19),decoration:BoxDecoration(borderRadius:BorderRadius.circular(23),gradient:const LinearGradient(colors:[Color(0xFF0F766E),Color(0xFF0D9488),Color(0xFF0284C7)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(tr('চলতি মাসের মোট খরচ','This Month Total'),style:const TextStyle(color:Colors.white70)),Text(monthTitle(),style:const TextStyle(color:Colors.white))]),
        const SizedBox(height:7),Text('৳ ${total.toStringAsFixed(0)}',style:const TextStyle(color:Colors.white,fontSize:34,fontWeight:FontWeight.bold)),
        const SizedBox(height:13),
        InkWell(onTap:setBudgetDialog,child:Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.white.withOpacity(.15),borderRadius:BorderRadius.circular(12)),child:Column(children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(widget.budget>0?'${tr('বাজেট','Budget')}: ৳${widget.budget.toStringAsFixed(0)}':tr('বাজেট সেট করতে ট্যাপ করুন','Tap to set budget'),style:const TextStyle(color:Colors.white)),if(widget.budget>0)Text('${(total/widget.budget*100).round()}%',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold))]),
          if(widget.budget>0)...[const SizedBox(height:7),ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(value:progress,minHeight:7,backgroundColor:Colors.white24,valueColor:const AlwaysStoppedAnimation(Colors.white))),if(total>widget.budget)Padding(padding:const EdgeInsets.only(top:6),child:Text(tr('সতর্কতা: বাজেট অতিক্রম হয়েছে','Warning: Budget exceeded'),style:const TextStyle(color:Colors.white,fontWeight:FontWeight.bold)))],
        ]))),
        const SizedBox(height:12),Row(children:[summaryBox(tr('আজকের খরচ','Today'),'৳${todayTotal.toStringAsFixed(0)}'),const SizedBox(width:9),summaryBox(tr('দৈনিক গড়','Daily Average'),'৳${average.toStringAsFixed(0)}')]),
      ])),
      if(total>0)Card(elevation:0,margin:const EdgeInsets.only(top:14),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(tr('ক্যাটাগরি অনুযায়ী খরচ','Spending by Category'),style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:12),Row(children:[
          SizedBox(width:88,height:88,child:CustomPaint(painter:DonutPainter(sums,total),child:Center(child:Text('৳${total.toStringAsFixed(0)}',style:const TextStyle(fontSize:10,fontWeight:FontWeight.bold))))),
          const SizedBox(width:14),Expanded(child:Column(children:cats.map((c){final v=sums[c.id]??0,pct=v/total;return Padding(padding:const EdgeInsets.only(bottom:7),child:Column(children:[Row(children:[Icon(c.icon,color:c.color,size:15),const SizedBox(width:5),Expanded(child:Text(bn?c.bn:c.en,style:const TextStyle(fontSize:11))),Text('${(pct*100).round()}%',style:const TextStyle(fontSize:11,fontWeight:FontWeight.bold))]),const SizedBox(height:3),LinearProgressIndicator(value:pct,minHeight:5,color:c.color,backgroundColor:c.color.withOpacity(.12))]));}).toList())),
        ]),
        Text('${tr('সর্বোচ্চ খরচ','Top category')}: ${bn?ranked.first.bn:ranked.first.en}',style:TextStyle(fontSize:12,color:Theme.of(context).hintColor)),
      ]))),
      const SizedBox(height:13),
      TextField(controller:searchCtrl,onChanged:(v)=>setState(()=>search=v),decoration:InputDecoration(hintText:tr('খরচ খুঁজুন...','Search expenses...'),prefixIcon:const Icon(Icons.search),filled:true,border:OutlineInputBorder(borderRadius:BorderRadius.circular(13),borderSide:BorderSide.none))),
      const SizedBox(height:9),
      SizedBox(height:42,child:ListView(scrollDirection:Axis.horizontal,children:[
        Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(label:Text(tr('সব','All')),selected:filter=='all',onSelected:(_)=>setState(()=>filter='all'))),
        ...cats.map((c)=>Padding(padding:const EdgeInsets.only(right:6),child:ChoiceChip(avatar:Icon(c.icon,color:c.color,size:16),label:Text(bn?c.bn:c.en),selected:filter==c.id,onSelected:(_)=>setState(()=>filter=c.id)))),
      ])),
      const SizedBox(height:8),
      if(filtered.isEmpty)Padding(padding:const EdgeInsets.all(30),child:Center(child:Text(tr('কোনো খরচ পাওয়া যায়নি','No expenses found')))) else ...filtered.map(expenseTile),
    ]);
  }

  Widget calendarPage(){
    final prefix='$year-${month.toString().padLeft(2,'0')}';
    final first=DateTime(year,month,1), offset=first.weekday%7, days=DateTime(year,month+1,0).day;
    final totals=<String,double>{};
    for(final e in expenses){final d=e['date'] as String;if(d.startsWith(prefix))totals[d]=(totals[d]??0)+(e['amount'] as num).toDouble();}
    final selected=expenses.where((e)=>e['date']==selectedDate).toList();
    final weekdays=bn?['রবি','সোম','মঙ্গল','বুধ','বৃহঃ','শুক্র','শনি']:['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
    return ListView(padding:const EdgeInsets.fromLTRB(14,14,14,100),children:[
      Card(elevation:0,child:Padding(padding:const EdgeInsets.all(13),child:Column(children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          IconButton(onPressed:()=>setState((){month--;if(month<1){month=12;year--;}selectedDate='$year-${month.toString().padLeft(2,'0')}-01';}),icon:const Icon(Icons.chevron_left)),
          Text(monthTitle(),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
          IconButton(onPressed:()=>setState((){month++;if(month>12){month=1;year++;}selectedDate='$year-${month.toString().padLeft(2,'0')}-01';}),icon:const Icon(Icons.chevron_right)),
        ]),
        Row(children:weekdays.map((d)=>Expanded(child:Center(child:Text(d,style:const TextStyle(fontSize:10,fontWeight:FontWeight.bold))))).toList()),
        const SizedBox(height:8),
        GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:offset+days,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,mainAxisSpacing:5,crossAxisSpacing:5,childAspectRatio:.9),itemBuilder:(ctx,i){
          if(i<offset)return const SizedBox.shrink();
          final day=i-offset+1,d='$prefix-${day.toString().padLeft(2,'0')}',amount=totals[d]??0,selectedDay=d==selectedDate;
          return InkWell(borderRadius:BorderRadius.circular(9),onTap:()=>setState(()=>selectedDate=d),child:Container(decoration:BoxDecoration(color:selectedDay?Theme.of(context).colorScheme.primary:amount>0?Theme.of(context).colorScheme.primary.withOpacity(.13):null,borderRadius:BorderRadius.circular(9)),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Text('$day',style:TextStyle(fontWeight:FontWeight.bold,color:selectedDay?Colors.white:null)),if(amount>0)Container(width:5,height:5,decoration:BoxDecoration(shape:BoxShape.circle,color:selectedDay?Colors.white:Theme.of(context).colorScheme.primary))])));
        }),
      ]))),
      const SizedBox(height:12),Text(selectedDate,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:15)),const SizedBox(height:8),
      if(selected.isEmpty)Center(child:Padding(padding:const EdgeInsets.all(25),child:Text(tr('এই দিনে কোনো খরচ নেই','No expenses on this date'))))else ...selected.map(expenseTile),
    ]);
  }

  Widget notesPage(){
    if(notes.isEmpty)return Center(child:Text(tr('এখনো কোনো নোট নেই','No notes yet')));
    return ListView(padding:const EdgeInsets.fromLTRB(14,14,14,100),children:notes.map((n){
      final a=(n['amount'] as num).toDouble();
      return Card(elevation:0,margin:const EdgeInsets.only(bottom:8),child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.note_alt_rounded)),
        title:Text(n['title'] as String,style:const TextStyle(fontWeight:FontWeight.w600)),
        subtitle:Text([if(a>0)'৳${a.toStringAsFixed(0)}' else tr('সাধারণ নোট','General note'),if(n['reminderAt']!=null)'🔔 ${DateFormat('dd/MM/yy hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(n['reminderAt'] as int))}'].join(' • ')),
        trailing:IconButton(icon:const Icon(Icons.delete_outline,color:Colors.redAccent),onPressed:()=>confirmDelete(n['title'] as String,()async{
          final noteId = n['id'] as int;
          // Delete the database row first; notification cancellation must not block deletion.
          await deleteRow('notes', noteId);
          try { await notifications.cancel(noteId); } catch (e) { debugPrint('Cancel reminder error: $e'); }
        })) ,
      ));
    }).toList());
  }

  Future<void> settings() async {
    await showModalBottomSheet(context:context,showDragHandle:true,builder:(sheet)=>SafeArea(child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.person_outline),title:Text(tr('নাম পরিবর্তন','Change name')),subtitle:Text(widget.name),onTap:()async{
        Navigator.pop(sheet);final c=TextEditingController(text:widget.name);
        final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(tr('আপনার নাম','Your name')),content:TextField(controller:c),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(tr('বাতিল','Cancel'))),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:Text(tr('সেভ','Save')))]));
        c.dispose();if(value!=null)widget.onName(value);
      }),
      SwitchListTile(secondary:const Icon(Icons.dark_mode_outlined),title:Text(tr('ডার্ক মোড','Dark Mode')),value:widget.dark,onChanged:widget.onDark),
      ListTile(leading:const Icon(Icons.language),title:Text(tr('ভাষা','Language')),trailing:DropdownButton<String>(value:widget.lang,underline:const SizedBox.shrink(),items:const[DropdownMenuItem(value:'bn',child:Text('বাংলা')),DropdownMenuItem(value:'en',child:Text('English'))],onChanged:(v){if(v!=null)widget.onLang(v);})),
      ListTile(leading:const Icon(Icons.account_balance_wallet_outlined),title:Text(tr('মাসিক বাজেট','Monthly budget')),subtitle:Text('৳${widget.budget.toStringAsFixed(0)}'),onTap:(){Navigator.pop(sheet);setBudgetDialog();}),
      const SizedBox(height:8),Text('Smart Hishab • Version 1.0.0',style:TextStyle(color:Theme.of(context).hintColor)),
    ]))));
  }

  @override
  Widget build(BuildContext context){
    final titles=[tr('স্মার্ট হিসাব','Smart Hishab'),tr('ক্যালেন্ডার','Calendar'),tr('নোট','Notes')];
    return Scaffold(
      appBar:AppBar(title:Row(children:[
        Container(width:37,height:37,decoration:BoxDecoration(borderRadius:BorderRadius.circular(11),gradient:const LinearGradient(colors:[Color(0xFF0F766E),Color(0xFF0284C7)])),child:const Center(child:Text('৳',style:TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.bold)))),
        const SizedBox(width:9),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.name.isEmpty?titles[tab]:'${tr('হ্যালো','Hello')}, ${widget.name}',style:const TextStyle(fontSize:16,fontWeight:FontWeight.bold)),
          Text(tr('আপনার দৈনিক হিসাব','Your daily finance tracker'),style:TextStyle(fontSize:11,color:Theme.of(context).hintColor)),
        ])),
      ]),actions:[IconButton(onPressed:settings,icon:const Icon(Icons.settings_rounded))]),
      body:IndexedStack(index:tab,children:[expensePage(),calendarPage(),notesPage()]),
      floatingActionButton:FloatingActionButton.extended(onPressed:tab==2?addNote:addExpense,icon:const Icon(Icons.add),label:Text(tab==2?tr('নোট যোগ করুন','Add Note'):tr('খরচ যোগ করুন','Add Expense'))),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:[
        NavigationDestination(icon:const Icon(Icons.account_balance_wallet_rounded),label:tr('খরচ','Expenses')),
        NavigationDestination(icon:const Icon(Icons.calendar_month_rounded),label:tr('ক্যালেন্ডার','Calendar')),
        NavigationDestination(icon:const Icon(Icons.note_alt_rounded),label:tr('নোট','Notes')),
      ]),
    );
  }
}


  
