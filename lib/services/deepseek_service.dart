import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_service.dart';

class DeepSeekException implements Exception {
  final String message;
  const DeepSeekException(this.message);
  @override
  String toString() => message;
}

class DeepSeekService {
  static const _keyName = 'deepseek_api_token';
  static const _enabledKey = 'deepseek_ai_enabled';
  static const _base = 'https://api.deepseek.com';

  Future<bool> isAiEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setAiEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  Future<String?> token() => PlatformService.secureRead(_keyName);
  Future<void> deleteToken() => PlatformService.secureDelete(_keyName);

  Future<void> validateAndSave(String token) async {
    final value = token.trim();
    if (!value.startsWith('sk-') || value.length < 11) {
      throw const DeepSeekException('Token 格式不正确，应以 sk- 开头');
    }
    final response = await http
        .get(
          Uri.parse('$_base/models'),
          headers: {'Authorization': 'Bearer $value'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DeepSeekException('Token 验证失败（HTTP ${response.statusCode}）');
    }
    await PlatformService.secureWrite(_keyName, value);
  }

  Future<String> analyze({
    required String title,
    required String text,
    required String url,
  }) async {
    final key = await token();
    if (key == null || key.isEmpty) throw const DeepSeekException('尚未设置 Token');
    final content = text.length > 12000 ? '${text.substring(0, 12000)}…' : text;
    final response = await http
        .post(
          Uri.parse('$_base/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $key',
          },
          body: jsonEncode({
            'model': 'deepseek-v4-flash',
            'temperature': 0.2,
            'thinking': {'type': 'disabled'},
            'stream': false,
            'messages': [
              {
                'role': 'system',
                'content':
                    '你是赚客吧帖子阅读助手，只根据用户提供的标题和正文回答。\n'
                    '先判断楼主真正需要的是简短答案、操作步骤，还是长文总结。回答长度必须与问题复杂度匹配。\n'
                    '简单事实、是非或二选一问题：直接给答案和最关键的一句原因，通常1至3句话，目标不超过120字。\n'
                    '简单操作问题：直接给必要步骤，最多3步。普通求助：结论加必要原因，通常不超过250字。\n'
                    '只有长文、复杂规则、教程或资讯才做较完整总结，并按“一句话结论、重点内容、必要的风险或提醒、可以怎么做”组织。\n'
                    '不要复述标题和原文，不要写客套开场，不要为了完整格式强行补充背景、风险、提醒或建议，不要追加模板式结尾。\n'
                    '如果信息不足，用一句话指出缺少的关键条件。除非问题确实复杂，否则宁可短而准确。\n'
                    '不要使用 Markdown 格式。严禁输出 ###、**、-、*、``` 等符号。\n'
                    '不要使用加粗、标题标记、代码块或项目符号。\n'
                    '用普通中文段落输出。涉及编号时，每个编号必须单独换行，不要把 1、2、3 写在同一行。\n'
                    '需要分点时，使用“1. 2. 3.”这种纯文本编号，每一点独占一行。\n'
                    '语言简洁直接，保留真正相关的金额、时间、规则和风险。不能编造。',
              },
              {
                'role': 'user',
                'content': '帖子地址：$url\n\n标题：$title\n\n楼主正文：\n$content',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const DeepSeekException('Token 已失效，请长按 AI 按钮重新设置');
      }
      throw DeepSeekException('DeepSeek 请求失败（HTTP ${response.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    final answer =
        data['choices']?[0]?['message']?['content']?.toString().trim() ?? '';
    if (answer.isEmpty) throw const DeepSeekException('DeepSeek 没有返回可读内容');
    return answer
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll('**', '')
        .replaceAll('```', '')
        .trim();
  }
}
