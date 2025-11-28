import 'package:shared_preferences/shared_preferences.dart';
import 'package:scn/utils/test_config.dart';

/// Wrapper for SharedPreferences that adds test instance prefix
/// This allows test instances to have separate storage from main app
class TestStorage {
  static SharedPreferences? _prefs;
  
  static String _prefixKey(String key) {
    final prefix = TestConfig.current.storagePrefix;
    return '$prefix$key';
  }
  
  static Future<SharedPreferences> get instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }
  
  // String operations
  static Future<String?> getString(String key) async {
    final prefs = await instance;
    return prefs.getString(_prefixKey(key));
  }
  
  static Future<bool> setString(String key, String value) async {
    final prefs = await instance;
    return prefs.setString(_prefixKey(key), value);
  }
  
  // Int operations
  static Future<int?> getInt(String key) async {
    final prefs = await instance;
    return prefs.getInt(_prefixKey(key));
  }
  
  static Future<bool> setInt(String key, int value) async {
    final prefs = await instance;
    return prefs.setInt(_prefixKey(key), value);
  }
  
  // Bool operations
  static Future<bool?> getBool(String key) async {
    final prefs = await instance;
    return prefs.getBool(_prefixKey(key));
  }
  
  static Future<bool> setBool(String key, bool value) async {
    final prefs = await instance;
    return prefs.setBool(_prefixKey(key), value);
  }
  
  // Remove operation
  static Future<bool> remove(String key) async {
    final prefs = await instance;
    return prefs.remove(_prefixKey(key));
  }
  
  /// Clear all test instance data (only for test instances)
  static Future<void> clearTestData() async {
    if (!TestConfig.current.isTestMode) return;
    
    final prefs = await instance;
    final prefix = TestConfig.current.storagePrefix;
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

