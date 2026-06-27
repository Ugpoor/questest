# 智能出题 (Questest)

基于 Flutter 的智能出题与考试应用，支持文档导入解析、题库管理、多维度智能选题、限时答题与自动批阅。面向 Android 平板横屏使用场景设计。

## 功能概览

应用包含五个功能模块，通过顶部 Tab 栏切换，使用 `IndexedStack` 保持各页面状态不丢失。

**文档导入** — 选择 `.docx` 或 `.doc` 文件后，系统自动完成解析入库。导入过程包含两级排重：文件级 SHA-256 哈希排重（防止同一文件重复导入）和题干级内容排重（过滤已有相同题目）。解析完成后显示新增、重复和总解析数量统计。

**题库管理** — 左侧显示所有题库列表（含题目数量），右侧展示选中题库的题目详情，支持关键词搜索和分页浏览。每个题库表包含三道维度标签（dim1/dim2/dim3），可通过 AI 自动分类或手动设定。删除题库需输入题库名称确认。

**智能选题** — 创建测试会话后，系统提供三种选题模式：

- 自动随机选题：按序号分段均匀采样，将总题数分成 N 段，每段随机取一题，保证题目在序号上的均匀分布。
- 按维度选题：选择 dim1/dim2/dim3 中的某个维度，系统列出该维度所有分类值及其题目数，用户为每个分类指定选取数量，最后一项自动计算（总数减去已分配数），从数据库直接按 `ORDER BY RANDOM()` 抽取。
- 智能维度分散：默认模式，遍历所有维度标签，优先保证每个分类至少有 1 题被选中，再按配额补足剩余名额。

选题过程有进度条实时反馈。测试会话经历 `待选题 → 待提交 → 已批阅` 的状态流转，另有 `已中止` 作为终止状态。

**限时答题** — 进入答题后显示倒计时，支持单选和多选两种题型。答题过程中可随时退出（答案自动保存），下次从测试列表点击进入继续作答。底部设有红色"终止"按钮，可中止当前测试。中止的测试不参与批阅，状态标记为"已中止"，可删除。提交后系统自动对比标准答案进行批阅。

**成绩报告** — 展示所有已完成测试的批阅结果，包括得分、用时、正确率等。仅显示状态为 `completed` 的测试记录。

## 技术架构

### 状态管理

采用 Provider + ChangeNotifier 模式，全局唯一的 `AppState` 管理所有应用状态：导航 Tab 索引、题库列表与选中项、测试会话列表与当前活跃测试、答题记录、导入结果计数器和加载/错误状态。各 Screen 通过 `Consumer<AppState>` 或 `context.watch<AppState>()` 响应状态变化。

### 数据存储

使用 sqflite（SQLite3）作为本地数据库，数据库 schema 版本为 2。首次启动时从 `assets/questest.db` 复制预置题库到应用数据库目录。如果检测到数据库为空（`question_tables` 表无记录），会重新从 assets 复制。

固定表结构：

- `question_tables` — 题库元信息（表名、显示名、文件路径、创建时间、题目数）
- `dimensions` — 维度定义（dim_index, dim_name）
- `file_hashes` — 文件哈希排重记录（SHA-256）
- `test_sessions` — 测试会话（标题、题库、题数、时长、状态、起止时间、得分）
- `test_answers` — 答题记录（test_id、question_id、用户答案、是否正确、得分）

动态表：每个题库创建一张 `q_<名称>` 表，包含 id、seq、content、options（JSON 数组）、correct_answers、explanation、dim1、dim2、dim3。

### LLM 集成

内置阿里云百炼（DashScope）API 调用，使用 `qwen3.7-plus` 模型，通过 OpenAI 兼容接口 (`/compatible-mode/v1/chat/completions`) 通信。API 密钥硬编码在源码中，用户无需配置。LLM 用于题目维度分类：将题目按批次（每批 10 题，间隔 500ms）发送给模型，返回 JSON 格式的 dim1/dim2/dim3 标签。当 LLM 不可用时，回退到基于关键词的本地分类。

### 文档解析

