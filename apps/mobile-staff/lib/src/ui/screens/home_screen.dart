import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "dart:async";
import "package:firebase_messaging/firebase_messaging.dart";

import "../../api/ams_api.dart";
import "../../auth/auth_controller.dart";
import "history_screen.dart";
import "punch_screen.dart";
import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";
import "stubs.dart";
import "support_screen.dart";
import "../../../main.dart";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _pushInitDone = false;
  AuthController? _authRef;
  StreamSubscription<RemoteMessage>? _subOnMessage;
  StreamSubscription<RemoteMessage>? _subOnMessageOpened;
  StreamSubscription<String>? _subOnTokenRefresh;
  String? _lastPushToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPushIfReady());
  }

  @override
  void dispose() {
    _subOnMessage?.cancel();
    _subOnMessageOpened?.cancel();
    _subOnTokenRefresh?.cancel();
    super.dispose();
  }

  Future<void> _initPushIfReady() async {
    if (_pushInitDone) return;
    final auth = context.read<AuthController>();
    _authRef = auth;
    final at = auth.accessToken;
    if (at == null || at.isEmpty) return;

    _pushInitDone = true;
    try {
      final messaging = FirebaseMessaging.instance;
      final perms = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (perms.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      _lastPushToken = token;
      await AmsApi().pushTokenUpsert(accessToken: at, token: token, platform: "android");

      // Foreground messages: show small banner + keep inbox fresh.
      _subOnMessage = FirebaseMessaging.onMessage.listen((m) {
        final title = m.notification?.title ?? "Notification";
        final body = m.notification?.body ?? "";
        final msg = body.isEmpty ? title : "$title • $body";
        final messenger = appMessengerKey.currentState;
        messenger?.showSnackBar(
          SnackBar(
            content: Text(msg),
            action: SnackBarAction(
              label: "Open",
              onPressed: () => appNavigatorKey.currentState?.push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
            ),
          ),
        );
      });

      // User tapped notification while app in background.
      _subOnMessageOpened = FirebaseMessaging.onMessageOpenedApp.listen((m) {
        routeFromRemoteMessage(m);
      });

      // Token rotation: re-register with backend.
      _subOnTokenRefresh = messaging.onTokenRefresh.listen((t) async {
        _lastPushToken = t;
        final at2 = _authRef?.accessToken;
        if (at2 == null || at2.isEmpty) return;
        try {
          await AmsApi().pushTokenUpsert(accessToken: at2, token: t, platform: "android");
        } catch (_) {
          // ignore
        }
      });

      // App launched via notification tap (terminated state).
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        // Delay slightly so navigator is ready.
        Future<void>.delayed(const Duration(milliseconds: 200), () => routeFromRemoteMessage(initial));
      }
    } catch (_) {
      // ignore; inbox will still work
    }
  }

  Future<void> _logoutWithPushCleanup() async {
    final auth = context.read<AuthController>();
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    final pages = [
      _Dashboard(auth: auth),
      const PunchScreen(),
      const HistoryScreen(),
      const ProfileScreen(),
    ];

    return AmsScaffold(
      title: "AMS Staff",
      actions: [
        IconButton(
          onPressed: () => _logoutWithPushCleanup(),
          icon: const Icon(Icons.logout),
          tooltip: "Logout",
        )
      ],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: "Home"),
          NavigationDestination(icon: Icon(Icons.fingerprint_outlined), selectedIcon: Icon(Icons.fingerprint), label: "Punch"),
          NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history), label: "History"),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: "Profile"),
        ],
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: pages[_tab],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final AuthController auth;

  const _Dashboard({required this.auth});

  @override
  Widget build(BuildContext context) {
    return _DashboardBody(auth: auth);
  }
}

class _DashboardBody extends StatefulWidget {
  final AuthController auth;

