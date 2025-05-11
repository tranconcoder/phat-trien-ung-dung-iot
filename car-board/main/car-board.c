#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/i2c.h"
#include "esp_log.h"
#include "esp_err.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "nvs_flash.h"
#include "http_server.h"
#include "driver/gpio.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"

#define LCD_ADDR 0x27           // I2C address of the LCD (typical for PCF8574)
#define I2C_MASTER_SCL_IO 22    // GPIO for SCL
#define I2C_MASTER_SDA_IO 21    // GPIO for SDA
#define I2C_MASTER_FREQ_HZ 100000  // I2C frequency
#define I2C_MASTER_PORT I2C_NUM_0  // I2C port number
#define I2C_TIMEOUT_MS 1000

// DHT22 Sensor Configuration
#define DHT_GPIO 35             // GPIO for DHT22 data pin
#define DHT_TIMEOUT_US 10000    // Timeout in microseconds

// WiFi credentials - replace with your WiFi SSID and password
#define WIFI_SSID "Mr_Duck"
#define WIFI_PASS "duck2003"
#define MAXIMUM_RETRY 5

// LCD commands
#define LCD_CLEAR        0x01
#define LCD_HOME         0x02
#define LCD_ENTRY_MODE   0x06  // Increment cursor position, no display shift
#define LCD_DISPLAY_ON   0x0C  // Display on, cursor off, blink off
#define LCD_FUNCTION_SET 0x28  // 4-bit mode, 2 lines, 5x8 dots
#define LCD_SET_DDRAM    0x80  // Set DDRAM address command

// LCD control bits for backlight and RS/RW/EN control
#define LCD_BACKLIGHT    0x08
#define LCD_ENABLE       0x04
#define LCD_RW           0x02
#define LCD_RS           0x01

// Update the LED pin definition
#define LED_PIN 12  // GPIO pin connected to relay 

static const char *TAG = "CAR_BOARD";
static int s_retry_num = 0;

// Function prototypes for WiFi
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data);
static void wifi_init_sta(void);

// Function prototypes
esp_err_t i2c_master_init(void);
void lcd_init(void);
void lcd_send_cmd(uint8_t cmd);
void lcd_send_data(uint8_t data);
void lcd_clear(void);
void lcd_home(void);
void lcd_set_cursor(uint8_t row, uint8_t col);
void lcd_print(const char *str);
static esp_err_t dht22_read(int gpio_pin, float *temperature, float *humidity);

// WiFi event handler
static void wifi_event_handler(void *arg, esp_event_base_t event_base,
                               int32_t event_id, void *event_data) {
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
        ESP_LOGI(TAG, "Trying to connect to WiFi...");
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        if (s_retry_num < MAXIMUM_RETRY) {
            esp_wifi_connect();
            s_retry_num++;
            ESP_LOGI(TAG, "Retry to connect to WiFi...");
        } else {
            ESP_LOGI(TAG, "Failed to connect to WiFi");
        }
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "WiFi connected! IP: " IPSTR, IP2STR(&event->ip_info.ip));
        s_retry_num = 0;
        
        // Initialize HTTP server once WiFi is connected
        esp_err_t ret = http_server_init();
        if (ret != ESP_OK) {
            ESP_LOGE(TAG, "Failed to initialize HTTP server");
        }
    }
}

// Initialize WiFi in station mode
static void wifi_init_sta(void) {
    s_retry_num = 0;
    
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();
    
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));
    
    // Register event handlers
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT,
                                                       ESP_EVENT_ANY_ID,
                                                       &wifi_event_handler,
                                                       NULL,
                                                       NULL));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT,
                                                       IP_EVENT_STA_GOT_IP,
                                                       &wifi_event_handler,
                                                       NULL,
                                                       NULL));
    
    // Configure WiFi with SSID and password
    wifi_config_t wifi_config = {
        .sta = {
            .ssid = WIFI_SSID,
            .password = WIFI_PASS,
            .threshold.authmode = WIFI_AUTH_WPA2_PSK,
        },
    };
    
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());
    
    ESP_LOGI(TAG, "WiFi initialization completed");
}

// Initialize I2C master
esp_err_t i2c_master_init(void) {
    i2c_config_t conf = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = I2C_MASTER_SDA_IO,
        .scl_io_num = I2C_MASTER_SCL_IO,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = I2C_MASTER_FREQ_HZ
    };
    
    esp_err_t err = i2c_param_config(I2C_MASTER_PORT, &conf);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "I2C parameter configuration failed: %s", esp_err_to_name(err));
        return err;
    }
    
    err = i2c_driver_install(I2C_MASTER_PORT, I2C_MODE_MASTER, 0, 0, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "I2C driver installation failed: %s", esp_err_to_name(err));
        return err;
    }
    
    return ESP_OK;
}

