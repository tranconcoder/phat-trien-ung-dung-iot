/* ---------------------------------------------------------- */
/*                            MQTT                            */
/* ---------------------------------------------------------- */
export const MQTT_HOST =
  process.env.MQTT_HOST || "fd66ecb3.ala.asia-southeast1.emqxsl.com";
export const MQTT_PORT = process.env.MQTT_PORT || 8883;
export const MQTT_USERNAME = process.env.MQTT_USERNAME || "trancon2";
export const MQTT_PASSWORD = process.env.MQTT_PASSWORD || "123";
export const MQTT_USE_TLS = process.env.MQTT_USE_TLS === "true" || true;
export const MQTT_CLIENT_ID = `server_${Math.random()
  .toString(16)
  .slice(2, 10)}`;

/* ---------------------------------------------------------- */
/*                            Topics                           */
/* ---------------------------------------------------------- */
export const METRICS_TOPIC = process.env.METRICS_TOPIC || "/metrics";
export const COMMANDS_TOPIC = process.env.COMMANDS_TOPIC || "/commands";
export const TURN_SIGNALS_TOPIC =
  process.env.TURN_SIGNALS_TOPIC || "/turn_signals";
