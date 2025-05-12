idf_component_register(SRCS "setup_esp_websocket_client.c"
                    INCLUDE_DIRS "include"
                    REQUIRES esp_websocket_client setup_esp32_cam nvs_flash)