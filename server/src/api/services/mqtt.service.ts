import mqtt from "mqtt";
import {
  MQTT_HOST,
  MQTT_PORT,
  MQTT_USERNAME,
  MQTT_PASSWORD,
  MQTT_USE_TLS,
  MQTT_CLIENT_ID,
  METRICS_TOPIC,
  COMMANDS_TOPIC,
  TURN_SIGNALS_TOPIC,
} from "../../configs/mqtt.config";
import redisService from "./redis.service";

interface CarData {
  temperature: number;
  humidity: number;
  battery: number;
  speed: number;
  simulated?: boolean;
  timestamp?: number;
  carId?: string;
}

class MqttService {
  private client: mqtt.MqttClient | null = null;
  private isConnected = false;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 10;

  constructor() {
    this.connect();
  }

  async connect() {
    try {
      const protocol = MQTT_USE_TLS ? "mqtts" : "mqtt";
      const url = `${protocol}://${MQTT_HOST}:${MQTT_PORT}`;

      console.log(`Connecting to MQTT broker at ${url}`);

      this.client = mqtt.connect(url, {
        clientId: MQTT_CLIENT_ID,
        username: MQTT_USERNAME,
        password: MQTT_PASSWORD,
        clean: true,
        connectTimeout: 30000, // 30 seconds
        reconnectPeriod: 5000, // 5 seconds
        rejectUnauthorized: false, // Skip certificate validation (for dev only)
      });

      this.setupEventHandlers();
    } catch (error) {
      console.error("MQTT connection error:", error);
      this.handleReconnect();
    }
  }

  private setupEventHandlers() {
    if (!this.client) return;

    this.client.on("connect", () => {
      console.log("Connected to MQTT broker");
      this.isConnected = true;
      this.reconnectAttempts = 0;

      // Subscribe to all relevant topics
      this.subscribe(METRICS_TOPIC);
      this.subscribe(COMMANDS_TOPIC);
      this.subscribe(TURN_SIGNALS_TOPIC);
    });

    this.client.on("message", (topic, message) => {
      this.handleMessage(topic, message);
    });

    this.client.on("error", (error) => {
      console.error("MQTT error:", error);
      this.isConnected = false;
    });

    this.client.on("close", () => {
      console.log("MQTT connection closed");
      this.isConnected = false;
      this.handleReconnect();
    });

    this.client.on("offline", () => {
      console.log("MQTT client is offline");
      this.isConnected = false;
    });
  }

  private handleReconnect() {
    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      console.log(
        `MQTT reconnect attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts}`
      );

      setTimeout(() => {
        this.connect();
      }, 5000 * this.reconnectAttempts); // Increasing backoff
    } else {
      console.error(
        "Failed to reconnect to MQTT broker after maximum attempts"
      );
    }
  }

  private subscribe(topic: string) {
    if (!this.client || !this.isConnected) return;

    this.client.subscribe(topic, (err) => {
      if (err) {
        console.error(`Error subscribing to ${topic}:`, err);
      } else {
        console.log(`Subscribed to ${topic}`);
      }
    });
  }

  private async handleMessage(topic: string, message: Buffer) {
    try {
      console.log(`Received message on topic ${topic}`);

      if (topic === METRICS_TOPIC) {
        const data: CarData = JSON.parse(message.toString());

        // Add timestamp and default carId if not present
        const timestamp = Date.now();
        const carId = data.carId || "car-001";
        const messageWithTimestamp = {
          ...data,
          timestamp,
          carId,
        };

        console.log("Car data:", messageWithTimestamp);

        // Store time-series data in Redis
        await this.storeCarData(carId, messageWithTimestamp);

        // Store latest data for quick access
        await this.storeLatestData(carId, messageWithTimestamp);
      }
    } catch (error) {
      console.error("Error handling MQTT message:", error);
    }
  }

  private async storeCarData(carId: string, data: CarData) {
    try {
      // Store in time series format
      // Key format: car:{carId}:metrics:{timestamp}
      const key = `car:${carId}:metrics:${data.timestamp}`;
      await redisService.client.set(key, JSON.stringify(data));

      // Set expiration for time series data (7 days)
      await redisService.client.expire(key, 60 * 60 * 24 * 7);

      // Add to sorted set for time-series queries
      // Set name: car:{carId}:metrics
      const setKey = `car:${carId}:metrics`;
      await redisService.client.zAdd(setKey, [
        {
          score: data.timestamp as number,
          value: JSON.stringify(data),
        },
      ]);

      // Trim the sorted set to keep only the last 1000 entries
      const count = await redisService.client.zCard(setKey);
      if (count > 1000) {
        await redisService.client.zRemRangeByRank(setKey, 0, count - 1001);
      }

      // Set expiration for the sorted set (7 days)
      await redisService.client.expire(setKey, 60 * 60 * 24 * 7);
    } catch (error) {
      console.error("Error storing car data in Redis:", error);
    }
  }

  private async storeLatestData(carId: string, data: CarData) {
    try {
      // Store latest data for quick access
      // Key format: car:{carId}:latest
      const key = `car:${carId}:latest`;
      await redisService.client.set(key, JSON.stringify(data));

      // No expiration for latest data

      // Also maintain a set of all car IDs
      await redisService.client.sAdd("cars", carId);
    } catch (error) {
      console.error("Error storing latest car data in Redis:", error);
    }
  }

  // Public methods to interact with the service

  public publish(topic: string, message: string | object) {
    if (!this.client || !this.isConnected) {
      console.error("Cannot publish: MQTT client not connected");
      return false;
    }

    try {
      const payload =
        typeof message === "string" ? message : JSON.stringify(message);

      this.client.publish(topic, payload);
      return true;
    } catch (error) {
      console.error("Error publishing MQTT message:", error);
      return false;
    }
  }

  public async disconnect() {
    if (this.client) {
      await this.client.end();
      this.client = null;
      this.isConnected = false;
      console.log("MQTT client disconnected");
    }
  }

  public isClientConnected() {
    return this.isConnected;
  }
}

export default new MqttService();
