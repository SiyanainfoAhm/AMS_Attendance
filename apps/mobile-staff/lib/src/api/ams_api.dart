import "dart:convert";

import "package:http/http.dart" as http;

import "../config/app_config.dart";

class AmsApiException implements Exception {
  final String message;
  final int? status;
  AmsApiException(this.message, {this.status});

  @override
  String toString() => "AmsApiException(status=$status, message=$message)";
}

class AmsSessionTokens {
  final String accessToken;
  final String refreshToken;

  AmsSessionTokens({required this.accessToken, required this.refreshToken});
}

class AmsUserSummary {
  final String id;
  final String displayName;
  final String email;

  AmsUserSummary({required this.id, required this.displayName, required this.email});
}

class AmsCompanySummary {
  final String id;
  final String code;
  final String name;

  AmsCompanySummary({required this.id, required this.code, required this.name});
}

class AmsLoginResult {
  final AmsUserSummary user;
  final List<AmsCompanySummary> companies;
  final AmsSessionTokens tokens;

  AmsLoginResult({required this.user, required this.companies, required this.tokens});
}

class AmsMeResult {
  final String userId;
  final String? companyId;
  final String? mappedStaffId;
  final List<String> permissions;
  final bool isPlatformSuperAdmin;

  AmsMeResult({
    required this.userId,
    required this.companyId,
    required this.mappedStaffId,
    required this.permissions,
    required this.isPlatformSuperAdmin,
  });
}

class AmsPunchResult {
  final String id;
  final String punchAt;
  final String shiftDate;

  AmsPunchResult({required this.id, required this.punchAt, required this.shiftDate});
}

class AmsAttendanceLogItem {
  final String id;
  final String staffId;
  final String stationId;
  final String? deviceId;
  final String punchType;
  final String punchAt;
  final bool? withinGeofence;

  AmsAttendanceLogItem({
    required this.id,
    required this.staffId,
    required this.stationId,
    required this.deviceId,
    required this.punchType,
    required this.punchAt,
    required this.withinGeofence,
  });
}

class AmsAttendanceHistoryResult {
  final List<AmsAttendanceLogItem> items;
  final int page;
  final int pageSize;
  final int total;

  AmsAttendanceHistoryResult({required this.items, required this.page, required this.pageSize, required this.total});
}

class AmsDailyAttendanceRow {
  final String shiftDate;
  final String staffId;
  final String? staffCode;
  final String? fullName;
  final String? stationId;
  final String? stationCode;
  final String? stationName;
  final String? lastPunchType;
  final int totalWorkMinutes;
  final int totalBreakMinutes;
  final int totalActiveMinutes;
  final bool missingOut;
  final bool missingBreakOut;

  AmsDailyAttendanceRow({
    required this.shiftDate,
    required this.staffId,
    required this.staffCode,
    required this.fullName,
    required this.stationId,
    required this.stationCode,
    required this.stationName,
    required this.lastPunchType,
    required this.totalWorkMinutes,
    required this.totalBreakMinutes,
    required this.totalActiveMinutes,
    required this.missingOut,
    required this.missingBreakOut,
  });
}

class AmsDailyAttendanceReportResult {
  final List<AmsDailyAttendanceRow> items;
  final int refreshed;

  AmsDailyAttendanceReportResult({required this.items, required this.refreshed});
}

class AmsAuditCase {
  final String id;
  final String caseType;
  final String status;
  final String? shiftDate;
  final String title;
  final String? description;
  final Map<String, dynamic> payload;
  final String createdAt;
  final String? resolvedAt;

  AmsAuditCase({
    required this.id,
    required this.caseType,
    required this.status,
    required this.shiftDate,
    required this.title,
    required this.description,
    required this.payload,
    required this.createdAt,
    required this.resolvedAt,
  });
}

class AmsAuditListResult {
  final int generated;
  final List<AmsAuditCase> items;

  AmsAuditListResult({required this.generated, required this.items});
}

class AmsSupportTicket {
  final String id;
  final String ticketCode;
  final String title;
  final String? description;
  final String priority;
  final String status;
  final String openedAt;
  final String? dueBy;
  final String? closedAt;
  final String? openedBy;

