import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/question.dart';

/// LLM 智能分类服务
/// 调用内置 LLM API 对题目进行维度归类（API 已内置，无需用户配置）
class LlmClassifyService {
  // 内置 LLM API 配置（不可修改）
  static const String _apiBaseUrl =
      'https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1';
  static const String _apiKey =
      'sk-sp-djI.QeproBpO2ETcfp1xL-WDC-RpOqV_IyiZ1F17hNtLdml0Udkz0yrABWjYgRordHPCsML-LrziIDX7Wz9jX3rL5LJ-wxNDsi2ctgTaOplV6psCTFWjhWg9SCMCe86MU_9e.MEYCIQDhcoKuUskddlZGhZ_ECWMxK5McO7fg2r_n_Q5F1yCTswIhAIDuZfg47wDD7OIlKVE9Y6wiDftGs7pDMgjMlkxQ1eFI';
  static const String _modelName = 'qwen3.7-plus';

  static bool get isConfigured => true;

  /// 使用 LLM 批量归类题目
  /// dimensions: 用户定义的维度列表（最多3个）
  /// 返回 Map<questionSeq, {dim1, dim2, dim3}>
  static Future<Map<int, Map<String, String?>>> classifyQuestions({
    required List<Question> questions,
    required List<String> dimensions,
    int batchSize = 10,
  }) async {
    if (!isConfigured || dimensions.isEmpty) {
      return {};
    }

    final results = <int, Map<String, String?>>{};
    final batches = _chunk(questions, batchSize);

    for (final batch in batches) {
      try {
        final classified = await _classifyBatch(batch, dimensions);
        results.addAll(classified);
      } catch (e) {
        // 批次失败，标记为未分类
        for (final q in batch) {
          results[q.seq] = {for (var d in dimensions) d: null};
        }
      }
      // 避免请求过快
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return results;
  }

  static Future<Map<int, Map<String, String?>>> _classifyBatch(
    List<Question> batch,
    List<String> dimensions,
  ) async {
    final prompt = _buildClassifyPrompt(batch, dimensions);
    final response = await _callLlm(prompt);
    return _parseLlmResponse(response, batch, dimensions);
  }

  static String _buildClassifyPrompt(List<Question> batch, List<String> dimensions) {
    final dimStr = dimensions.asMap().entries.map((e) => 'dim${e.key + 1}: ${e.value}').join(', ');
    final questionsStr = batch.map((q) {
      final opts = q.options.map((o) => '${o.label}. ${o.text}').join(' | ');
      return 'Q${q.seq}: ${q.content} ($opts)';
    }).join('\n');

    return '''
你是一个题目分类专家。请根据以下维度对每道题目标注标签。

维度定义：
$dimStr

题目列表：
$questionsStr

请以 JSON 格式返回，格式为：
{
  "results": [
    {"seq": 题号, "dim1": "标签1", "dim2": "标签2", "dim3": "标签3"}
  ]
}

要求：
- 每个维度的标签应简洁（不超过10个字符）
- 仅从题目内容和选项推断标签，不要臆造
- 如果某题无法归入某个维度，该维度标签填 null
- 只输出 JSON，不要有任何额外文字
''';
  }

  static Future<String> _callLlm(String prompt) async {
    final url = Uri.parse('${_apiBaseUrl.replaceAll(RegExp(r'/$'), '')}/chat/completions');
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_apiKey',
    };

    final body = jsonEncode({
      'model': _modelName,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.3,
      'max_tokens': 2000,
    });

    final resp = await http.post(url, headers: headers, body: body);
    if (resp.statusCode != 200) {
      throw Exception('LLM API 错误: ${resp.statusCode} - ${resp.body}');
    }

    final data = jsonDecode(resp.body);
    return data['choices'][0]['message']['content'] as String;
  }

  static Map<int, Map<String, String?>> _parseLlmResponse(
    String response,
    List<Question> batch,
    List<String> dimensions,
  ) {
    final results = <int, Map<String, String?>>{};

    // 提取 JSON 部分
    String jsonStr = response;
    final jsonStart = response.indexOf('{');
    final jsonEnd = response.lastIndexOf('}');
    if (jsonStart >= 0 && jsonEnd > jsonStart) {
      jsonStr = response.substring(jsonStart, jsonEnd + 1);
    }

    try {
      final data = jsonDecode(jsonStr);
      final resultsList = data['results'] as List;
      for (final item in resultsList) {
        final seq = item['seq'] as int;
        results[seq] = {
          for (int i = 0; i < dimensions.length; i++)
            dimensions[i]: item['dim${i + 1}'] as String?,
        };
      }
    } catch (e) {
      // 解析失败，返回空
      for (final q in batch) {
        results[q.seq] = {for (var d in dimensions) d: null};
      }
    }

    return results;
  }

  /// 基于关键词的本地快速分类（无 LLM 时使用）
  static Map<int, Map<String, String?>> localClassifyByKeywords({
    required List<Question> questions,
    required List<String> dimensions,
  }) {
    // 维度关键词映射
    final keywordsMap = <String, List<String>>{};
    for (final dim in dimensions) {
      keywordsMap[dim] = _extractKeywords(dim);
    }

    final results = <int, Map<String, String?>>{};
    for (final q in questions) {
      final result = <String, String?>{};
      final fullText = q.content + q.options.map((o) => o.text).join(' ');
      for (final dim in dimensions) {
        result[dim] = _matchKeyword(fullText, keywordsMap[dim] ?? []);
      }
      results[q.seq] = result;
    }
    return results;
  }

  static List<String> _extractKeywords(String dim) {
    // 基于维度名称推断关键词
    final dimLower = dim.toLowerCase();
    if (dimLower.contains('难度') || dimLower.contains('难易')) {
      return ['复杂', '困难', '简单', '基础', '进阶', '高级'];
    }
    if (dimLower.contains('类型') || dimLower.contains('题型')) {
      return ['选择', '判断', '填空', '计算', '概念', '应用'];
    }
    if (dimLower.contains('章节') || dimLower.contains('模块')) {
      return ['第一章', '第二章', '第三', '第四', '第五'];
    }
    // 默认：取维度名中的每个字作为关键词
    return dim.split('').where((c) => RegExp(r'[\u4e00-\u9fa5]').hasMatch(c)).toList();
  }

  static String? _matchKeyword(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return kw;
    }
    return null;
  }

  static List<List<Question>> _chunk(List<Question> list, int size) {
    final chunks = <List<Question>>[];
    for (int i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }
}
