import type { IUser } from "../models/user.model";
import pool from "./mysql2.service";
import bcrypt from "bcrypt";
import redisService from "./redis.service";
import jwtService from "./jwt.service";
import type { ResultSetHeader, RowDataPacket } from "mysql2";

export default new (class AuthService {
  async register(payload: Omit<IUser, "id" | "createdAt" | "updatedAt">) {
    const { email, password, address, fullName, phoneNumber } = payload;

    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT * FROM users WHERE email = ?",
      [email]
    );

    if (rows.length > 0) {
      throw new Error("User already exists");
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const [result] = await pool.query<ResultSetHeader>(
      "INSERT INTO users (email, address, full_name, phone_number, password) VALUES (?, ?, ?, ?, ?)",
      [email, address, fullName, phoneNumber, hashedPassword]
    );

    const userId = result.insertId;

    // Generate tokens using jwt service
    const tokens = jwtService.generateTokens({ id: userId, email });

    // Store refresh token in Redis
    await redisService.storeKeyToken(
      userId,
      tokens.accessToken,
      tokens.refreshToken
    );

    return {
      user: {
        id: userId,
        email,
        fullName,
        phoneNumber,
        address,
      },
      tokens,
    };
  }

  async login(email: string, password: string) {
    const [rows] = await pool.query<RowDataPacket[]>(
      "SELECT * FROM users WHERE email = ?",
      [email]
    );

    if (rows.length === 0) {
      throw new Error("Invalid email or password");
    }

    const user = rows[0] as RowDataPacket & IUser;
    const isPasswordValid = await bcrypt.compare(password, user.password);

    if (!isPasswordValid) {
      throw new Error("Invalid email or password");
    }

    // Generate tokens using jwt service
    const tokens = jwtService.generateTokens({
      id: user.id,
      email: user.email,
    });

    // Store tokens in Redis
    await redisService.storeKeyToken(
      user.id,
      tokens.accessToken,
      tokens.refreshToken
    );

    return {
      user: {
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        phoneNumber: user.phoneNumber,
        address: user.address,
      },
      tokens,
    };
  }

  async refreshToken(userId: number, refreshToken: string) {
    // Get tokens from Redis
    const storedTokens = await redisService.getKeyToken(userId);

    if (
      !storedTokens ||
      !storedTokens.refreshToken ||
      storedTokens.refreshToken !== refreshToken
    ) {
      throw new Error("Invalid refresh token");
    }

    try {
      // Verify the refresh token using jwt service
      const decoded = jwtService.verifyRefreshToken(refreshToken);

      // Get user info
      const [rows] = await pool.query<RowDataPacket[]>(
        "SELECT * FROM users WHERE id = ?",
        [userId]
      );

      if (rows.length === 0) {
        throw new Error("User not found");
      }

      const user = rows[0] as RowDataPacket & IUser;

      // Generate new tokens using jwt service
      const tokens = jwtService.generateTokens({
        id: userId,
        email: user.email,
      });

      // Update tokens in Redis
      await redisService.storeKeyToken(
        userId,
        tokens.accessToken,
        tokens.refreshToken
      );

      return tokens;
    } catch (error) {
      // If refresh token is invalid or expired, remove all tokens
      await redisService.removeKeyToken(userId);
      throw new Error("Refresh token expired");
    }
  }

  async logout(userId: number) {
    return await redisService.removeKeyToken(userId);
  }
})();
