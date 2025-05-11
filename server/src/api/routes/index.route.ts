import { Router } from "express";
import authRouter from "./auth.route";

const rootRouter = Router();

rootRouter.use("/auth", authRouter);

export default rootRouter;