// Send a byte to the I2C LCD
esp_err_t lcd_write(uint8_t data) {
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (LCD_ADDR << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, data | LCD_BACKLIGHT, true);
    i2c_master_stop(cmd);
    esp_err_t ret = i2c_master_cmd_begin(I2C_MASTER_PORT, cmd, I2C_TIMEOUT_MS / portTICK_PERIOD_MS);
    i2c_cmd_link_delete(cmd);
    return ret;
}

// Pulse the EN pin to execute the command
void lcd_pulse_enable(uint8_t data) {
    lcd_write(data | LCD_ENABLE);   // EN high
    vTaskDelay(1 / portTICK_PERIOD_MS);  // 1ms delay
    lcd_write(data & ~LCD_ENABLE);  // EN low
    vTaskDelay(1 / portTICK_PERIOD_MS);  // 1ms delay
}

// Send a command to the LCD
void lcd_send_cmd(uint8_t cmd) {
    uint8_t high_nibble = (cmd & 0xF0);
    uint8_t low_nibble = ((cmd << 4) & 0xF0);
    
    // Send high nibble
    lcd_pulse_enable(high_nibble);
    // Send low nibble
    lcd_pulse_enable(low_nibble);
}

// Send data to the LCD
void lcd_send_data(uint8_t data) {
    uint8_t high_nibble = (data & 0xF0) | LCD_RS;
    uint8_t low_nibble = ((data << 4) & 0xF0) | LCD_RS;
    
    // Send high nibble
    lcd_pulse_enable(high_nibble);
    // Send low nibble
    lcd_pulse_enable(low_nibble);
}

// Initialize the LCD
void lcd_init(void) {
    vTaskDelay(50 / portTICK_PERIOD_MS);  // Wait for LCD to power up
    
    // Initial 8-bit mode (even though we'll use 4-bit)
    lcd_pulse_enable(0x30);  // 8-bit mode
    vTaskDelay(5 / portTICK_PERIOD_MS);
    lcd_pulse_enable(0x30);  // 8-bit mode
    vTaskDelay(1 / portTICK_PERIOD_MS);
    lcd_pulse_enable(0x30);  // 8-bit mode
    vTaskDelay(1 / portTICK_PERIOD_MS);
    
    // Switch to 4-bit mode
    lcd_pulse_enable(0x20);  // 4-bit mode
    vTaskDelay(1 / portTICK_PERIOD_MS);
    
    // Now in 4-bit mode, configure LCD
    lcd_send_cmd(LCD_FUNCTION_SET);  // 4-bit, 2 lines, 5x8 dots
    vTaskDelay(1 / portTICK_PERIOD_MS);
    lcd_send_cmd(LCD_DISPLAY_ON);    // Display on, cursor off, blink off
    vTaskDelay(1 / portTICK_PERIOD_MS);
    lcd_send_cmd(LCD_CLEAR);         // Clear display
    vTaskDelay(2 / portTICK_PERIOD_MS);
    lcd_send_cmd(LCD_ENTRY_MODE);    // Entry mode set
    vTaskDelay(1 / portTICK_PERIOD_MS);
    
    ESP_LOGI(TAG, "LCD initialized");
}

// Clear the LCD display
void lcd_clear(void) {
    lcd_send_cmd(LCD_CLEAR);
    vTaskDelay(2 / portTICK_PERIOD_MS);  // Clear command needs more time
}

// Move cursor to home position
void lcd_home(void) {
    lcd_send_cmd(LCD_HOME);
    vTaskDelay(2 / portTICK_PERIOD_MS);  // Home command needs more time
}

// Set the cursor position
void lcd_set_cursor(uint8_t row, uint8_t col) {
    uint8_t row_offsets[] = {0x00, 0x40};  // Row offsets: 0 for row 0, 0x40 for row 1
    lcd_send_cmd(LCD_SET_DDRAM | (col + row_offsets[row]));
}

// Print a string to the LCD
void lcd_print(const char *str) {
    while (*str) {
        lcd_send_data(*str);
        str++;
    }
}

