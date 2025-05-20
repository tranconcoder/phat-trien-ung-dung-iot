/* ---------------------------------------------------------- */
/*                           Server                           */
/* ---------------------------------------------------------- */
export const SERVER_HOST = process.env.SERVER_HOST || "192.168.1.92";
export const SERVER_PORT = Number(process.env.SERVER_PORT || 3000);

/* ---------------------------------------------------------- */
/*                            Redis                           */
/* ---------------------------------------------------------- */
export const REDIS_HOST = process.env.REDIS_HOST || "0.0.0.0";
export const REDIS_PORT = process.env.REDIS_PORT || 6379;
export const REDIS_USER = process.env.REDIS_USER || "default";
export const REDIS_PASSWORD = process.env.REDIS_PASSWORD || "";

/* ---------------------------------------------------------- */
/*                            MySQL                           */
/* ---------------------------------------------------------- */
export const MYSQL_HOST = process.env.MYSQL_HOST || "192.168.1.92";
export const MYSQL_PORT = Number(process.env.MYSQL_PORT || 3306);
export const MYSQL_USER = process.env.MYSQL_USER || "root";
export const MYSQL_PASSWORD = process.env.MYSQL_PASSWORD || "";
export const MYSQL_DATABASE = process.env.MYSQL_DATABASE || "app_db";
