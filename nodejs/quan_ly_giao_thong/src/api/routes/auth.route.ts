import { Router } from "express";
import authController from "../controllers/auth.controller";
import asyncHandler from "../middlewares/async.middleware";
import { authMiddleware } from "../middlewares/auth.middleware";

const router = Router();

router.post("/register", asyncHandler(authController.register));

router.post("/login", asyncHandler(authController.login));

router.post("/refresh-token", asyncHandler(authController.refreshToken));

router.post("/logout", authMiddleware, asyncHandler(authController.logout));

export default router;