  const _DashboardBody({required this.auth});

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> with WidgetsBindingObserver {
  final _api = AmsApi();

  bool _loadingLastPunch = true;
  String? _lastPunchLabel;
  String? _lastPunchType;
  DateTime? _lastPunchAtLocal;
  bool _loadingToday = true;
  String? _nextAction;

  Timer? _ticker;
  DateTime _now = DateTime.now();

  int _notifUnread = 0;

  int _baseTotalSec = 0;
  int _baseBreakSec = 0;
  int _baseActiveSec = 0;
  DateTime? _baseAtLocal;
  String? _todayLastPunchType;
  DateTime? _snapshotAtLocal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadLastPunch();
      await _loadTodayTotals();
      await _refreshNotifUnread();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotifUnread();
    }
  }

  Future<void> _refreshNotifUnread() async {
    final auth = widget.auth;
    await auth.ensureReady();
    final at = auth.accessToken;
    if (at == null || at.isEmpty) return;
    try {
      final r = await _api.notificationsList(accessToken: at, page: 1, pageSize: 1, unreadOnly: true);
      if (!mounted) return;
      setState(() => _notifUnread = r.total);
    } catch (_) {
      // ignore; badge is best-effort
    }
  }

  Widget _notificationsButton() {
    final btn = AmsSecondaryButton(
      label: "Notifications",
      icon: Icons.notifications_outlined,
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
        await _refreshNotifUnread();
      },
    );

    if (_notifUnread <= 0) return btn;
    final countLabel = _notifUnread > 99 ? "99+" : "$_notifUnread";
    return Stack(
      clipBehavior: Clip.none,
      children: [
        btn,
        Positioned(
          right: 6,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AmsTokens.danger,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              countLabel,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadLastPunch() async {
    final auth = widget.auth;
    await auth.ensureReady();

    final at = auth.accessToken;
    final staffId = auth.mappedStaffId;
    if (at == null || staffId == null || staffId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loadingLastPunch = false;
        _lastPunchLabel = "—";
      });
      return;
    }

    try {
      final r = await _api.attendanceHistory(accessToken: at, staffId: staffId, page: 1, pageSize: 1);
      final it = r.items.isNotEmpty ? r.items.first : null;
      final label = it == null ? "—" : _formatPunchLabel(it.punchType, it.punchAt);
      if (!mounted) return;
      setState(() {
        _loadingLastPunch = false;
        _lastPunchLabel = label;
        _lastPunchType = it?.punchType;
        _lastPunchAtLocal = DateTime.tryParse(it?.punchAt ?? "")?.toLocal();
      });
      _rebaseUsingPunchTimeIfPossible();
    } catch (e) {
      // Auto-heal expired sessions (401) by refreshing tokens, then retry once.
      if (e is AmsApiException && e.status == 401) {
        try {
          await auth.init();
          await auth.ensureReady();
          final at2 = auth.accessToken;
          final staffId2 = auth.mappedStaffId;
          if (at2 != null && staffId2 != null && staffId2.isNotEmpty) {
            final r2 = await _api.attendanceHistory(accessToken: at2, staffId: staffId2, page: 1, pageSize: 1);
            final it2 = r2.items.isNotEmpty ? r2.items.first : null;
            final label2 = it2 == null ? "—" : _formatPunchLabel(it2.punchType, it2.punchAt);
            if (!mounted) return;
            setState(() {
              _loadingLastPunch = false;
              _lastPunchLabel = label2;
              _lastPunchType = it2?.punchType;
              _lastPunchAtLocal = DateTime.tryParse(it2?.punchAt ?? "")?.toLocal();
            });
            _rebaseUsingPunchTimeIfPossible();
            return;
          }
        } catch (_) {
          // fall through
        }
      }
      if (!mounted) return;
      setState(() {
        _loadingLastPunch = false;
        _lastPunchLabel = "—";
        _lastPunchType = null;
        _lastPunchAtLocal = null;
      });
    }
  }

  String _formatPunchLabel(String punchType, String punchAt) {
    final t = punchType.toUpperCase();
    final dt = DateTime.tryParse(punchAt);
    if (dt == null) return "$t • $punchAt";

    // API timestamps are typically UTC (e.g. ...Z). Convert to device-local time for display.
    final local = dt.toLocal();
    final hh = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final mm = local.minute.toString().padLeft(2, "0");
    final ampm = local.hour >= 12 ? "PM" : "AM";
    return "$t • $hh:$mm $ampm";
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
    // Filter to local-calendar-day punches (client display semantics).
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

  String _computeNextActionFromLast(String? lastPunchType) {
    switch ((lastPunchType ?? "").trim()) {
      case "":
        return "Punch IN";
      case "in":
        return "Punch OUT / Break IN";
      case "break_in":
        return "Break OUT / Punch OUT";
      case "break_out":
        return "Punch OUT / Break IN";
      case "out":
      default:
        return "Punch IN";
    }
  }

  Future<void> _loadTodayTotals() async {
    final auth = widget.auth;
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

      // Keep the server rollup minutes for fallback display/consistency, but compute
      // live seconds from punch timestamps so sub-minute durations aren't shown as 0.
      final rHist = await _api.attendanceHistory(accessToken: at, staffId: staffId, page: 1, pageSize: 200);
      final nowLocal = DateTime.now();
      final computed = _computeTodayFromPunches(rHist.items, nowLocal);

      setState(() {
        _loadingToday = false;
        _todayLastPunchType = row?.lastPunchType ?? computed.lastPunchType;
        _nextAction = _computeNextActionFromLast(_todayLastPunchType);

        _baseTotalSec = computed.totalClosedSec;
        _baseBreakSec = computed.breakClosedSec;
        _baseActiveSec = computed.activeClosedSec;

        // If there's an open segment, tick from its start; otherwise tick from now but no segment will add.
        _baseAtLocal = computed.openStartLocal ?? nowLocal;
        _snapshotAtLocal = nowLocal;
      });

      // Backward-compatible rebase (uses last punch time) in case history paging missed something.
      _rebaseUsingPunchTimeIfPossible();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingToday = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final auth = widget.auth;
    final trimmed = auth.userDisplayName?.trim() ?? "";
    final name = trimmed.isEmpty ? "Staff" : trimmed;
    final company = (auth.companyName ?? "").trim().isNotEmpty ? auth.companyName!.trim() : (auth.companyId ?? "—");

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        AmsCard(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AmsTokens.brand, Color(0xFF312E81)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Hi, $name", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text(
                      "${now.day}/${now.month}/${now.year} • ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}",
                      style: const TextStyle(color: Color(0xCCFFFFFF)),
                    ),
                    const SizedBox(height: 10),
                    Text("Company: $company", style: const TextStyle(color: Color(0xCCFFFFFF))),
                  ],
                ),
              ),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.verified_user_outlined, color: Colors.white),
              )
            ],
          ),
        ),
        const SizedBox(height: 14),
        const AmsSectionHeader(
          title: "Today",
          subtitle: "Quick overview",
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: AmsCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AmsTokens.success.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.login, color: AmsTokens.success, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Last punch", style: TextStyle(color: AmsTokens.muted)),
                          const SizedBox(height: 2),
                          Text(
                            _loadingLastPunch ? "Loading…" : (_lastPunchLabel ?? "—"),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AmsCard(
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
                      child: const Icon(Icons.my_location_outlined, color: AmsTokens.brand, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Active hours", style: TextStyle(color: AmsTokens.muted)),
                          const SizedBox(height: 2),
                          Text(
                            _loadingToday ? "Loading…" : _fmtSeconds(_liveActiveSec()),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _miniMetric(icon: Icons.work_outline, label: "Total", value: _loadingToday ? "…" : _fmtSeconds(_liveTotalSec()))),
            const SizedBox(width: 10),
            Expanded(child: _miniMetric(icon: Icons.coffee_outlined, label: "Break", value: _loadingToday ? "…" : _fmtSeconds(_liveBreakSec()))),
          ],
        ),
        const SizedBox(height: 10),
        AmsCard(
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AmsTokens.brand.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.playlist_add_check_circle_outlined, color: AmsTokens.brand, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Next action", style: TextStyle(color: AmsTokens.muted)),
                    const SizedBox(height: 2),
                    Text(_nextAction ?? "—", style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        AmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AmsSectionHeader(title: "Quick actions", subtitle: "Most used"),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AmsPrimaryButton(
                      label: "Punch now",
                      icon: Icons.fingerprint,
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PunchScreen()));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _notificationsButton(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AmsSecondaryButton(
                label: "Audit",
                icon: Icons.fact_check_outlined,
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuditResponseScreen()));
                },
              ),
              const SizedBox(height: 10),
              AmsSecondaryButton(
                label: "Settings & help",
                icon: Icons.help_outline,
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupportScreen()));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget _miniMetric({required IconData icon, required String label, required String value}) {
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

