import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { clearSession, loadSession, saveSession, StoredSession } from "./storage";
import { AMS_SESSION_INVALID_EVENT, amsLogin, amsLogout, amsMe, amsSelectCompany } from "../lib/amsApi";

type AuthState = StoredSession & {
  ready: boolean;
  me: any | null;
};

type AuthCtx = {
  state: AuthState;
  login: (email: string, password: string) => Promise<{ companies: any[] }>;
  selectCompany: (companyId: string) => Promise<void>;
  logout: () => Promise<void>;
  getAccessToken: () => Promise<string | null>;
  refreshMe: () => Promise<any>;
};

const Ctx = createContext<AuthCtx | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const initial = loadSession();
  const [accessToken, setAccessToken] = useState(initial?.accessToken ?? "");
  const [refreshToken, setRefreshToken] = useState(initial?.refreshToken ?? "");
  const [companyId, setCompanyId] = useState<string | null>(initial?.companyId ?? null);
  const [ready] = useState(true);
  const [me, setMe] = useState<any | null>(null);

  useEffect(() => {
    const onSessionInvalid = () => {
      setAccessToken("");
      setRefreshToken("");
      setCompanyId(null);
      setMe(null);
      clearSession();
      window.location.replace("/login");
    };
    window.addEventListener(AMS_SESSION_INVALID_EVENT, onSessionInvalid);
    return () => window.removeEventListener(AMS_SESSION_INVALID_EVENT, onSessionInvalid);
  }, []);

  const login = useCallback(async (email: string, password: string) => {
    const res = await amsLogin(email, password);
    setAccessToken(res.session.access_token);
    setRefreshToken(res.session.refresh_token);
    setCompanyId(null);
    saveSession({ accessToken: res.session.access_token, refreshToken: res.session.refresh_token, companyId: null });
    return { companies: res.companies ?? [] };
  }, []);

  const selectCompany = useCallback(
    async (nextCompanyId: string) => {
      if (!accessToken) throw new Error("missing_access_token");
      await amsSelectCompany(accessToken, nextCompanyId);
      setCompanyId(nextCompanyId);
      saveSession({ accessToken, refreshToken, companyId: nextCompanyId });
      const meRes = await amsMe(accessToken);
      setMe(meRes);
    },
    [accessToken, refreshToken]
  );

  const logout = useCallback(async () => {
    try {
      if (accessToken) await amsLogout(accessToken);
    } finally {
      setAccessToken("");
      setRefreshToken("");
      setCompanyId(null);
      setMe(null);
      clearSession();
    }
  }, [accessToken]);

  const getAccessToken = useCallback(async () => {
    if (accessToken) return accessToken;
    return null;
  }, [accessToken]);

  const refreshMe = useCallback(async () => {
    if (!accessToken) throw new Error("missing_access_token");
    const meRes = await amsMe(accessToken);
    setMe(meRes);
    return meRes;
  }, [accessToken]);

  const state = useMemo<AuthState>(
    () => ({ accessToken, refreshToken, companyId, ready, me }),
    [accessToken, refreshToken, companyId, ready, me]
  );

  const value = useMemo<AuthCtx>(
    () => ({ state, login, selectCompany, logout, getAccessToken, refreshMe }),
    [state, login, selectCompany, logout, getAccessToken, refreshMe]
  );

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAuth() {
  const v = useContext(Ctx);
  if (!v) throw new Error("AuthProvider missing");
  return v;
}
