import type { Request, Response } from "express";

/**
 * Controller for page routes
 */
export class PageController {
  /**
   * Render the home page
   */
  getHomePage(req: Request, res: Response): void {
    res.render("index", {
      title: "Trang chủ",
      isHome: true,
    });
  }

  /**
   * Render the dashboard page
   */
  getDashboardPage(req: Request, res: Response): void {
    // Normally this would come from a database
    const cars = [
      {
        id: 1,
        name: "Toyota Camry",
        licensePlate: "51F-123.45",
        status: "Active",
        lastMaintenance: "2023-05-15",
        nextMaintenance: "2023-11-15",
        location: "Quận 7, TP.HCM",
      },
      {
        id: 2,
        name: "Honda Civic",
        licensePlate: "51G-678.90",
        status: "Maintenance",
        lastMaintenance: "2023-04-20",
        nextMaintenance: "2023-10-20",
        location: "Quận 2, TP.HCM",
      },
      {
        id: 3,
        name: "Ford Ranger",
        licensePlate: "51H-246.80",
        status: "Active",
        lastMaintenance: "2023-06-10",
        nextMaintenance: "2023-12-10",
        location: "Quận 1, TP.HCM",
      },
    ];

    res.render("dashboard", {
      title: "Quản lý xe",
      cars,
      isDashboard: true,
      useDashboardCss: true,
      useDashboardJs: true,
    });
  }

  /**
   * Render the map page
   */
  getMapPage(req: Request, res: Response): void {
    res.render("map", {
      title: "Bản đồ xe",
      useMapCss: true,
      useMapJs: true,
    });
  }

  /**
   * Render the 404 page
   */
  get404Page(req: Request, res: Response): void {
    res.status(404).render("error", {
      title: "Page Not Found",
      errorCode: 404,
      errorMessage: "Trang bạn đang tìm kiếm không tồn tại.",
      isError: true,
    });
  }
}
