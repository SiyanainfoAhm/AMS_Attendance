import "package:flutter/foundation.dart";

import "../api/ams_api.dart";
import "auth_store.dart";

enum AuthStage {
  loading,
  loggedOut,
  needsCompany,
  ready,
}

class AuthController extends ChangeNotifier {
  final AmsApi _api;
  final AuthStore _store;

  AuthStage stage = AuthStage.loading;
  String? accessToken;
  String? refreshToken;
  String? companyId;
  String? mappedStaffId;

  List<AmsCompanySummary> companies = [];
  String? userDisplayName;
  String? userEmail;

  AuthController({AmsApi? api, AuthStore? store})
      : _api = api ?? AmsApi(),
        _store = store ?? AuthStore();

  Future<void> init() async {
    stage = AuthStage.loading;
    notifyListeners();

    accessToken = await _store.accessToken();
    refreshToken = await _store.refreshToken();
    companyId = await _store.companyId();

    if (refreshToken == null || refreshToken!.isEmpty) {
      stage = AuthStage.loggedOut;
      notifyListeners();
      return;
    }

    // Try to refresh to get a valid access token.
    try {
      final t = await _api.refresh(refreshToken: refreshToken!);
      accessToken = t.accessToken;
      refreshToken = t.refreshToken;
      await _store.saveTokens(accessToken: t.accessToken, refreshToken: t.refreshToken);
      if (companyId == null || companyId!.isEmpty) {
        stage = AuthStage.needsCompany;
      } else {
        // Ensure company context is set for this access token.
        // After refresh, the DB session may not have company selected even if we stored companyId locally.
        try {
          await _api.selectCompany(accessToken: t.accessToken, companyId: companyId!);
        } catch (_) {
          // If selection fails, force company re-select.
          companyId = null;
          mappedStaffId = null;
          stage = AuthStage.needsCompany;
          notifyListeners();
          return;
        }

        // If a company was previously selected, load /me so mappedStaffId is available
        // for punch/history after app restart. Retry once for eventual consistency.
        mappedStaffId = await _fetchMappedStaffIdWithRetry(t.accessToken);
        stage = AuthStage.ready;
      }
    } catch (_) {
      await _store.clear();
      accessToken = null;
      refreshToken = null;
      companyId = null;
      mappedStaffId = null;
      stage = AuthStage.loggedOut;
    }

    notifyListeners();
  }

  Future<String?> _fetchMappedStaffIdWithRetry(String accessToken) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final me = await _api.me(accessToken: accessToken);
        // If server says company not selected, we are not ready.
        if (me.companyId == null || me.companyId!.isEmpty) return null;
        return me.mappedStaffId;
      } catch (_) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          continue;
        }
        return null;
      }
    }
    return null;
  }

  /// Ensure we have mapped staff id for history/punch flows.
  /// Safe to call from screens right before hitting attendance APIs.
  Future<void> ensureReady() async {
    final at = accessToken;
    if (at == null || at.isEmpty) return;
    if (companyId == null || companyId!.isEmpty) return;
    if (mappedStaffId != null && mappedStaffId!.isNotEmpty) return;

    // Best effort: select company then call /me.
    try {
      await _api.selectCompany(accessToken: at, companyId: companyId!);
    } catch (_) {
      return;
    }
    mappedStaffId = await _fetchMappedStaffIdWithRetry(at);
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final r = await _api.login(email: email, password: password);
    accessToken = r.tokens.accessToken;
    refreshToken = r.tokens.refreshToken;
    companies = r.companies;
    userDisplayName = r.user.displayName;
    userEmail = r.user.email;

    await _store.saveTokens(accessToken: r.tokens.accessToken, refreshToken: r.tokens.refreshToken);
    await _store.saveUser(
      userId: r.user.id,
      displayName: r.user.displayName,
      email: r.user.email,
    );

    stage = AuthStage.needsCompany;
    notifyListeners();
  }

  Future<void> selectCompany(String companyId) async {
    final at = accessToken;
    if (at == null) throw AmsApiException("missing_access_token");
    await _api.selectCompany(accessToken: at, companyId: companyId);
    this.companyId = companyId;
    await _store.saveCompanyId(companyId);
    // After selecting company, fetch /me to learn mapped staff id (staff self-punch).
    mappedStaffId = await _fetchMappedStaffIdWithRetry(at);
    stage = AuthStage.ready;
    notifyListeners();
  }

  Future<void> logout() async {
    final at = accessToken;
    if (at != null && at.isNotEmpty) {
      try {
        // Best-effort: disable push token for this user/session.
        try {
          // Disable all tokens for this user; avoids relying on device token being available at logout time.
          await _api.pushTokenDisableAll(accessToken: at);
        } catch (_) {
          // ignore
        }

        await _api.logout(accessToken: at);
      } catch (_) {
        // ignore
      }
    }
    await _store.clear();
    accessToken = null;
    refreshToken = null;
    companyId = null;
    mappedStaffId = null;
    companies = [];
    stage = AuthStage.loggedOut;
    notifyListeners();
  }
}

