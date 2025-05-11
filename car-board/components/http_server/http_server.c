#include <stdio.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_system.h"
#include "driver/gpio.h"
#include "http_server.h"

static const char *TAG = "HTTP_SERVER";

// HTTP server handle
static httpd_handle_t server = NULL;

// Initialize GPIO pins for L298N motor driver
static void init_motor_pins(void) {
    // Configure motor output pins
    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << MOTOR_A_IN1) | (1ULL << MOTOR_A_IN2) |
                         (1ULL << MOTOR_B_IN1) | (1ULL << MOTOR_B_IN2),
        .pull_down_en = 0,
        .pull_up_en = 0
    };
    gpio_config(&io_conf);
    
    // Initialize all pins to LOW (motors stopped)
    gpio_set_level(MOTOR_A_IN1, 0);
    gpio_set_level(MOTOR_A_IN2, 0);
    gpio_set_level(MOTOR_B_IN1, 0);
    gpio_set_level(MOTOR_B_IN2, 0);
    
    ESP_LOGI(TAG, "Motor pins initialized");
}

// Initialize GPIO for LED control
static void init_led_pin(void) {
    // Configure LED output pin
    gpio_config_t io_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << LED_PIN),
        .pull_down_en = 0,
        .pull_up_en = 0
    };
    gpio_config(&io_conf);
    
    // Initialize LED to OFF
    gpio_set_level(LED_PIN, 0);
    
    ESP_LOGI(TAG, "LED pin initialized");
}

// Turn LED on
void led_on(void) {
    gpio_set_level(LED_PIN, 1);
    ESP_LOGI(TAG, "LED turned ON");
}

// Turn LED off
void led_off(void) {
    gpio_set_level(LED_PIN, 0);
    ESP_LOGI(TAG, "LED turned OFF");
}

// Set motor direction function implementation
void set_motor_direction(motor_direction_t direction) {
    switch (direction) {
        case MOTOR_FORWARD:  // Top direction
            // Motor A forward
            gpio_set_level(MOTOR_A_IN1, 1);
            gpio_set_level(MOTOR_A_IN2, 0);
            // Motor B forward
            gpio_set_level(MOTOR_B_IN1, 1);
            gpio_set_level(MOTOR_B_IN2, 0);
            ESP_LOGI(TAG, "Motors moving FORWARD");
            break;
            
        case MOTOR_BACKWARD:  // Bottom direction
            // Motor A backward
            gpio_set_level(MOTOR_A_IN1, 0);
            gpio_set_level(MOTOR_A_IN2, 1);
            // Motor B backward
            gpio_set_level(MOTOR_B_IN1, 0);
            gpio_set_level(MOTOR_B_IN2, 1);
            ESP_LOGI(TAG, "Motors moving BACKWARD");
            break;
            
        case MOTOR_LEFT:
            // Motor A backward (or stop)
            gpio_set_level(MOTOR_A_IN1, 0);
            gpio_set_level(MOTOR_A_IN2, 1);
            // Motor B forward
            gpio_set_level(MOTOR_B_IN1, 1);
            gpio_set_level(MOTOR_B_IN2, 0);
            ESP_LOGI(TAG, "Motors turning LEFT");
            break;
            
        case MOTOR_RIGHT:
            // Motor A forward
            gpio_set_level(MOTOR_A_IN1, 1);
            gpio_set_level(MOTOR_A_IN2, 0);
            // Motor B backward (or stop)
            gpio_set_level(MOTOR_B_IN1, 0);
            gpio_set_level(MOTOR_B_IN2, 1);
            ESP_LOGI(TAG, "Motors turning RIGHT");
            break;
            
        case MOTOR_STOP:
        default:
            // Stop both motors
            gpio_set_level(MOTOR_A_IN1, 0);
            gpio_set_level(MOTOR_A_IN2, 0);
            gpio_set_level(MOTOR_B_IN1, 0);
            gpio_set_level(MOTOR_B_IN2, 0);
            ESP_LOGI(TAG, "Motors STOPPED");
            break;
    }
}

