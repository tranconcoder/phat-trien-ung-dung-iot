#include <WiFi.h>
#include <WebServer.h>
#include <Wire.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>
#include <ArduinoJson.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <EEPROM.h>
#include <DNSServer.h>

// Pin definitions
#define I2C_SDA_PIN 21
#define I2C_SCL_PIN 22
#define DHT_PIN 35
#define RELAY_PIN 14  // Pin connected to relay instead of direct LED
#define LEFT_SIGNAL_PIN -1  // Default -1 means not configured
#define RIGHT_SIGNAL_PIN -1 // Default -1 means not configured

// Motor control pins (L298N)
#define MOTOR_A_IN1 27 //banh truoc phai
#define MOTOR_A_IN2 26 //banh truoc phai


#define MOTOR_B_IN1 33 //banh truoc trai
#define MOTOR_B_IN2 25 //banh truoc trai

#define MOTOR_C_IN1 2 //banh sau phai
#define MOTOR_C_IN2 4 //banh sau phai
#define MOTOR_D_IN1 23 //banh sau trai
#define MOTOR_D_IN2 32 //banh sau trai

// Relay logic - adjust based on your relay type
#define RELAY_ON HIGH   // Set to LOW if using a low-trigger relay
#define RELAY_OFF LOW   // Set to HIGH if using a low-trigger relay

// DHT sensor configuration
#define DHT_TYPE DHT22

// WiFi credentials
// const char* ssid = "AI-LAB-A0305";
// const char* password = "fit*2025";
 char* ssid = "TP-Link M7350";
 char* password = "password";

// MQTT Configuration
 char* mqtt_server = "fd66ecb3.ala.asia-southeast1.emqxsl.com";
 int mqtt_port = 8883;
 char* mqtt_username = "trancon2";
 char* mqtt_password = "123";
 char* metrics_topic = "/metrics";
 char* commands_topic = "/commands";
 char* turn_signals_topic = "/turn_signals"; // New topic for turn signals
 int mqtt_keep_alive = 30;
bool mqtt_use_tls = true;

// Configuration AP settings
 char* ap_ssid = "CarBoard-Config";
 char* ap_password = "12345678";

// DNS Server for captive portal
const byte DNS_PORT = 53;
DNSServer dnsServer;
bool config_mode = false;
bool settings_changed = false;

// EEPROM Configuration
#define EEPROM_SIZE 512
#define CONFIG_VERSION "V1" // Change when config structure changes
struct ConfigData {
  char version[4]; // For config version check
  char wifi_ssid[33];
  char wifi_password[65];
  char mqtt_server[65];
  int mqtt_port;
  char mqtt_username[33];
  char mqtt_password[33];
  char metrics_topic[33];
  char commands_topic[33];
  bool mqtt_use_tls;
  bool use_static_ip;
  IPAddress static_ip;
  IPAddress gateway;
  IPAddress subnet;
  IPAddress dns1;
};
ConfigData config;

// Tasks
TaskHandle_t taskSensorMQTT = NULL;
TaskHandle_t taskWeb = NULL;
TaskHandle_t taskWifiMonitorHandle = NULL;

// Create objects
WebServer server(80);
LiquidCrystal_I2C lcd(0x27, 16, 2);  // Set the LCD address to 0x27 for a 16 chars and 2 line display
DHT dht(DHT_PIN, DHT_TYPE);
WiFiClientSecure espClient;
PubSubClient mqttClient(espClient);

int emulatorsBattery = 100;

// Direction enum
enum MotorDirection {
  MOTOR_STOP = 0,
  MOTOR_FORWARD,
  MOTOR_BACKWARD,
  MOTOR_LEFT,
  MOTOR_RIGHT
};

// Function prototypes
void handleRoot();
void handleForward();
void handleBackward();
void handleLeft();
void handleRight();
void handleStop();
void handleRelayOn();
void handleRelayOff();
void handleLeftSignalOn();
void handleLeftSignalOff();
void handleRightSignalOn();
void handleRightSignalOff();
void setMotorDirection(MotorDirection direction);
void mqttCallback(char* topic, byte* payload, unsigned int length);
void reconnectMQTT();
void taskSensorMQTTFunction(void * parameter);
void taskWebFunction(void * parameter);
void taskWifiMonitorFunction(void * parameter);
// Configuration interface
void handleConfigPage();
void handleSaveConfig();
void handleConfigSuccess();
void startConfigMode();
void stopConfigMode();
void loadConfig();
void saveConfig();
bool validateConfig();
String getNetworkList();

// Variables for DHT readings
float temperature = 0;
float humidity = 0;
unsigned long lastDHTReadTime = 0;
const long dhtReadInterval = 2000;  // Read DHT every 2 seconds
SemaphoreHandle_t xMutex = NULL;

// LCD status
bool lcd_available = false;

// Variables for speed simulation
float currentSpeed = 0;
const float maxSpeed = 120.0; // Max speed in km/h
const float minSpeedChange = 1.0; // Minimum speed change
const float maxSpeedChange = 5.0; // Maximum speed change

// Add a global variable to track whether to use simulation mode
bool dht_simulation_mode = false;

// Function to update LCD safely
void updateLCD(int row, const String& message) {
  if (lcd_available) {
    lcd.setCursor(0, row);
    lcd.print(message);
    // Clear the rest of the line
    for (int i = message.length(); i < 16; i++) {
      lcd.print(" ");
    }
  }
}

