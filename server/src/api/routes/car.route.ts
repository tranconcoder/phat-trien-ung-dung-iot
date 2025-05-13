import express from "express";
import carController from "../controllers/car.controller";

const router = express.Router();

// Get all car IDs
router.get("/cars", carController.getAllCars);

// Get latest data for a car
router.get("/cars/:carId/latest", carController.getCarLatestData);

// Get data for a specific car in a time range
router.get("/cars/:carId/metrics", carController.getCarMetrics);

// Get chart data for a specific car
router.get("/cars/:carId/chart", carController.getCarChartData);

export default router;
