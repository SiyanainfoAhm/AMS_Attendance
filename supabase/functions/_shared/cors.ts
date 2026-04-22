export const corsHeaders: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type, x-ams-refresh-token, x-ams-access-token",
  "access-control-allow-methods": "GET,POST,PATCH,PUT,DELETE,OPTIONS"
};