void setup() {
  // Initialize serial
  Serial.begin(115200);
  
  // Initialize EEPROM
  EEPROM.begin(EEPROM_SIZE);
  loadConfig();
  
  // Initialize I2C for LCD with lower speed for better reliability
  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(100000); // Lower I2C clock speed to 100kHz for better reliability
  
  // Check if LCD is available by writing and reading back a byte
  Wire.beginTransmission(0x27); // Default LCD address
  lcd_available = (Wire.endTransmission() == 0);
  
  // Try alternative LCD address if first one failed
  if (!lcd_available) {
    Wire.beginTransmission(0x3F); // Alternative common address
    lcd_available = (Wire.endTransmission() == 0);
  }
  
  if (lcd_available) {
    // Give LCD more time to initialize
    delay(100);
    
    // Try initializing with retries
    bool lcd_init_success = false;
    for (int i = 0; i < 3; i++) {
      // Arduino doesn't support try-catch, so use simple retry
      lcd.init();
      delay(100);
      
      // Verify LCD by writing a test character
      lcd.setCursor(0, 0);
      lcd.print(".");
      delay(50);
      
      lcd_init_success = true;
      break;
    }
    
    if (lcd_init_success) {
      lcd.backlight();
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("Car Board Ready");
      lcd.setCursor(0, 1);
      lcd.print("Init DHT22...");
      Serial.println("LCD initialized");
    } else {
      lcd_available = false;
      Serial.println("LCD init failed after retries");
    }
  } else {
    Serial.println("LCD not found - continuing without display");
  }
  
  // Disable verbose I2C error logging
  esp_log_level_set("i2c", ESP_LOG_NONE);
  
  // Initialize Motor pins
  pinMode(MOTOR_A_IN1, OUTPUT);
  pinMode(MOTOR_A_IN2, OUTPUT);
  pinMode(MOTOR_B_IN1, OUTPUT);
  pinMode(MOTOR_B_IN2, OUTPUT);
  pinMode(MOTOR_C_IN1, OUTPUT);
  pinMode(MOTOR_C_IN2, OUTPUT);
  pinMode(MOTOR_D_IN1, OUTPUT);
  pinMode(MOTOR_D_IN2, OUTPUT);
  
  // Initialize all motors to stop
  digitalWrite(MOTOR_A_IN1, LOW);
  digitalWrite(MOTOR_A_IN2, LOW);
  digitalWrite(MOTOR_B_IN1, LOW);
  digitalWrite(MOTOR_B_IN2, LOW);

  // LOW LOW -> di toi
  // HIGH LOW -> dung
  //LOW HIGH -> DI TOI
  // HIGH HIGH -> DUNG
  digitalWrite(MOTOR_C_IN1, LOW);
  digitalWrite(MOTOR_C_IN2, LOW);

  digitalWrite(MOTOR_D_IN1, LOW);
  digitalWrite(MOTOR_D_IN2, LOW);
  
  // Initialize relay pin with internal pulldown resistor if available
  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, RELAY_ON);  // Ensure relay starts in OFF state
  Serial.println("Relay initialized");
  
  // Initialize DHT sensor with check for proper initialization
  dht.begin();
  delay(1000); // Allow DHT to stabilize
  
  // Test if DHT is working
  float test_humidity = dht.readHumidity();
  float test_temperature = dht.readTemperature();
  
  if (isnan(test_humidity) || isnan(test_temperature)) {
    Serial.println("DHT sensor not detected or not working properly!");
    Serial.println("Starting in DHT simulation mode");
    dht_simulation_mode = true;
    
    // Initialize simulation values
    temperature = 25.0;  // Default starting temperature
    humidity = 50.0;     // Default starting humidity
    
    if (lcd_available) {
      updateLCD(1, "DHT Sim Mode");
    }
  } else {
    Serial.print("DHT sensor working: ");
    Serial.print(test_temperature);
    Serial.print("°C, ");
    Serial.print(test_humidity);
    Serial.println("%");
    
    // Store initial readings
    temperature = test_temperature;
    humidity = test_humidity;
    
    dht_simulation_mode = false;
  }
  
  // Always run in dual mode (AP+STA)
  WiFi.mode(WIFI_AP_STA);
  
  // Start access point for configuration
  WiFi.softAP(ap_ssid, ap_password);
  Serial.print("AP Started. IP: ");
  Serial.println(WiFi.softAPIP());
  updateLCD(0, "AP: " + String(ap_ssid));
  
  // Setup captive portal
  dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());
  
  // Also try to connect to WiFi if credentials are available
  if (strlen(config.wifi_ssid) > 0) {
    Serial.print("Connecting to WiFi: ");
    Serial.println(config.wifi_ssid);
    
    if (config.use_static_ip) {
      if (!WiFi.config(config.static_ip, config.gateway, config.subnet, config.dns1)) {
        Serial.println("STA Failed to configure static IP");
      }
    }
    
    WiFi.begin(config.wifi_ssid, config.wifi_password);
    // Don't wait for connection here, let it connect in background
  }
  
  // Set up all web server routes (for both control and config)
  server.on("/", handleRoot);
  server.on("/forward", handleForward);
  server.on("/backward", handleBackward);
  server.on("/left", handleLeft);
  server.on("/right", handleRight);
  server.on("/stop", handleStop);
  server.on("/led/on", handleRelayOn);
  server.on("/led/off", handleRelayOff);
  server.on("/config", handleConfigPage);
  server.on("/saveconfig", HTTP_POST, handleSaveConfig);
  server.on("/configsuccess", handleConfigSuccess);
  server.on("/restart", []() {
    server.send(200, "text/plain", "Restarting...");
    delay(1000);
    ESP.restart();
  });
  
  // Handle other URLs with captive portal if accessed via AP
  server.onNotFound([]() {
    // If accessed via SoftAP and not requesting a known file type, redirect to config
    if (WiFi.softAPgetStationNum() > 0) {
      IPAddress remoteIP = server.client().remoteIP();
      if (WiFi.softAPIP()[0] == remoteIP[0] && WiFi.softAPIP()[1] == remoteIP[1] && 
          WiFi.softAPIP()[2] == remoteIP[2]) {
        server.sendHeader("Location", "http://" + WiFi.softAPIP().toString() + "/config", true);
        server.send(302, "text/plain", "");
        return;
      }
    }
    server.send(404, "text/plain", "Not Found");
  });
  
  server.begin();
  Serial.println("HTTP server started");
  
  // Initialize MQTT client
  if (mqtt_use_tls) {
    espClient.setInsecure(); // Skip certificate verification (not secure but helps in development)
  }
  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  mqttClient.setKeepAlive(mqtt_keep_alive);
  
  // Create mutex for shared resources
  xMutex = xSemaphoreCreateMutex();
  
  // Create tasks
  xTaskCreate(
    taskSensorMQTTFunction,
    "Sensor+MQTT Task",
    8192,
    NULL,
    1,
    &taskSensorMQTT
  );
  
  xTaskCreate(
    taskWebFunction,
    "Web Task",
    4096,
    NULL,
    1,
    &taskWeb
  );
  
  // Add a WiFi monitoring task
  xTaskCreate(
    taskWifiMonitorFunction,
    "WiFi Monitor",
    4096,
    NULL,
    1,
    &taskWifiMonitorHandle
  );
  
  Serial.println("FreeRTOS tasks started");
}

void loop() {
  // Empty loop - tasks are handling everything
  vTaskDelay(1000 / portTICK_PERIOD_MS); // Keep watchdog happy
}

// Task for handling web requests and DNS
void taskWebFunction(void * parameter) {
  for(;;) {
    // Always process DNS requests for captive portal
    dnsServer.processNextRequest();
    
    // Handle web server requests
    server.handleClient();
    
    vTaskDelay(10 / portTICK_PERIOD_MS); // Small delay to prevent hogging CPU
  }
}

