import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../api/ams_api.dart";
import "../../auth/auth_controller.dart";
import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";

const _statuses = ["open", "in_progress", "resolved", "closed", "cancelled"];
const _priorities = ["low", "medium", "high", "critical"];

bool _supportAccess(AmsMeResult me) {
  if (me.isPlatformSuperAdmin) return true;
  return me.permissions.contains("COMPANY_SUPPORT_READ") || me.permissions.contains("STAFF_SUPPORT_TICKET");
}

bool _canCreateTicket(AmsMeResult me) {
  if (me.isPlatformSuperAdmin) return true;
  return me.permissions.contains("COMPANY_SUPPORT_WRITE") || me.permissions.contains("STAFF_SUPPORT_TICKET");
}

bool _canSetTicketStatus(AmsMeResult me) {
  if (me.isPlatformSuperAdmin) return true;
  return me.permissions.contains("COMPANY_SUPPORT_WRITE");
}

String _fmtDate(String iso) {
  try {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")} "
        "${d.hour.toString().padLeft(2, "0")}:${d.minute.toString().padLeft(2, "0")}";
  } catch (_) {
    return iso;
  }
}

class SupportScreen extends StatefulWidget {
  /// When set (e.g. from a push notification deep link), we try to load pages until the ticket appears.
  final String? focusTicketId;

  const SupportScreen({super.key, this.focusTicketId});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _api = AmsApi();

  AmsMeResult? _me;
  bool _loadingMeta = true;
  bool _loadingList = false;
  String? _error;

  List<AmsSupportTicket> _items = [];
  int _page = 1;
  final int _pageSize = 25;
  int _total = 0;

  String _statusFilter = "";
  bool _focusApplied = false;

  Future<void> _loadMe() async {
    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    if (at == null || at.isEmpty) {
      setState(() {
        _loadingMeta = false;
        _error = "Not signed in.";
      });
      return;
    }
    try {
      final me = await _api.me(accessToken: at);
      if (!mounted) return;
      setState(() {
        _me = me;
        _loadingMeta = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMeta = false;
        _error = e is AmsApiException ? e.message : "$e";
      });
    }
  }

