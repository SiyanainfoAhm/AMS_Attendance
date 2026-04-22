import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "dart:typed_data";

import "../../api/ams_api.dart";
import "../../auth/auth_controller.dart";
import "../../device/device_id.dart";
import "../../location/location_service.dart";
import "face_auto_capture_screen.dart";
import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";

class PunchScreen extends StatefulWidget {
  const PunchScreen({super.key});

  @override
  State<PunchScreen> createState() => _PunchScreenState();
}

class _PunchScreenState extends State<PunchScreen> {
  final _api = AmsApi();
  final _loc = LocationService();
  String _punchType = "in";
  String? _lastPunchType;
  /// ISO time of latest punch (for calendar-day check vs strict sequence).
  String? _lastPunchAt;
  bool _loadingLastPunchType = false;
  String? _selectedStationId;
  List<AmsStationSummary> _stations = const [];
  bool _loadingStations = false;
  bool _gpsLoading = false;
  String? _deviceId;
  Uint8List? _faceBytes;
  bool _faceLoading = false;

  LocationResult? _location;
  double? _distanceM;

  String? _error;
  AmsPunchResult? _result;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStations());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDeviceId());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLastPunchType());
  }

  Future<void> _loadLastPunchType() async {
    final auth = context.read<AuthController>();
    await auth.ensureReady();
    final at = auth.accessToken;
    final staffId = auth.mappedStaffId;
    if (at == null || staffId == null || staffId.isEmpty) return;

    if (mounted) setState(() => _loadingLastPunchType = true);
    try {
      final r = await _api.attendanceHistory(accessToken: at, staffId: staffId, page: 1, pageSize: 1);
      final it = r.items.isNotEmpty ? r.items.first : null;
      if (!mounted) return;
      setState(() {
        _lastPunchType = it?.punchType;
        _lastPunchAt = it?.punchAt;
        final allowed = _allowedPunchTypes();
        if (!allowed.contains(_punchType)) _punchType = allowed.first;
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
            final r2 = await _api.attendanceHistory(accessToken: at2, staffId: staffId2, page: 1, pageSize: 1);
            final it2 = r2.items.isNotEmpty ? r2.items.first : null;
            if (!mounted) return;
            setState(() {
              _lastPunchType = it2?.punchType;
              _lastPunchAt = it2?.punchAt;
              final allowed = _allowedPunchTypes();
              if (!allowed.contains(_punchType)) _punchType = allowed.first;
            });
            return;
          }
        } catch (_) {
          // fall through
        }
      }
    } finally {
      if (mounted) setState(() => _loadingLastPunchType = false);
    }
  }

  /// True if the latest punch is from an earlier **local** calendar day than today.
  /// Then we start a new IN→OUT shift today (missed OUT on old days stays in reporting/audit).
  bool _lastPunchIsBeforeTodayLocal() {
    final iso = _lastPunchAt;
    if (iso == null || iso.isEmpty) return false;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return false;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final punchDay = DateTime(dt.year, dt.month, dt.day);
    return punchDay.isBefore(today);
  }

  Future<void> _submitPunch() async {
    final auth = context.read<AuthController>();

    Future<AmsPunchResult> doPunch(String token, String staffIdStr) async {
      final st = _selectedStation();
      final radiusConfigured =
          st != null && st.latitude != null && st.longitude != null && (st.radiusM ?? 0) > 0;
      final radiusVal = (st?.radiusM ?? 0).toDouble();
      final within = (_distanceM == null || !radiusConfigured) ? null : (_distanceM! <= radiusVal);
      return _api.punch(
        accessToken: token,
        staffId: staffIdStr,
        punchType: _punchType,
        stationId: _selectedStationId,
        deviceId: _isUuid(_deviceId) ? _deviceId : null,
        withinGeofence: within,
      );
    }

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      var token = auth.accessToken;
      var staffIdStr = auth.mappedStaffId;
      if (token == null || staffIdStr == null || staffIdStr.isEmpty) {
        if (mounted) setState(() => _error = "Not signed in.");
        return;
      }

      late AmsPunchResult r;
      try {
        r = await doPunch(token, staffIdStr);
      } on AmsApiException catch (e) {
        if (e.status != 401) rethrow;
        await auth.init();
        await auth.ensureReady();
        token = auth.accessToken;
        staffIdStr = auth.mappedStaffId;
        if (token == null || staffIdStr == null || staffIdStr.isEmpty) {
          if (mounted) setState(() => _error = "Session expired. Please sign in again.");
          return;
        }
        r = await doPunch(token, staffIdStr);
      }

      if (!mounted) return;
      setState(() {
        _result = r;
        _lastPunchType = _punchType;
        _lastPunchAt = r.punchAt;
        final allowed = _allowedPunchTypes();
        if (!allowed.contains(_punchType)) _punchType = allowed.first;
      });
      _loadLastPunchType();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is AmsApiException ? e.message : "$e");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> _allowedPunchTypes() {
    final last = (_lastPunchType ?? "").trim();
    if (last.isEmpty) return const ["in"];

    // Stale open session from a past day (e.g. IN on 17th, no OUT, today is 20th) → today’s punch is IN.
    if (_lastPunchIsBeforeTodayLocal()) {
      return const ["in"];
    }

    switch (last) {
      case "in":
        return const ["out", "break_in"];
      case "break_in":
        return const ["break_out", "out"];
      case "out":
        return const ["in"];
      case "break_out":
        // Break is finished; user is still "in" the work session.
        return const ["out", "break_in"];
      default:
        return const ["in"];
    }
  }

  String _punchLabel(String t) {
    switch (t) {
      case "in":
        return "IN";
      case "out":
        return "OUT";
      case "break_in":
        return "Break IN";
      case "break_out":
        return "Break OUT";
      default:
        return t;
    }
  }

  Future<void> _captureFace() async {
    if (_faceLoading) return;
    setState(() {
      _faceLoading = true;
      _error = null;
    });
    try {
      final res = await Navigator.of(context).push<FaceAutoCaptureResult>(
        MaterialPageRoute(builder: (_) => const FaceAutoCaptureScreen()),
      );
      final bytes = res?.bytes;
      if (bytes == null) {
        if (!mounted) return;
        setState(() => _faceLoading = false);
        return;
      }
      if (!mounted) return;
      setState(() {
        _faceBytes = bytes;
        _faceLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _faceLoading = false;
        _error = "$e";
      });
    }
  }

  void _removeFace() {
    setState(() => _faceBytes = null);
  }

  Future<void> _loadDeviceId() async {
    try {
      final id = await DeviceId.getOrCreate();
      if (!mounted) return;
      setState(() => _deviceId = id);
    } catch (_) {
      // Not critical for punch; omit device id if storage fails.
    }
  }

  AmsStationSummary? _selectedStation() {
    for (final s in _stations) {
      if (s.id == _selectedStationId) return s;
    }
    return null;
  }

  String _accuracyLabel(double? m) {
    if (m == null) return "Unknown";
    if (m <= 20) return "Good";
    if (m <= 50) return "OK";
    return "Poor";
  }

  String _fmtLocalTime(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final hh = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final mm = dt.minute.toString().padLeft(2, "0");
    final ampm = dt.hour >= 12 ? "PM" : "AM";
    return "$hh:$mm $ampm";
  }

  String _fmtLocalDate(String isoOrDate) {
    final dt = DateTime.tryParse(isoOrDate);
    if (dt == null) return isoOrDate;
    final local = dt.toLocal();
    return "${local.day.toString().padLeft(2, "0")}/${local.month.toString().padLeft(2, "0")}/${local.year}";
  }

  bool _isUuid(String? v) {
    if (v == null) return false;
    final s = v.trim();
    final re = RegExp(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");
    return re.hasMatch(s);
  }

  Future<void> _loadStations() async {
    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    if (at == null) return;
    setState(() {
      _loadingStations = true;
      _error = null;
    });
    try {
      final s = await _api.stationsMeta(accessToken: at);
      setState(() {
        _stations = s;
        if (_selectedStationId == null && s.isNotEmpty) _selectedStationId = s.first.id;
      });
      await _refreshDistance();
    } catch (e) {
      setState(() => _error = "$e");
    } finally {
      if (mounted) setState(() => _loadingStations = false);
    }
  }

  Future<void> _refreshDistance() async {
    final st = _selectedStation();
    if (st == null || st.latitude == null || st.longitude == null) {
      setState(() {
        _location = null;
        _distanceM = null;
      });
      return;
    }
    try {
      if (mounted) {
        setState(() {
          _gpsLoading = true;
          _error = null;
        });
      }
      final loc = await _loc.getCurrentLocation();
      final d = _loc.distanceM(fromLat: loc.latitude, fromLng: loc.longitude, toLat: st.latitude!, toLng: st.longitude!);
      setState(() {
        _location = loc;
        _distanceM = d;
        _gpsLoading = false;
      });
    } catch (e) {
      setState(() {
        // Keep last known location/distance if any; don't wipe it while GPS refresh fails.
        _gpsLoading = false;
        _error = "$e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final at = auth.accessToken;
    final staffId = auth.mappedStaffId;
    final st = _selectedStation();
    final geofenceConfigured = st != null && st.latitude != null && st.longitude != null;
    final radiusVal = (st?.radiusM ?? 0).toDouble();
    final radiusConfigured = radiusVal > 0;

    if (staffId == null || staffId.isEmpty) {
      return AmsScaffold(
        title: "Punch attendance",
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmsNotice(
                title: "Account not linked",
                message: "Your login user is not mapped to a staff record.\nAsk admin to link this login user to staff.",
                icon: Icons.link_off_outlined,
                color: AmsTokens.warning,
              ),
              const SizedBox(height: 14),
              AmsSecondaryButton(label: "Back", icon: Icons.arrow_back, onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      );
    }

    return AmsScaffold(
      title: "Punch attendance",
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
            AmsCard(
              gradient: const LinearGradient(colors: [Color(0xFFEEF2FF), Colors.white]),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: AmsTokens.brand.withOpacity(0.10),
                    ),
                    child: const Icon(Icons.fingerprint, color: AmsTokens.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Mark attendance", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          "${_faceBytes != null ? "Face captured" : "Face optional"} • Location check • Shift validation",
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AmsCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text("Face verification", style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                    _faceBytes != null ? "Selfie captured (optional for now)." : "Capture a selfie (optional).",
                    style: const TextStyle(color: AmsTokens.muted),
                  ),
                  const SizedBox(height: 12),
                  if (_faceBytes != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(_faceBytes!, height: 160, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AmsSecondaryButton(
                            label: "Retake",
                            icon: Icons.cameraswitch_outlined,
                            onPressed: _faceLoading ? null : _captureFace,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AmsSecondaryButton(
                            label: "Remove",
                            icon: Icons.delete_outline,
                            onPressed: _faceLoading ? null : _removeFace,
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    AmsPrimaryButton(
                      label: "Capture selfie",
                      icon: Icons.camera_alt_outlined,
                      loading: _faceLoading,
                      onPressed: _faceLoading ? null : _captureFace,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _selectedStationId,
              decoration: const InputDecoration(labelText: "Station"),
              items: _stations
                  .map((s) => DropdownMenuItem(value: s.id, child: Text("${s.name} (${s.code})")))
                  .toList(),
              onChanged: _loadingStations
                  ? null
                  : (v) async {
                      setState(() => _selectedStationId = v);
                      await _refreshDistance();
                    },
            ),
            const SizedBox(height: 8),
            if (_loadingStations) const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 8),
            if (!geofenceConfigured) ...[
              AmsNotice(
                title: "Station geofence not configured",
                message: "This station does not have location coordinates. Ask admin to set station geofence so within/outside can be calculated.",
                icon: Icons.location_off_outlined,
                color: AmsTokens.warning,
              ),
              const SizedBox(height: 8),
            ],
            AmsCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (_distanceM != null && radiusConfigured && _distanceM! <= radiusVal ? AmsTokens.success : AmsTokens.warning).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _distanceM != null && radiusConfigured && _distanceM! <= radiusVal ? Icons.location_on : Icons.location_searching,
                      color: _distanceM != null && radiusConfigured && _distanceM! <= radiusVal ? AmsTokens.success : AmsTokens.warning,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Location verification", style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          _distanceM == null
                              ? (_gpsLoading ? "Updating GPS…" : "Tap Update GPS to calculate distance.")
                              : "Distance ${_distanceM!.toStringAsFixed(0)} m • Radius ${radiusConfigured ? radiusVal.toStringAsFixed(0) : "-"} m"
                                  "${_location?.accuracyM != null ? " • acc ${_location!.accuracyM!.toStringAsFixed(0)}m" : ""}",
                          style: const TextStyle(color: AmsTokens.muted),
                        ),
                        if (geofenceConfigured && !radiusConfigured) ...[
                          const SizedBox(height: 6),
                          const Text(
                            "Radius not configured for this station geofence. Within/outside will be logged as unknown.",
                            style: TextStyle(color: AmsTokens.muted),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          "GPS accuracy: ${_accuracyLabel(_location?.accuracyM)}${_location?.accuracyM != null ? " (${_location!.accuracyM!.toStringAsFixed(0)}m)" : ""}",
                          style: const TextStyle(color: AmsTokens.muted),
                        ),
                        if (_gpsLoading) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: (_loading || _gpsLoading || !geofenceConfigured) ? null : _refreshDistance,
                    child: const Text("Update GPS"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _punchType,
              decoration: const InputDecoration(labelText: "Punch type"),
              items: _allowedPunchTypes().map((t) => DropdownMenuItem(value: t, child: Text(_punchLabel(t)))).toList(),
              onChanged: _loadingLastPunchType ? null : (v) => setState(() => _punchType = v ?? "in"),
            ),
            const SizedBox(height: 16),
            AmsPrimaryButton(
              label: "Submit punch",
              icon: Icons.verified_rounded,
              loading: _loading,
              // Allow submit even while GPS is updating; we use last known distance if available.
              onPressed: _loading || at == null ? null : () => _submitPunch(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              AmsNotice(title: "Punch failed", message: _error, icon: Icons.error_outline, color: AmsTokens.danger),
            ],
            if (_result != null) ...[
              const SizedBox(height: 12),
              AmsCard(
                gradient: LinearGradient(colors: [AmsTokens.success.withOpacity(0.12), Colors.white]),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: AmsTokens.success.withOpacity(0.18), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.check_circle_outline, color: AmsTokens.success),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Punch recorded", style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text("Punch at: ${_fmtLocalTime(_result!.punchAt)}", style: const TextStyle(color: AmsTokens.muted)),
                          Text("Shift date: ${_fmtLocalDate(_result!.shiftDate)}", style: const TextStyle(color: AmsTokens.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }
}

