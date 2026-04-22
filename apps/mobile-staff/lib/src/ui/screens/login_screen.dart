import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../auth/auth_controller.dart";
import "../design/ams_tokens.dart";
import "../widgets/ams_widgets.dart";

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController(text: "staff1@demo.local");
  final _password = TextEditingController(text: "ChangeMe@123");
  String? _error;
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEEF2FF), Color(0xFFF6F7FB), Color(0xFFE0F2FE)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(colors: [AmsTokens.brand, AmsTokens.brand2]),
                        boxShadow: AmsTokens.shadowSm,
                      ),
                      child: const Icon(Icons.badge_outlined, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("AMS Staff", style: Theme.of(context).textTheme.titleLarge),
                          Text("Secure workforce attendance", style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text("Sign in", style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text("Use your company login to continue.", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                AmsCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _email,
                        decoration: const InputDecoration(
                          labelText: "Email / Username / Mobile",
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        decoration: InputDecoration(
                          labelText: "Password",
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          ),
                        ),
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Ask admin to reset your password if needed.")),
                                  );
                                },
                          child: const Text("Forgot password?"),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 4),
                        AmsNotice(
                          title: "Sign in failed",
                          message: _error,
                          icon: Icons.error_outline,
                          color: AmsTokens.danger,
                        ),
                      ],
                      const SizedBox(height: 12),
                      AmsPrimaryButton(
                        label: "Continue",
                        icon: Icons.arrow_forward_rounded,
                        loading: _loading,
                        onPressed: _loading
                            ? null
                            : () async {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                });
                                try {
                                  await auth.login(_email.text.trim(), _password.text);
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
                const Spacer(),
                Text(
                  "Tip: Keep location enabled for faster punching.",
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

