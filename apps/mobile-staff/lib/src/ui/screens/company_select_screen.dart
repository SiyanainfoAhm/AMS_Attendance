import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../auth/auth_controller.dart";
import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";

class CompanySelectScreen extends StatefulWidget {
  const CompanySelectScreen({super.key});

  @override
  State<CompanySelectScreen> createState() => _CompanySelectScreenState();
}

class _CompanySelectScreenState extends State<CompanySelectScreen> {
  String? _selectedCompanyId;
  String? _error;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final companies = auth.companies;

    return AmsScaffold(
      title: "Select company",
      actions: [
        IconButton(
          onPressed: _loading ? null : () => context.read<AuthController>().logout(),
          icon: const Icon(Icons.logout),
          tooltip: "Logout",
        )
      ],
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AmsCard(
              gradient: const LinearGradient(colors: [Color(0xFFEEF2FF), Colors.white]),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AmsTokens.brand.withOpacity(0.12),
                    ),
                    child: const Icon(Icons.apartment_outlined, color: AmsTokens.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Choose workspace", style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text("Pick the company you want to punch attendance for.", style: Theme.of(context).textTheme.bodySmall),
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
                  DropdownButtonFormField<String>(
                    value: _selectedCompanyId,
                    items: companies.map((c) => DropdownMenuItem(value: c.id, child: Text("${c.name} (${c.code})"))).toList(),
                    onChanged: _loading ? null : (v) => setState(() => _selectedCompanyId = v),
                    decoration: const InputDecoration(labelText: "Company", prefixIcon: Icon(Icons.business_outlined)),
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    AmsNotice(
                      title: "Could not select company",
                      message: _error,
                      icon: Icons.error_outline,
                      color: AmsTokens.danger,
                    ),
                    const SizedBox(height: 12),
                  ],
                  AmsPrimaryButton(
                    label: "Continue",
                    icon: Icons.arrow_forward_rounded,
                    loading: _loading,
                    onPressed: _loading || _selectedCompanyId == null
                        ? null
                        : () async {
                            setState(() {
                              _loading = true;
                              _error = null;
                            });
                            try {
                              await auth.selectCompany(_selectedCompanyId!);
                            } catch (e) {
                              setState(() => _error = "$e");
                            } finally {
                              if (mounted) setState(() => _loading = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

