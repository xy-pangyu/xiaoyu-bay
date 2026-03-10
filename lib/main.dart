import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const XiaoyuBayApp());
}

class XiaoyuBayApp extends StatelessWidget {
  const XiaoyuBayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小鱼霸业',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.orange,
        fontFamily: GoogleFonts.poppins().fontFamily,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.orange,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.orange, width: 2),
          ),
        ),
      ),
      home: const LoginPage(),
    );
  }
}

// ---------- 城池模型 ----------
class City {
  final String name;
  final String type;
  final String level;      // '低级', '中级', '高级'
  final int baseRequired;
  final int dailyGold;
  final int dailyCap;
  final List<String> neighbors;
  String? owner;
  bool isUpgraded;

  City({
    required this.name,
    required this.type,
    required this.level,
    required this.baseRequired,
    required this.dailyGold,
    required this.dailyCap,
    required this.neighbors,
    this.owner,
    this.isUpgraded = false,
  });

  int get requiredSoldiers {
    if (level == '低级' && isUpgraded) return 100000;
    if (level == '中级') return 100000;
    if (level == '高级') return 300000;
    return baseRequired;
  }

  int get actualDailyGold {
    if (level == '低级' && isUpgraded) return 200000;
    if (level == '中级') return 200000;
    if (level == '高级') return 500000;
    return dailyGold;
  }

  int get actualDailyCap {
    if (level == '低级' && isUpgraded) return 5000;
    if (level == '中级') return 5000;
    if (level == '高级') return 10000;
    return dailyCap;
  }

  bool get isOwned => owner != null;
  bool get isUpgradable => level == '低级' && !isUpgraded && owner != null && type != '飞地';

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'level': level,
        'baseRequired': baseRequired,
        'dailyGold': dailyGold,
        'dailyCap': dailyCap,
        'neighbors': neighbors,
        'owner': owner,
        'isUpgraded': isUpgraded,
      };

  factory City.fromJson(Map<String, dynamic> json) => City(
        name: json['name'],
        type: json['type'],
        level: json['level'],
        baseRequired: json['baseRequired'],
        dailyGold: json['dailyGold'],
        dailyCap: json['dailyCap'],
        neighbors: List<String>.from(json['neighbors']),
        owner: json['owner'],
        isUpgraded: json['isUpgraded'] ?? false,
      );
}

// ---------- 宣战记录 ----------
class BattleRecord {
  final String cityName;
  final DateTime startTime;
  Map<String, int> attackers; // 玩家ID -> 兵力
  String? defender;           // 原主人
  int defenderExtra;          // 防守方额外投入
  String? leadingAttacker;    // 当前进攻方（抢宣阶段结束后确定）
  BattlePhase phase;
  bool resolved;

  BattleRecord({
    required this.cityName,
    required this.startTime,
    required this.attackers,
    this.defender,
    this.defenderExtra = 0,
    this.leadingAttacker,
    this.phase = BattlePhase.declare,
    this.resolved = false,
  });

  int get totalAttackers => attackers.values.fold(0, (a, b) => a + b);
  int totalDefense(City city) => city.requiredSoldiers + defenderExtra;

  String? get topAttacker {
    if (attackers.isEmpty) return null;
    return attackers.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }

  Map<String, dynamic> toJson() => {
        'cityName': cityName,
        'startTime': startTime.toIso8601String(),
        'attackers': attackers,
        'defender': defender,
        'defenderExtra': defenderExtra,
        'leadingAttacker': leadingAttacker,
        'phase': phase.index,
        'resolved': resolved,
      };

  factory BattleRecord.fromJson(Map<String, dynamic> json) => BattleRecord(
        cityName: json['cityName'],
        startTime: DateTime.parse(json['startTime']),
        attackers: Map<String, int>.from(json['attackers']),
        defender: json['defender'],
        defenderExtra: json['defenderExtra'],
        leadingAttacker: json['leadingAttacker'],
        phase: BattlePhase.values[json['phase']],
        resolved: json['resolved'],
      );
}

enum BattlePhase { declare, compete, attack, finished }

// ---------- 玩家待办类型 ----------
enum TodoType { defend, attackRespond, upgradeAvailable, battleOvertaken }

class TodoItem {
  final String? cityName;
  final TodoType type;
  final String? opponent;
  bool isDone;

  TodoItem({this.cityName, required this.type, this.opponent, this.isDone = false});
}

// ---------- 全局资源条组件（美化）----------
class ResourceBar extends StatelessWidget {
  final int gold;
  final int soldiers;
  const ResourceBar({super.key, required this.gold, required this.soldiers});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange[50],
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildResourceItem(Icons.monetization_on, '黄金', _formatNumber(gold), Colors.amber),
          _buildResourceItem(Icons.shield, '士兵', soldiers.toString(), Colors.red),
        ],
      ),
    );
  }

  String _formatNumber(int num) {
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toString();
  }

  Widget _buildResourceItem(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 登录/注册页（美化）----------
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLogin = true;
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _pwdController = TextEditingController();
  final TextEditingController _confirmPwdController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.orange[100]!, Colors.white],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.orange.withValues(alpha: 0.4),
                          spreadRadius: 5,
                          blurRadius: 20,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: Image.asset(
                        'assets/images/xybylogo.jpg',
                        width: 130,
                        height: 130,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    '小鱼霸业',
                    style: GoogleFonts.poppins(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isLogin ? '私人应用' : '创建新账号',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 40),

                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextField(
                            controller: _userController,
                            decoration: InputDecoration(
                              labelText: '用户名',
                              prefixIcon: const Icon(Icons.person, color: Colors.orange),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _pwdController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: '密码',
                              prefixIcon: const Icon(Icons.lock, color: Colors.orange),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (!_isLogin)
                            TextField(
                              controller: _confirmPwdController,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: '确认密码',
                                prefixIcon: const Icon(Icons.lock_outline, color: Colors.orange),
                              ),
                            ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _handleLogin,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                _isLogin ? '登录' : '注册',
                                style: const TextStyle(fontSize: 18),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isLogin = !_isLogin;
                        _userController.clear();
                        _pwdController.clear();
                        _confirmPwdController.clear();
                      });
                    },
                    child: Text(
                      _isLogin ? '还没有账号？立即注册' : '已有账号？去登录',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _handleLogin() async {
    String username = _userController.text.trim();
    String password = _pwdController.text.trim();

    if (username.isEmpty) {
      _showSnackBar('请输入用户名');
      return;
    }
    if (password.isEmpty) {
      _showSnackBar('请输入密码');
      return;
    }
    if (!_isLogin && _pwdController.text != _confirmPwdController.text) {
      _showSnackBar('两次密码不一致');
      return;
    }

    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      String uid = userCredential.user!.uid;

      bool isAdmin = (username == '992767100' && password == '20030516');

      await FirebaseFirestore.instance.collection('players').doc(uid).set({
        'username': username,
        'isAdmin': isAdmin,
        'gold': 1000000,
        'soldiers': 0,
        'rankIndex': 0,
        'remainingUpgrades': 2,
        'lastClaimDate': null,
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => GameHomePage(
            uid: uid,
            username: username,
            isAdmin: isAdmin,
          ),
        ),
      );
    } catch (e) {
      print('登录错误: $e');
      _showSnackBar('登录失败: ${e.toString()}');
    }
  }
}

