// Pin map for the Heltec WiFi LoRa 32 (V3), ESP32-S3FN8.
//
// The PlatformIO variant header (variants/heltec_wifi_lora_32_V3/pins_arduino.h)
// covers some of this, but it is incomplete (no battery-sense pins) and one name
// is wrong: it calls the SX1262 interrupt line DIO0, which is an SX127x name.
// The V3 carries an SX1262, whose interrupt is DIO1. Everything is named here so
// the firmware never depends on the variant.
#pragma once

#include <Arduino.h>

// --- Semtech SX1262 (SPI2 / FSPI) ---
static constexpr uint8_t LORA_NSS = 8;
static constexpr uint8_t LORA_SCK = 9;
static constexpr uint8_t LORA_MOSI = 10;
static constexpr uint8_t LORA_MISO = 11;
static constexpr uint8_t LORA_RST = 12;
static constexpr uint8_t LORA_BUSY = 13;
static constexpr uint8_t LORA_DIO1 = 14;

// The V3 clocks the SX1262 from a 1.8 V TCXO powered off the radio's DIO3 rail,
// and switches its RF front end with DIO2. Both differ from the RadioLib
// defaults, so both must be set at begin() time or the radio will not lock.
static constexpr float LORA_TCXO_VOLTAGE = 1.8f;

// --- SSD1306 OLED, 128x64, I2C ---
// Its own bus, separate from the SDA=41/SCL=42 pins on the expansion header.
static constexpr uint8_t OLED_SDA = 17;
static constexpr uint8_t OLED_SCL = 18;
static constexpr uint8_t OLED_RST = 21;
static constexpr uint8_t OLED_I2C_ADDR = 0x3C;

// --- Power control ---
// Vext gates the OLED supply and the 3V3 pin on the expansion header.
// Active LOW: drive LOW to turn the rail on.
static constexpr uint8_t VEXT_CTRL = 36;

// The battery divider is disconnected until ADC_CTRL is driven LOW, so idle
// current is not wasted through it. Measured voltage must be scaled back up;
// the divider is nominally 390k/100k, and Heltec's own examples use 4.9 to
// account for the ADC input impedance. Calibrate per board against a meter.
static constexpr uint8_t ADC_CTRL = 37;
static constexpr uint8_t VBAT_ADC = 1;
static constexpr float VBAT_DIVIDER = 4.9f;

// --- User I/O ---
static constexpr uint8_t LED_WHITE = 35;
static constexpr uint8_t BUTTON_PRG = 0;  // also the bootloader strap; active LOW

inline void vextOn() {
  pinMode(VEXT_CTRL, OUTPUT);
  digitalWrite(VEXT_CTRL, LOW);
}

inline void vextOff() {
  pinMode(VEXT_CTRL, OUTPUT);
  digitalWrite(VEXT_CTRL, HIGH);
}