// Task functions
void taskSensorMQTTFunction(void * parameter) {
  for(;;) {
    // Check MQTT connection
    if (!mqttClient.connected()) {
      reconnectMQTT();
    }
    
    if (mqttClient.connected()) {
      mqttClient.loop();
      
      // Take mutex before accessing shared variables
      if (xSemaphoreTake(xMutex, portMAX_DELAY) == pdTRUE) {
        // Read temperature and humidity (or simulate)
        float newHumidity, newTemperature;
        bool validReadings = true;
        
        if (!dht_simulation_mode) {
          // Attempt real sensor readings
          newHumidity = dht.readHumidity();
          newTemperature = dht.readTemperature();
          
          // Check if readings are valid
          validReadings = !isnan(newHumidity) && !isnan(newTemperature);
          
          // If readings failed but we weren't in simulation mode before, switch to simulation
          if (!validReadings && !dht_simulation_mode) {
            static int failCount = 0;
            failCount++;
            
            if (failCount >= 3) {
              Serial.println("DHT read failed multiple times, switching to simulation mode");
              dht_simulation_mode = true;
              failCount = 0;
            }
          }
        }
        
        // Either use valid readings or simulate data
        if (validReadings && !dht_simulation_mode) {
          // Use actual DHT readings
          humidity = newHumidity;
          temperature = newTemperature;
          
          Serial.print("Temperature: ");
          Serial.print(temperature);
          Serial.print("°C, Humidity: ");
          Serial.print(humidity);
          Serial.print(", Speed: ");
          Serial.print(currentSpeed);
          Serial.println(" km/h");
        } else {
          // Generate simulated data
          static unsigned long lastSimTime = 0;
          
          // Only change values every 15 seconds to make it appear realistic
          if (millis() - lastSimTime > 15000) {
            lastSimTime = millis();
            // Random fluctuations within reasonable ranges
            temperature += random(-100, 100) / 100.0;     // +/- 1°C change
            humidity += random(-200, 200) / 100.0; // +/- 2% change
            
            // Keep values in realistic ranges
            temperature = constrain(temperature, 15.0, 35.0);
            humidity = constrain(humidity, 30.0, 90.0);
          }
          
          Serial.print("Simulated Temperature: ");
          Serial.print(temperature);
          Serial.print("°C, Humidity: ");
          Serial.print(humidity);
          Serial.print(", Speed: ");
          Serial.print(currentSpeed);
          Serial.println(" km/h (SIMULATED)");
        }
        
        // Simulate speed with realistic changes regardless of DHT status
        simulateSpeed();
        
        // Update LCD
        if (lcd_available) {
          char lcdBuffer[17];
          sprintf(lcdBuffer, "T:%.1fC%s Spd:%.1f", 
                  temperature, 
                  dht_simulation_mode ? "*" : "", // Add asterisk to indicate simulation
                  currentSpeed);
          updateLCD(1, String(lcdBuffer));
        }
        
        // Publish sensor data to MQTT
        DynamicJsonDocument doc(256);
        doc["temperature"] = temperature;
        doc["humidity"] = humidity;
        doc["battery"] = emulatorsBattery;
        doc["speed"] = currentSpeed;
        
        if (dht_simulation_mode) {
          doc["simulated"] = true;  // Flag to indicate data is simulated
        }
        
        char mqttBuffer[256];
        serializeJson(doc, mqttBuffer);
        mqttClient.publish(metrics_topic, mqttBuffer);
        
        // Mock battery decrease for testing
        if (emulatorsBattery > 0) {
          emulatorsBattery -= 1;
          if (emulatorsBattery < 0) emulatorsBattery = 0;
        }
        
        xSemaphoreGive(xMutex);
      }
    }
    
    vTaskDelay(5000 / portTICK_PERIOD_MS); // Read and publish every 5 seconds
  }
}

// MQTT reconnection function
void reconnectMQTT() {
  int attempts = 0;
  while (!mqttClient.connected() && attempts < 5) {
    Serial.print("Attempting MQTT connection...");
    
    String clientId = "ESP32CarBoard-";
    clientId += String(random(0xffff), HEX);
    
    if (mqttClient.connect(clientId.c_str(), config.mqtt_username, config.mqtt_password)) {
      Serial.println("connected");
      
      // Subscribe to command topic
      mqttClient.subscribe(config.commands_topic);
      
      // Update LCD
      updateLCD(0, "MQTT Connected  ");
    } else {
      Serial.print("failed, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" retrying...");
      
      updateLCD(0, "MQTT Failed     ");
      
      attempts++;
      vTaskDelay(5000 / portTICK_PERIOD_MS);
    }
  }
}

// MQTT callback
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  Serial.print("Message arrived [");
  Serial.print(topic);
  Serial.print("] ");
  
  char message[length + 1];
  for (unsigned int i = 0; i < length; i++) {
    message[i] = (char)payload[i];
    Serial.print((char)payload[i]);
  }
  message[length] = '\0';
  Serial.println();
}

// Simulate speed with realistic changes based on current motor direction
void simulateSpeed() {
  // Get a random value for speed change
  float speedChange = random(int(minSpeedChange * 10), int(maxSpeedChange * 10)) / 10.0;
  
  // 30% chance to decrease speed, 70% chance to increase when moving
  bool decreaseSpeed = (random(100) < 30);
  
  // Adjust speed based on motor state
  switch (getCurrentMotorState()) {
    case MOTOR_FORWARD:
    case MOTOR_BACKWARD:
    case MOTOR_LEFT:
    case MOTOR_RIGHT:
      // If moving, speed can go up or down, but never below a minimum
      if (decreaseSpeed && currentSpeed > 5.0) {
        currentSpeed -= speedChange;
      } else if (currentSpeed < maxSpeed) {
        currentSpeed += speedChange;
      }
      // Cap at max speed
      if (currentSpeed > maxSpeed) currentSpeed = maxSpeed;
      break;
      
    case MOTOR_STOP:
    default:
      // When stopped, gradually decrease speed to 0
      if (currentSpeed > 0) {
        currentSpeed -= speedChange * 2; // Decelerate faster when stopped
        if (currentSpeed < 0) currentSpeed = 0;
      }
      break;
  }
}

// Track current motor state
MotorDirection currentMotorState = MOTOR_STOP;

// Get current motor state
MotorDirection getCurrentMotorState() {
  return currentMotorState;
}

