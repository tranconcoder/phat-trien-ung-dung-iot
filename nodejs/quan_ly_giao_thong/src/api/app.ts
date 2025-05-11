import express from "express";
import helmet from "helmet";
import compression from "compression";
import cors from "cors";
import path from "path";
import morgan from "morgan";
import { connect } from "./services/mysql2.service";
import authRouter from "./routes/auth.route";
import rootRouter from "./routes/index.route";
import handleError from "./middlewares/error.middleware";
const app = express();

// Body parser
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Security
app.use(cors());
app.use(helmet());

// Compression
app.use(compression());

// Logger
app.use(morgan("dev"));

// Routes
app.use("/api", rootRouter);

// Error handler
app.use(handleError);

await connect();

export default app;