// DHT22 sensor read (implementation of more robust reading protocol)
static esp_err_t dht22_read(int gpio_pin, float *temperature, float *humidity) {
    uint8_t data[5] = {0};
    uint32_t start_time = 0;
    uint32_t end_time = 0;
    uint32_t width = 0;
    uint8_t bit_index = 7;
    uint8_t byte_index = 0;
    
    // Reset values
    *temperature = 0.0;
    *humidity = 0.0;
    
    // Configure GPIO with internal pull-up for when pin is set as input
    gpio_config_t io_conf = {
        .pin_bit_mask = (1ULL << gpio_pin),
        .mode = GPIO_MODE_INPUT_OUTPUT_OD,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE
    };
    gpio_config(&io_conf);
    
    // DHT22 start sequence
    gpio_set_direction(gpio_pin, GPIO_MODE_OUTPUT);
    gpio_set_level(gpio_pin, 0);               // Pull down for at least 1ms to start
    vTaskDelay(5 / portTICK_PERIOD_MS);        // Host start signal, pull-down 5ms
    
    // Pull up for 30us
    gpio_set_level(gpio_pin, 1);
    esp_rom_delay_us(30);

    // Change to input mode
    gpio_set_direction(gpio_pin, GPIO_MODE_INPUT);
    
    // DHT will keep line low for 80us and then high for 80us
    esp_rom_delay_us(5);  // Give time to ensure we're reading the response
    
    // Wait for DHT response (should go low)
    start_time = esp_timer_get_time();
    while (gpio_get_level(gpio_pin) == 1) {
        if (esp_timer_get_time() - start_time > DHT_TIMEOUT_US) {
            ESP_LOGW(TAG, "DHT22 response timeout waiting for initial low");
            return ESP_ERR_TIMEOUT;
        }
    }
    
    // DHT pulled line low, wait for it to go high
    start_time = esp_timer_get_time();
    while (gpio_get_level(gpio_pin) == 0) {
        if (esp_timer_get_time() - start_time > DHT_TIMEOUT_US) {
            ESP_LOGW(TAG, "DHT22 response timeout waiting for high after initial low");
            return ESP_ERR_TIMEOUT;
        }
    }
    
    // DHT pulled line high, wait for it to go low again
    start_time = esp_timer_get_time();
    while (gpio_get_level(gpio_pin) == 1) {
        if (esp_timer_get_time() - start_time > DHT_TIMEOUT_US) {
            ESP_LOGW(TAG, "DHT22 response timeout waiting for data start");
            return ESP_ERR_TIMEOUT;
        }
    }
    
    // Read 40 bits (5 bytes) of data
    for (byte_index = 0; byte_index < 5; byte_index++) {
        for (bit_index = 0; bit_index < 8; bit_index++) {
            // Every bit starts with a ~50us low pulse
            // Wait for line to go high
            start_time = esp_timer_get_time();
            while (gpio_get_level(gpio_pin) == 0) {
                if (esp_timer_get_time() - start_time > DHT_TIMEOUT_US) {
                    ESP_LOGW(TAG, "DHT22 timeout waiting for bit start");
                    return ESP_ERR_TIMEOUT;
                }
            }
            
            // Measure the width of the high pulse to determine if it's 0 or 1
            start_time = esp_timer_get_time();
            while (gpio_get_level(gpio_pin) == 1) {
                if (esp_timer_get_time() - start_time > DHT_TIMEOUT_US) {
                    ESP_LOGW(TAG, "DHT22 timeout waiting for bit end");
                    return ESP_ERR_TIMEOUT;
                }
            }
            
            end_time = esp_timer_get_time();
            width = end_time - start_time;
            
            // A high pulse of ~26-28us means '0', ~70us means '1'
            if (width > 40) {  // Using 40us as the threshold between 0 and 1
                data[byte_index] |= (1 << (7 - bit_index));
            }
        }
    }
    
    ESP_LOGD(TAG, "DHT22 raw data: 0x%02x 0x%02x 0x%02x 0x%02x 0x%02x", 
             data[0], data[1], data[2], data[3], data[4]);
    
    // Verify checksum
    if (data[4] != ((data[0] + data[1] + data[2] + data[3]) & 0xFF)) {
        ESP_LOGE(TAG, "DHT22 checksum failed: %02x != %02x", 
                data[4], ((data[0] + data[1] + data[2] + data[3]) & 0xFF));
        return ESP_ERR_INVALID_CRC;
    }
    
    // Convert data to humidity and temperature
    *humidity = ((data[0] << 8) | data[1]) / 10.0;
    
    // Temperature - check sign bit (MSB of byte 2)
    if (data[2] & 0x80) {
        *temperature = -((((data[2] & 0x7F) << 8) | data[3]) / 10.0);
    } else {
        *temperature = ((data[2] << 8) | data[3]) / 10.0;
    }
    
    // Validate readings are within reasonable range
    if (*humidity > 100 || *humidity < 0 || *temperature > 80 || *temperature < -40) {
        ESP_LOGE(TAG, "DHT22 readings out of range: Temp=%.1f°C, Humidity=%.1f%%", 
                 *temperature, *humidity);
        return ESP_ERR_INVALID_RESPONSE;
    }
    
    return ESP_OK;
}