// Set motor direction
void setMotorDirection(MotorDirection direction) {
  // Update current motor state
  currentMotorState = direction;
  
  switch (direction) {
    case MOTOR_FORWARD:
      // All 4 wheels move forward
      digitalWrite(MOTOR_A_IN1, HIGH);
      digitalWrite(MOTOR_A_IN2, LOW);
      digitalWrite(MOTOR_B_IN1, HIGH);
      digitalWrite(MOTOR_B_IN2, LOW);

      digitalWrite(MOTOR_C_IN1, HIGH);
      digitalWrite(MOTOR_C_IN2, LOW);
      digitalWrite(MOTOR_D_IN1, HIGH);
      digitalWrite(MOTOR_D_IN2, LOW);
      Serial.println("Motors: FORWARD");
      break;
      
    case MOTOR_BACKWARD:
      // All 4 wheels move backward
      digitalWrite(MOTOR_A_IN1, LOW);
      digitalWrite(MOTOR_A_IN2, HIGH);
      digitalWrite(MOTOR_B_IN1, LOW);
      digitalWrite(MOTOR_B_IN2, HIGH);

      digitalWrite(MOTOR_C_IN1, LOW);
      digitalWrite(MOTOR_C_IN2, HIGH);
      digitalWrite(MOTOR_D_IN1, LOW);
      digitalWrite(MOTOR_D_IN2, HIGH);
      Serial.println("Motors: BACKWARD");
      break;
      
    case MOTOR_LEFT:
      // Left wheels move backward, right wheels move forward
      // Right wheels (A and C)
      digitalWrite(MOTOR_A_IN1, HIGH);
      digitalWrite(MOTOR_A_IN2, LOW);
      digitalWrite(MOTOR_B_IN1, LOW);
      digitalWrite(MOTOR_B_IN2, HIGH);
      // Left wheels (B and D)
      digitalWrite(MOTOR_C_IN1, HIGH);
      digitalWrite(MOTOR_C_IN2, LOW);
      digitalWrite(MOTOR_D_IN1, LOW);
      digitalWrite(MOTOR_D_IN2, HIGH);
      Serial.println("Motors: LEFT");
      break;
      
    case MOTOR_RIGHT:
      // Right wheels move backward, left wheels move forward
      // Right wheels (A and C)
      digitalWrite(MOTOR_A_IN1, LOW);
      digitalWrite(MOTOR_A_IN2, HIGH);
      digitalWrite(MOTOR_B_IN1, HIGH);
      digitalWrite(MOTOR_B_IN2, LOW);
      // Left wheels (B and D)
      digitalWrite(MOTOR_C_IN1, LOW);
      digitalWrite(MOTOR_C_IN2, HIGH);
      digitalWrite(MOTOR_D_IN1, HIGH);
      digitalWrite(MOTOR_D_IN2, LOW);
      Serial.println("Motors: RIGHT");
      break;
      
    case MOTOR_STOP:
    default:
      // Stop all motors
      digitalWrite(MOTOR_A_IN1, LOW);
      digitalWrite(MOTOR_A_IN2, LOW);
      digitalWrite(MOTOR_B_IN1, LOW);
      digitalWrite(MOTOR_B_IN2, LOW);

      digitalWrite(MOTOR_C_IN1, LOW);
      digitalWrite(MOTOR_C_IN2, LOW);
      digitalWrite(MOTOR_D_IN1, LOW);
      digitalWrite(MOTOR_D_IN2, LOW);
      Serial.println("Motors: STOP");
      break;
  }
}

// Web server route handlers
void handleRoot() {
  String html = "<!DOCTYPE html>"
                "<html>"
                "<head>"
                "    <title>ESP32 Control Panel</title>"
                "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                "    <style>"
                "        body { font-family: Arial; text-align: center; margin: 0; padding: 20px; }"
                "        .button {"
                "            padding: 20px 40px;"
                "            font-size: 20px;"
                "            margin: 10px;"
                "            cursor: pointer;"
                "            background-color: #4CAF50;"
                "            color: white;"
                "            border: none;"
                "            border-radius: 5px;"
                "        }"
                "        .stop { background-color: #f44336; }"
                "        .led-on { background-color: #ffeb3b; color: black; }"
                "        .led-off { background-color: #607d8b; }"
                "        .controls { margin: 20px; }"
                "        .led-control { margin-top: 30px; }"
                "        .status { margin: 20px; padding: 10px; background-color: #f1f1f1; border-radius: 5px; }"
                "        .config-link { margin-top: 20px; }"
                "        .config-link a { color: #2196F3; text-decoration: none; }"
                "        .config-link a:hover { text-decoration: underline; }"
                "    </style>"
                "</head>"
                "<body>"
                "    <h1>ESP32 Control Panel</h1>"
                "    <div class=\"status\">"
                "        <p>Temperature: " + String(temperature) + "°C</p>"
                "        <p>Humidity: " + String(humidity) + "%</p>"
                "        <p>Battery: " + String(emulatorsBattery) + "%</p>"
                "    </div>"
                "    <div class=\"controls\">"
                "        <div>"
                "            <button class=\"button\" onclick=\"fetch('/forward')\">Forward</button>"
                "        </div>"
                "        <div>"
                "            <button class=\"button\" onclick=\"fetch('/left')\">Left</button>"
                "            <button class=\"button stop\" onclick=\"fetch('/stop')\">Stop</button>"
                "            <button class=\"button\" onclick=\"fetch('/right')\">Right</button>"
                "        </div>"
                "        <div>"
                "            <button class=\"button\" onclick=\"fetch('/backward')\">Backward</button>"
                "        </div>"
                "    </div>"
                "    <div class=\"led-control\">"
                "        <h2>Relay Control</h2>"
                "        <button class=\"button led-on\" onclick=\"fetch('/led/on')\">RELAY ON</button>"
                "        <button class=\"button led-off\" onclick=\"fetch('/led/off')\">RELAY OFF</button>"
                "    </div>"
                "    <div class=\"config-link\">"
                "        <a href=\"/config\">⚙️ Advanced Configuration</a>"
                "    </div>"
                "    <script>"
                "        setInterval(function() { location.reload(); }, 10000);"
                "    </script>"
                "</body>"
                "</html>";
  
  server.send(200, "text/html", html);
}

void handleForward() {
  setMotorDirection(MOTOR_FORWARD);
  server.send(200, "text/plain", "OK");
}

void handleBackward() {
  setMotorDirection(MOTOR_BACKWARD);
  server.send(200, "text/plain", "OK");
}

void handleLeft() {
  setMotorDirection(MOTOR_LEFT);
  server.send(200, "text/plain", "OK");
}

