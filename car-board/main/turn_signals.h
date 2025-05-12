#ifndef TURN_SIGNALS_H
#define TURN_SIGNALS_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize turn signals module
 * 
 * Initializes GPIO pins for turn signals and sets up necessary configurations.
 */
void turn_signals_init();

/**
 * @brief Set turn signal pins
 * 
 * Set the GPIO pins to use for left and right turn signals
 * 
 * @param left_pin GPIO pin for left turn signal (-1 to disable)
 * @param right_pin GPIO pin for right turn signal (-1 to disable)
 */
void set_turn_signal_pins(int left_pin, int right_pin);

/**
 * @brief Turn on left signal
 */
void left_signal_on();

/**
 * @brief Turn off left signal
 */
void left_signal_off();

/**
 * @brief Turn on right signal
 */
void right_signal_on();

/**
 * @brief Turn off right signal
 */
void right_signal_off();

#ifdef __cplusplus
}
#endif

#endif /* TURN_SIGNALS_H */ 