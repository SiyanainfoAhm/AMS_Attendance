import "package:flutter/material.dart";

import "../design/ams_tokens.dart";

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeInOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.96, end: 1.02).animate(_a),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(colors: [AmsTokens.brand, AmsTokens.brand2]),
                      boxShadow: AmsTokens.shadowMd,
                    ),
                    child: const Icon(Icons.badge_outlined, color: Colors.white, size: 34),
                  ),
                ),
                const SizedBox(height: 16),
                Text("AMS Staff", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text("Preparing your session…", style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

