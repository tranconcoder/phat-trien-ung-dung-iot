import express from "express";
import authRouter from "./auth.route";
import carRouter from "./car.route";

const router = express.Router();

router.use("/auth", authRouter);
router.use("/", carRouter);

export default router;
