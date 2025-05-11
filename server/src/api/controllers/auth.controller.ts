import type { NextFunction, Request, Response } from "express";
import authService from "../services/auth.service";

export default new (class AuthController {
  async register(req: Request, res: Response, next: NextFunction) {
    const { email, password, fullName, phoneNumber, address } = req.body;

    // Validate input
    if (!email || !password || !fullName) {
      return next(new Error("Email, password and fullName are required"));
    }

    const result = await authService.register({
      email,
      password,
      fullName,
      phoneNumber,
      address,
    });

    return res.status(201).json({
      status: "success",
      data: result,
    });
  }

  async login(req: Request, res: Response, next: NextFunction) {
    const { email, password } = req.body;

    // Validate input
    if (!email || !password) {
      return next(new Error("Email and password are required"));
    }

    const result = await authService.login(email, password);

    return res.status(200).json({
      status: "success",
      data: result,
    });
  }

  async refreshToken(req: Request, res: Response, next: NextFunction) {
    const { userId, refreshToken } = req.body;

    // Validate input
    if (!userId || !refreshToken) {
      return next(new Error("User ID and refresh token are required"));
    }

    const result = await authService.refreshToken(userId, refreshToken);

    return res.status(200).json({
      status: "success",
      data: result,
    });
  }

  async logout(req: Request, res: Response, next: NextFunction) {
    const userId = req.user?.id;

    if (!userId) {
      return next(new Error("User ID is required"));
    }

    await authService.logout(userId);

    return res.status(200).json({
      status: "success",
      message: "Logged out successfully",
    });
  }
})();
