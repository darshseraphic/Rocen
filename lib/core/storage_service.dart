import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static const String boxName = 'captures';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(boxName);
  }

  static Box get box => Hive.box(boxName);
}