// ---------- 游戏主界面 ----------
class GameHomePage extends StatefulWidget {
  final String uid;
  final String username;
  final bool isAdmin;
  const GameHomePage({
    super.key,
    required this.uid,
    required this.username,
    required this.isAdmin,
  });

  @override
  State<GameHomePage> createState() => _GameHomePageState();
}

class _GameHomePageState extends State<GameHomePage> {
  int _selectedIndex = 0;

  // 玩家数据
  int _gold = 0;
  int _soldiers = 0;
  int _rankIndex = 0;
  DateTime? _lastClaimDate;
  int _remainingUpgrades = 2;

  // 所有城池
  List<City> _allCities = [];

  // 宣战记录
  Map<String, BattleRecord> _battleRecords = {};

  // 每小时宣战次数
  Map<String, int> _newAttacksThisHour = {};
  int _currentHour = -1;

  // 待办列表
  List<TodoItem> _todos = [];

  // 活动奖励
  int _activityGoldReward = 10000;
  int _activitySoldiersReward = 10;

  // 爵位列表
  final List<String> _ranks = [
    '平民', '什长', '百夫长', '千夫长', '九品提督', '八品将军',
    '七品统领', '六品将军', '五品官员', '四品大将', '三品大将',
    '二品大将', '一品大将', '六等王', '五等王', '四等王', '三等王',
    '二等王', '一等王'
  ];

  // 时钟
  String _currentTime = '';
  int _currentMinute = 0;

  // 定时器
  Timer? _phaseTimer;
  Timer? _clockTimer;

  // UID -> 用户名映射
  Map<String, String> _playerNames = {};

  // 战争时间检查：18-24点
  bool get isWarTime {
    final hour = DateTime.now().hour;
    return hour >= 18 && hour < 24;
  }

  // 当前阶段
  GamePhase get currentPhase {
    if (_currentMinute < 10) return GamePhase.declare;
    if (_currentMinute < 20) return GamePhase.compete;
    if (_currentMinute < 40) return GamePhase.attack;
    return GamePhase.finished;
  }

  List<City> get _ownedCities => _allCities.where((c) => c.owner == widget.uid).toList();

  int get totalDailyGold => _ownedCities.fold(0, (total, city) => total + city.actualDailyGold);
  int get totalDailyCap => _ownedCities.fold(0, (total, city) => total + city.actualDailyCap);
  String get currentRank => _ranks[_rankIndex];

