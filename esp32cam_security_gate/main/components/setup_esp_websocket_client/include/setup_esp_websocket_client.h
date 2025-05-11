#include "esp_websocket_client.h"
#include "setup_esp32_cam.h"
#include "esp_log.h"
#include "esp_camera.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "mbedtls/bignum.h"
#include <string.h>
#include <stdlib.h>

void setup_esp_websocket_client_init();