/* ---------------------------------------------------------- */
/*                             JWT                            */
/* ---------------------------------------------------------- */
export const JWT_SECRET = process.env.JWT_SECRET || "your_jwt_secret_key";
export const JWT_REFRESH_SECRET =
  process.env.JWT_REFRESH_SECRET || "your_jwt_refresh_secret_key";
export const JWT_ACCESS_EXPIRATION =
  Number(process.env.JWT_ACCESS_EXPIRATION) || 1 * 60 * 60;
export const JWT_REFRESH_EXPIRATION =
  Number(process.env.JWT_REFRESH_EXPIRATION) || 7 * 24 * 60 * 60;

/* ---------------------------------------------------------- */
/*                         Key Token                          */
/* ---------------------------------------------------------- */
export const KEY_TOKEN_EXPIRATION = 60 * 60 * 24 * 7; // 7 days in seconds
