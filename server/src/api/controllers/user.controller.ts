import type { NextFunction, Request, RequestHandler, Response } from "express";
import UserProfileService from "../services/user.profile";

export default new (class UserController {
  /* ---------------------------------------------------------- */
  /*                      Get user profile                      */
  /* ---------------------------------------------------------- */
  getUserProfile: RequestHandler = async (req, res, next) => {
    try {
      const user = await UserProfileService.getUserProfile(req.user.id);

      res.status(200).json(user);
    } catch (error) {
      next(error);
    }
  };
})();
