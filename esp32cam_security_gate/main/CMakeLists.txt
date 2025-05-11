idf_component_register(SRCS "esp32cam_security_gate.c"
                       INCLUDE_DIRS "."
                       REQUIRES "setup_esp32_cam" 
                               "setup_esp_websocket_client"
                               "http_server")
