import "package:flutter_dotenv/flutter_dotenv.dart";

class AppConfig {
  static String supabaseUrl() => dotenv.get("SUPABASE_URL");
  static String supabaseAnonKey() => dotenv.get("SUPABASE_ANON_KEY");

  static void validate() {
    final url = supabaseUrl().trim();
    final anon = supabaseAnonKey().trim();
    if (url.isEmpty) throw StateError("Missing SUPABASE_URL in .env");
    if (anon.isEmpty) throw StateError("Missing SUPABASE_ANON_KEY in .env");
  }

  static String functionsBaseUrl() {
    final v = dotenv.maybeGet("FUNCTIONS_BASE_URL");
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return "${supabaseUrl()}/functions/v1";
  }
}

