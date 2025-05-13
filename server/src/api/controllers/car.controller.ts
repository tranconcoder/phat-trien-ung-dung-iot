import { Request, Response, NextFunction } from "express";
import redisService from "../services/redis.service";

class CarController {
  // Get all cars
  async getAllCars(req: Request, res: Response, next: NextFunction) {
    try {
      const carIds = await redisService.getAllCarIds();

      // Get latest data for each car
      const carsPromises = carIds.map(async (carId) => {
        const data = await redisService.getCarLatestData(carId);
        return {
          carId,
          ...data,
        };
      });

      const cars = await Promise.all(carsPromises);

      res.json({
        success: true,
        data: cars,
      });
    } catch (error) {
      next(error);
    }
  }

  // Get latest data for a car
  async getCarLatestData(req: Request, res: Response, next: NextFunction) {
    try {
      const { carId } = req.params;
      const data = await redisService.getCarLatestData(carId);

      if (!data) {
        return res.status(404).json({
          success: false,
          message: `No data found for car ${carId}`,
        });
      }

      res.json({
        success: true,
        data,
      });
    } catch (error) {
      next(error);
    }
  }

  // Get metrics for a car in a time range
  async getCarMetrics(req: Request, res: Response, next: NextFunction) {
    try {
      const { carId } = req.params;
      const { start, end, limit } = req.query;

      let startTime = start
        ? parseInt(start as string)
        : Date.now() - 24 * 60 * 60 * 1000; // Default to last 24 hours
      let endTime = end ? parseInt(end as string) : Date.now();

      // Get metrics in range
      let metrics;
      if (limit) {
        // If limit is specified, get the latest n entries
        const count = parseInt(limit as string);
        metrics = await redisService.getCarMetricsLatest(carId, count);
      } else {
        // Otherwise, get metrics in the specified time range
        metrics = await redisService.getCarMetricsInRange(
          carId,
          startTime,
          endTime
        );
      }

      if (!metrics || metrics.length === 0) {
        return res.status(404).json({
          success: false,
          message: `No metrics found for car ${carId} in the specified time range`,
        });
      }

      res.json({
        success: true,
        data: {
          carId,
          metrics,
          count: metrics.length,
          timeRange: {
            start: startTime,
            end: endTime,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  }

  // Get chart data for a car
  async getCarChartData(req: Request, res: Response, next: NextFunction) {
    try {
      const { carId } = req.params;
      const { type, period } = req.query;

      // Default values
      const dataType = (type as string) || "temperature";
      const timePeriod = (period as string) || "24h";

      // Calculate time range based on period
      let startTime: number;
      const endTime = Date.now();

      switch (timePeriod) {
        case "1h":
          startTime = endTime - 60 * 60 * 1000;
          break;
        case "6h":
          startTime = endTime - 6 * 60 * 60 * 1000;
          break;
        case "24h":
          startTime = endTime - 24 * 60 * 60 * 1000;
          break;
        case "7d":
          startTime = endTime - 7 * 24 * 60 * 60 * 1000;
          break;
        default:
          startTime = endTime - 24 * 60 * 60 * 1000; // Default to 24 hours
      }

      // Get metrics in range
      const metrics = await redisService.getCarMetricsInRange(
        carId,
        startTime,
        endTime
      );

      if (!metrics || metrics.length === 0) {
        return res.status(404).json({
          success: false,
          message: `No metrics found for car ${carId} in the specified time range`,
        });
      }

      // Format data for charts
      const chartData = {
        labels: metrics.map((m) => new Date(m.timestamp).toLocaleTimeString()),
        datasets: [
          {
            label: this.getDataTypeLabel(dataType),
            data: metrics.map((m) => m[dataType] || 0),
            borderColor: this.getDataTypeColor(dataType),
            fill: false,
          },
        ],
      };

      res.json({
        success: true,
        data: chartData,
        meta: {
          carId,
          dataType,
          period: timePeriod,
          pointCount: metrics.length,
          timeRange: {
            start: startTime,
            end: endTime,
          },
        },
      });
    } catch (error) {
      next(error);
    }
  }

  // Helper method to get label for data type
  private getDataTypeLabel(type: string): string {
    switch (type) {
      case "temperature":
        return "Temperature (°C)";
      case "humidity":
        return "Humidity (%)";
      case "battery":
        return "Battery (%)";
      case "speed":
        return "Speed (km/h)";
      default:
        return "Value";
    }
  }

  // Helper method to get color for data type
  private getDataTypeColor(type: string): string {
    switch (type) {
      case "temperature":
        return "rgb(255, 99, 132)";
      case "humidity":
        return "rgb(54, 162, 235)";
      case "battery":
        return "rgb(75, 192, 192)";
      case "speed":
        return "rgb(153, 102, 255)";
      default:
        return "rgb(201, 203, 207)";
    }
  }
}

export default new CarController();