  @override
  void initState() {
    super.initState();
    _loadGameData();
    _startClock();
    _startPhaseTimer();
    _updateHour();
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGameData() async {
    FirebaseFirestore.instance
        .collection('players')
        .doc(widget.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _gold = snapshot.data()?['gold'] ?? 1000000;
          _soldiers = snapshot.data()?['soldiers'] ?? 0;
          _rankIndex = snapshot.data()?['rankIndex'] ?? 0;
          _remainingUpgrades = snapshot.data()?['remainingUpgrades'] ?? 2;
          _lastClaimDate = (snapshot.data()?['lastClaimDate'] as Timestamp?)?.toDate();
        });
      }
    });

    FirebaseFirestore.instance.collection('players').snapshots().listen((snapshot) {
      final Map<String, String> names = {};
      for (var doc in snapshot.docs) {
        names[doc.id] = doc.data()['username'] ?? '未知';
      }
      setState(() {
        _playerNames = names;
      });
    });

    FirebaseFirestore.instance.collection('cities').snapshots().listen((snapshot) {
      List<City> cities = [];
      for (var doc in snapshot.docs) {
        cities.add(City.fromJson(doc.data()));
      }
      setState(() {
        _allCities = cities;
      });
    });

    FirebaseFirestore.instance.collection('battles').snapshots().listen((snapshot) {
      Map<String, BattleRecord> records = {};
      for (var doc in snapshot.docs) {
        records[doc.id] = BattleRecord.fromJson(doc.data());
      }
      setState(() {
        _battleRecords = records;
      });
    });

    FirebaseFirestore.instance
        .collection('config')
        .doc('activity')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _activityGoldReward = snapshot.data()?['gold'] ?? 10000;
          _activitySoldiersReward = snapshot.data()?['soldiers'] ?? 10;
        });
      }
    });

    await _initCitiesIfNeeded();
    await _initConfigIfNeeded();
  }

  Future<void> _initCitiesIfNeeded() async {
    final snapshot = await FirebaseFirestore.instance.collection('cities').limit(1).get();
    if (snapshot.docs.isNotEmpty) return;

    Map<String, List<String>> neighborMap = {
      '基尔村': ['波城'],
      '波城': ['阳城'],
      '阳城': ['明城'],
      '明城': ['吊口城'],
      '吊口城': ['东方城'],
      '东方城': ['2号飞地'],
      '2号飞地': ['猫土9', '萧州烟阳'],
      '一号飞地': ['靖州'],
      '靖州': ['泉城', '辽州天雪'],
      '泉城': ['红城'],
      '红城': ['加州'],
      '加州': ['3号飞地'],
      '辽州天雪': ['萨城'],
      '猫土9': ['萨城', '云落关', '2号飞地'],
      '萧州烟阳': ['猫土16'],
      '云落关': ['猫土9', '五号飞地'],
      '狭小城': ['猫土16', '浮云城'],
      '浮云城': ['大华城', '青云城'],
      '青云城': ['10号飞地', '渊州君泽'],
      '大华城': ['小风城'],
      '渊州君泽': ['下午城', '云梦泽'],
      '下午城': ['中午城'],
      '中午城': ['下午城', '上上城', '上午城'],
      '上上城': ['左劈城'],
      '左劈城': ['冀霸城'],
      '冀霸城': ['左劈城', '上午城', '澜州云梦'],
      '澜州云梦': ['滇州苍郎'],
      '滇州苍郎': ['澜州云梦', '7号飞地'],
      '云梦泽': ['丹尔斯村'],
      '丹尔斯村': ['11号飞地', '寒山', '潘代尔村'],
      '寒山': ['卡西丘村', '明城澜州', '太南院'],
      '卡西丘村': ['卡普里村'],
      '卡普里村': ['霍姆村'],
      '潘代尔村': ['纳克斯城', '特拉福德城'],
      '4号飞地': ['赤兀部'],
      '赤兀部': ['乌珠部'],
      '乌珠部': ['那赫部'],
      '那赫部': ['燕州燕然部'],
      '燕州燕然部': ['折兰部'],
      '折兰部': ['兰颜部'],
      '兰颜部': ['北凉关'],
      '北凉关': ['8号飞地', '甘州'],
      '9号飞地': ['凉州朝月'],
      '甘州': ['9号飞地'],
      '五号飞地': ['安州天启'],
      '安州天启': ['猫土15', '猫土2', '5号飞地', '乐土'],
      '猫土15': ['猫土17'],
      '猫土17': ['猫土18'],
      '猫土18': ['昭阳关'],
      '7号飞地': ['拒马', '猫土13', '范阳'],
      '拒马': ['猫土5'],
      '猫土5': ['猫土2'],
      '猫土2': ['空1'],
      '猫土13': ['猫土14'],
      '猫土14': ['靖门关'],
      '里伯斯城': ['基比堡'],
      '基比堡': ['比伦尼城'],
      '比伦尼城': ['飞花谷', '姆哈拉堡'],
      '姆哈拉堡': ['达卡堡'],
      '范阳': ['永玄'],
      '永玄': ['志恒'],
      '志恒': ['靖州安阳', '墨尔堡'],
      '6号飞地': ['靖门关', '基帕堡', '志恒'],
      '靖州安阳': ['志恒', '飞花谷'],
    };

    Set<String> allCityNames = {...neighborMap.keys};
    for (var ns in neighborMap.values) {
      allCityNames.addAll(ns);
    }
    for (var name in allCityNames) {
      neighborMap.putIfAbsent(name, () => []);
    }

    final Set<String> highLevelCities = {
      '辽州天雪', '云落关', '萧州烟阳', '滇州苍郎', '安州天启',
      '澜州云梦', '渊州君泽', '太南院', '北凉关', '靖州安阳', '燕州燕然部'
    };

    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (var name in allCityNames) {
      String type = '低级城';
      String level = '低级';
      int baseRequired = 20000;
      int dailyGold = 100000;
      int dailyCap = 1000;

      if (name.contains('飞地')) {
        type = '飞地';
        level = '低级';
        baseRequired = 20000;
        dailyGold = 100000;
        dailyCap = 1000;
      } else if (highLevelCities.contains(name)) {
        type = '高级城';
        level = '高级';
        baseRequired = 300000;
        dailyGold = 500000;
        dailyCap = 10000;
      } else if (name.contains('关') || name.contains('村') || name.contains('堡')) {
        type = name.contains('关') ? '关隘' : (name.contains('村') ? '村庄' : '城堡');
        level = '低级';
      } else if (name.contains('部') || name.contains('州') || name.contains('泽') || name.contains('海')) {
        type = '区域';
        level = '低级';
      } else {
        type = '低级城';
        level = '低级';
      }

      City city = City(
        name: name,
        type: type,
        level: level,
        baseRequired: baseRequired,
        dailyGold: dailyGold,
        dailyCap: dailyCap,
        neighbors: neighborMap[name] ?? [],
        owner: null,
      );
      batch.set(FirebaseFirestore.instance.collection('cities').doc(name), city.toJson());
    }
    await batch.commit();
  }

  Future<void> _initConfigIfNeeded() async {
    final doc = await FirebaseFirestore.instance.collection('config').doc('activity').get();
    if (!doc.exists) {
      await FirebaseFirestore.instance.collection('config').doc('activity').set({
        'gold': 10000,
        'soldiers': 10,
      });
    }
  }

  void _updateHour() {
    final now = DateTime.now();
    _currentHour = now.hour;
    _newAttacksThisHour.clear();
  }

  void _startClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final now = DateTime.now();
      if (now.hour != _currentHour) {
        _updateHour();
      }
      setState(() {
        _currentTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
        _currentMinute = now.minute;
      });
    });
  }

  void _startPhaseTimer() {
    _phaseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final now = DateTime.now();
      final minute = now.minute;
      final second = now.second;

      if (second == 0) {
        if (minute == 20) {
          _onCompetePhaseEnd();
        } else if (minute == 40) {
          _onAttackPhaseEnd();
        }
      }
    });
  }

  void _onCompetePhaseEnd() {
    for (var record in _battleRecords.values) {
      if (record.resolved) continue;
      final city = _allCities.firstWhere((c) => c.name == record.cityName);
      if (record.phase == BattlePhase.compete) {
        if (city.owner != null) {
          if (record.attackers.isNotEmpty) {
            final leader = record.topAttacker!;
            record.leadingAttacker = leader;
            record.phase = BattlePhase.attack;
            for (var entry in record.attackers.entries) {
              if (entry.key != leader) {
                _refundSoldiers(entry.key, entry.value);
              }
            }
            record.attackers = {leader: record.attackers[leader]!};
            if (record.defender != null) {
              _todos.add(TodoItem(
                cityName: record.cityName,
                type: TodoType.defend,
                opponent: leader,
              ));
            }
          } else {
            record.resolved = true;
          }
        } else {
          _resolveNeutralCity(record, city);
          record.resolved = true;
        }
      }
    }
    _saveAllToFirestore();
  }

  void _onAttackPhaseEnd() {
    for (var record in _battleRecords.values) {
      if (record.resolved) continue;
      final city = _allCities.firstWhere((c) => c.name == record.cityName);
      if (record.phase == BattlePhase.attack) {
        _resolveBattle(record, city);
        record.resolved = true;
      }
    }
    _battleRecords.clear();
    _todos.clear();
    _saveAllToFirestore();
  }

  void _resolveNeutralCity(BattleRecord record, City city) {
    int total = record.totalAttackers;
    if (total >= city.requiredSoldiers) {
      String winner = record.topAttacker!;
      city.owner = winner;
      int winnerAmount = record.attackers[winner]!;
      if (winnerAmount >= city.requiredSoldiers) {
        int remaining = winnerAmount - city.requiredSoldiers;
        _refundSoldiers(winner, remaining);
      }
      for (var entry in record.attackers.entries) {
        if (entry.key != winner) {
          _refundSoldiers(entry.key, entry.value);
        }
      }
      if (winner == widget.uid) {
        _gold += 50;
      }
    } else {
      if (record.attackers.containsKey(widget.uid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('💥 进攻 ${city.name} 失败，兵力损失'), backgroundColor: Colors.orange),
        );
      }
    }
    _saveAllToFirestore();
  }

  void _refundSoldiers(String playerId, int amount) {
    FirebaseFirestore.instance.collection('players').doc(playerId).update({
      'soldiers': FieldValue.increment(amount),
    });
  }

  Future<void> _saveAllToFirestore() async {
    await FirebaseFirestore.instance.collection('players').doc(widget.uid).update({
      'gold': _gold,
      'soldiers': _soldiers,
      'rankIndex': _rankIndex,
      'remainingUpgrades': _remainingUpgrades,
    });

    for (var city in _allCities) {
      await FirebaseFirestore.instance.collection('cities').doc(city.name).set(city.toJson());
    }

    for (var record in _battleRecords.values) {
      await FirebaseFirestore.instance
          .collection('battles')
          .doc(record.cityName)
          .set(record.toJson());
    }
  }

  List<City> _getAttackableCities() {
    final ownedNames = _ownedCities.map((c) => c.name).toSet();
    if (ownedNames.isEmpty) {
      return _allCities.where((c) => c.type == '飞地' && (c.owner == null || c.owner == widget.uid)).toList();
    }
    final attackable = <City>[];
    for (var city in _allCities.where((c) => c.owner == null || c.owner != widget.uid)) {
      if (city.owner == widget.uid) continue;
      for (var neighbor in city.neighbors) {
        if (ownedNames.contains(neighbor)) {
          attackable.add(city);
          break;
        }
      }
    }
    return attackable;
  }

  Future<void> _declareWar(City city) async {
    if (!isWarTime) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前不是战争时间（18:00-24:00）'), backgroundColor: Colors.red),
      );
      return;
    }
    if (currentPhase != GamePhase.declare) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前不是宣战阶段（0-10分钟）'), backgroundColor: Colors.red),
      );
      return;
    }

    final record = _battleRecords[city.name];
    if (record != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该城池已被宣战，请等待抢宣阶段'), backgroundColor: Colors.red),
      );
      return;
    }

    int myAttacks = _newAttacksThisHour[widget.uid] ?? 0;
    if (myAttacks >= 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本小时宣战次数已达上限（2次）'), backgroundColor: Colors.red),
      );
      return;
    }

    final TextEditingController inputController = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('宣战 ${city.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('基础需求: ${city.requiredSoldiers}'),
            TextField(
              controller: inputController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '投入兵力',
                hintText: '输入数量',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              int? value = int.tryParse(inputController.text);
              if (value != null && value > 0) {
                Navigator.pop(ctx, value);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入有效数字')),
                );
              }
            },
            child: const Text('宣战'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (_soldiers < result) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('士兵不足，你只有 $_soldiers 名士兵'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() {
      _soldiers -= result;
      _battleRecords[city.name] = BattleRecord(
        cityName: city.name,
        startTime: DateTime.now(),
        attackers: {widget.uid: result},
        defender: city.owner,
        phase: BattlePhase.declare,
      );
      _newAttacksThisHour[widget.uid] = myAttacks + 1;
    });
    _saveAllToFirestore();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ 宣战成功！投入 $result 兵力'), backgroundColor: Colors.green),
    );
  }  Future<void> _addTroops(BuildContext context, BattleRecord record, bool isAttacker) async {
    if (!isWarTime) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前不是战争时间（18:00-24:00）'), backgroundColor: Colors.red),
      );
      return;
    }
    final phase = currentPhase;
    if (phase == GamePhase.finished) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前阶段不能操作'), backgroundColor: Colors.red),
      );
      return;
    }

    if (phase == GamePhase.compete) {
      if (!record.attackers.containsKey(widget.uid)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('你没有宣战此城池'), backgroundColor: Colors.red),
        );
        return;
      }
    } else if (phase == GamePhase.attack) {
      if (isAttacker && record.leadingAttacker != widget.uid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('你不是进攻方'), backgroundColor: Colors.red),
        );
        return;
      }
      if (!isAttacker && record.defender != widget.uid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('你不是防守方'), backgroundColor: Colors.red),
        );
        return;
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前阶段不能追加兵力'), backgroundColor: Colors.red),
      );
      return;
    }

    if (record.resolved) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该战斗已结算'), backgroundColor: Colors.red),
      );
      return;
    }

    final city = _allCities.firstWhere((c) => c.name == record.cityName);
    final TextEditingController inputController = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isAttacker ? '追加进攻兵力' : '追加防守兵力'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前总兵力: ${isAttacker ? record.totalAttackers : record.totalDefense(city)}'),
            TextField(
              controller: inputController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '追加数量',
                hintText: '输入数量',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              int? value = int.tryParse(inputController.text);
              if (value != null && value > 0) {
                Navigator.pop(ctx, value);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入有效数字')),
                );
              }
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
    if (result == null) return;

    if (isAttacker) {
      if (_soldiers < result) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('士兵不足'), backgroundColor: Colors.red),
        );
        return;
      }
      setState(() {
        _soldiers -= result;
        record.attackers[widget.uid] = (record.attackers[widget.uid] ?? 0) + result;
      });
      _saveAllToFirestore();
      if (phase == GamePhase.compete) {
        _checkAndAddBattleOvertakenTodo(record);
      }
      if (phase == GamePhase.attack && record.defender != null) {
        _todos.add(TodoItem(
          cityName: record.cityName,
          type: TodoType.defend,
          opponent: record.defender,
        ));
      }
    } else {
      if (_soldiers < result) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('士兵不足'), backgroundColor: Colors.red),
        );
        return;
      }
      setState(() {
        _soldiers -= result;
        record.defenderExtra += result;
      });
      _saveAllToFirestore();
      if (record.leadingAttacker != null) {
        _todos.add(TodoItem(
          cityName: record.cityName,
          type: TodoType.attackRespond,
          opponent: record.leadingAttacker!,
        ));
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ 追加 $result 兵力成功'), backgroundColor: Colors.green),
    );
  }

  void _checkAndAddBattleOvertakenTodo(BattleRecord record) {
    if (record.attackers.length <= 1) return;
    final leader = record.topAttacker;
    final myAmount = record.attackers[widget.uid] ?? 0;
    if (leader != widget.uid && myAmount > 0) {
      _todos.add(TodoItem(
        cityName: record.cityName,
        type: TodoType.battleOvertaken,
        opponent: leader,
      ));
    }
  }

  void _surrender(BattleRecord record, String player, bool isAttacker) {
    if (!isWarTime) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前不是战争时间（18:00-24:00）'), backgroundColor: Colors.red),
      );
      return;
    }
    if (currentPhase != GamePhase.attack) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('只能在进攻阶段放弃'), backgroundColor: Colors.red),
      );
      return;
    }
    final city = _allCities.firstWhere((c) => c.name == record.cityName);
    setState(() {
      _resolveBattle(record, city, surrenderBy: player);
      record.resolved = true;
    });
    _saveAllToFirestore();
  }

  void _resolveBattle(BattleRecord record, City city, {String? surrenderBy}) {
    if (record.resolved) return;

    if (surrenderBy != null) {
      bool attackerSurrender = record.attackers.containsKey(surrenderBy) && surrenderBy == record.leadingAttacker;
      if (attackerSurrender) {
        int attackTotal = record.totalAttackers;
        int defenseTotal = record.totalDefense(city);
        int consume = min(attackTotal, defenseTotal);
        int defenseRemaining = defenseTotal - consume;
        if (record.defender != null) {
          FirebaseFirestore.instance.collection('players').doc(record.defender).update({
            'soldiers': FieldValue.increment(defenseRemaining),
          });
        }
        if (record.defender == widget.uid && record.defender != null) {
          setState(() {
            if (_rankIndex < _ranks.length - 1) _rankIndex++;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('💥 你放弃了进攻，防守方获胜'), backgroundColor: Colors.orange),
        );
      } else {
        int attackTotal = record.totalAttackers;
        int defenseTotal = record.totalDefense(city);
        int consume = min(attackTotal, defenseTotal);
        int attackRemaining = attackTotal - consume;
        if (record.leadingAttacker != null) {
          FirebaseFirestore.instance.collection('players').doc(record.leadingAttacker).update({
            'soldiers': FieldValue.increment(attackRemaining),
          });
        }
        city.owner = record.leadingAttacker;
        if (record.leadingAttacker == widget.uid) {
          setState(() {
            if (record.defender != null) _rankIndex++;
            _gold += 50;
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🏆 敌方放弃，你获得 ${city.name}'), backgroundColor: Colors.green),
        );
      }
      return;
    }

    int attackTotal = record.totalAttackers;
    int defenseTotal = record.totalDefense(city);
    int consume = min(attackTotal, defenseTotal);
    int attackRemaining = attackTotal - consume;
    int defenseRemaining = defenseTotal - consume;

    if (record.defender != null) {
      FirebaseFirestore.instance.collection('players').doc(record.defender).update({
        'soldiers': FieldValue.increment(defenseRemaining),
      });
    }
    if (record.leadingAttacker != null) {
      FirebaseFirestore.instance.collection('players').doc(record.leadingAttacker).update({
        'soldiers': FieldValue.increment(attackRemaining),
      });
    }

    if (attackRemaining > 0) {
      city.owner = record.leadingAttacker;
      if (record.leadingAttacker == widget.uid) {
        setState(() {
          if (record.defender != null) _rankIndex++;
          _gold += 50;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🎉 攻占 ${city.name} 成功！'), backgroundColor: Colors.green),
      );
    } else {
      if (record.defender == widget.uid) {
        setState(() {
          if (_rankIndex < _ranks.length - 1) _rankIndex++;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('🛡️ 成功防守 ${city.name}'), backgroundColor: Colors.green),
      );
    }
  }

  void _upgradeCity(City city) async {
    if (_remainingUpgrades <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('你已没有升级次数'), backgroundColor: Colors.red),
      );
      return;
    }
    if (!city.isUpgradable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该城池不可升级'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      city.isUpgraded = true;
      _remainingUpgrades--;
    });
    await _saveAllToFirestore();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${city.name} 已升级为中级城'), backgroundColor: Colors.green),
    );
  }

  void _recruitCustom(int count) async {
    int cost = count * 10;
    if (_gold < cost) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('黄金不足！'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() {
      _gold -= cost;
      _soldiers += count;
    });
    await _saveAllToFirestore();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('招募 $count 名士兵，消耗 ${_formatNumber(cost)} 黄金'), backgroundColor: Colors.green),
    );
  }

  void _claimActivity() async {
    DateTime now = DateTime.now();
    if (_lastClaimDate != null &&
        _lastClaimDate!.year == now.year &&
        _lastClaimDate!.month == now.month &&
        _lastClaimDate!.day == now.day) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今日已经领取过奖励啦，明天再来吧！'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() {
      _gold += _activityGoldReward;
      _soldiers += _activitySoldiersReward;
      _lastClaimDate = now;
    });
    await _saveAllToFirestore();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🎁 领取成功：${_activityGoldReward}黄金 + ${_activitySoldiersReward}士兵'), backgroundColor: Colors.green),
    );
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
    );
  }

  String _formatNumber(int num) {
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toString();
  }

  List<BattleRecord> get _activeRecords => _battleRecords.values.where((r) => !r.resolved).toList();

  List<TodoItem> get _myTodos {
    final todos = _todos.where((t) => !t.isDone).toList();
    if (_remainingUpgrades > 0 && _ownedCities.any((c) => c.isUpgradable)) {
      todos.add(TodoItem(type: TodoType.upgradeAvailable));
    }
    return todos;
  }

  void _openAdminPanel() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminPanel(
          uid: widget.uid,
          activityGold: _activityGoldReward,
          activitySoldiers: _activitySoldiersReward,
          onPlayerDeleted: (deletedUid) {},
        ),
      ),
    );
  }

  List<Widget> get _pages => [
        MapPage(gold: _gold, soldiers: _soldiers),
        WarPage(
          soldiers: _soldiers,
          attackableCities: _getAttackableCities(),
          onDeclareWar: _declareWar,
          onAddTroops: _addTroops,
          onSurrender: _surrender,
          battleRecords: _battleRecords,
          currentPlayer: widget.uid,
          playerNames: _playerNames,
          currentPhase: currentPhase,
          isWarTime: isWarTime,
        ),
        const IntroPage(),
        ProfilePage(
          username: widget.username,
          gold: _gold,
          soldiers: _soldiers,
          rank: currentRank,
          ownedCities: _ownedCities,
          totalDailyGold: totalDailyGold,
          totalDailyCap: totalDailyCap,
          activeBattles: _activeRecords,
          remainingUpgrades: _remainingUpgrades,
          onUpgrade: _upgradeCity,
          onLogout: _logout,
          onRecruitCustom: _recruitCustom,
          formatNumber: _formatNumber,
          isAdmin: widget.isAdmin,
          onAdminPressed: _openAdminPanel,
        ),
        TaskActivityPage(
          gold: _gold,
          soldiers: _soldiers,
          cities: _ownedCities.length,
          lastClaimDate: _lastClaimDate,
          onClaim: _claimActivity,
          todos: _myTodos,
          battleRecords: _battleRecords,
          currentPlayer: widget.uid,
          playerNames: _playerNames,
          onAddTroops: _addTroops,
          onSurrender: _surrender,
          onNavigateToProfile: () {
            setState(() {
              _selectedIndex = 3;
            });
          },
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.username} 的霸业',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Center(
              child: Text(
                _currentTime,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: '地图'),
          BottomNavigationBarItem(icon: Icon(Icons.gavel), label: '宣战'),
          BottomNavigationBarItem(icon: Icon(Icons.info), label: '玩法'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '信息'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: '任务活动'),
        ],
        selectedItemColor: Colors.orange,
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}

