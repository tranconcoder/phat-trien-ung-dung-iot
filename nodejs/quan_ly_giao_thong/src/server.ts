import app from "@/app";
import { createServer } from "http";
import { SERVER_HOST, SERVER_PORT } from "./configs/server.config";

const server = createServer(app);

server.listen(SERVER_PORT, SERVER_HOST, () => {
  console.log(`Server is running on http://${SERVER_HOST}:${SERVER_PORT}`);
});

server.on("error", (error) => {
  console.error(error);
});

process.on("SIGINT", () => {
  server.close(() => {
    console.log("Server closed");
  });
});

process.on("SIGTERM", () => {
  server.close(() => {
    console.log("Server closed");
  });
});

export default server;
