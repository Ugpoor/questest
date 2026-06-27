import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/app_state.dart';
import 'screens/import_screen.dart';
import 'screens/question_bank_screen.dart';
import 'screens/selection_screen.dart';
import 'screens/test_screen.dart';
import 'screens/results_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 强制横屏
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 全屏沉浸式
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const QuestestApp());
}

class QuestestApp extends StatelessWidget {
  const QuestestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: '刷题宝宝',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4A90E2),
            brightness: Brightness.light,
          ),
          fontFamily: 'PingFang SC',
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF4A90E2),
            foregroundColor: Colors.white,
            elevation: 0,
          ),
        ),
        home: const MainScreen(),
      ),
    );
  }
}

// ==================== 主界面 ====================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabLabels = ['导入', '题库', '选题', '测试', '成绩报告'];
  static const _tabIcons = [
    Icons.file_upload_outlined,
    Icons.library_books_outlined,
    Icons.filter_list_outlined,
    Icons.edit_note_outlined,
    Icons.assessment_outlined,
  ];
  static const _tabActiveIcons = [
    Icons.file_upload,
    Icons.library_books,
    Icons.filter_list,
    Icons.edit_note,
    Icons.assessment,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// TabController 用户交互 -> 同步到 AppState
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final app = context.read<AppState>();
    if (app.currentTab != _tabController.index) {
      app.setTab(_tabController.index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, app, _) {
        // AppState 外部调用 setTab -> 同步到 TabController
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_tabController.index != app.currentTab) {
            _tabController.animateTo(app.currentTab);
          }
        });

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          body: Column(
            children: [
              _buildTopBar(context, app),
              Expanded(
                child: IndexedStack(
                  index: app.currentTab,
                  children: const [
                    ImportScreen(),
                    QuestionBankScreen(),
                    SelectionScreen(),
                    TestScreen(),
                    ResultsScreen(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== 顶部导航栏 ====================

  Widget _buildTopBar(BuildContext context, AppState app) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              // 左侧 Logo + 标题
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4A90E2), Color(0xFF6C5CE7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.quiz, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              const Text(
                '刷题宝宝',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(width: 24),
              // Tab 按钮组
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: const Color(0xFF4A90E2),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF4A90E2),
                  indicatorWeight: 3,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                  dividerColor: Colors.transparent,
                  onTap: (index) {
                    app.setTab(index);
                  },
                  tabs: List.generate(_tabLabels.length, (i) {
                    final isActive = app.currentTab == i;
                    return Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isActive ? _tabActiveIcons[i] : _tabIcons[i],
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(_tabLabels[i]),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
