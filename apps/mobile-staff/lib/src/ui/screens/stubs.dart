import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "dart:async";
import "package:firebase_messaging/firebase_messaging.dart";

import "../../api/ams_api.dart";
import "../../auth/auth_controller.dart";
import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";
import "support_screen.dart";

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _api = AmsApi();
  bool _loading = true;
  String? _error;
  List<AmsNotificationItem> _items = const [];
  int _page = 1;
  final int _pageSize = 25;
  int _total = 0;
  bool _unreadOnly = true;
  AuthorizationStatus? _authz;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final s = await FirebaseMessaging.instance.getNotificationSettings();
        if (mounted) setState(() => _authz = s.authorizationStatus);
      } catch (_) {
        // ignore
      }
      await _load(reset: true);
    });
  }

  Future<void> _load({required bool reset}) async {
    final auth = context.read<AuthController>();
    await auth.ensureReady();
    final at = auth.accessToken;
    if (at == null || at.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Missing access token";
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        if (reset) _page = 1;
      });
    }

    try {
      final res = await _api.notificationsList(accessToken: at, page: _page, pageSize: _pageSize, unreadOnly: _unreadOnly);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = res.items;
        _total = res.total;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is AmsApiException ? e.message : "$e";
      });
    }
  }

  Future<void> _markAllRead() async {
    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    if (at == null || at.isEmpty) return;
    try {
      await _api.notificationsMarkAllRead(accessToken: at);
      await _load(reset: true);
    } catch (_) {
      // ignore
    }
  }

  Future<void> _markRead(String id) async {
    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    if (at == null || at.isEmpty) return;
    try {
      await _api.notificationsMarkRead(accessToken: at, id: id);
      if (!mounted) return;
      setState(() {
        _items = _items.map((x) => x.id == id ? AmsNotificationItem(
          id: x.id,
          type: x.type,
          title: x.title,
          body: x.body,
          status: "read",
          channel: x.channel,
          priority: x.priority,
          payload: x.payload,
          createdAt: x.createdAt,
          readAt: DateTime.now().toUtc().toIso8601String(),
        ) : x).toList();
      });
    } catch (_) {
      // ignore
    }
  }

  String _fmtTs(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final l = dt.toLocal();
    return "${l.year}-${l.month.toString().padLeft(2, "0")}-${l.day.toString().padLeft(2, "0")} "
        "${l.hour.toString().padLeft(2, "0")}:${l.minute.toString().padLeft(2, "0")}";
  }

  @override
  Widget build(BuildContext context) {
    return AmsScaffold(
      title: "Notifications",
      actions: [
        IconButton(
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh),
          tooltip: "Refresh",
        ),
        IconButton(
          onPressed: _loading ? null : _markAllRead,
          icon: const Icon(Icons.done_all),
          tooltip: "Mark all read",
        ),
      ],
      child: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          children: [
            if (_authz == AuthorizationStatus.denied) ...[
              AmsNotice(
                title: "Notifications are disabled",
                message: "Enable notifications in phone settings to receive push alerts. Inbox will still work when you open the app.",
                icon: Icons.notifications_off_outlined,
                color: AmsTokens.warning,
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    value: _unreadOnly,
                    onChanged: _loading
                        ? null
                        : (v) {
                            setState(() => _unreadOnly = v);
                            _load(reset: true);
                          },
                    title: const Text("Unread only"),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 10),
                Text("$_total", style: const TextStyle(color: AmsTokens.muted)),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              AmsNotice(title: "Failed to load", message: _error, icon: Icons.error_outline, color: AmsTokens.danger),
            ],
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text("No notifications", style: TextStyle(color: AmsTokens.muted))),
              )
            else
              ..._items.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AmsCard(
                    onTap: n.readAt == null ? () => _markRead(n.id) : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                            if (n.readAt == null)
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: AmsTokens.brand,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (n.body != null && n.body!.isNotEmpty)
                          Text(n.body!, style: const TextStyle(color: AmsTokens.muted, height: 1.3)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(_fmtTs(n.createdAt), style: const TextStyle(color: AmsTokens.muted, fontSize: 12)),
                            const Spacer(),
                            Text(n.type, style: const TextStyle(color: AmsTokens.muted, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LeaveRequestScreen extends StatelessWidget {
  const LeaveRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AmsScaffold(
      title: "Leave request",
      child: Center(child: Text("Leave requests coming soon.")),
    );
  }
}

class AuditResponseScreen extends StatefulWidget {
  const AuditResponseScreen({super.key});

  @override
  State<AuditResponseScreen> createState() => _AuditResponseScreenState();
}

class _AuditResponseScreenState extends State<AuditResponseScreen> {
  final _api = AmsApi();
  bool _loading = true;
  String? _error;
  List<AmsAuditCase> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    await auth.ensureReady();
    final at = auth.accessToken;
    if (at == null || at.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Missing access token";
      });
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final r = await _api.staffAuditList(accessToken: at, status: "open", limit: 100);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = r.items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "$e";
      });
    }
  }

  String _fmtDate(String yyyyMmDd) {
    final dt = DateTime.tryParse(yyyyMmDd);
    if (dt == null) return yyyyMmDd;
    final local = dt.toLocal();
    return "${local.day.toString().padLeft(2, "0")}/${local.month.toString().padLeft(2, "0")}/${local.year}";
  }

  String _typeLabel(String t) {
    switch (t) {
      case "missing_out":
        return "Missing OUT";
      case "missing_break_out":
        return "Missing Break OUT";
      default:
        return t;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmsScaffold(
      title: "Audit",
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: "Refresh",
        )
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AmsSectionHeader(title: "Pending audits", subtitle: "Please respond to resolve issues"),
            const SizedBox(height: 10),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!, style: const TextStyle(color: AmsTokens.danger))))
            else if (_items.isEmpty)
              const Expanded(child: Center(child: Text("No pending audits.")))
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = _items[i];
                    final date = c.shiftDate == null ? null : _fmtDate(c.shiftDate!);
                    return AmsCard(
                      child: ListTile(
                        leading: const Icon(Icons.report_outlined, color: AmsTokens.brand),
                        title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Text([_typeLabel(c.caseType), if (date != null) date].join(" • ")),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => _AuditCaseDetailScreen(auditCase: c)),
                          );
                          await _load();
                        },
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AuditCaseDetailScreen extends StatefulWidget {
  final AmsAuditCase auditCase;

  const _AuditCaseDetailScreen({required this.auditCase});

  @override
  State<_AuditCaseDetailScreen> createState() => _AuditCaseDetailScreenState();
}