void handleRight() {
  setMotorDirection(MOTOR_RIGHT);
  server.send(200, "text/plain", "OK");
}

void handleStop() {
  setMotorDirection(MOTOR_STOP);
  server.send(200, "text/plain", "OK");
}

void handleRelayOn() {
  digitalWrite(RELAY_PIN, RELAY_ON);
  Serial.println("Relay: ON");
  server.send(200, "text/plain", "RELAY ON");
}

void handleRelayOff() {
  digitalWrite(RELAY_PIN, RELAY_OFF);
  Serial.println("Relay: OFF");
  server.send(200, "text/plain", "RELAY OFF");
}

// Connect to WiFi using stored credentials
void connectToWiFi() {
  Serial.print("Connecting to WiFi...");
  updateLCD(1, "WiFi: " + String(ssid));
  
  // Use stored credentials if available, otherwise use defaults
  if (strlen(config.wifi_ssid) > 0) {
    ssid = config.wifi_ssid;
    password = config.wifi_password;
  }
  
  // Configure static IP if enabled
  if (config.use_static_ip) {
    if (!WiFi.config(config.static_ip, config.gateway, config.subnet, config.dns1)) {
      Serial.println("STA Failed to configure static IP");
    }
  }
  
  WiFi.begin(ssid, password);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("");
    Serial.print("Connected to WiFi. IP address: ");
    Serial.println(WiFi.localIP());
    
    updateLCD(1, WiFi.localIP().toString());
    delay(2000);
  } else {
    Serial.println("Failed to connect to WiFi");
    updateLCD(1, "WiFi Failed    ");
    
    // Enter config mode on WiFi failure
    delay(2000);
    startConfigMode();
  }
}

// Start configuration AP mode
void startConfigMode() {
  config_mode = true;
  
  updateLCD(0, "Config Mode");
  updateLCD(1, ap_ssid);
  
  // Start AP for configuration while keeping station mode
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(ap_ssid, ap_password);
  
  Serial.print("Config AP started. IP: ");
  Serial.println(WiFi.softAPIP());
  
  // Setup captive portal
  dnsServer.start(DNS_PORT, "*", WiFi.softAPIP());
  
  // Note: we don't stop existing tasks or web server since we want both to run
}

// Stop configuration mode and restart
void stopConfigMode() {
  if (config_mode) {
    dnsServer.stop();
    server.stop();
    delay(500);
    ESP.restart();
  }
}

// Load configuration from EEPROM
void loadConfig() {
  Serial.println("Loading configuration...");
  EEPROM.get(0, config);
  
  // Check if config is valid (version matches)
  if (strcmp(config.version, CONFIG_VERSION) != 0) {
    Serial.println("Config version mismatch. Using defaults.");
    // Set default configuration
    strcpy(config.version, CONFIG_VERSION);
    strcpy(config.wifi_ssid, ssid);
    strcpy(config.wifi_password, password);
    strcpy(config.mqtt_server, mqtt_server);
    config.mqtt_port = mqtt_port;
    strcpy(config.mqtt_username, mqtt_username);
    strcpy(config.mqtt_password, mqtt_password);
    strcpy(config.metrics_topic, metrics_topic);
    strcpy(config.commands_topic, commands_topic);
    config.mqtt_use_tls = mqtt_use_tls;
    config.use_static_ip = false;
    config.static_ip = IPAddress(0, 0, 0, 0);
    config.gateway = IPAddress(0, 0, 0, 0);
    config.subnet = IPAddress(255, 255, 255, 0);
    config.dns1 = IPAddress(8, 8, 8, 8);
    
    saveConfig();
  } else {
    // Apply loaded configuration
    mqtt_server = config.mqtt_server;
    mqtt_port = config.mqtt_port;
    mqtt_username = config.mqtt_username;
    mqtt_password = config.mqtt_password;
    metrics_topic = config.metrics_topic;
    commands_topic = config.commands_topic;
    mqtt_use_tls = config.mqtt_use_tls;
    Serial.println("Configuration loaded successfully");
  }
}

// Save configuration to EEPROM
void saveConfig() {
  Serial.println("Saving configuration...");
  EEPROM.put(0, config);
  EEPROM.commit();
  Serial.println("Configuration saved");
}

// Validate configuration parameters
bool validateConfig() {
  if (strlen(config.wifi_ssid) < 1) return false;
  if (strlen(config.mqtt_server) < 1) return false;
  if (config.mqtt_port < 1 || config.mqtt_port > 65535) return false;
  if (strlen(config.metrics_topic) < 1) return false;
  if (strlen(config.commands_topic) < 1) return false;
  return true;
}

// Get list of available WiFi networks
String getNetworkList() {
  String networkList = "";
  int n = WiFi.scanNetworks();
  
  if (n == 0) {
    return "<option value=''>No networks found</option>";
  }
  
  for (int i = 0; i < n; ++i) {
    String encryption = (WiFi.encryptionType(i) == WIFI_AUTH_OPEN) ? " (Open)" : " (Secured)";
    networkList += "<option value='" + WiFi.SSID(i) + "'>" + WiFi.SSID(i) + " (" + WiFi.RSSI(i) + "dBm)" + encryption + "</option>";
    delay(10);
  }
  
  return networkList;
}

