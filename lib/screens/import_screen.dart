import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/app_state.dart';
import '../services/database_service.dart';
import '../services/doc_parser_service.dart';
import '../models/question.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _displayNameController = TextEditingController();
  PlatformFile? _selectedFile;

  // Hash dedup state
  bool _isCheckingHash = false;
  bool _isDuplicate = false;
  String? _duplicateFileName;

  // Import progress
  bool _isImporting = false;
  String _loadingMessage = '';

  // Import result
  int? _parsedCount;
  int? _addedCount;
  int? _duplicatedCount;
  String? _importError;

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['doc', 'docx'],
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    // Reset state
    setState(() {
      _selectedFile = file;
      _parsedCount = null;
      _addedCount = null;
      _duplicatedCount = null;
      _importError = null;
      _isDuplicate = false;
      _duplicateFileName = null;
      _displayNameController.text =
          file.name.replaceAll(RegExp(r'\.(doc|docx)$', caseSensitive: false), '');
    });

    await _checkFileHash(file.path!);
  }

  Future<void> _checkFileHash(String filePath) async {
    setState(() => _isCheckingHash = true);
    try {
      final hash = await DatabaseService.computeFileHash(filePath);
      final database = await DatabaseService.db;
      final rows = await database.query(
        'file_hashes',
        where: 'hash = ?',
        whereArgs: [hash],
      );

      if (rows.isNotEmpty && mounted) {
        setState(() {
          _isDuplicate = true;
          _duplicateFileName = rows.first['file_name'] as String?;
          _isCheckingHash = false;
        });
      } else if (mounted) {
        setState(() {
          _isDuplicate = false;
          _duplicateFileName = null;
          _isCheckingHash = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingHash = false);
      }
    }
  }

  Future<void> _importDocument() async {
    if (_selectedFile == null || _selectedFile!.path == null) return;
    if (_isDuplicate) return;

    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入题库显示名称')),
      );
      return;
    }

    setState(() {
      _isImporting = true;
      _loadingMessage = '正在解析文档...';
      _parsedCount = null;
      _addedCount = null;
      _duplicatedCount = null;
      _importError = null;
    });

    try {
      final filePath = _selectedFile!.path!;
      final tableName = await DatabaseService.createQuestionTable(displayName);

      // Parse
      setState(() => _loadingMessage = '正在解析文档...');
      final allQuestions = await DocParserService.parseFile(filePath, tableName);
      final parsed = allQuestions.length;

      if (parsed == 0) {
        throw Exception('未能从文档中解析出任何题目');
      }

      // Deduplicate within the document by content
      setState(() => _loadingMessage = '正在排重检查...');
      final seen = <String>{};
      final uniqueQuestions = <Question>[];
      int dupCount = 0;

      for (final q in allQuestions) {
        final key = q.content.trim();
        if (seen.contains(key)) {
          dupCount++;
        } else {
          seen.add(key);
          uniqueQuestions.add(q);
        }
      }

      // Re-number seq for unique questions
      for (int i = 0; i < uniqueQuestions.length; i++) {
        uniqueQuestions[i] = uniqueQuestions[i].copyWith(seq: i + 1);
      }

      // Insert
      setState(() => _loadingMessage = '正在保存 ${uniqueQuestions.length} 道题目...');
      await DatabaseService.insertQuestions(tableName, uniqueQuestions);

      // Record metadata
      await DatabaseService.recordTableMeta(
        tableName: tableName,
        displayName: displayName,
        filePath: filePath,
        questionCount: uniqueQuestions.length,
      );

      // Record file hash for future dedup
      final hash = await DatabaseService.computeFileHash(filePath);
      await DatabaseService.recordFileHash(
        hash: hash,
        fileName: _selectedFile!.name,
        tableName: tableName,
      );

      // Refresh tables
      await context.read<AppState>().refreshTables();

      if (mounted) {
        setState(() {
          _parsedCount = parsed;
          _addedCount = uniqueQuestions.length;
          _duplicatedCount = dupCount;
          _isImporting = false;
          _loadingMessage = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importError = e.toString().replaceFirst('Exception: ', '');
          _isImporting = false;
          _loadingMessage = '';
        });
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedFile = null;
      _displayNameController.clear();
      _isDuplicate = false;
      _duplicateFileName = null;
      _parsedCount = null;
      _addedCount = null;
      _duplicatedCount = null;
      _importError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('导入题库文档'),
        backgroundColor: const Color(0xFF4A90E2),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Row(
        children: [
          // Left: Import form
          Expanded(
            flex: 5,
            child: _buildImportPanel(),
          ),
          // Divider
          Container(width: 1, color: Colors.grey.shade200),
          // Right: Existing tables
          Expanded(
            flex: 4,
            child: _buildTablesPanel(app),
          ),
        ],
      ),
    );
  }

  Widget _buildImportPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Instructions
          _buildInstructions(),
          const SizedBox(height: 20),

          // File picker
          _buildFilePicker(),
          const SizedBox(height: 16),

          // Selected file info + display name
          if (_selectedFile != null) ...[
            _buildFileInfo(),
            const SizedBox(height: 16),
            _buildDisplayNameField(),
            const SizedBox(height: 16),

            // Duplicate warning
            if (_isCheckingHash)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('正在检查文件...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                ),
              ),
            if (_isDuplicate)
              _buildDuplicateWarning(),

            // Import button
            _buildImportButton(),
            const SizedBox(height: 16),

            // Loading
            if (_isImporting)
              _buildLoadingIndicator(),

            // Import result
            if (_parsedCount != null)
              _buildResultCard(),

            // Import error
            if (_importError != null)
              _buildErrorCard(),
          ],

          // Empty state when no file selected
          if (_selectedFile == null)
            _buildEmptyPickerState(),
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A90E2).withAlpha(51)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Color(0xFF4A90E2), size: 18),
              SizedBox(width: 8),
              Text(
                '导入说明',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF4A90E2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _instructionItem('支持 .doc 和 .docx 格式的题库文件'),
          _instructionItem('题目格式：题号 + 选项(A-E) + 答案 + 解析(可选)'),
          _instructionItem('相同文件会自动排重，不会重复导入'),
          _instructionItem('同一文档内重复题目也会被自动排重'),
        ],
      ),
    );
  }

  Widget _instructionItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('  \u2022  ', style: TextStyle(fontSize: 13, color: Color(0xFF4A90E2))),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePicker() {
    return OutlinedButton.icon(
      onPressed: _isImporting ? null : _pickFile,
      icon: const Icon(Icons.folder_open, size: 20),
      label: const Text('选择 .doc / .docx 文件'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF4A90E2),
        side: const BorderSide(color: Color(0xFF4A90E2)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _buildFileInfo() {
    final file = _selectedFile!;
    final sizeStr = file.size > 1024 * 1024
        ? '${(file.size / 1024 / 1024).toStringAsFixed(1)} MB'
        : '${(file.size / 1024).toStringAsFixed(0)} KB';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _getFileColor(file.extension).withAlpha(26),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.description_outlined,
              color: _getFileColor(file.extension),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${file.extension?.toUpperCase() ?? ""} \u00b7 $sizeStr',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (!_isImporting)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              color: Colors.grey,
              onPressed: _clearSelection,
              tooltip: '清除选择',
            ),
        ],
      ),
    );
  }

  Widget _buildDisplayNameField() {
    return TextField(
      controller: _displayNameController,
      enabled: !_isImporting,
      decoration: InputDecoration(
        labelText: '题库显示名称',
        hintText: '输入题库的显示名称',
        prefixIcon: const Icon(Icons.label_outline, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF4A90E2), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
    );
  }

  Widget _buildDuplicateWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF9800).withAlpha(102)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9800), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '此文件已导入过（文件名：${_duplicateFileName ?? "未知"}）',
              style: const TextStyle(fontSize: 13, color: Color(0xFFE65100)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportButton() {
    final canImport = !_isImporting && !_isDuplicate && !_isCheckingHash
        && _displayNameController.text.trim().isNotEmpty;

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: canImport ? _importDocument : null,
        icon: const Icon(Icons.cloud_upload_outlined, size: 20),
        label: const Text('导入', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade200,
          disabledForegroundColor: Colors.grey,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: canImport ? 2 : 0,
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFF4A90E2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _loadingMessage,
              style: const TextStyle(fontSize: 14, color: Color(0xFF4A90E2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFF1F8E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF4CAF50).withAlpha(77)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 22),
              SizedBox(width: 8),
              Text(
                '导入完成',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _resultStat('解析出', '$_parsedCount', const Color(0xFF1565C0)),
              const SizedBox(width: 12),
              _resultStat('导入', '$_addedCount', const Color(0xFF2E7D32)),
              const SizedBox(width: 12),
              _resultStat('排重拒绝', '$_duplicatedCount', const Color(0xFFE65100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$value 题',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withAlpha(77)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _importError!,
              style: const TextStyle(fontSize: 13, color: Color(0xFFC62828)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPickerState() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload_file_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            Text(
              '请选择要导入的题库文件',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              '支持 .doc 和 .docx 格式',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTablesPanel(AppState app) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            child: Row(
              children: [
                const Icon(Icons.folder_open, color: Color(0xFF4A90E2), size: 20),
                const SizedBox(width: 8),
                const Text(
                  '已导入题库',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF333333),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A90E2).withAlpha(20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${app.tables.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A90E2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Table list
          Expanded(
            child: app.tables.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('暂无题库', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: app.tables.length,
                    itemBuilder: (ctx, i) {
                      final table = app.tables[i];
                      return _buildTableItem(context, app, table);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableItem(
    BuildContext context,
    AppState app,
    Map<String, dynamic> table,
  ) {
    final displayName = table['display_name'] as String? ?? table['table_name'] as String;
    final questionCount = table['question_count'] as int? ?? 0;
    final createdAt = table['created_at'] as String? ?? '';
    final dateStr = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF4A90E2).withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.quiz_outlined, color: Color(0xFF4A90E2), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '$questionCount 题 \u00b7 $dateStr',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$questionCount',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4CAF50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getFileColor(String? ext) {
    if (ext == 'docx') return const Color(0xFF2196F3);
    if (ext == 'doc') return const Color(0xFF4A90E2);
    return Colors.grey;
  }
}