class _AuditCaseDetailScreenState extends State<_AuditCaseDetailScreen> {
  final _api = AmsApi();
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = "Response is required");
      return;
    }

    final auth = context.read<AuthController>();
    await auth.ensureReady();
    final at = auth.accessToken;
    if (at == null || at.isEmpty) {
      setState(() => _error = "Missing access token");
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _api.staffAuditSubmitResponse(accessToken: at, caseId: widget.auditCase.id, responseText: text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = "$e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.auditCase;
    return AmsScaffold(
      title: "Audit response",
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          AmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(c.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 8),
                if ((c.description ?? "").trim().isNotEmpty) Text(c.description!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text("Your response", style: TextStyle(color: AmsTokens.muted)),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  minLines: 3,
                  maxLines: 8,
                  decoration: InputDecoration(
                    hintText: "Explain what happened…",
                    errorText: _error,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                AmsPrimaryButton(
                  label: _submitting ? "Submitting…" : "Submit response",
                  icon: Icons.send,
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = AmsApi();
  String _lastPunch = "—";
  bool _loadingLastPunch = true;
  String? _lastPunchType;
  DateTime? _lastPunchAtLocal;
  bool _loadingToday = true;

  Timer? _ticker;
  DateTime _now = DateTime.now();

  int _baseTotalSec = 0;
  int _baseBreakSec = 0;
  int _baseActiveSec = 0;
  DateTime? _baseAtLocal;
  String? _todayLastPunchType;
  DateTime? _snapshotAtLocal;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadLastPunch();
      await _loadTodayTotals();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadLastPunch() async {
    final auth = context.read<AuthController>();
    await auth.ensureReady();
    final at = auth.accessToken;
    final staffId = auth.mappedStaffId;
    if (at == null || staffId == null || staffId.isEmpty) {
      if (!mounted) return;
      setState(() => _loadingLastPunch = false);
      return;
    }

    try {
      final r = await _api.attendanceHistory(accessToken: at, staffId: staffId, page: 1, pageSize: 1);
      final it = r.items.isNotEmpty ? r.items.first : null;
      final dt = DateTime.tryParse(it?.punchAt ?? "")?.toLocal();
      final t = it?.punchType.toUpperCase();
      final label = (dt == null || t == null)
          ? "—"
          : "$t • ${(dt.hour % 12 == 0 ? 12 : dt.hour % 12)}:${dt.minute.toString().padLeft(2, "0")} ${dt.hour >= 12 ? "PM" : "AM"}";
      if (!mounted) return;
      setState(() {
        _lastPunch = label;
        _loadingLastPunch = false;
        _lastPunchType = it?.punchType;
        _lastPunchAtLocal = dt;
      });
      _rebaseUsingPunchTimeIfPossible();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLastPunch = false);
    }
  }

  String _fmtSeconds(int s) {
    final ss = s < 0 ? 0 : s;
    final h = ss ~/ 3600;
    final m = (ss % 3600) ~/ 60;
    final r = ss % 60;
    return "${h}h ${m.toString().padLeft(2, "0")}m ${r.toString().padLeft(2, "0")}s";
  }

  int _elapsedSinceBaseSec() {
    final baseAt = _baseAtLocal;
    if (baseAt == null) return 0;
    final d = _now.difference(baseAt).inSeconds;
    return d < 0 ? 0 : d;
  }

  String _modeForPunchType(String? t) {
    final v = (t ?? "").trim();
    if (v == "break_in") return "break";
    if (v == "in" || v == "break_out") return "work";
    return "none";
  }

  void _rebaseUsingPunchTimeIfPossible() {
    if (!mounted) return;
    if (_loadingToday) return;
    final snapshotAt = _snapshotAtLocal;
    final punchAt = _lastPunchAtLocal;
    final punchType = _todayLastPunchType ?? _lastPunchType;
    if (snapshotAt == null || punchAt == null) return;

    final mode = _modeForPunchType(punchType);
    if (mode == "none") return;

    final elapsed = snapshotAt.difference(punchAt).inSeconds;
    if (elapsed <= 0) return;

    setState(() {
      if (mode == "work") {
        _baseTotalSec = (_baseTotalSec - elapsed).clamp(0, 1 << 30);
        _baseActiveSec = (_baseActiveSec - elapsed).clamp(0, 1 << 30);
      } else if (mode == "break") {
        _baseTotalSec = (_baseTotalSec - elapsed).clamp(0, 1 << 30);
        _baseBreakSec = (_baseBreakSec - elapsed).clamp(0, 1 << 30);
      }
      _baseAtLocal = punchAt;
    });
  }

  int _liveTotalSec() {
    final base = _baseTotalSec;
    if (_loadingToday) return base;
    final mode = _modeForPunchType(_todayLastPunchType);
    if (mode == "work" || mode == "break") return base + _elapsedSinceBaseSec();
    return base;
  }

  int _liveBreakSec() {
    final base = _baseBreakSec;
    if (_loadingToday) return base;
    if (_modeForPunchType(_todayLastPunchType) != "break") return base;
    return base + _elapsedSinceBaseSec();
  }

  int _liveActiveSec() {
    final base = _baseActiveSec;
    if (_loadingToday) return base;
    if (_modeForPunchType(_todayLastPunchType) != "work") return base;
    return base + _elapsedSinceBaseSec();
  }

  ({int totalClosedSec, int breakClosedSec, int activeClosedSec, DateTime? openStartLocal, String? lastPunchType}) _computeTodayFromPunches(
    List<AmsAttendanceLogItem> items,
    DateTime todayLocal,
  ) {
    final dayItems = items.where((it) {
      final dt = DateTime.tryParse(it.punchAt)?.toLocal();
      if (dt == null) return false;
      return dt.year == todayLocal.year && dt.month == todayLocal.month && dt.day == todayLocal.day;
    }).toList();

    dayItems.sort((a, b) {
      final da = DateTime.tryParse(a.punchAt)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = DateTime.tryParse(b.punchAt)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
      return da.compareTo(db);
    });

    int totalClosed = 0;
    int breakClosed = 0;
    int activeClosed = 0;
    DateTime? openWorkStart;
    DateTime? openBreakStart;
    String? lastType;

    for (final it in dayItems) {
      final t = it.punchType.trim();
      final at = DateTime.tryParse(it.punchAt)?.toLocal();
      if (at == null) continue;
      lastType = t;

      if (t == "in") {
        openWorkStart = at;
        openBreakStart = null;
        continue;
      }
      if (t == "break_in") {
        final ws = openWorkStart;
        if (ws != null) {
          final d = at.difference(ws).inSeconds;
          if (d > 0) {
            totalClosed += d;
            activeClosed += d;
          }
        }
        openWorkStart = null;
        openBreakStart = at;
        continue;
      }
      if (t == "break_out") {
        final bs = openBreakStart;
        if (bs != null) {
          final d = at.difference(bs).inSeconds;
          if (d > 0) {
            totalClosed += d;
            breakClosed += d;
          }
        }
        openBreakStart = null;
        openWorkStart = at;
        continue;
      }
      if (t == "out") {
        final ws = openWorkStart;
        if (ws != null) {
          final d = at.difference(ws).inSeconds;
          if (d > 0) {
            totalClosed += d;
            activeClosed += d;
          }
        }
        final bs = openBreakStart;
        if (bs != null) {
          final d = at.difference(bs).inSeconds;
          if (d > 0) {
            totalClosed += d;
            breakClosed += d;
          }
        }
        openWorkStart = null;
        openBreakStart = null;
        continue;
      }
    }

    DateTime? openStart;
    if (openWorkStart != null) openStart = openWorkStart;
    if (openBreakStart != null) openStart = openBreakStart;

    return (totalClosedSec: totalClosed, breakClosedSec: breakClosed, activeClosedSec: activeClosed, openStartLocal: openStart, lastPunchType: lastType);
  }

  Future<void> _loadTodayTotals() async {
    final auth = context.read<AuthController>();
    await auth.ensureReady();
    final at = auth.accessToken;
    final staffId = auth.mappedStaffId;
    if (at == null || staffId == null || staffId.isEmpty) {
      if (!mounted) return;
      setState(() => _loadingToday = false);
      return;
    }
    final now = DateTime.now();
    final today =
        "${now.year.toString().padLeft(4, "0")}-${now.month.toString().padLeft(2, "0")}-${now.day.toString().padLeft(2, "0")}";
    try {
      final rep = await _api.dailyAttendanceReport(accessToken: at, from: today, to: today, staffId: staffId);
      final row = rep.items.isNotEmpty ? rep.items.first : null;
      if (!mounted) return;

      final rHist = await _api.attendanceHistory(accessToken: at, staffId: staffId, page: 1, pageSize: 200);
      final nowLocal = DateTime.now();
      final computed = _computeTodayFromPunches(rHist.items, nowLocal);

      setState(() {
        _loadingToday = false;
        _todayLastPunchType = row?.lastPunchType ?? computed.lastPunchType;

        _baseTotalSec = computed.totalClosedSec;
        _baseBreakSec = computed.breakClosedSec;
        _baseActiveSec = computed.activeClosedSec;

        _baseAtLocal = computed.openStartLocal ?? nowLocal;
        _snapshotAtLocal = nowLocal;
      });

      _rebaseUsingPunchTimeIfPossible();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingToday = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final trimmedName = auth.userDisplayName?.trim() ?? "";
    final name = trimmedName.isEmpty ? "Staff" : trimmedName;
    final email = auth.userEmail ?? "—";
    final company = auth.companyId ?? "—";
    final staffId = auth.mappedStaffId ?? "—";

    return AmsScaffold(
      title: "Profile",
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          AmsCard(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AmsTokens.brand, Color(0xFF312E81)],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.person_outline, color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(email, style: const TextStyle(color: Color(0xCCFFFFFF))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const AmsSectionHeader(title: "Work details", subtitle: "Your current context"),
          const SizedBox(height: 10),
          AmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _kv("Company", company),
                const Divider(height: 22, color: AmsTokens.border),
                _kv("Mapped staff ID", staffId),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const AmsSectionHeader(title: "Attendance snapshot", subtitle: "Quick view"),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metric(icon: Icons.work_outline, label: "Total", value: _loadingToday ? "Loading…" : _fmtSeconds(_liveTotalSec()))),
              const SizedBox(width: 10),
              Expanded(child: _metric(icon: Icons.timer_outlined, label: "Last punch", value: _loadingLastPunch ? "Loading…" : _lastPunch)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metric(icon: Icons.coffee_outlined, label: "Break", value: _loadingToday ? "Loading…" : _fmtSeconds(_liveBreakSec()))),
              const SizedBox(width: 10),
              Expanded(child: _metric(icon: Icons.bolt_outlined, label: "Active", value: _loadingToday ? "Loading…" : _fmtSeconds(_liveActiveSec()))),
            ],
          ),
          const SizedBox(height: 14),
          const AmsSectionHeader(title: "Account", subtitle: "Support & security"),
          const SizedBox(height: 10),
          AmsCard(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline, color: AmsTokens.brand),
                  title: const Text("Help & support"),
                  subtitle: const Text("FAQs, contact, app info"),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen()));
                  },
                ),
                const Divider(height: 1, color: AmsTokens.border),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined, color: AmsTokens.brand),
                  title: const Text("Notifications"),
                  subtitle: const Text("Updates and reminders"),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
                  },
                ),
                const Divider(height: 1, color: AmsTokens.border),
                ListTile(
                  leading: const Icon(Icons.logout, color: AmsTokens.danger),
                  title: const Text("Logout"),
                  subtitle: const Text("Sign out from this device"),
                  onTap: () => context.read<AuthController>().logout(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _kv(String k, String v) {
  return Row(
    children: [
      Expanded(child: Text(k, style: const TextStyle(color: AmsTokens.muted))),
      const SizedBox(width: 12),
      Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
    ],
  );
}

Widget _metric({required IconData icon, required String label, required String value}) {
  return AmsCard(
    padding: const EdgeInsets.all(14),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AmsTokens.brand.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AmsTokens.brand, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AmsTokens.muted)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    ),
  );
}