enum GamePhase {
  declare,   // 0-10
  compete,   // 10-20
  attack,    // 20-40
  finished,  // 40-60
}

// ---------- 地图页面（美化）----------
class MapPage extends StatelessWidget {
  final int gold;
  final int soldiers;
  const MapPage({super.key, required this.gold, required this.soldiers});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ResourceBar(gold: gold, soldiers: soldiers),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'S1地图',
            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.3),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/s1dt.jpeg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[300],
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.map, size: 80, color: Colors.grey),
                            SizedBox(height: 10),
                            Text('地图加载失败'),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------- 宣战页面（美化）----------
class WarPage extends StatelessWidget {
  final int soldiers;
  final List<City> attackableCities;
  final Future<void> Function(City) onDeclareWar;
  final Future<void> Function(BuildContext, BattleRecord, bool) onAddTroops;
  final void Function(BattleRecord, String, bool) onSurrender;
  final Map<String, BattleRecord> battleRecords;
  final String currentPlayer;
  final Map<String, String> playerNames;
  final GamePhase currentPhase;
  final bool isWarTime;

  const WarPage({
    super.key,
    required this.soldiers,
    required this.attackableCities,
    required this.onDeclareWar,
    required this.onAddTroops,
    required this.onSurrender,
    required this.battleRecords,
    required this.currentPlayer,
    required this.playerNames,
    required this.currentPhase,
    required this.isWarTime,
  });

