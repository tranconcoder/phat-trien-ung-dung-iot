import type { Request, Response } from "express";

/**
 * Render home page
 */
export const renderHomePage = (req: Request, res: Response) => {
  res.render("index", {
    title: "Hệ thống quản lý giao thông thông minh",
    isHome: true,
  });
};

/**
 * Render dashboard page
 */
export const renderDashboardPage = (req: Request, res: Response) => {
  res.render("dashboard", {
    title: "Bảng điều khiển - Hệ thống quản lý giao thông",
    isDashboard: true,
  });
};

/**
 * Render reports page
 */
export const renderReportsPage = (req: Request, res: Response) => {
  res.render("reports", {
    title: "Báo cáo - Hệ thống quản lý giao thông",
    isReports: true,
  });
};

/**
 * Render settings page
 */
export const renderSettingsPage = (req: Request, res: Response) => {
  res.render("settings", {
    title: "Cài đặt - Hệ thống quản lý giao thông",
    isSettings: true,
  });
};

/**
 * Render 404 page
 */
export const renderNotFoundPage = (req: Request, res: Response) => {
  res.status(404).render("404", {
    title: "Không tìm thấy trang - Hệ thống quản lý giao thông",
  });
};
