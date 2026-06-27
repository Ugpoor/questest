import 'dart:io';
import '../models/question.dart';

/// 文档解析服务
/// 支持 .docx 和 .doc 文件解析
class DocParserService {
  /// 解析文件，返回题目列表
  static Future<List<Question>> parseFile(String filePath, String tableName) async {
    if (filePath.endsWith('.docx')) {
      return _parseDocx(filePath, tableName);
    } else if (filePath.endsWith('.doc')) {
      return _parseDoc(filePath, tableName);
    } else {
      throw Exception('不支持的文件格式，仅支持 .docx 和 .doc');
    }
  }

  /// 解析 .docx 文件（通过 Python 脚本）
  static Future<List<Question>> _parseDocx(String filePath, String tableName) async {
    final result = await Process.run(
      'python3',
      [
        '-c',
        _pythonDocxParser,
        filePath,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception('DOCX解析失败: ${result.stderr}');
    }

    final jsonStr = result.stdout as String;
    return _parseExtractedText(jsonStr, tableName);
  }

  /// 解析 .doc 文件（通过 textutil 转换为文本再解析）
  static Future<List<Question>> _parseDoc(String filePath, String tableName) async {
    // 使用 macOS 内置 textutil 转换为纯文本
    final result = await Process.run(
      'textutil',
      ['-convert', 'txt', '-stdout', filePath],
    );

    if (result.exitCode != 0) {
      throw Exception('DOC解析失败: ${result.stderr}');
    }

    final text = (result.stdout as String).trim();
    return _parseExtractedText(text, tableName);
  }

  /// 从纯文本解析题目
  static List<Question> _parseExtractedText(String text, String tableName) {
    final questions = <Question>[];

    // 预处理：统一换行符
    final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final buffer = StringBuffer();
    bool inQuestion = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 检测题目编号（1. 2. 或 1、2、）
      if (_isQuestionStart(trimmed)) {
        if (buffer.isNotEmpty) {
          final parsed = _parseQuestionBlock(buffer.toString(), questions.length + 1, tableName);
          if (parsed != null) questions.add(parsed);
          buffer.clear();
        }
        buffer.write(trimmed);
        inQuestion = true;
      } else if (inQuestion) {
        buffer.write('\n');
        buffer.write(trimmed);
      }
    }

    // 处理最后一道题
    if (buffer.isNotEmpty) {
      final parsed = _parseQuestionBlock(buffer.toString(), questions.length + 1, tableName);
      if (parsed != null) questions.add(parsed);
    }

    return questions;
  }

  /// 判断是否是新题目的开始
  static bool _isQuestionStart(String line) {
    // 匹配：1. 2. 12. 或 1、 2、 或 1．2．
    final regex = RegExp(r'^[\u0000-\u007f]?[\d零一二三四五六七八九十百千万]+[.、．\s]');
    if (regex.hasMatch(line)) return true;
    // 匹配纯数字开头的题目
    if (RegExp(r'^\d{1,4}[\.\、\．\s]').hasMatch(line)) return true;
    return false;
  }

  /// 解析一个题目块
  static Question? _parseQuestionBlock(String block, int fallbackSeq, String tableName) {
    final lines = block.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.isEmpty) return null;

    // 第一行是题目内容
    final questionLine = lines.first;
    final content = questionLine.replaceFirst(RegExp(r'^[\d零一二三四五六七八九十百千万]+[\.\、\．\s]+'), '');

    if (content.isEmpty) return null;

    // 找选项（A. B. C. D. E.）
    final options = <QuestionOption>[];
    final optionRegex = RegExp(r'^([A-Ea-e])[.\．\s]+(.*)');
    final correctAnswers = <String>[];

    for (final line in lines) {
      final optMatch = optionRegex.firstMatch(line);
      if (optMatch != null) {
        final label = optMatch.group(1)!.toUpperCase();
        final optText = optMatch.group(2)!.trim();
        if (optText.isNotEmpty) {
          options.add(QuestionOption(label: label, text: optText));
        }
      }
    }

    // 找答案
    for (final line in lines) {
      final ansMatch = RegExp(r'答案\s*[:：]\s*([A-Za-e,，、]+)').firstMatch(line);
      if (ansMatch != null) {
        final ansStr = ansMatch.group(1)!;
        // 提取字母答案
        final letters = RegExp(r'[A-Ea-e]').allMatches(ansStr);
        for (final m in letters) {
          correctAnswers.add(m.group(0)!.toUpperCase());
        }
      }
    }

    // 找解析
    String? explanation;
    for (final line in lines) {
      final expMatch = RegExp(r'解析\s*[:：]\s*(.*)').firstMatch(line);
      if (expMatch != null) {
        explanation = expMatch.group(1)!.trim();
      }
    }

    if (options.isEmpty || correctAnswers.isEmpty) {
      // 尝试从内容中找答案（格式：...答案B）
      final inlineAns = RegExp(r'答案\s*([A-Ea-e])[\s\.\．]').firstMatch(block);
      if (inlineAns != null) {
        correctAnswers.add(inlineAns.group(1)!.toUpperCase());
      }
      if (options.isEmpty || correctAnswers.isEmpty) return null;
    }

    // 提取题号
    final seqMatch = RegExp(r'^([\d零一二三四五六七八九十百千万]+)[\.\、\．\s]').firstMatch(questionLine);
    int seq = fallbackSeq;
    if (seqMatch != null) {
      seq = _chineseToNumber(seqMatch.group(1)!);
    }

    return Question(
      tableName: tableName,
      seq: seq,
      content: content,
      options: options,
      correctAnswers: correctAnswers,
      explanation: explanation,
    );
  }

  /// 中文数字转整数
  static int _chineseToNumber(String s) {
    const map = {
      '零': 0, '一': 1, '二': 2, '三': 3, '四': 4,
      '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    };
    int result = 0;
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      result = result * 10 + (map[c] ?? int.tryParse(c) ?? 0);
    }
    return result > 0 ? result : 1;
  }

  // Python DOCX 解析脚本
  static const String _pythonDocxParser = r'''
import sys, zipfile, xml.etree.ElementTree as ET, re, json

def parse_docx(path):
    ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    texts = []
    with zipfile.ZipFile(path) as z:
        with z.open('word/document.xml') as f:
            tree = ET.parse(f)
            root = tree.getroot()
            paras = root.findall('.//w:p', ns)
            for p in paras:
                runs = p.findall('.//w:t', ns)
                line = ''.join(r.text or '' for r in runs).strip()
                if line:
                    texts.append(line)
    return '\n'.join(texts)

if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else ''
    if path:
        try:
            print(parse_docx(path))
        except Exception as e:
            print(f'ERROR: {e}', file=sys.stderr)
''';
}
