#include "esp_camera.h"
#include "esp_log.h"
#include "esp_err.h"
#include "esp_system.h"
#include "esp_chip_info.h"

#define FLASH_PIN 4

esp_err_t setup_esp32_cam();
esp_err_t init_camera(void);
