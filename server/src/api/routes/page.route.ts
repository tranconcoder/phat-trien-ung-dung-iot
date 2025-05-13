import { Router } from "express";
import { PageController } from "../controllers/page.controller";

const router = Router();
const pageController = new PageController();

// Home page
router.get("/", pageController.getHomePage);

// Dashboard page
router.get("/dashboard", pageController.getDashboardPage);

// Map page
router.get("/map", pageController.getMapPage);

// 404 page - This should be at the end
router.use(pageController.get404Page);

export default router;
