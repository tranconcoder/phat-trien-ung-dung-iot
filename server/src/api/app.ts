import express from "express";
import helmet from "helmet";
import compression from "compression";
import cors from "cors";
import path from "path";
import morgan from "morgan";
import { engine as handlebars } from "express-handlebars";
import { connect } from "./services/mysql2.service";
import authRouter from "./routes/auth.route";
import rootRouter from "./routes/index.route";
import pageRouter from "./routes/page.route";
import handleError from "./middlewares/error.middleware";
import mqttService from "./services/mqtt.service";

const app = express();

// Body parser
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Security
app.use(cors());
app.use(
  helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'", "'unsafe-inline'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", "data:"],
      },
    },
  })
);

// Compression
app.use(compression());

// Logger
app.use(morgan("dev"));

// Setup Handlebars as the view engine
app.engine(
  "hbs",
  handlebars({
    defaultLayout: "main",
    extname: ".hbs",
    layoutsDir: path.join(__dirname, "../views/layouts"),
    partialsDir: path.join(__dirname, "../views/partials"),
  })
);
app.set("view engine", "hbs");
app.set("views", path.join(__dirname, "../views"));

// Serve static files
app.use(express.static(path.join(__dirname, "../public")));

// Routes
app.use("/api", rootRouter);
app.use("/", pageRouter);

// Error handler
app.use(handleError);

// Connect to databases and services
const initServices = async () => {
  try {
    // Connect to MySQL
    await connect();
    console.log("MySQL connected successfully");

    // Initialize MQTT service
    // The connection is handled in the service constructor
    console.log("MQTT service initialized");

    // Handle process termination
    process.on("SIGINT", async () => {
      console.log("Closing connections...");
      await mqttService.disconnect();
      process.exit(0);
    });
  } catch (error) {
    console.error("Service initialization error:", error);
  }
};

initServices();

export default app;
