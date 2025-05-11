import type { NextFunction, Request, Response } from "express";

export default function handleError(
  err: any,
  req: Request,
  res: Response,
  next: NextFunction
) {
  console.log({
    message: err.message,
    stack: err.stack,
    status: res.statusCode,
    path: req.path,
    method: req.method,
    body: req.body,
    query: req.query,
  });

  if (err instanceof Error) {
    res.status(500).json({
      status: "error",
      message: err.message,
    });
  }
  res.status(500).json({
    status: "error",
    message: err.message,
  });
}
