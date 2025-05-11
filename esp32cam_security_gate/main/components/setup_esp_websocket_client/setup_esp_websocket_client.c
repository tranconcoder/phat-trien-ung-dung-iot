#include "setup_esp_websocket_client.h"
#include "mbedtls/bignum.h" // Add this line to include the mbedtls_mpi type
#include "mbedtls/md.h"
#include "nvs_flash.h" // Add this line to include NVS functions
#include "nvs.h"       // Add this line to include NVS functions
#include <string.h>
#include <stdlib.h>
#include "esp_log.h"
#include "http_server.h"

#define STACK_SIZE 32 * 1024 // Increased from 4K to 8K

const char *TAG = "websocket_client";

TaskHandle_t pv_task_send_image_to_websocket = NULL;

void ws_connected_cb()
{
     if (pv_task_send_image_to_websocket != NULL)
          vTaskResume(pv_task_send_image_to_websocket);

     ESP_LOGI(TAG, "WebSocket client connected");
}

void ws_disconnected_cb()
{
     vTaskSuspend(pv_task_send_image_to_websocket);
     ESP_LOGW(TAG, "WebSocket client disconnected");
}

void ws_error_cb()
{
     ESP_LOGE(TAG, "WebSocket client error");
}

void task_send_image_to_websocket(void *ws_client)
{
     uint64_t last_send_time = esp_timer_get_time();

     while (true)
     {
          camera_fb_t *fb = esp_camera_fb_get();
          if (!fb)
          {
               ESP_LOGE(TAG, "Camera Capture Failed");
               vTaskDelay(pdMS_TO_TICKS(1000)); // Add delay on error
               continue;
          }

          // Ensure memory allocation
          bool success = esp_websocket_client_send_bin(
              (esp_websocket_client_handle_t)ws_client,
              (char *)fb->buf,
              fb->len,
              pdMS_TO_TICKS(200)) > 0;

          esp_camera_fb_return(fb);

          if (success)
          {
               uint64_t current_time = esp_timer_get_time();
               ESP_LOGI(TAG,
                        "Image sent to WebSocket: %d bytes (%.1ffps)",
                        fb->len,
                        1000.0 / ((current_time - last_send_time) / 1000));
               last_send_time = current_time;
          }
          else
          {
               ESP_LOGW(TAG, "Send frame error!");
          }

          // Add small delay to prevent tight loop
          // vTaskDelay(pdMS_TO_TICKS(100));
     }
}

void setup_esp_websocket_client_init()
{
     // Get the websocket URI from NVS
     char uri[128];
     esp_err_t err = get_websocket_uri(uri, sizeof(uri));
     if (err != ESP_OK) {
          ESP_LOGW(TAG, "Failed to get WebSocket URI from NVS, using default");
     }
     
     ESP_LOGI(TAG, "Using WebSocket URI: %s", uri);

     esp_websocket_client_config_t ws_cfg = {
         .uri = uri,
         .buffer_size = 32 * 1024,
         .reconnect_timeout_ms = 500,
         .network_timeout_ms = 10000,
     };
     esp_websocket_client_handle_t ws_client = esp_websocket_client_init(&ws_cfg);

     xTaskCreate(
         task_send_image_to_websocket,
         "send_image_to_websocket",
         STACK_SIZE,
         ws_client,
         tskIDLE_PRIORITY + 1, // Lower priority than configMAX_PRIORITIES - 1
         &pv_task_send_image_to_websocket);
     vTaskSuspend(pv_task_send_image_to_websocket);

     esp_websocket_client_start(ws_client);
     esp_websocket_register_events(ws_client, WEBSOCKET_EVENT_CONNECTED, ws_connected_cb, NULL);
     esp_websocket_register_events(ws_client, WEBSOCKET_EVENT_ERROR, ws_error_cb, NULL);
     esp_websocket_register_events(ws_client, WEBSOCKET_EVENT_DISCONNECTED, ws_disconnected_cb, NULL);
}