`DocParserService` 通过调用本地进程解析文档：`.docx` 使用 `python3` 内联脚本读取 zip/XML 结构；`.doc` 使用 macOS 原生的 `textutil` 命令转换为纯文本。解析器识别题号（阿拉伯数字或中文数字）、选项（A-E）、答案和解析，支持单选和多选。

**注意：** 文档解析依赖本地 `python3` 和 `textutil` 命令，仅在 macOS 上完整可用。Android 端可通过预置数据库使用内置题库，但无法导入新文档。

## 项目结构

```
questest_app/
├── lib/
│   ├── main.dart                    # 入口 + MainScreen（5-Tab IndexedStack）
│   ├── models/
│   │   ├── question.dart            # Question / QuestionOption 模型
│   │   ├── test_session.dart        # TestSession / TestAnswer 模型
│   │   └── app_settings.dart        # AppSettings（时长、维度定义）
│   ├── providers/
│   │   └── app_state.dart           # 全局状态管理（ChangeNotifier）
│   ├── screens/
│   │   ├── import_screen.dart       # 文档导入
│   │   ├── question_bank_screen.dart # 题库浏览与管理
│   │   ├── selection_screen.dart    # 创建测试 + 选题
│   │   ├── test_screen.dart         # 答题 + 批阅
│   │   └── results_screen.dart      # 成绩报告
│   ├── services/
│   │   ├── database_service.dart    # SQLite 数据库操作
│   │   ├── doc_parser_service.dart  # 文档解析（.docx/.doc）
│   │   ├── llm_classify_service.dart # LLM 题目分类
│   │   └── question_selector.dart   # 智能选题算法
│   └── widgets/                     # 公共组件（当前为空）
├── assets/
│   ├── questest.db                  # 预置题库（1000 题，10 个主题分类）
│   └── 青少年人工智能基础知识大赛题库.doc  # 示例源文档
├── android/                         # Android 平台配置
├── pubspec.yaml                     # 依赖声明
└── README.md
```

## 预置题库

`assets/questest.db` 包含 1000 道"青少年人工智能基础知识大赛"题目，已通过 LLM（qwen3.7-plus）完成分类打标，覆盖 10 个主题：人工智能基础、机器学习与深度学习、计算机视觉、自然语言处理、语音识别与合成、智能机器人、自动驾驶与智能交通、AI 伦理与安全、AI 编程与工具、前沿应用与未来趋势。每道题均包含题干、选项（JSON 格式）、正确答案、解析和 dim1 维度标签。

## 依赖项

| 包 | 用途 |
|---|---|
| `sqflite` | 本地 SQLite3 数据库 |
| `provider` | 状态管理 |
| `file_picker` | 文件选择（文档导入） |
| `http` | LLM API 网络请求 |
| `crypto` | SHA-256 文件哈希 |
| `shared_preferences` | 应用设置持久化 |
| `path_provider` | 数据库目录定位 |
| `flutter_markdown` | Markdown 内容渲染 |
| `intl` | 日期时间格式化 |
| `uuid` | 唯一标识生成 |

## 构建与运行

```bash
# 确保 Flutter SDK 已安装
flutter pub get

# 调试运行（连接设备或模拟器）
flutter run

# 构建 Android APK
flutter build apk --debug    # 调试版
flutter build apk --release  # 发布版（需配置签名）
```

应用强制横屏显示（`landscapeLeft` + `landscapeRight`），启用全屏沉浸式模式（`immersiveSticky`）。

## 平台限制

文档导入功能依赖 `python3`（解析 .docx）和 `textutil`（解析 .doc），目前仅在 macOS 上可用。Android 端可使用预置题库和全部考试功能，但无法从外部文档导入新题目。LLM 分类功能需要网络连接。

## 关键设计约束

`Question.fromMap` 需要显式传入 `tableName` 参数，因为数据库表结构中不包含 `table_name` 列。相应地，`toMap()` 不输出 `table_name` 字段，避免 INSERT 时因列不存在而报错。

测试会话中的派生 UI 状态（如维度选题中最后一项的自动计算数量）使用纯 getter 派生，不在 `build()` 中调用 `addPostFrameCallback` + `setState`，以避免无限重建循环。

预置数据库复制逻辑不仅检查文件是否存在，还会打开数据库验证 `question_tables` 是否为空。这确保旧版安装（可能复制了空库）能正确被覆盖。
