import { Router } from "express";
import {
  renderHomePage,
  renderDashboardPage,
  renderReportsPage,
  renderSettingsPage,
  renderNotFoundPage,
} from "../controllers/page.controller";

const router = Router();

// Home page
router.get("/", renderHomePage);

// Dashboard page
router.get("/dashboard", renderDashboardPage);

// Reports page
router.get("/reports", renderReportsPage);

// Settings page
router.get("/settings", renderSettingsPage);

// 404 page - Should be last
router.use((req, res) => renderNotFoundPage(req, res));

export default router;
