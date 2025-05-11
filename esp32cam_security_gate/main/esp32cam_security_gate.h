#include <inttypes.h>
#include "freertos/FreeRTOS.h"
#include "freertos/timers.h"
#include "freertos/task.h"
#include "esp_mac.h"
#include "esp_wifi.h"
#include "esp_log.h"
#include <esp_system.h>
#include "nvs_flash.h"
#include <stdint.h>
#include <sys/param.h>
#include <sys/socket.h>
#include <stdlib.h>
#include "driver/gpio.h"
#include <stdio.h>

#include "setup_esp32_cam.h"
#include "setup_esp_websocket_client.h"

#include "esp_tls.h"
#include "esp_event.h"
#include "esp_netif.h"

#define STACK_SIZE 32 * 1024

#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT BIT1

#define EXAMPLE_ESP_WIFI_SSID CONFIG_ROUTER_SSID
#define EXAMPLE_ESP_WIFI_PASS CONFIG_ROUTER_PASSWORD
#define EXAMPLE_ESP_MAXIMUM_RETRY 10