// Configuration interface
void handleConfigPage() {
  String networks = getNetworkList();
  
  String html = "<!DOCTYPE html>"
                "<html lang='en'>"
                "<head>"
                "  <meta charset='UTF-8'>"
                "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
                "  <title>Car Board Configuration</title>"
                "  <style>"
                "    :root {"
                "      --primary: #4361ee;"
                "      --secondary: #3f37c9;"
                "      --success: #4cc9f0;"
                "      --info: #4895ef;"
                "      --warning: #f72585;"
                "      --danger: #e63946;"
                "      --light: #f8f9fa;"
                "      --dark: #212529;"
                "    }"
                "    body {"
                "      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;"
                "      margin: 0;"
                "      padding: 20px;"
                "      background-color: #f5f7fa;"
                "      color: var(--dark);"
                "    }"
                "    .container {"
                "      max-width: 800px;"
                "      margin: 0 auto;"
                "      background: white;"
                "      border-radius: 10px;"
                "      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);"
                "      overflow: hidden;"
                "    }"
                "    header {"
                "      background: linear-gradient(135deg, var(--primary) 0%, var(--secondary) 100%);"
                "      color: white;"
                "      padding: 20px;"
                "      text-align: center;"
                "    }"
                "    h1 {"
                "      margin: 0;"
                "      font-size: 24px;"
                "    }"
                "    .content {"
                "      padding: 20px;"
                "    }"
                "    .tab-container {"
                "      margin-bottom: 20px;"
                "    }"
                "    .tabs {"
                "      display: flex;"
                "      border-bottom: 1px solid #dee2e6;"
                "    }"
                "    .tab {"
                "      padding: 10px 15px;"
                "      cursor: pointer;"
                "      border-bottom: 2px solid transparent;"
                "      transition: all 0.3s;"
                "    }"
                "    .tab.active {"
                "      border-bottom: 2px solid var(--primary);"
                "      color: var(--primary);"
                "      font-weight: bold;"
                "    }"
                "    .tab-content {"
                "      display: none;"
                "      padding: 20px 0;"
                "    }"
                "    .tab-content.active {"
                "      display: block;"
                "    }"
                "    .form-group {"
                "      margin-bottom: 15px;"
                "    }"
                "    label {"
                "      display: block;"
                "      margin-bottom: 5px;"
                "      font-weight: 500;"
                "    }"
                "    input[type='text'], input[type='password'], input[type='number'], select {"
                "      width: 100%;"
                "      padding: 10px;"
                "      border: 1px solid #ddd;"
                "      border-radius: 5px;"
                "      box-sizing: border-box;"
                "      font-size: 16px;"
                "    }"
                "    .checkbox-container {"
                "      display: flex;"
                "      align-items: center;"
                "      margin-bottom: 15px;"
                "    }"
                "    .checkbox-container input {"
                "      margin-right: 10px;"
                "    }"
                "    .ip-inputs {"
                "      display: flex;"
                "      gap: 5px;"
                "    }"
                "    .ip-inputs input {"
                "      width: 100%;"
                "      text-align: center;"
                "    }"
                "    button {"
                "      background-color: var(--primary);"
                "      color: white;"
                "      border: none;"
                "      padding: 12px 20px;"
                "      font-size: 16px;"
                "      border-radius: 5px;"
                "      cursor: pointer;"
                "      transition: background-color 0.3s;"
                "      width: 100%;"
                "    }"
                "    button:hover {"
                "      background-color: var(--secondary);"
                "    }"
                "    .status {"
                "      padding: 15px;"
                "      border-radius: 5px;"
                "      margin-bottom: 20px;"
                "    }"
                "    .status-info {"
                "      background-color: rgba(72, 149, 239, 0.2);"
                "      border-left: 4px solid var(--info);"
                "    }"
                "    .refresh-btn {"
                "      background-color: var(--info);"
                "      padding: 5px 10px;"
                "      font-size: 14px;"
                "      margin-left: 10px;"
                "    }"
                "    footer {"
                "      text-align: center;"
                "      margin-top: 20px;"
                "      color: #6c757d;"
                "      font-size: 14px;"
                "    }"
                "    @media (max-width: 600px) {"
                "      .tabs {"
                "        flex-direction: column;"
                "      }"
                "      .tab {"
                "        border-bottom: 1px solid #dee2e6;"
                "      }"
                "      .tab.active {"
                "        border-bottom: 1px solid var(--primary);"
                "        border-left: 4px solid var(--primary);"
                "      }"
                "      .ip-inputs {"
                "        flex-wrap: wrap;"
                "      }"
                "    }"
                "  </style>"
                "</head>"
                "<body>"
                "  <div class='container'>"
                "    <header>"
                "      <h1>Car Board Configuration</h1>"
                "    </header>"
                "    <div class='content'>"
                "      <div class='status status-info'>"
                "        <p>Configure your CarBoard settings below. Device will restart after saving.</p>"
                "      </div>"
                "      <div class='tab-container'>"
                "        <div class='tabs'>"
                "          <div class='tab active' data-tab='wifi'>WiFi Settings</div>"
                "          <div class='tab' data-tab='mqtt'>MQTT Settings</div>"
                "          <div class='tab' data-tab='network'>Network Settings</div>"
                "        </div>"
                "        <form action='/saveconfig' method='post' id='configForm'>"
                "          <div class='tab-content active' id='wifi-tab'>"
                "            <div class='form-group'>"
                "              <label for='wifi_ssid'>WiFi Network</label>"
                "              <select id='wifi_ssid' name='wifi_ssid' onchange='updateWifiSSID()'>"
                "                " + networks + ""
                "              </select>"
                "              <button type='button' class='refresh-btn' onclick='refreshNetworks()'>Refresh</button>"
                "            </div>"
                "            <div class='form-group'>"
                "              <label for='wifi_ssid_custom'>WiFi SSID</label>"
                "              <input type='text' id='wifi_ssid_custom' name='wifi_ssid_custom' value='" + String(config.wifi_ssid) + "'>"
                "            </div>"
                "            <div class='form-group'>"
                "              <label for='wifi_password'>WiFi Password</label>"
                "              <input type='password' id='wifi_password' name='wifi_password' value='" + String(config.wifi_password) + "'>"
                "            </div>"
                "          </div>"
                "          <div class='tab-content' id='mqtt-tab'>"
                "            <div class='form-group'>"
                "              <label for='mqtt_server'>MQTT Broker Address</label>"
                "              <input type='text' id='mqtt_server' name='mqtt_server' value='" + String(config.mqtt_server) + "'>"
                "            </div>"
                "            <div class='form-group'>"
                "              <label for='mqtt_port'>MQTT Port</label>"
                "              <input type='number' id='mqtt_port' name='mqtt_port' value='" + String(config.mqtt_port) + "'>"
                "            </div>"
                "            <div class='checkbox-container'>"
                "              <input type='checkbox' id='mqtt_use_tls' name='mqtt_use_tls' " + (config.mqtt_use_tls ? "checked" : "") + ">"
                "              <label for='mqtt_use_tls'>Use TLS/SSL</label>"
                "            </div>"
                "            <div class='form-group'>"
                "              <label for='mqtt_username'>MQTT Username</label>"
                "              <input type='text' id='mqtt_username' name='mqtt_username' value='" + String(config.mqtt_username) + "'>"
                "            </div>"
                "            <div class='form-group'>"
                "              <label for='mqtt_password'>MQTT Password</label>"
                "              <input type='password' id='mqtt_password' name='mqtt_password' value='" + String(config.mqtt_password) + "'>"
                "            </div>"
                "            <div class='form-group'>"
                "              <label for='metrics_topic'>Metrics Topic</label>"
                "              <input type='text' id='metrics_topic' name='metrics_topic' value='" + String(config.metrics_topic) + "'>"
                "            </div>"
                "            <div class='form-group'>"
                "              <label for='commands_topic'>Commands Topic</label>"
                "              <input type='text' id='commands_topic' name='commands_topic' value='" + String(config.commands_topic) + "'>"
                "            </div>"
                "          </div>"
                "          <div class='tab-content' id='network-tab'>"
                "            <div class='checkbox-container'>"
                "              <input type='checkbox' id='use_static_ip' name='use_static_ip' " + (config.use_static_ip ? "checked" : "") + " onchange='toggleStaticIP()'>"
                "              <label for='use_static_ip'>Use Static IP</label>"
                "            </div>"
                "            <div id='static_ip_fields' " + (config.use_static_ip ? "" : "style='display:none'") + ">"
                "              <div class='form-group'>"
                "                <label for='static_ip'>Static IP</label>"
                "                <div class='ip-inputs' id='static_ip_inputs'>"
                "                  <input type='number' name='ip1' min='0' max='255' value='" + String(config.static_ip[0]) + "'>"
                "                  <input type='number' name='ip2' min='0' max='255' value='" + String(config.static_ip[1]) + "'>"
                "                  <input type='number' name='ip3' min='0' max='255' value='" + String(config.static_ip[2]) + "'>"
                "                  <input type='number' name='ip4' min='0' max='255' value='" + String(config.static_ip[3]) + "'>"
                "                </div>"
                "              </div>"
                "              <div class='form-group'>"
                "                <label for='gateway'>Gateway</label>"
                "                <div class='ip-inputs'>"
                "                  <input type='number' name='gw1' min='0' max='255' value='" + String(config.gateway[0]) + "'>"
                "                  <input type='number' name='gw2' min='0' max='255' value='" + String(config.gateway[1]) + "'>"
                "                  <input type='number' name='gw3' min='0' max='255' value='" + String(config.gateway[2]) + "'>"
                "                  <input type='number' name='gw4' min='0' max='255' value='" + String(config.gateway[3]) + "'>"
                "                </div>"
                "              </div>"
                "              <div class='form-group'>"
                "                <label for='subnet'>Subnet Mask</label>"
                "                <div class='ip-inputs'>"
                "                  <input type='number' name='sn1' min='0' max='255' value='" + String(config.subnet[0]) + "'>"
                "                  <input type='number' name='sn2' min='0' max='255' value='" + String(config.subnet[1]) + "'>"
                "                  <input type='number' name='sn3' min='0' max='255' value='" + String(config.subnet[2]) + "'>"
                "                  <input type='number' name='sn4' min='0' max='255' value='" + String(config.subnet[3]) + "'>"
                "                </div>"
                "              </div>"
                "              <div class='form-group'>"
                "                <label for='dns'>DNS Server</label>"
                "                <div class='ip-inputs'>"
                "                  <input type='number' name='dns1' min='0' max='255' value='" + String(config.dns1[0]) + "'>"
                "                  <input type='number' name='dns2' min='0' max='255' value='" + String(config.dns1[1]) + "'>"
                "                  <input type='number' name='dns3' min='0' max='255' value='" + String(config.dns1[2]) + "'>"
                "                  <input type='number' name='dns4' min='0' max='255' value='" + String(config.dns1[3]) + "'>"
                "                </div>"
                "              </div>"
                "            </div>"
                "          </div>"
                "          <button type='submit'>Save Configuration</button>"
                "        </form>"
                "      </div>"
                "    </div>"
                "    <footer>"
                "      <p>Car Board Configuration Interface v1.0</p>"
                "    </footer>"
                "  </div>"
                "  <script>"
                "    document.addEventListener('DOMContentLoaded', function() {"
                "      const tabs = document.querySelectorAll('.tab');"
                "      tabs.forEach(tab => {"
                "        tab.addEventListener('click', function() {"
                "          const tabId = this.getAttribute('data-tab');"
                "          document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));"
                "          document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));"
                "          this.classList.add('active');"
                "          document.getElementById(tabId + '-tab').classList.add('active');"
                "        });"
                "      });"
                "      updateWifiSSID();"
                "    });"
                "    function updateWifiSSID() {"
                "      const select = document.getElementById('wifi_ssid');"
                "      const input = document.getElementById('wifi_ssid_custom');"
                "      if (select.value) {"
                "        input.value = select.value;"
                "      }"
                "    }"
                "    function refreshNetworks() {"
                "      window.location.reload();"
                "    }"
                "    function toggleStaticIP() {"
                "      const useStaticIP = document.getElementById('use_static_ip').checked;"
                "      document.getElementById('static_ip_fields').style.display = useStaticIP ? 'block' : 'none';"
                "    }"
                "  </script>"
                "</body>"
                "</html>";
  
  server.send(200, "text/html", html);
}