  AmsSupportTicket({
    required this.id,
    required this.ticketCode,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.openedAt,
    required this.dueBy,
    required this.closedAt,
    required this.openedBy,
  });
}

class AmsSupportListResult {
  final List<AmsSupportTicket> items;
  final int page;
  final int pageSize;
  final int total;

  AmsSupportListResult({required this.items, required this.page, required this.pageSize, required this.total});
}

class AmsNotificationItem {
  final String id;
  final String type;
  final String title;
  final String? body;
  final String status;
  final String channel;
  final String priority;
  final Map<String, dynamic> payload;
  final String createdAt;
  final String? readAt;

  AmsNotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.status,
    required this.channel,
    required this.priority,
    required this.payload,
    required this.createdAt,
    required this.readAt,
  });
}

class AmsNotificationsListResult {
  final List<AmsNotificationItem> items;
  final int page;
  final int pageSize;
  final int total;

  AmsNotificationsListResult({required this.items, required this.page, required this.pageSize, required this.total});
}

class AmsStationSummary {
  final String id;
  final String code;
  final String name;
  final double? latitude;
  final double? longitude;
  final double? radiusM;
  final String? geofenceName;

  AmsStationSummary({
    required this.id,
    required this.code,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.geofenceName,
  });
}

Map<String, String> _gatewayHeaders() {
  final anon = AppConfig.supabaseAnonKey();
  return {
    "apikey": anon,
    "authorization": "Bearer $anon",
  };
}

Uri _fn(String path, [Map<String, String>? query]) {
  final base = AppConfig.functionsBaseUrl().replaceAll(RegExp(r"/+$"), "");
  final uri = Uri.parse("$base/$path");
  return query == null ? uri : uri.replace(queryParameters: query);
}

dynamic _readJson(http.Response res) {
  try {
    return jsonDecode(res.body);
  } catch (_) {
    return null;
  }
}

String _amsUserFacingError(Map<String, dynamic> json) {
  final err = json["error"];
  final details = json["details"];
  final errStr = err == null ? "" : "$err";
  final detStr = details == null ? "" : "$details";

  if (errStr == "out_without_in" || detStr.contains("out_without_in")) {
    return "Punch OUT requires a prior punch IN.";
  }
  if (errStr == "out_not_same_company_day_as_in" || detStr.contains("out_not_same_company_day_as_in")) {
    return "Use Punch OUT to close the open session from the previous day first.";
  }

  if (errStr == "invalid_session" || errStr == "missing_access_token") {
    return "Session expired. Sign in again.";
  }

  if (errStr == "forbidden") {
    return "You don’t have permission for this action.";
  }

  if (details != null) return "$details";
  if (err != null) return "$err";
  return "request_failed";
}

void _throwIfNotOk(http.Response res, dynamic json) {
  if (res.statusCode >= 200 && res.statusCode < 300) return;
  if (json is Map<String, dynamic>) {
    throw AmsApiException(_amsUserFacingError(json), status: res.statusCode);
  }
  final body = res.body.trim();
  final snippet = body.isEmpty ? null : (body.length > 300 ? body.substring(0, 300) : body);
  throw AmsApiException(snippet ?? "request_failed", status: res.statusCode);
}

