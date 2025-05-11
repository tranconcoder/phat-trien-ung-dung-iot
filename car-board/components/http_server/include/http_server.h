#ifndef HTTP_SERVER_H
#define HTTP_SERVER_H

#include "esp_err.h"

// Motor control pins
#define MOTOR_A_IN1 25
#define MOTOR_A_IN2 26
#define MOTOR_B_IN1 27
#define MOTOR_B_IN2 14

// LED control pin
#define LED_PIN 14

// Motor control directions
typedef enum {
    MOTOR_STOP = 0,
    MOTOR_FORWARD,
    MOTOR_BACKWARD,
    MOTOR_LEFT,
    MOTOR_RIGHT
} motor_direction_t;

/**
 * @brief Initialize the HTTP server
 * 
 * @return ESP_OK if successful, error code otherwise
 */
esp_err_t http_server_init(void);

/**
 * @brief Set motor direction
 * 
 * @param direction Direction to move (FORWARD, BACKWARD, LEFT, RIGHT, STOP)
 */
void set_motor_direction(motor_direction_t direction);

/**
 * @brief Turn LED on
 */
void led_on(void);

/**
 * @brief Turn LED off
 */
void led_off(void);

#endif // HTTP_SERVER_H
