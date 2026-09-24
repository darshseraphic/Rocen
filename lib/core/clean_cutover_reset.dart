import 'package:hive_flutter/hive_flutter.dart';

/// One-time clean-cutover cleanup for disposable development data.
///
/// This is deliberately a reset, not a migration: obsolete protected-data
/// boxes and legacy security keys are destroyed rather than interpreted.
class CleanCutoverReset {
  CleanCutoverReset._();

  static const String _capturesBox = 'rocen_captures_box';
  static const String _todosBox = 'rocen_todos_box';
  static const String _settingsBox = 'rocen_settings_box';
  static const String _completionKey = 'block_b_clean_cutover_completed_v1';

  static const Set<String> _obsoleteSettingsKeys = <String>{
    'system_crypto_pin',
    'last_active_crypto_pin_snapshot',
    'github_access_encrypted',
    'device_key_owned_repo',
    'hw_wrapped_pin',
    'kdf_hardened',
  };

  /// Returns true only after all obsolete persistent stores/keys are confirmed
  /// deleted. Any failure is a hard startup failure for the clean cutover.
  static Future<bool> run({
    Future<void> Function(String boxName)? deleteBox,
  }) async {
    final Future<void> Function(String) deleter =
        deleteBox ?? Hive.deleteBoxFromDisk;
    try {
      final Box settings = Hive.box(_settingsBox);
      if (settings.get(_completionKey) == true) {
        for (final String key in _obsoleteSettingsKeys) {
          if (settings.containsKey(key)) return false;
        }
        if (settings.keys.any(
            (dynamic key) => key.toString().startsWith('hw_key_tier_'))) {
          return false;
        }
        return true;
      }

      for (final String boxName in <String>[_capturesBox, _todosBox]) {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
        }
        await deleter(boxName);
      }

      for (final String key in _obsoleteSettingsKeys) {
        if (settings.containsKey(key)) {
          await settings.delete(key);
        }
      }

      final List<dynamic> remainingObsoleteKeys = settings.keys
          .where((dynamic key) => key.toString().startsWith('hw_key_tier_'))
          .toList(growable: false);
      for (final dynamic key in remainingObsoleteKeys) {
        await settings.delete(key);
      }

      for (final String key in _obsoleteSettingsKeys) {
        if (settings.containsKey(key)) return false;
      }
      if (settings.keys.any(
          (dynamic key) => key.toString().startsWith('hw_key_tier_'))) {
        return false;
      }

      await settings.put(_completionKey, true);
      if (settings.get(_completionKey) != true) return false;
      return true;
    } catch (_) {
      return false;
    }
  }
}