void handleSaveConfig() {
  // Store the previous values for comparison
  String prevWifiSSID = String(config.wifi_ssid);
  String prevWifiPassword = String(config.wifi_password);
  
  // Update WiFi settings
  if (server.hasArg("wifi_ssid_custom")) {
    server.arg("wifi_ssid_custom").toCharArray(config.wifi_ssid, sizeof(config.wifi_ssid));
  }
  if (server.hasArg("wifi_password")) {
    server.arg("wifi_password").toCharArray(config.wifi_password, sizeof(config.wifi_password));
  }
  
  // Update MQTT settings
  if (server.hasArg("mqtt_server")) {
    server.arg("mqtt_server").toCharArray(config.mqtt_server, sizeof(config.mqtt_server));
  }
  if (server.hasArg("mqtt_port")) {
    config.mqtt_port = server.arg("mqtt_port").toInt();
  }
  if (server.hasArg("mqtt_username")) {
    server.arg("mqtt_username").toCharArray(config.mqtt_username, sizeof(config.mqtt_username));
  }
  if (server.hasArg("mqtt_password")) {
    server.arg("mqtt_password").toCharArray(config.mqtt_password, sizeof(config.mqtt_password));
  }
  if (server.hasArg("metrics_topic")) {
    server.arg("metrics_topic").toCharArray(config.metrics_topic, sizeof(config.metrics_topic));
  }
  if (server.hasArg("commands_topic")) {
    server.arg("commands_topic").toCharArray(config.commands_topic, sizeof(config.commands_topic));
  }
  
  // TLS setting
  config.mqtt_use_tls = server.hasArg("mqtt_use_tls");
  
  // Network settings
  config.use_static_ip = server.hasArg("use_static_ip");
  if (config.use_static_ip) {
    config.static_ip[0] = server.arg("ip1").toInt();
    config.static_ip[1] = server.arg("ip2").toInt();
    config.static_ip[2] = server.arg("ip3").toInt();
    config.static_ip[3] = server.arg("ip4").toInt();
    
    config.gateway[0] = server.arg("gw1").toInt();
    config.gateway[1] = server.arg("gw2").toInt();
    config.gateway[2] = server.arg("gw3").toInt();
    config.gateway[3] = server.arg("gw4").toInt();
    
    config.subnet[0] = server.arg("sn1").toInt();
    config.subnet[1] = server.arg("sn2").toInt();
    config.subnet[2] = server.arg("sn3").toInt();
    config.subnet[3] = server.arg("sn4").toInt();
    
    config.dns1[0] = server.arg("dns1").toInt();
    config.dns1[1] = server.arg("dns2").toInt();
    config.dns1[2] = server.arg("dns3").toInt();
    config.dns1[3] = server.arg("dns4").toInt();
  }
  
  // Validate and save configuration
  if (validateConfig()) {
    saveConfig();
    settings_changed = true;
    
    // Apply new settings for MQTT
    mqtt_server = config.mqtt_server;
    mqtt_port = config.mqtt_port;
    mqtt_username = config.mqtt_username;
    mqtt_password = config.mqtt_password;
    metrics_topic = config.metrics_topic;
    commands_topic = config.commands_topic;
    mqtt_use_tls = config.mqtt_use_tls;
    
    // Redirect to success page
    server.sendHeader("Location", "/configsuccess", true);
    server.send(302, "text/plain", "");
  } else {
    server.send(400, "text/plain", "Invalid configuration");
  }
}

