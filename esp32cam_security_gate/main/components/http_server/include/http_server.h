#pragma once

#include "esp_http_server.h"
#include "esp_log.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "esp_system.h"

/**
 * @brief Initialize the HTTP server for configuration
 * 
 * @return ESP_OK if successful, otherwise an error code
 */
esp_err_t start_config_http_server(void);

/**
 * @brief Get the websocket URI from NVS storage
 * 
 * @param uri_buffer Buffer to store the URI
 * @param buffer_size Size of the buffer
 * @return ESP_OK if successful, otherwise an error code
 */
esp_err_t get_websocket_uri(char *uri_buffer, size_t buffer_size);

/**
 * @brief Save the websocket URI to NVS storage
 * 
 * @param uri The URI to save
 * @return ESP_OK if successful, otherwise an error code
 */
esp_err_t save_websocket_uri(const char *uri); 