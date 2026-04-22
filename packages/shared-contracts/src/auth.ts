export type AMS_LoginRequest = {
  email: string;
  password: string;
};

export type AMS_SessionTokens = {
  accessToken: string;
  refreshToken: string;
  accessExpiresAtIso: string;
  refreshExpiresAtIso: string;
};

export type AMS_UserSummary = {
  id: string;
  displayName: string;
  email: string;
};

export type AMS_CompanySummary = {
  id: string;
  code: string;
  name: string;
};

export type AMS_LoginResponse = {
  user: AMS_UserSummary;
  companies: AMS_CompanySummary[];
  tokens: AMS_SessionTokens;
};

export type AMS_SelectCompanyRequest = {
  companyId: string;
};

export type AMS_PasswordResetRequestResponse = {
  requested: boolean;
  /** Present only when server sets AMS_RETURN_RESET_TOKEN_IN_RESPONSE=true (dev). */
  reset_token?: string;
};

export type AMS_PasswordResetConfirmResponse = {
  reset: boolean;
};