  Future<void> _loadTickets({bool resetPage = true}) async {
    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    final me = _me;
    if (at == null || me == null || !_supportAccess(me)) return;

    if (resetPage) _page = 1;
    setState(() {
      _loadingList = true;
      _error = null;
    });
    try {
      final res = await _api.supportTicketList(
        accessToken: at,
        page: _page,
        pageSize: _pageSize,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _items = res.items;
        _total = res.total;
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _error = e is AmsApiException ? e.message : "$e";
      });
    }
  }

  Future<void> _loadMore() async {
    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    final me = _me;
    if (at == null || me == null || !_supportAccess(me)) return;
    if (_items.length >= _total) return;

    setState(() => _loadingList = true);
    try {
      final nextPage = _page + 1;
      final res = await _api.supportTicketList(
        accessToken: at,
        page: nextPage,
        pageSize: _pageSize,
        status: _statusFilter.isEmpty ? null : _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _items = [..._items, ...res.items];
        _total = res.total;
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _error = e is AmsApiException ? e.message : "$e";
      });
    }
  }

  int _indexOfFocusTicket() {
    final id = widget.focusTicketId;
    if (id == null || id.isEmpty) return -1;
    return _items.indexWhere((t) => t.id == id);
  }

  Future<void> _ensureFocusTicketLoaded() async {
    final id = widget.focusTicketId;
    if (id == null || id.isEmpty) return;

    // Best-effort paging search (bounded) so deep links still work for older tickets.
    for (var i = 0; i < 25; i++) {
      if (!mounted) return;
      if (_indexOfFocusTicket() >= 0) return;
      if (_items.length >= _total) return;
      await _loadMore();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadMe();
      final me = _me;
      if (me != null && _supportAccess(me)) {
        await _loadTickets();
        await _ensureFocusTicketLoaded();
        if (!mounted) return;
        setState(() => _focusApplied = true);
      }
    });
  }

  Future<void> _openCreateSheet() async {
    final me = _me;
    if (me == null || !_canCreateTicket(me)) return;

    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    if (at == null) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String priority = "medium";

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: StatefulBuilder(
            builder: (context, setModal) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("New ticket", style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: "Title", border: OutlineInputBorder()),
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: "Description (optional)", border: OutlineInputBorder()),
                      minLines: 2,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: priority,
                      decoration: const InputDecoration(labelText: "Priority", border: OutlineInputBorder()),
                      items: _priorities
                          .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                          .toList(),
                      onChanged: (v) => setModal(() => priority = v ?? "medium"),
                    ),
                    const SizedBox(height: 16),
                    AmsPrimaryButton(
                      label: "Submit ticket",
                      onPressed: () {
                        if (titleCtrl.text.trim().isEmpty) return;
                        Navigator.of(context).pop(true);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (ok != true) return;

    try {
      await _api.supportTicketCreate(
        accessToken: at,
        title: titleCtrl.text.trim(),
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        priority: priority,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ticket submitted")));
      await _loadTickets(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AmsApiException ? e.message : "Could not create ticket")),
      );
    }
  }

  Future<void> _changeStatus(AmsSupportTicket t, String next) async {
    final auth = context.read<AuthController>();
    final at = auth.accessToken;
    if (at == null) return;
    try {
      await _api.supportTicketSetStatus(accessToken: at, id: t.id, status: next);
      if (!mounted) return;
      await _loadTickets(resetPage: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AmsApiException ? e.message : "Update failed")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingMeta) {
      return const AmsScaffold(
        title: "Help & support",
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final me = _me;
    if (me == null) {
      return AmsScaffold(
        title: "Help & support",
        child: Center(child: Text(_error ?? "Something went wrong.")),
      );
    }

    if (!_supportAccess(me)) {
      return AmsScaffold(
        title: "Help & support",
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AmsNotice(
              title: "Support not available",
              message: "Your account doesn’t include support tickets. Ask a company admin to enable access, "
                  "or use the AMS Admin web app if you manage the company.",
              icon: Icons.info_outline,
              color: AmsTokens.brand,
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AmsTokens.danger)),
            ],
          ],
        ),
      );
    }

    final canCreate = _canCreateTicket(me);
    final canSetStatus = _canSetTicketStatus(me);
    final staffOnly =
        me.permissions.contains("STAFF_SUPPORT_TICKET") && !me.permissions.contains("COMPANY_SUPPORT_READ");
    final focusId = widget.focusTicketId;
    final focusIdx = _indexOfFocusTicket();
    final focusMissing = _focusApplied && focusId != null && focusId.isNotEmpty && focusIdx < 0 && !_loadingList;

    return AmsScaffold(
      title: "Help & support",
      actions: [
        if (canCreate)
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: "New ticket",
            onPressed: _loadingList ? null : _openCreateSheet,
          ),
      ],
      child: RefreshIndicator(
        onRefresh: () => _loadTickets(resetPage: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AmsNotice(
              title: staffOnly ? "Your tickets" : "Company support",
              message: staffOnly
                  ? "You can open new tickets and track items you submitted. Admins manage all company tickets in AMS Admin."
                  : "Create tickets for IT or HR issues. Status updates are visible below.",
              icon: Icons.support_agent_outlined,
              color: AmsTokens.brand,
            ),
            if (focusMissing) ...[
              const SizedBox(height: 12),
              AmsNotice(
                title: "Ticket not found in this list",
                message: "It may be older than the tickets loaded here, filtered out, or you may not have access.",
                icon: Icons.info_outline,
                color: AmsTokens.muted,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _statusFilter,
                    decoration: const InputDecoration(
                      labelText: "Filter",
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(value: "", child: Text("All statuses")),
                      ..._statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _statusFilter = v ?? "";
                        _page = 1;
                      });
                      _loadTickets(resetPage: true);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: AmsTokens.danger)),
              ),
            if (_loadingList && _items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text("No tickets yet.", style: TextStyle(color: AmsTokens.muted))),
              )
            else
              ..._items.map((t) => _TicketCard(
                    ticket: t,
                    highlighted: focusId != null && focusId.isNotEmpty && t.id == focusId,
                    canSetStatus: canSetStatus,
                    meUserId: me.userId,
                    onStatus: canSetStatus ? (s) => _changeStatus(t, s) : null,
                  )),
            if (_items.length < _total && _items.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _loadingList ? null : _loadMore,
                  child: _loadingList
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text("Load more"),
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (canCreate) AmsSecondaryButton(label: "New ticket", onPressed: _loadingList ? null : _openCreateSheet),
          ],
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final AmsSupportTicket ticket;
  final bool highlighted;
  final bool canSetStatus;
  final String meUserId;
  final void Function(String status)? onStatus;

  const _TicketCard({
    required this.ticket,
    required this.highlighted,
    required this.canSetStatus,
    required this.meUserId,
    this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final mine = ticket.openedBy != null && ticket.openedBy == meUserId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: highlighted ? AmsTokens.brand : Colors.transparent,
            width: highlighted ? 2 : 0,
          ),
        ),
        padding: EdgeInsets.all(highlighted ? 2 : 0),
        child: AmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.title,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ticket.ticketCode,
                          style: const TextStyle(color: AmsTokens.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AmsTokens.brand.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(ticket.priority, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              if (ticket.description != null && ticket.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(ticket.description!, style: const TextStyle(color: AmsTokens.muted, height: 1.35)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (mine)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text("You", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AmsTokens.brand)),
                    ),
                  Text("Opened ${_fmtDate(ticket.openedAt)}", style: const TextStyle(fontSize: 12, color: AmsTokens.muted)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text("Status:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (canSetStatus && onStatus != null)
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: ticket.status,
                          items: _statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (v) {
                            if (v != null && v != ticket.status) onStatus!(v);
                          },
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Text(ticket.status, style: const TextStyle(fontSize: 14)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
