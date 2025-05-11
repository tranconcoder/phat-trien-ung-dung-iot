import type { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";
import redisService from "../services/redis.service";
import jwtService from "../services/jwt.service";

interface JwtPayload {
  id: number;
  email: string;
}

declare global {
  namespace Express {
    interface Request {
      user: JwtPayload;
    }
  }
}

export const authMiddleware = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    // 1. Get the token from headers
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return next(new Error("No token provided"));
    }

    const token = authHeader.split(" ")[1];

    if (!token) {
      return next(new Error("Access token is required"));
    }

    // 2. Verify the token using jwt service
    const decoded = jwtService.verifyAccessToken(token);
    const { id } = decoded;

    // 3. Check if token is in Redis
    const storedTokens = await redisService.getKeyToken(id);
    if (!storedTokens || storedTokens.accessToken !== token) {
      return next(new Error("Invalid token or token revoked"));
    }

    // 4. Add user info to request
    req.user = decoded;

    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      return next(new Error("Invalid token"));
    }

    if (error instanceof jwt.TokenExpiredError) {
      return next(new Error("Token expired"));
    }

    return next(new Error("Internal server error"));
  }
};

export const adminAuthMiddleware = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    // First verify the user is authenticated
    await authMiddleware(req, res, () => {
      // Then check if user is admin (extend this as needed)
      // This would require additional logic to check if the user has admin privileges
      // For example, querying the database to check user roles

      // For now, we'll just continue
      next();
    });
  } catch (error) {
    return res.status(500).json({
      status: "error",
      code: "SERVER_ERROR",
      message: "Internal server error",
    });
  }
};
