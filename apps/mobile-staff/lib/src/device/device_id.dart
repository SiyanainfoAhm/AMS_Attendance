import "dart:math";

import "../storage/secure_kv.dart";

class DeviceId {
  DeviceId._();

  static const _key = "ams.deviceId";

  static Future<String> getOrCreate() async {
    final existing = await SecureKv.read(_key);
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();

    // Good enough for device correlation in logs (not a security token).
    final rnd = Random.secure();
    final suffix = List<int>.generate(8, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, "0"))
        .join();
    final id = "dev-${DateTime.now().millisecondsSinceEpoch}-$suffix";
    await SecureKv.write(_key, id);
    return id;
  }
}