  String get phaseName {
    if (!isWarTime) return '非战争时间 (18:00-24:00)';
    switch (currentPhase) {
      case GamePhase.declare:
        return '宣战阶段 (0-10分钟)';
      case GamePhase.compete:
        return '抢宣阶段 (10-20分钟)';
      case GamePhase.attack:
        return '进攻阶段 (20-40分钟)';
      case GamePhase.finished:
        return '阶段结束 (40-60分钟)';
    }
  }

  String displayName(String uid) {
    return playerNames[uid] ?? uid;
  }

  @override
  Widget build(BuildContext context) {
    final canOperate = isWarTime && currentPhase != GamePhase.finished;
    return Column(
      children: [
        ResourceBar(gold: 0, soldiers: soldiers),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                phaseName,
                style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: canOperate ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  canOperate ? '可操作' : '不可操作',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: attackableCities.isEmpty
              ? Center(
                  child: Text(
                    '暂无可以宣战的城池',
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: attackableCities.length,
                  itemBuilder: (ctx, index) {
                    final city = attackableCities[index];
                    final record = battleRecords[city.name];
                    final myAttack = record?.attackers[currentPlayer] ?? 0;
                    final otherAttackers = record?.attackers.entries.where((e) => e.key != currentPlayer).toList() ?? [];
                    final canDeclare = isWarTime && currentPhase == GamePhase.declare && record == null;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    city.name,
                                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (canDeclare)
                                  ElevatedButton(
                                    onPressed: () => onDeclareWar(city),
                                    child: const Text('宣战'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '类型: ${city.type} 需求: ${city.requiredSoldiers}',
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[700]),
                            ),
                            if (record != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('你投入: $myAttack', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
                                    if (otherAttackers.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text('其他玩家:', style: GoogleFonts.poppins()),
                                      ...otherAttackers.map((e) => Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Text('  ${displayName(e.key)}: ${e.value}'),
                                      )),
                                    ],
                                    if (record.leadingAttacker != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          '当前进攻方: ${displayName(record.leadingAttacker!)}',
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            color: record.leadingAttacker == currentPlayer ? Colors.green : Colors.red,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (canOperate && (currentPhase == GamePhase.compete || currentPhase == GamePhase.attack))
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (currentPhase == GamePhase.compete && record.attackers.containsKey(currentPlayer))
                                      ElevatedButton(
                                        onPressed: () => onAddTroops(context, record, true),
                                        child: const Text('追加进攻'),
                                      ),
                                    if (currentPhase == GamePhase.attack) ...[
                                      if (record.leadingAttacker == currentPlayer)
                                        ElevatedButton(
                                          onPressed: () => onAddTroops(context, record, true),
                                          child: const Text('追加进攻'),
                                        ),
                                      if (record.defender == currentPlayer)
                                        ElevatedButton(
                                          onPressed: () => onAddTroops(context, record, false),
                                          child: const Text('追加防守'),
                                        ),
                                      if (record.leadingAttacker == currentPlayer)
                                        ElevatedButton(
                                          onPressed: () => onSurrender(record, currentPlayer, true),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          child: const Text('放弃进攻'),
                                        ),
                                      if (record.defender == currentPlayer)
                                        ElevatedButton(
                                          onPressed: () => onSurrender(record, currentPlayer, false),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                          child: const Text('放弃防守'),
                                        ),
                                    ],
                                  ],
                                ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ---------- 玩法介绍页面（美化）----------
class IntroPage extends StatelessWidget {
  const IntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.orange[50]!, Colors.white],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.3),
                    spreadRadius: 5,
                    blurRadius: 15,
                  ),
                ],
              ),
              child: const Icon(Icons.menu_book, color: Colors.white, size: 45),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '游戏玩法介绍',
            style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orange),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),

          _buildSectionCard(
            icon: Icons.location_city,
            title: '🏰 城池详情',
            color: Colors.blue,
            children: [
              _buildInfoRow('低级城', '需要 20,000 士兵攻占（飞地）'),
              _buildInfoRow('中级城', '需要 100,000 士兵攻占'),
              _buildInfoRow('高级城', '需要 300,000 士兵攻占'),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Text(
                  '• 所有城池初始无人认领\n• 每个玩家可任选 2 座低级城升级为中级城（升级后不可更改）',
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
              ),
            ],
          ),

          _buildSectionCard(
            icon: Icons.trending_up,
            title: '💰 城池收益（每日）',
            color: Colors.green,
            children: [
              _buildInfoRow('低级城', '10万黄金 + 1000 带兵上限'),
              _buildInfoRow('中级城', '20万黄金 + 5000 带兵上限'),
              _buildInfoRow('高级城', '50万黄金 + 10000 带兵上限'),
            ],
          ),

          _buildSectionCard(
            icon: Icons.emoji_events,
            title: '🏅 爵位系统',
            color: Colors.purple,
            children: [
              const Text(
                '每打赢一场真实玩家战斗，爵位提升一级，带兵上限增加：',
                style: TextStyle(fontSize: 14, color: Colors.black54),
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: WidgetStateProperty.all(Colors.purple[50]),
                  headingTextStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                  columns: const [
                    DataColumn(label: Text('爵位')),
                    DataColumn(label: Text('带兵上限加成')),
                  ],
                  rows: _buildRankRows(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Text(
              value,
              style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  List<DataRow> _buildRankRows() {
    List<String> ranks = [
      '平民', '什长', '百夫长', '千夫长', '九品提督', '八品将军',
      '七品统领', '六品将军', '五品官员', '四品大将', '三品大将',
      '二品大将', '一品大将', '六等王', '五等王', '四等王', '三等王',
      '二等王', '一等王'
    ];

    return List.generate(ranks.length, (index) {
      int bonus = (index + 1) * 10000;
      return DataRow(cells: [
        DataCell(Text(ranks[index])),
        DataCell(Text('+${bonus.toString()} 上限')),
      ]);
    });
  }
}

// ---------- 个人信息页面（美化）----------
class ProfilePage extends StatefulWidget {
  final String username;
  final int gold;
  final int soldiers;
  final String rank;
  final List<City> ownedCities;
  final int totalDailyGold;
  final int totalDailyCap;
  final List<BattleRecord> activeBattles;
  final int remainingUpgrades;
  final Function(City) onUpgrade;
  final VoidCallback onLogout;
  final void Function(int) onRecruitCustom;
  final String Function(int) formatNumber;
  final bool isAdmin;
  final VoidCallback onAdminPressed;

  const ProfilePage({
    super.key,
    required this.username,
    required this.gold,
    required this.soldiers,
    required this.rank,
    required this.ownedCities,
    required this.totalDailyGold,
    required this.totalDailyCap,
    required this.activeBattles,
    required this.remainingUpgrades,
    required this.onUpgrade,
    required this.onLogout,
    required this.onRecruitCustom,
    required this.formatNumber,
    required this.isAdmin,
    required this.onAdminPressed,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final TextEditingController _recruitController = TextEditingController();
  bool _showCities = false;
  bool _showBattles = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.orange[50]!, Colors.white],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.orange, Colors.deepOrange],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withValues(alpha: 0.5),
                    spreadRadius: 5,
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.fitness_center,
                color: Colors.white,
                size: 70,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              widget.username,
              style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '普通玩家',
                style: GoogleFonts.poppins(color: Colors.orange, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 30),

          // 资源卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  _buildProfileInfoItem(Icons.monetization_on, '黄金', widget.formatNumber(widget.gold), Colors.amber),
                  const Divider(),
                  _buildProfileInfoItem(Icons.shield, '士兵', widget.soldiers.toString(), Colors.red),
                  const Divider(),
                  _buildProfileInfoItem(Icons.location_city, '占领城池', widget.ownedCities.length.toString(), Colors.green),
                  const Divider(),
                  _buildProfileInfoItem(Icons.emoji_events, '您的爵位', widget.rank, Colors.purple),
                  const Divider(),
                  _buildProfileInfoItem(Icons.gavel, '可宣战兵力', widget.soldiers.toString(), Colors.orange),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 加成卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '🏅 城池加成',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: Icon(_showCities ? Icons.expand_less : Icons.expand_more),
                        onPressed: () {
                          setState(() {
                            _showCities = !_showCities;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildBuffRow(Icons.trending_up, '每日黄金收益', '${widget.formatNumber(widget.totalDailyGold)}/天'),
                  const SizedBox(height: 5),
                  _buildBuffRow(Icons.shield, '带兵上限', '+${widget.formatNumber(widget.totalDailyCap)}'),
                  if (_showCities) ...[
                    const SizedBox(height: 15),
                    Text(
                      '已占领城池：',
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    if (widget.ownedCities.isEmpty)
                      Text('暂无占领城池', style: GoogleFonts.poppins(color: Colors.grey))
                    else
                      ...widget.ownedCities.map((city) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.location_on, size: 18, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('${city.name} (${city.level}${city.isUpgraded ? '已升级' : ''})'),
                            ),
                            if (city.isUpgradable && widget.remainingUpgrades > 0)
                              ElevatedButton(
                                onPressed: () => widget.onUpgrade(city),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  minimumSize: const Size(60, 30),
                                ),
                                child: const Text('升级'),
                              ),
                          ],
                        ),
                      )),
                  ],

                  const Divider(height: 30),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '⚔️ 当前战斗',
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                      IconButton(
                        icon: Icon(_showBattles ? Icons.expand_less : Icons.expand_more),
                        onPressed: () {
                          setState(() {
                            _showBattles = !_showBattles;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_showBattles) ...[
                    if (widget.activeBattles.isEmpty)
                      Text('暂无战斗', style: GoogleFonts.poppins(color: Colors.grey))
                    else
                      ...widget.activeBattles.map((record) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(record.cityName, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                            Text('进攻: ${record.attackers}'),
                            if (record.defender != null) Text('防守: ${record.defender} 额外 ${record.defenderExtra}'),
                          ],
                        ),
                      )),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 招募士兵卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '招募士兵',
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _recruitController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '输入数量',
                            prefixIcon: const Icon(Icons.person_add),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () {
                          int? count = int.tryParse(_recruitController.text);
                          if (count == null || count <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请输入有效的数量'), backgroundColor: Colors.red),
                            );
                            return;
                          }
                          widget.onRecruitCustom(count);
                          _recruitController.clear();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        child: const Text('招募'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '每名士兵消耗10黄金，当前可招募最多 ${widget.gold ~/ 10} 名',
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          if (widget.isAdmin)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _buildActionItem(
                  Icons.admin_panel_settings,
                  '管理后台',
                  '修改玩家数据及活动奖励',
                  widget.onAdminPressed,
                  isLogout: false,
                ),
              ),
            ),

          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _buildActionItem(
                Icons.logout,
                '退出登录',
                '返回登录页面',
                widget.onLogout,
                isLogout: true,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildBuffRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.orange),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.poppins(fontSize: 16)),
        const Spacer(),
        Text(value, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange)),
      ],
    );
  }

  Widget _buildProfileInfoItem(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem(IconData icon, String title, String subtitle, VoidCallback onTap, {bool isLogout = false}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isLogout ? Colors.red.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isLogout ? Colors.red : Colors.orange),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          color: isLogout ? Colors.red : Colors.black87,
        ),
      ),
      subtitle: Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
      trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
      onTap: onTap,
    );
  }
}

