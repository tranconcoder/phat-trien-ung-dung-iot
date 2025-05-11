import pool from "@/services/mysql2.service";

export const getUserProfile = async (userId: number) => {
  const [rows] = await pool.query("SELECT * FROM users WHERE id = ?", [userId]);

  return rows;
};
