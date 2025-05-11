#include <Wire.h>

#define SLAVE_ADDRESS 0x08  // I2C slave address
#define LED_PIN 8           // LED connected to pin 8

byte ledState = LOW;        // Current state of LED

void setup() {
  pinMode(LED_PIN, OUTPUT);        // Set LED pin as output
  digitalWrite(LED_PIN, ledState); // Initialize LED to OFF
  
  Wire.begin(SLAVE_ADDRESS);       // Initialize I2C communication as slave
  Wire.onReceive(receiveEvent);    // Register receive event handler
  
  Serial.begin(9600);              // Start serial for debugging
  Serial.println("I2C Slave LED Controller Ready");
}

void loop() {
  // Nothing to do in loop - all handled in I2C event
  delay(100);
}

// Function that executes when data is received from master
void receiveEvent(int howMany) {
  if (Wire.available()) {
    byte receivedData = Wire.read();  // Read byte from I2C
    
    // Check if received data is for LED control
    if (receivedData == 0x01) {
      ledState = HIGH;               // Turn LED ON
      Serial.println("LED ON");
    } else if (receivedData == 0x00) {
      ledState = LOW;                // Turn LED OFF
      Serial.println("LED OFF");  
    }
    
    digitalWrite(LED_PIN, ledState); // Update LED state
  }
}