import "../storage/secure_kv.dart";

class AuthStoreKeys {
  static const accessToken = "ams.accessToken";
  static const refreshToken = "ams.refreshToken";
  static const companyId = "ams.companyId";
  static const userId = "ams.userId";
  static const userDisplayName = "ams.userDisplayName";
  static const userEmail = "ams.userEmail";
}

class AuthStore {
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await SecureKv.write(AuthStoreKeys.accessToken, accessToken);
    await SecureKv.write(AuthStoreKeys.refreshToken, refreshToken);
  }

  Future<void> saveUser({
    required String userId,
    required String displayName,
    required String email,
  }) async {
    await SecureKv.write(AuthStoreKeys.userId, userId);
    await SecureKv.write(AuthStoreKeys.userDisplayName, displayName);
    await SecureKv.write(AuthStoreKeys.userEmail, email);
  }

  Future<void> saveCompanyId(String companyId) => SecureKv.write(AuthStoreKeys.companyId, companyId);

  Future<String?> accessToken() => SecureKv.read(AuthStoreKeys.accessToken);
  Future<String?> refreshToken() => SecureKv.read(AuthStoreKeys.refreshToken);
  Future<String?> companyId() => SecureKv.read(AuthStoreKeys.companyId);

  Future<void> clear() => SecureKv.deleteAll();
}

