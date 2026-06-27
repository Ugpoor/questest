# Questest - 智能出题

支持文档导入、题库管理、AI 智能归类与组卷出题的 Flutter 应用。

## 功能概览

**文档导入** — 从 .doc/.docx 文件中批量解析选择题，自动提取题干、选项（A-E）、答案和解析。

**题库管理** — 每次导入生成独立题库表，支持多题库切换、浏览和删除。题目按三维标签（dim1/dim2/dim3）组织。

**AI 归类** — 配置 OpenAI 兼容的 LLM API 后，可按自定义维度（如"知识点/难度/题型"）自动为题目打标签。未配置 LLM 时回退到本地关键词匹配。

**智能组卷** — 基于维度分层抽样选题，支持设定题目数量、维度过滤和覆盖率参数，自动避免连续同序号题目。

**计时考试** — 横屏全屏答题，支持单选/多选，每题计时，完成后展示成绩报告。

## 项目结构

```
questest_app/
  lib/
    main.dart                   # 入口，Provider 注入，横屏全屏配置
    models/
      question.dart             # Question / QuestionOption 模型
      quiz_session.dart         # QuizSession / QuizAnswer 模型
      app_settings.dart         # AppSettings 模型（计时器、维度等）
    providers/
      app_state.dart            # AppState (ChangeNotifier) — 全局状态管理
    screens/
      home_screen.dart          # 主页：统计概览 + 功能入口
      import_screen.dart        # 文档导入（file_picker 选择 .doc/.docx）
      question_bank_screen.dart # 题库浏览 + 维度分布查看
      classify_screen.dart      # AI 归类操作界面
      quiz_setup_screen.dart    # 组卷设置（数量、维度过滤、策略）
      quiz_screen.dart          # 答题界面（计时、翻页）
      result_screen.dart        # 成绩报告
      settings_screen.dart      # 设置（计时器、维度定义、LLM API 配置）
    services/
      database_service.dart     # SQLite 数据层（sqflite）
      doc_parser_service.dart   # .doc/.docx 解析
      llm_classify_service.dart # LLM 调用 + 本地关键词分类
      question_selector.dart    # 智能选题算法
    widgets/                    # 自定义组件（预留）
```

## 技术栈

- Flutter 3.x + Dart 3.x
- 状态管理：Provider (ChangeNotifier)
- 数据库：sqflite（每个导入文档一张表，元数据表 `question_tables`，维度表 `dimensions`）
- 依赖：file_picker, path_provider, shared_preferences, http, flutter_markdown, uuid, intl
- LLM 接口：OpenAI 兼容格式 `/chat/completions`，用户可在设置页配置 API 地址和 Key

## 环境要求与 Android Studio 调试配置

### 前置条件

- Flutter SDK >= 3.0（推荐 stable 最新版）
- Android Studio（含 Flutter 和 Dart 插件）
- Android SDK（cmdline-tools + 已接受 license）
- macOS 环境（文档解析的 .doc 格式依赖系统自带 `textutil`）
- Python 3（文档解析的 .docx 格式依赖 `python3` 命令）

### 初始化 Android 平台

项目默认只包含 iOS 和 macOS 平台代码。如需 Android 调试，先在项目根目录执行：

```bash
cd questest_app
flutter create . --platforms=android
```

### 修复 Android toolchain（命令行自动化）

如果 `flutter doctor` 报 cmdline-tools 缺失或 license 未接受，可全部用命令行完成，无需打开 AS 的 SDK Manager GUI：

```bash
# 1. 下载并安装 cmdline-tools
curl -sL -o /tmp/cmdline-tools.zip \
  "https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip"
cd /tmp && unzip -q cmdline-tools.zip
mkdir -p $ANDROID_HOME/cmdline-tools
mv /tmp/cmdline-tools $ANDROID_HOME/cmdline-tools/latest

# 2. 安装所需 SDK 组件
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
sdkmanager --install "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# 3. 自动接受所有 license
yes | sdkmanager --licenses

# 4. 验证
flutter doctor
```

### 打开项目

用 Android Studio 打开 **`questest_app/`** 目录（即 `pubspec.yaml` 所在的那一层），不要打开外层的 `questest/` 容器目录。AS 的 Flutter 插件会自动识别项目类型，`.idea/runConfigurations/main_dart.xml` 中已有默认运行配置。

### 运行与调试

连接 Android 设备或启动模拟器后，直接在 AS 中点击 Run 即可。如需断点调试，在 Dart 代码行号旁设置断点，使用 Debug 模式启动。

## 文档解析说明

文档导入功能依赖外部工具：

- **.docx** — 通过内嵌 Python 脚本（`zipfile` + `xml.etree`）解析，需要系统 PATH 中有 `python3`
- **.doc** — 通过 macOS 内置 `textutil` 转换为纯文本后正则解析，仅限 macOS

在 Android/iOS 设备上运行时，这两种外部工具均不可用，文档导入功能将受限。

## 注意事项

- 应用强制横屏显示（`landscapeLeft` + `landscapeRight`），启动后进入全屏沉浸模式
- LLM 归类按每批 10 题调用，批次间隔 500ms 防止限流
- 本地关键词分类是 LLM 的降级方案，准确度有限
- `widgets/` 目录当前为空，可提取公共 UI 组件到此目录