// ---------- 任务活动页面（美化）----------
class TaskActivityPage extends StatelessWidget {
  final int gold;
  final int soldiers;
  final int cities;
  final DateTime? lastClaimDate;
  final VoidCallback onClaim;
  final List<TodoItem> todos;
  final Map<String, BattleRecord> battleRecords;
  final String currentPlayer;
  final Map<String, String> playerNames;
  final Future<void> Function(BuildContext, BattleRecord, bool) onAddTroops;
  final void Function(BattleRecord, String, bool) onSurrender;
  final VoidCallback onNavigateToProfile;

  const TaskActivityPage({
    super.key,
    required this.gold,
    required this.soldiers,
    required this.cities,
    required this.lastClaimDate,
    required this.onClaim,
    required this.todos,
    required this.battleRecords,
    required this.currentPlayer,
    required this.playerNames,
    required this.onAddTroops,
    required this.onSurrender,
    required this.onNavigateToProfile,
  });

  bool get canClaim {
    if (lastClaimDate == null) return true;
    DateTime now = DateTime.now();
    return lastClaimDate!.year != now.year ||
        lastClaimDate!.month != now.month ||
        lastClaimDate!.day != now.day;
  }

  String displayName(String? uid) {
    if (uid == null) return '未知';
    return playerNames[uid] ?? uid;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.orange[50]!, Colors.white],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          ResourceBar(gold: gold, soldiers: soldiers),
          const SizedBox(height: 20),