// HTTP GET handler for the root path
static esp_err_t root_get_handler(httpd_req_t *req) {
    const char *html = "<!DOCTYPE html>"
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
                       "    </style>"
                       "</head>"
                       "<body>"
                       "    <h1>ESP32 Control Panel</h1>"
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
                       "        <h2>LED Control</h2>"
                       "        <button class=\"button led-on\" onclick=\"fetch('/led/on')\">LED ON</button>"
                       "        <button class=\"button led-off\" onclick=\"fetch('/led/off')\">LED OFF</button>"
                       "    </div>"
                       "</body>"
                       "</html>";
    
    httpd_resp_set_type(req, "text/html");
    httpd_resp_send(req, html, strlen(html));
    return ESP_OK;
}

// Motor control handler - common for all directions
static esp_err_t motor_control_handler(httpd_req_t *req, motor_direction_t direction) {
    set_motor_direction(direction);
    
    // Send a simple response
    const char *resp = "OK";
    httpd_resp_send(req, resp, strlen(resp));
    return ESP_OK;
}

// Handler for forward direction
static esp_err_t forward_handler(httpd_req_t *req) {
    return motor_control_handler(req, MOTOR_FORWARD);
}

// Handler for backward direction
static esp_err_t backward_handler(httpd_req_t *req) {
    return motor_control_handler(req, MOTOR_BACKWARD);
}

// Handler for left direction
static esp_err_t left_handler(httpd_req_t *req) {
    return motor_control_handler(req, MOTOR_LEFT);
}

// Handler for right direction
static esp_err_t right_handler(httpd_req_t *req) {
    return motor_control_handler(req, MOTOR_RIGHT);
}

// Handler for stop command
static esp_err_t stop_handler(httpd_req_t *req) {
    return motor_control_handler(req, MOTOR_STOP);
}

// Handler for LED ON command
static esp_err_t led_on_handler(httpd_req_t *req) {
    led_on();
    
    // Send a simple response
    const char *resp = "LED ON";
    httpd_resp_send(req, resp, strlen(resp));
    return ESP_OK;
}

// Handler for LED OFF command
static esp_err_t led_off_handler(httpd_req_t *req) {
    led_off();
    
    // Send a simple response
    const char *resp = "LED OFF";
    httpd_resp_send(req, resp, strlen(resp));
    return ESP_OK;
}

// Start the HTTP server
static httpd_handle_t start_webserver(void) {
    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.max_uri_handlers = 10;  // Increase if adding more handlers
    
    ESP_LOGI(TAG, "Starting HTTP server on port: %d", config.server_port);
    
    if (httpd_start(&server, &config) == ESP_OK) {
        // URI handlers
        httpd_uri_t root = {
            .uri       = "/",
            .method    = HTTP_GET,
            .handler   = root_get_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &root);
        
        httpd_uri_t forward = {
            .uri       = "/forward",
            .method    = HTTP_GET,
            .handler   = forward_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &forward);
        
        httpd_uri_t backward = {
            .uri       = "/backward",
            .method    = HTTP_GET,
            .handler   = backward_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &backward);
        
        httpd_uri_t left = {
            .uri       = "/left",
            .method    = HTTP_GET,
            .handler   = left_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &left);
        
        httpd_uri_t right = {
            .uri       = "/right",
            .method    = HTTP_GET,
            .handler   = right_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &right);
        
        httpd_uri_t stop = {
            .uri       = "/stop",
            .method    = HTTP_GET,
            .handler   = stop_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &stop);
        
        // LED control routes
        httpd_uri_t led_on_route = {
            .uri       = "/led/on",
            .method    = HTTP_GET,
            .handler   = led_on_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &led_on_route);
        
        httpd_uri_t led_off_route = {
            .uri       = "/led/off",
            .method    = HTTP_GET,
            .handler   = led_off_handler,
            .user_ctx  = NULL
        };
        httpd_register_uri_handler(server, &led_off_route);
        
        return server;
    }
    
    ESP_LOGE(TAG, "Error starting HTTP server!");
    return NULL;
}

// Initialize the HTTP server
esp_err_t http_server_init(void) {
    // Initialize motor control pins
    init_motor_pins();
    
    // Initialize LED control pin
    init_led_pin();
    
    // Start the HTTP server
    if (start_webserver() != NULL) {
        ESP_LOGI(TAG, "HTTP server initialized successfully");
        return ESP_OK;
    } else {
        ESP_LOGE(TAG, "Failed to initialize HTTP server");
        return ESP_FAIL;
    }
}
