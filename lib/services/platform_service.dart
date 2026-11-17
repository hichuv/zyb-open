import 'package:flutter/services.dart';

class PlatformService {
  static const _channel = MethodChannel('zybapp/platform');

  static Future<List<String>> pickImages() async =>
      (await _channel.invokeListMethod<String>('pickImages')) ?? const [];

  static Future<void> secureWrite(String key, String value) =>
      _channel.invokeMethod('secureWrite', {'key': key, 'value': value});

  static Future<String?> secureRead(String key) =>
      _channel.invokeMethod<String>('secureRead', {'key': key});

  static Future<void> secureDelete(String key) =>
      _channel.invokeMethod('secureDelete', {'key': key});
}