          Text(
            '🔥 紧急待办',
            style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 10),

          if (todos.isNotEmpty)
            ...todos.map((todo) {
              if (todo.type == TodoType.upgradeAvailable) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: Colors.green[50],
                  child: ListTile(
                    leading: const Icon(Icons.upgrade, color: Colors.green),
                    title: const Text('有城池可升级'),
                    subtitle: const Text('你有低级城池可以升级为中级城'),
                    trailing: ElevatedButton(
                      onPressed: () {
                        todo.isDone = true;
                        onNavigateToProfile();
                      },
                      child: const Text('前往升级'),
                    ),
                  ),
                );
              }
              if (todo.type == TodoType.battleOvertaken) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: Colors.yellow[100],
                  child: ListTile(
                    leading: const Icon(Icons.warning, color: Colors.orange),
                    title: Text('争夺 ${todo.cityName} 被反超'),
                    subtitle: Text('领先者: ${displayName(todo.opponent)}'),
                    trailing: ElevatedButton(
                      onPressed: () {
                        todo.isDone = true;
                      },
                      child: const Text('查看'),
                    ),
                  ),
                );
              }
              final record = battleRecords[todo.cityName ?? ''];
              if (record == null || record.resolved) return const SizedBox.shrink();
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                color: Colors.red[50],
                child: ListTile(
                  title: Text(todo.type == TodoType.defend ? '需要防守 ${todo.cityName}' : '进攻 ${todo.cityName} 对方已防守'),
                  subtitle: Text('对手: ${displayName(todo.opponent)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          if (todo.type == TodoType.defend) {
                            onAddTroops(context, record, false);
                          } else {
                            onAddTroops(context, record, true);
                          }
                          todo.isDone = true;
                        },
                        child: const Text('处理'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          onSurrender(record, currentPlayer, todo.type == TodoType.defend ? false : true);
                          todo.isDone = true;
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('放弃'),
                      ),
                    ],
                  ),
                ),
              );
            }),

          if (todos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('暂无待办', style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey)),
              ),
            ),

          const SizedBox(height: 30),

          Card(
            color: Colors.purple[50],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.card_giftcard, color: Colors.purple, size: 40),
                      SizedBox(width: 10),
                      Text(
                        '每日奖励',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.purple),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '每日可领取一次',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: canClaim ? onClaim : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple,
                      padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      canClaim ? '立即领取' : '今日已领',
                      style: const TextStyle(fontSize: 20, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ---------- 管理员后台（美化）----------
class AdminPanel extends StatefulWidget {
  final String uid;
  final int activityGold;
  final int activitySoldiers;
  final void Function(String) onPlayerDeleted;

  const AdminPanel({
    super.key,
    required this.uid,
    required this.activityGold,
    required this.activitySoldiers,
    required this.onPlayerDeleted,
  });

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final TextEditingController _goldController = TextEditingController();
  final TextEditingController _soldiersController = TextEditingController();
  final TextEditingController _activityGoldController = TextEditingController();
  final TextEditingController _activitySoldiersController = TextEditingController();
  String? _selectedPlayerId;
  List<Map<String, dynamic>> _players = [];

  @override
  void initState() {
    super.initState();
    _activityGoldController.text = widget.activityGold.toString();
    _activitySoldiersController.text = widget.activitySoldiers.toString();
    _loadPlayers();
  }

  Future<void> _loadPlayers() async {
    final snapshot = await FirebaseFirestore.instance.collection('players').get();
    setState(() {
      _players = snapshot.docs.map((doc) {
        return {
          'uid': doc.id,
          'username': doc.data()['username'] ?? '未知',
          'gold': doc.data()['gold'] ?? 0,
          'soldiers': doc.data()['soldiers'] ?? 0,
        };
      }).toList();
    });
  }

  Future<void> _deletePlayer(String uid, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除玩家 "$username" 吗？此操作不可恢复，该玩家拥有的城池将变为无主。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final citiesSnapshot = await FirebaseFirestore.instance
          .collection('cities')
          .where('owner', isEqualTo: uid)
          .get();
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in citiesSnapshot.docs) {
        batch.update(doc.reference, {'owner': null});
      }
      await batch.commit();

      await FirebaseFirestore.instance.collection('players').doc(uid).delete();

      await _loadPlayers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('玩家 "$username" 已删除'), backgroundColor: Colors.green),
      );
      widget.onPlayerDeleted(uid);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理后台'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择玩家', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButton<String>(
                value: _selectedPlayerId,
                hint: const Text('选择玩家'),
                isExpanded: true,
                underline: const SizedBox(),
                items: _players.map<DropdownMenuItem<String>>((p) {
                  return DropdownMenuItem<String>(
                    value: p['uid'] as String,
                    child: Text('${p['username']} (黄金: ${p['gold']}, 士兵: ${p['soldiers']})'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPlayerId = value;
                    if (value != null) {
                      final p = _players.firstWhere((p) => p['uid'] == value);
                      _goldController.text = p['gold'].toString();
                      _soldiersController.text = p['soldiers'].toString();
                    } else {
                      _goldController.clear();
                      _soldiersController.clear();
                    }
                  });
                },
              ),
            ),
            if (_selectedPlayerId != null) ...[
              const SizedBox(height: 20),
              Text('修改资源', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _goldController,
                decoration: const InputDecoration(labelText: '黄金'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _soldiersController,
                decoration: const InputDecoration(labelText: '士兵'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        int newGold = int.tryParse(_goldController.text) ?? 0;
                        int newSoldiers = int.tryParse(_soldiersController.text) ?? 0;
                        await FirebaseFirestore.instance
                            .collection('players')
                            .doc(_selectedPlayerId)
                            .update({'gold': newGold, 'soldiers': newSoldiers});
                        _loadPlayers();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已更新')),
                        );
                      },
                      child: const Text('保存修改'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final p = _players.firstWhere((p) => p['uid'] == _selectedPlayerId);
                        _deletePlayer(p['uid'], p['username']);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('删除玩家'),
                    ),
                  ),
                ],
              ),
            ],
            const Divider(height: 40),
            Text('活动奖励设置', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _activityGoldController,
              decoration: const InputDecoration(labelText: '活动黄金'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _activitySoldiersController,
              decoration: const InputDecoration(labelText: '活动士兵'),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  int newGold = int.tryParse(_activityGoldController.text) ?? 10000;
                  int newSoldiers = int.tryParse(_activitySoldiersController.text) ?? 10;
                  await FirebaseFirestore.instance.collection('config').doc('activity').set({
                    'gold': newGold,
                    'soldiers': newSoldiers,
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('活动奖励已更新')),
                  );
                },
                child: const Text('保存活动奖励'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}