class AmsApi {
  Future<AmsLoginResult> login({required String email, required String password}) async {
    final res = await http.post(
      _fn("auth-login"),
      headers: {..._gatewayHeaders(), "content-type": "application/json"},
      body: jsonEncode({"email": email, "password": password, "clientType": "mobile"}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);

    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final userJson = result["user"] as Map<String, dynamic>;
    final sessionJson = result["session"] as Map<String, dynamic>;
    final companiesJson = (result["companies"] as List<dynamic>).cast<Map<String, dynamic>>();

    return AmsLoginResult(
      user: AmsUserSummary(
        id: "${userJson["id"]}",
        displayName: "${userJson["display_name"]}",
        email: "${userJson["email"]}",
      ),
      companies: companiesJson
          .map(
            (c) => AmsCompanySummary(
              id: "${c["id"]}",
              code: "${c["code"]}",
              name: "${c["name"]}",
            ),
          )
          .toList(),
      tokens: AmsSessionTokens(
        accessToken: "${sessionJson["access_token"]}",
        refreshToken: "${sessionJson["refresh_token"]}",
      ),
    );
  }

  Future<void> selectCompany({required String accessToken, required String companyId}) async {
    final res = await http.post(
      _fn("select-company"),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({"companyId": companyId}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<AmsMeResult> me({required String accessToken}) async {
    final res = await http.get(
      _fn("me"),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final session = result["session"] as Map<String, dynamic>;
    final userJson = result["user"] as Map<String, dynamic>?;
    final platformRaw = userJson?["is_platform_super_admin"];
    final isPlatform = platformRaw == true || platformRaw == "true";
    final permissions = (result["permissions"] as List<dynamic>? ?? []).map((x) => "$x").toList();
    return AmsMeResult(
      userId: "${session["user_id"]}",
      companyId: session["company_id"] == null ? null : "${session["company_id"]}",
      mappedStaffId: result["mappedStaffId"] == null ? null : "${result["mappedStaffId"]}",
      permissions: permissions,
      isPlatformSuperAdmin: isPlatform,
    );
  }

  Future<AmsPunchResult> punch({
    required String accessToken,
    required String staffId,
    required String punchType,
    String? stationId,
    String? deviceId,
    bool? withinGeofence,
  }) async {
    final res = await http.post(
      _fn("company-attendance", {"action": "punch"}),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({
        "staffId": staffId,
        "punchType": punchType,
        if (stationId != null) "stationId": stationId,
        if (deviceId != null) "deviceId": deviceId,
        if (withinGeofence != null) "withinGeofence": withinGeofence,
      }),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    return AmsPunchResult(
      id: "${result["id"]}",
      punchAt: "${result["punch_at"]}",
      shiftDate: "${result["shift_date"]}",
    );
  }

  Future<AmsAttendanceHistoryResult> attendanceHistory({
    required String accessToken,
    required String staffId,
    int page = 1,
    int pageSize = 50,
  }) async {
    final res = await http.get(
      _fn("company-attendance", {
        "page": "$page",
        "pageSize": "$pageSize",
        "staffId": staffId,
      }),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final items = (result["items"] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>()
        .map(
          (it) => AmsAttendanceLogItem(
            id: "${it["id"]}",
            staffId: "${it["ams_staff_id"]}",
            stationId: "${it["ams_station_id"]}",
            deviceId: it["ams_device_id"] == null ? null : "${it["ams_device_id"]}",
            punchType: "${it["punch_type"]}",
            punchAt: "${it["punch_at"]}",
            withinGeofence: it["within_geofence"] == null ? null : (it["within_geofence"] as bool),
          ),
        )
        .toList();

    return AmsAttendanceHistoryResult(
      items: items,
      page: (result["page"] as num?)?.toInt() ?? page,
      pageSize: (result["pageSize"] as num?)?.toInt() ?? pageSize,
      total: (result["total"] as num?)?.toInt() ?? items.length,
    );
  }

  Future<List<AmsStationSummary>> stationsMeta({required String accessToken}) async {
    final res = await http.get(
      _fn("company-attendance", {"page": "1", "pageSize": "1", "include": "meta"}),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final meta = (result["meta"] as Map<String, dynamic>?);
    final stations = (meta?["stations"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return stations
        .map(
          (s) => AmsStationSummary(
            id: "${s["id"]}",
            code: "${s["code"]}",
            name: "${s["name"]}",
            latitude: (s["latitude"] as num?)?.toDouble(),
            longitude: (s["longitude"] as num?)?.toDouble(),
            radiusM: (s["radiusM"] as num?)?.toDouble(),
            geofenceName: s["geofenceName"] == null ? null : "${s["geofenceName"]}",
          ),
        )
        .toList();
  }

  Future<AmsDailyAttendanceReportResult> dailyAttendanceReport({
    required String accessToken,
    required String from,
    required String to,
    String? staffId,
    String? stationId,
  }) async {
    final q = <String, String>{"report": "daily_attendance", "from": from, "to": to};
    if (staffId != null) q["staffId"] = staffId;
    if (stationId != null) q["stationId"] = stationId;
    final res = await http.get(
      _fn("company-reports", q),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final inner = (result["result"] is Map<String, dynamic>) ? (result["result"] as Map<String, dynamic>) : result;
    final refreshed = (inner["refreshed"] as num?)?.toInt() ?? 0;
    final itemsJson = (inner["items"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final items = itemsJson
        .map(
          (r) => AmsDailyAttendanceRow(
            shiftDate: "${r["shift_date"]}",
            staffId: "${r["staff_id"]}",
            staffCode: r["staff_code"] == null ? null : "${r["staff_code"]}",
            fullName: r["full_name"] == null ? null : "${r["full_name"]}",
            stationId: r["station_id"] == null ? null : "${r["station_id"]}",
            stationCode: r["station_code"] == null ? null : "${r["station_code"]}",
            stationName: r["station_name"] == null ? null : "${r["station_name"]}",
            lastPunchType: r["last_punch_type"] == null ? null : "${r["last_punch_type"]}",
            totalWorkMinutes: (r["total_work_minutes"] as num?)?.toInt() ?? 0,
            totalBreakMinutes: (r["total_break_minutes"] as num?)?.toInt() ?? 0,
            totalActiveMinutes: (r["total_active_minutes"] as num?)?.toInt() ?? 0,
            missingOut: (r["missing_out"] as bool?) ?? false,
            missingBreakOut: (r["missing_break_out"] as bool?) ?? false,
          ),
        )
        .toList();
    return AmsDailyAttendanceReportResult(items: items, refreshed: refreshed);
  }

  Future<AmsAuditListResult> staffAuditList({
    required String accessToken,
    String status = "open",
    int limit = 50,
  }) async {
    final q = <String, String>{"status": status, "limit": "${limit.clamp(1, 200)}"};
    final res = await http.get(
      _fn("staff-audit", q),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final inner = (result["result"] is Map<String, dynamic>) ? (result["result"] as Map<String, dynamic>) : result;
    final generated = (inner["generated"] as num?)?.toInt() ?? 0;
    final itemsJson = (inner["items"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final items = itemsJson
        .map(
          (r) => AmsAuditCase(
            id: "${r["id"]}",
            caseType: "${r["case_type"]}",
            status: "${r["status"]}",
            shiftDate: r["shift_date"] == null ? null : "${r["shift_date"]}",
            title: "${r["title"]}",
            description: r["description"] == null ? null : "${r["description"]}",
            payload: (r["payload_json"] is Map<String, dynamic>) ? (r["payload_json"] as Map<String, dynamic>) : <String, dynamic>{},
            createdAt: "${r["created_at"]}",
            resolvedAt: r["resolved_at"] == null ? null : "${r["resolved_at"]}",
          ),
        )
        .toList();
    return AmsAuditListResult(generated: generated, items: items);
  }

  Future<AmsSupportListResult> supportTicketList({
    required String accessToken,
    int page = 1,
    int pageSize = 25,
    String? status,
    String? from,
    String? to,
  }) async {
    final q = <String, String>{
      "page": "$page",
      "pageSize": "${pageSize.clamp(1, 100)}",
    };
    if (status != null && status.isNotEmpty) q["status"] = status;
    if (from != null && from.isNotEmpty) q["from"] = from;
    if (to != null && to.isNotEmpty) q["to"] = to;
    final res = await http.get(
      _fn("company-support", q),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final itemsJson = (result["items"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final items = itemsJson
        .map(
          (t) => AmsSupportTicket(
            id: "${t["id"]}",
            ticketCode: "${t["ticket_code"]}",
            title: "${t["title"]}",
            description: t["description"] == null ? null : "${t["description"]}",
            priority: "${t["priority"]}",
            status: "${t["status"]}",
            openedAt: "${t["opened_at"]}",
            dueBy: t["due_by"] == null ? null : "${t["due_by"]}",
            closedAt: t["closed_at"] == null ? null : "${t["closed_at"]}",
            openedBy: t["opened_by"] == null ? null : "${t["opened_by"]}",
          ),
        )
        .toList();
    return AmsSupportListResult(
      items: items,
      page: (result["page"] as num?)?.toInt() ?? page,
      pageSize: (result["pageSize"] as num?)?.toInt() ?? pageSize,
      total: (result["total"] as num?)?.toInt() ?? items.length,
    );
  }

  Future<void> supportTicketCreate({
    required String accessToken,
    required String title,
    String? description,
    String priority = "medium",
  }) async {
    final res = await http.post(
      _fn("company-support", {"action": "create"}),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({
        "title": title,
        if (description != null && description.isNotEmpty) "description": description,
        "priority": priority,
      }),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<void> supportTicketSetStatus({
    required String accessToken,
    required String id,
    required String status,
  }) async {
    final res = await http.post(
      _fn("company-support", {"action": "set-status"}),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({"id": id, "status": status}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<void> pushTokenUpsert({
    required String accessToken,
    required String token,
    String? platform,
    String? deviceId,
  }) async {
    final res = await http.post(
      _fn("push-token"),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({
        "token": token,
        if (platform != null && platform.isNotEmpty) "platform": platform,
        if (deviceId != null && deviceId.isNotEmpty) "deviceId": deviceId,
      }),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<void> pushTokenDisable({required String accessToken, required String token}) async {
    final res = await http.post(
      _fn("push-token", {"action": "disable"}),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({"token": token}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<void> pushTokenDisableAll({required String accessToken}) async {
    final res = await http.post(
      _fn("push-token", {"action": "disable-all"}),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<AmsNotificationsListResult> notificationsList({
    required String accessToken,
    int page = 1,
    int pageSize = 25,
    bool unreadOnly = false,
  }) async {
    final q = <String, String>{
      "page": "$page",
      "pageSize": "${pageSize.clamp(1, 100)}",
      if (unreadOnly) "unread": "1",
    };
    final res = await http.get(
      _fn("notifications", q),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final itemsJson = (result["items"] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final items = itemsJson
        .map(
          (n) => AmsNotificationItem(
            id: "${n["id"]}",
            type: "${n["notif_type"]}",
            title: "${n["title"]}",
            body: n["body"] == null ? null : "${n["body"]}",
            status: "${n["status"]}",
            channel: "${n["channel"]}",
            priority: "${n["priority"]}",
            payload: (n["payload_json"] is Map<String, dynamic>) ? (n["payload_json"] as Map<String, dynamic>) : <String, dynamic>{},
            createdAt: "${n["created_at"]}",
            readAt: n["read_at"] == null ? null : "${n["read_at"]}",
          ),
        )
        .toList();
    return AmsNotificationsListResult(
      items: items,
      page: (result["page"] as num?)?.toInt() ?? page,
      pageSize: (result["pageSize"] as num?)?.toInt() ?? pageSize,
      total: (result["total"] as num?)?.toInt() ?? items.length,
    );
  }

  Future<void> notificationsMarkRead({required String accessToken, required String id}) async {
    final res = await http.post(
      _fn("notifications", {"action": "mark-read"}),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({"id": id}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<void> notificationsMarkAllRead({required String accessToken}) async {
    final res = await http.post(
      _fn("notifications", {"action": "mark-all-read"}),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<void> staffAuditSubmitResponse({
    required String accessToken,
    required String caseId,
    required String responseText,
  }) async {
    final res = await http.post(
      _fn("staff-audit"),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-access-token": accessToken},
      body: jsonEncode({"caseId": caseId, "responseText": responseText}),
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }

  Future<AmsSessionTokens> refresh({required String refreshToken}) async {
    final res = await http.post(
      _fn("auth-refresh"),
      headers: {..._gatewayHeaders(), "content-type": "application/json", "x-ams-refresh-token": refreshToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
    final result = (json as Map<String, dynamic>)["result"] as Map<String, dynamic>;
    final sessionJson = result["session"] as Map<String, dynamic>;
    return AmsSessionTokens(
      accessToken: "${sessionJson["access_token"]}",
      refreshToken: "${sessionJson["refresh_token"]}",
    );
  }

  Future<void> logout({required String accessToken}) async {
    final res = await http.post(
      _fn("auth-logout"),
      headers: {..._gatewayHeaders(), "x-ams-access-token": accessToken},
    );
    final json = _readJson(res);
    _throwIfNotOk(res, json);
  }
}

