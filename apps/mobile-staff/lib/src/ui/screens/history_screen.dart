import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../api/ams_api.dart";
import "../../auth/auth_controller.dart";
import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = AmsApi();
  bool _loading = true;
  String? _error;
  AmsAttendanceHistoryResult? _result;

  @override
  void initState() {
    super.initState();
    // Defer load until after first build so AuthController.init() can run.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    // In case init/refresh finished but mappedStaffId is still missing, try to repair session context.
    await auth.ensureReady();
    final at = auth.accessToken;
    final staffId = auth.mappedStaffId;
    if (at == null || staffId == null || staffId.isEmpty) {
      setState(() {
        _loading = false;
        _error = "Session not ready yet. If this persists, re-login and select company again.";
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final r = await _api.attendanceHistory(accessToken: at, staffId: staffId, page: 1, pageSize: 50);
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (e) {
      // Auto-heal expired sessions (401) by refreshing tokens, then retry once.
      if (e is AmsApiException && e.status == 401) {
        try {
          await auth.init();
          await auth.ensureReady();
          final at2 = auth.accessToken;
          final staffId2 = auth.mappedStaffId;
          if (at2 != null && staffId2 != null && staffId2.isNotEmpty) {
            final r2 = await _api.attendanceHistory(accessToken: at2, staffId: staffId2, page: 1, pageSize: 50);
            if (!mounted) return;
            setState(() {
              _result = r2;
              _loading = false;
            });
            return;
          }
        } catch (_) {
          // fall through
        }
      }
      setState(() {
        _error = "$e";
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AmsScaffold(
      title: "Attendance history",
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: "Refresh"),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AmsNotice(title: "Could not load history", message: _error, icon: Icons.error_outline, color: AmsTokens.danger),
                      const SizedBox(height: 12),
                      AmsPrimaryButton(label: "Retry", icon: Icons.refresh, onPressed: _load),
                    ],
                  ),
                )
              : _buildList(),
    );
  }

  Widget _buildList() {
    final items = _result?.items ?? const <AmsAttendanceLogItem>[];
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          children: [
            AmsCard(
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AmsTokens.brand.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.history, color: AmsTokens.brand, size: 28),
                  ),
                  const SizedBox(height: 12),
                  const Text("No punches yet", style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  const Text("Your attendance logs will appear here.", style: TextStyle(color: AmsTokens.muted)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final it = items[i];
        final type = it.punchType;
        final isIn = type == "in" || type == "break_in";
        final color = isIn ? AmsTokens.success : AmsTokens.warning;
        final icon = isIn ? Icons.login : Icons.logout;
        final title = type.replaceAll("_", " ").toUpperCase();
        return AmsCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text("At: ${it.punchAt}", style: const TextStyle(color: AmsTokens.muted)),
                    Text("Station: ${it.stationId}", style: const TextStyle(color: AmsTokens.muted)),
                    Text("Geofence: ${it.withinGeofence ?? "-"}", style: const TextStyle(color: AmsTokens.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text("#${i + 1}", style: const TextStyle(color: AmsTokens.muted, fontWeight: FontWeight.w700)),
            ],
          ),
        );
      },
    );
  }
}

