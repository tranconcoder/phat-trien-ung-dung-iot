import { createClient } from "redis";
import {
  REDIS_HOST,
  REDIS_PORT,
  REDIS_PASSWORD,
  REDIS_USER,
} from "../../configs/server.config";
import { KEY_TOKEN_EXPIRATION } from "../../configs/jwt.config";

class RedisService {
  private client;

  constructor() {
    this.client = createClient({
      url: `redis://${REDIS_HOST}:${REDIS_PORT}`,
      username: REDIS_USER,
      password: REDIS_PASSWORD,
    });

    this.client.on("error", (err) => {
      console.error("Redis Client Error", err);
    });

    this.connect();
  }

  async connect() {
    try {
      await this.client.connect();
      console.log("Redis client connected");
    } catch (error) {
      console.error("Redis connection error:", error);
    }
  }

  async storeKeyToken(userId: number, token: string, refreshToken: string) {
    try {
      const key = `token:${userId}`;
      await this.client.hSet(key, {
        accessToken: token,
        refreshToken: refreshToken,
      });
      // Set expiration time using the config value
      await this.client.expire(key, KEY_TOKEN_EXPIRATION);
      return true;
    } catch (error) {
      console.error("Error storing token in Redis:", error);
      throw error;
    }
  }

  async getKeyToken(userId: number) {
    try {
      const key = `token:${userId}`;
      return await this.client.hGetAll(key);
    } catch (error) {
      console.error("Error retrieving token from Redis:", error);
      throw error;
    }
  }

  async removeKeyToken(userId: number) {
    try {
      const key = `token:${userId}`;
      return await this.client.del(key);
    } catch (error) {
      console.error("Error removing token from Redis:", error);
      throw error;
    }
  }

  async disconnect() {
    await this.client.disconnect();
  }
}

export default new RedisService();
