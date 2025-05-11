#include "setup_esp32_cam.h"

static const char *TAG = "setup_esp32_cam";

#if ESP_CAMERA_SUPPORTED

esp_err_t init_camera(void)
{
     camera_config_t camera_config = {
         .pin_pwdn = -1,
         .pin_reset = -1, // software reset will be performed
         .pin_xclk = -1,
         .pin_sccb_sda = -1,
         .pin_sccb_scl = -1,

         .pin_d7 = -1,
         .pin_d6 = -1,
         .pin_d5 = -1,
         .pin_d4 = -1,
         .pin_d3 = -1,
         .pin_d2 = -1,
         .pin_d1 = -1,
         .pin_d0 = -1,
         .pin_vsync = -1,
         .pin_href = -1,
         .pin_pclk = -1,

         .xclk_freq_hz = 20000000,
         .ledc_timer = LEDC_TIMER_0,
         .ledc_channel = LEDC_CHANNEL_0,

         .pixel_format = PIXFORMAT_JPEG,
         .frame_size = FRAMESIZE_VGA,
         .jpeg_quality = 5,
         .fb_count = 2,
         .fb_location = CAMERA_FB_IN_PSRAM,
         .grab_mode = CAMERA_GRAB_WHEN_EMPTY,
     };

     esp_chip_info_t chip_info;
     esp_chip_info(&chip_info);

     if (chip_info.model == CHIP_ESP32)
     {
          camera_config.pin_pwdn = 32;
          camera_config.pin_xclk = 0;
          camera_config.pin_sccb_sda = 26;
          camera_config.pin_sccb_scl = 27;

          camera_config.pin_d7 = 35;
          camera_config.pin_d6 = 34;
          camera_config.pin_d5 = 39;
          camera_config.pin_d4 = 36;
          camera_config.pin_d3 = 21;
          camera_config.pin_d2 = 19;
          camera_config.pin_d1 = 18;
          camera_config.pin_d0 = 5;
          camera_config.pin_vsync = 25;
          camera_config.pin_href = 23;
          camera_config.pin_pclk = 22;
     }
     else if (chip_info.model == CHIP_ESP32S3)
     {
          camera_config.pin_pwdn = 38;
          camera_config.pin_xclk = 15;
          camera_config.pin_sccb_sda = 4;
          camera_config.pin_sccb_scl = 5;

          camera_config.pin_d7 = 16;
          camera_config.pin_d6 = 17;
          camera_config.pin_d5 = 18;
          camera_config.pin_d4 = 12;
          camera_config.pin_d3 = 10;
          camera_config.pin_d2 = 8;
          camera_config.pin_d1 = 9;
          camera_config.pin_d0 = 11;
          camera_config.pin_vsync = 6;
          camera_config.pin_href = 7;
          camera_config.pin_pclk = 13;
     }

     // initialize the camera
     esp_err_t err = esp_camera_init(&camera_config);
     if (err != ESP_OK)
     {
          ESP_LOGE(TAG, "Camera Init Failed");
          return err;
     }

     return ESP_OK;
}

#endif

esp_err_t setup_esp32_cam()
{
#if ESP_CAMERA_SUPPORTED
     return init_camera();
#else
     ESP_LOGE(TAG, "Camera support is not available for this chip");
     return ESP_FAIL;
#endif
}
