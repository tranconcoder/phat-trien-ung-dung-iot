import express from "express";
import { PageController } from "../controllers/page.controller";

const router = express.Router();
const pageController = new PageController();

// Home page
router.get("/", pageController.getHomePage);

// Dashboard page
router.get("/dashboard", pageController.getDashboardPage);

// Map page
router.get("/map", pageController.getMapPage);

// Charts page
router.get("/charts", pageController.getChartsPage);

// 404 page - This should be at the end
router.use(pageController.get404Page);

export default router;