void handleConfigSuccess() {
  String html = "<!DOCTYPE html>"
                "<html lang='en'>"
                "<head>"
                "  <meta charset='UTF-8'>"
                "  <meta name='viewport' content='width=device-width, initial-scale=1.0'>"
                "  <title>Configuration Saved</title>"
                "  <style>"
                "    body {"
                "      font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;"
                "      margin: 0;"
                "      padding: 20px;"
                "      background-color: #f5f7fa;"
                "      color: #212529;"
                "      text-align: center;"
                "      display: flex;"
                "      justify-content: center;"
                "      align-items: center;"
                "      min-height: 100vh;"
                "    }"
                "    .container {"
                "      max-width: 600px;"
                "      background: white;"
                "      border-radius: 10px;"
                "      box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);"
                "      padding: 30px;"
                "    }"
                "    h1 {"
                "      color: #4361ee;"
                "      margin-bottom: 20px;"
                "    }"
                "    .success-icon {"
                "      font-size: 80px;"
                "      color: #4cc9f0;"
                "      margin-bottom: 20px;"
                "    }"
                "    p {"
                "      font-size: 18px;"
                "      margin-bottom: 30px;"
                "    }"
                "    button {"
                "      background-color: #4361ee;"
                "      color: white;"
                "      border: none;"
                "      padding: 12px 20px;"
                "      font-size: 16px;"
                "      border-radius: 5px;"
                "      cursor: pointer;"
                "      transition: background-color 0.3s;"
                "    }"
                "    button:hover {"
                "      background-color: #3f37c9;"
                "    }"
                "    .countdown {"
                "      margin-top: 20px;"
                "      font-size: 14px;"
                "      color: #6c757d;"
                "    }"
                "  </style>"
                "</head>"
                "<body>"
                "  <div class='container'>"
                "    <div class='success-icon'>✓</div>"
                "    <h1>Configuration Saved Successfully</h1>"
                "    <p>Your settings have been saved. The device will restart in <span id='countdown'>5</span> seconds.</p>"
                "    <button onclick='restartNow()'>Restart Now</button>"
                "    <div class='countdown'>You will be disconnected from the configuration network.</div>"
                "  </div>"
                "  <script>"
                "    let seconds = 5;"
                "    const countdownElem = document.getElementById('countdown');"
                "    "
                "    const timer = setInterval(() => {"
                "      seconds--;"
                "      countdownElem.textContent = seconds;"
                "      if (seconds <= 0) {"
                "        clearInterval(timer);"
                "        restartNow();"
                "      }"
                "    }, 1000);"
                "    "
                "    function restartNow() {"
                "      fetch('/restart')"
                "        .then(() => {"
                "          // Handle disconnection gracefully"
                "        })"
                "        .catch(() => {"
                "          // Expected disconnect"
                "        });"
                "    }"
                "  </script>"
                "</body>"
                "</html>";
  
  server.send(200, "text/html", html);
  
  // Set up restart after a short delay
  if (settings_changed) {
    delay(5000); // Give the client time to get the page
    ESP.restart();
  }
}

// Task to monitor WiFi status and update LCD
void taskWifiMonitorFunction(void * parameter) {
  bool wasConnected = false;
  bool isFirstConnect = true;
  
  for(;;) {
    bool isConnected = WiFi.status() == WL_CONNECTED;
    
    // On connection state change
    if (isConnected != wasConnected) {
      wasConnected = isConnected;
      
      if (isConnected) {
        // Just connected
        Serial.print("Connected to WiFi. IP: ");
        Serial.println(WiFi.localIP());
        updateLCD(1, WiFi.localIP().toString());
        
        // If this is first connect, store credentials if they worked
        if (isFirstConnect && strlen(config.wifi_ssid) == 0) {
          strcpy(config.wifi_ssid, ssid);
          strcpy(config.wifi_password, password);
          saveConfig();
          Serial.println("Saved working WiFi credentials");
        }
        isFirstConnect = false;
        
      } else {
        // Just disconnected
        Serial.println("Disconnected from WiFi");
        updateLCD(1, "WiFi Disconnected");
        
        // Try to reconnect
        if (strlen(config.wifi_ssid) > 0) {
          WiFi.begin(config.wifi_ssid, config.wifi_password);
        }
      }
    }
    
    // Print connection info periodically
    static unsigned long lastInfoTime = 0;
    unsigned long now = millis();
    if (now - lastInfoTime > 30000) {  // Every 30 seconds
      lastInfoTime = now;
      
      Serial.print("WiFi Status: ");
      if (isConnected) {
        Serial.print("Connected to: ");
        Serial.print(WiFi.SSID());
        Serial.print(" (");
        Serial.print(WiFi.RSSI());
        Serial.print(" dBm) IP: ");
        Serial.println(WiFi.localIP());
      } else {
        Serial.println("Disconnected");
      }
      
      Serial.print("AP Status: ");
      Serial.print(WiFi.softAPIP());
      Serial.print(" (");
      Serial.print(WiFi.softAPgetStationNum());
      Serial.println(" clients)");
    }
    
    vTaskDelay(1000 / portTICK_PERIOD_MS);
  }
} 