// DHT22 reading task
static void dht22_task(void *pvParameters) {
    // Buffer for values and display
    float temperature = 0.0;
    float humidity = 0.0;
    char display_buffer[17] = {0}; // 16 chars for LCD + null terminator
    
    // Allow the sensor to stabilize
    vTaskDelay(2000 / portTICK_PERIOD_MS);
    
    int retry_count = 0;
    int success_count = 0;
    
    while (1) {
        // Try to read DHT22 sensor
        esp_err_t result = dht22_read(DHT_GPIO, &temperature, &humidity);
        
        if (result == ESP_OK) {
            ESP_LOGI(TAG, "DHT22 readings - Temp: %.1f°C, Humidity: %.1f%%", temperature, humidity);
            
            // Format and display on LCD line 1
            snprintf(display_buffer, sizeof(display_buffer), "T:%.1fC H:%.1f%%", temperature, humidity);
            lcd_set_cursor(1, 0); // Line 1, position 0
            lcd_print(display_buffer);
            
            // Reset retry counter on success
            retry_count = 0;
            success_count++;
        } else {
            retry_count++;
            
            // More detailed error messages
            switch (result) {
                case ESP_ERR_TIMEOUT:
                    ESP_LOGE(TAG, "DHT22 timeout error (retry %d)", retry_count);
                    break;
                case ESP_ERR_INVALID_CRC:
                    ESP_LOGE(TAG, "DHT22 checksum error (retry %d)", retry_count);
                    break;
                case ESP_ERR_INVALID_RESPONSE:
                    ESP_LOGE(TAG, "DHT22 invalid response error (retry %d)", retry_count);
                    break;
                default:
                    ESP_LOGE(TAG, "Failed to read from DHT22 sensor: %s (retry %d)", 
                            esp_err_to_name(result), retry_count);
            }
            
            // Only update LCD after several consecutive failures
            if (retry_count >= 5) {
                lcd_set_cursor(1, 0);
                lcd_print("DHT Error      ");
            }
            
            // If we have multiple failures in a row and had success before,
            // try a soft reset of the sensor with a longer delay
            if (retry_count >= 10 && success_count > 0) {
                ESP_LOGW(TAG, "Too many failures, resetting DHT22 connection");
                
                // Reset sensor by toggling pin
                gpio_set_direction(DHT_GPIO, GPIO_MODE_OUTPUT);
                gpio_set_level(DHT_GPIO, 1);
                vTaskDelay(1000 / portTICK_PERIOD_MS);
                
                // Reinitialize DHT GPIO
                gpio_config_t io_conf = {
                    .pin_bit_mask = (1ULL << DHT_GPIO),
                    .mode = GPIO_MODE_INPUT_OUTPUT_OD,
                    .pull_up_en = GPIO_PULLUP_ENABLE,
                    .pull_down_en = GPIO_PULLDOWN_DISABLE,
                    .intr_type = GPIO_INTR_DISABLE
                };
                gpio_config(&io_conf);
                
                // Reset counters
                retry_count = 0;
            }
        }
        
        // DHT22 readings should be at least 2 seconds apart
        // Add longer delay after errors to allow sensor to stabilize
        if (result != ESP_OK) {
            vTaskDelay(3000 / portTICK_PERIOD_MS);
        } else {
            vTaskDelay(2000 / portTICK_PERIOD_MS);
        }
    }
}

void app_main(void) {
    // Initialize NVS (needed for WiFi)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
    
    // Initialize I2C
    if (i2c_master_init() != ESP_OK) {
        ESP_LOGE(TAG, "I2C master initialization failed");
        return;
    }
    
    // Initialize LCD
    lcd_init();
    
    // Print welcome message on LCD
    lcd_clear();
    lcd_set_cursor(0, 0);  // First line, first position
    lcd_print("Car Board Ready");
    lcd_set_cursor(1, 0);  // Second line, first position
    lcd_print("Init DHT22...   ");
    
    // Delay before initializing DHT22 to ensure stable power
    vTaskDelay(1000 / portTICK_PERIOD_MS);
    
    // Start DHT22 reading task
    xTaskCreate(dht22_task, "dht22_task", 4096, NULL, 5, NULL);
    
    ESP_LOGI(TAG, "Starting WiFi...");
    
    // Initialize WiFi in station mode
    wifi_init_sta();
    
    // Add initialization for the relay
    // Configure GPIO for relay with appropriate pull-up/down
    gpio_config_t relay_conf = {
        .intr_type = GPIO_INTR_DISABLE,
        .mode = GPIO_MODE_OUTPUT,
        .pin_bit_mask = (1ULL << LED_PIN),
        .pull_down_en = GPIO_PULLDOWN_ENABLE,  // Add pull-down to ensure stable initial state
        .pull_up_en = GPIO_PULLUP_DISABLE
    };
    gpio_config(&relay_conf);
    
    // Initialize relay to OFF state (might be inverted based on relay type)
    gpio_set_level(LED_PIN, 0);
    ESP_LOGI(TAG, "Relay initialized on pin %d", LED_PIN);
}
