// Bring-up firmware for the Heltec WiFi LoRa 32 (V3).
//
// This transmits nothing. It only proves out the hardware and the toolchain:
// serial console, Vext rail, OLED presence on I2C, SX1262 initialisation over
// SPI, battery sense, LED and button. Run it once on each board before writing
// any link code, so that a later radio failure can be blamed on the protocol
// rather than on a cold solder joint.

#include <Arduino.h>
#include <RadioLib.h>
#include <SPI.h>
#include <Wire.h>

#include "board_pins.h"

// US ISM band. All three sites are FCC Part 15.247 territory, so 902-928 MHz.
// 915.0 is the band centre and is only a bring-up placeholder -- the real
// channel plan gets decided with the link protocol.
static constexpr float LORA_FREQ_MHZ = 915.0f;

static SX1262 radio =
    new Module(LORA_NSS, LORA_DIO1, LORA_RST, LORA_BUSY, SPI);

static void reportChip() {
  // getChipRevision() on this core reports only the major wafer version, so an
  // ESP32-S3 v0.2 prints as 0. esptool reports the full major.minor.
  Serial.printf("chip      : %s rev %d (major), %d core(s) @ %lu MHz\n",
                ESP.getChipModel(), ESP.getChipRevision(), ESP.getChipCores(),
                (unsigned long)getCpuFrequencyMhz());
  Serial.printf("flash     : %lu bytes @ %lu Hz\n",
                (unsigned long)ESP.getFlashChipSize(),
                (unsigned long)ESP.getFlashChipSpeed());
  Serial.printf("heap free : %lu bytes\n", (unsigned long)ESP.getFreeHeap());
  Serial.printf("psram     : %lu bytes\n", (unsigned long)ESP.getPsramSize());
  // getEfuseMac() packs the MAC little-endian: octet 1 of the printed address
  // is the low byte of the return value, not the high byte. Printing it
  // high-byte-first yields the address reversed, which will not match what
  // esptool reports and would give every node the wrong identity.
  const uint64_t mac = ESP.getEfuseMac();
  Serial.printf("efuse mac : %02X:%02X:%02X:%02X:%02X:%02X\n", (uint8_t)mac,
                (uint8_t)(mac >> 8), (uint8_t)(mac >> 16), (uint8_t)(mac >> 24),
                (uint8_t)(mac >> 32), (uint8_t)(mac >> 40));
  Serial.printf("arduino   : %d.%d.%d\n", ESP_ARDUINO_VERSION_MAJOR,
                ESP_ARDUINO_VERSION_MINOR, ESP_ARDUINO_VERSION_PATCH);
  Serial.printf("radiolib  : %d.%d.%d\n", RADIOLIB_VERSION_MAJOR,
                RADIOLIB_VERSION_MINOR, RADIOLIB_VERSION_PATCH);
}

// Walks the OLED's I2C bus. A healthy V3 answers at 0x3C and nowhere else.
// Silence usually means Vext is off or the display flex is not seated.
static bool scanOledBus() {
  vextOn();
  delay(50);

  // The SSD1306 holds itself in reset until this line goes high.
  pinMode(OLED_RST, OUTPUT);
  digitalWrite(OLED_RST, LOW);
  delay(20);
  digitalWrite(OLED_RST, HIGH);
  delay(50);

  Wire.begin(OLED_SDA, OLED_SCL, 400000u);

  bool foundOled = false;
  int devices = 0;
  for (uint8_t addr = 0x08; addr < 0x78; ++addr) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  i2c device at 0x%02X%s\n", addr,
                    addr == OLED_I2C_ADDR ? "  (SSD1306 OLED)" : "");
      ++devices;
      if (addr == OLED_I2C_ADDR) {
        foundOled = true;
      }
    }
  }
  if (devices == 0) {
    Serial.println("  no i2c devices responded");
  }
  return foundOled;
}

static bool initRadio() {
  // RadioLib calls SPI.begin() with no arguments, which on the ESP32-S3 would
  // pick the default pin set rather than the SX1262's. Claim the pins first.
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_NSS);

  const int16_t state = radio.begin(LORA_FREQ_MHZ,
                                    /*bw   */ 125.0,
                                    /*sf   */ 9,
                                    /*cr   */ 7,
                                    RADIOLIB_SX126X_SYNC_WORD_PRIVATE,
                                    /*power*/ 14,
                                    /*preamb*/ 8, LORA_TCXO_VOLTAGE,
                                    /*LDO  */ false);
  if (state != RADIOLIB_ERR_NONE) {
    Serial.printf("  SX1262 begin() failed: %d\n", state);
    if (state == RADIOLIB_ERR_CHIP_NOT_FOUND) {
      Serial.println("  -> no SPI response; check NSS/BUSY wiring");
    } else if (state == RADIOLIB_ERR_SPI_CMD_TIMEOUT) {
      Serial.println("  -> BUSY never cleared; usually a wrong TCXO voltage");
    }
    return false;
  }

  // The V3 switches its RF front end from the radio's DIO2 line. Without this
  // the SX1262 initialises cleanly and then transmits into a dead path.
  const int16_t rfsw = radio.setDio2AsRfSwitch(true);
  if (rfsw != RADIOLIB_ERR_NONE) {
    Serial.printf("  setDio2AsRfSwitch() failed: %d\n", rfsw);
    return false;
  }

  Serial.printf("  SX1262 up at %.1f MHz, SF9/BW125/CR4:7\n", LORA_FREQ_MHZ);
  Serial.printf("  random sample from radio RSSI: 0x%08lX\n",
                (unsigned long)radio.random(0x7FFFFFFF));
  return true;
}

// Averaged reading at the ADC pin, in millivolts, with ADC_CTRL held at the
// given level. This is the divider *output*, not the pack voltage.
static float readDividerMillivolts(uint8_t ctrl_level) {
  pinMode(ADC_CTRL, OUTPUT);
  digitalWrite(ADC_CTRL, ctrl_level);
  delay(50);  // let it settle before the first sample

  constexpr int kSamples = 64;
  uint32_t accum = 0;
  for (int i = 0; i < kSamples; ++i) {
    accum += analogReadMilliVolts(VBAT_ADC);
    delay(2);
  }
  // Release the pin so the divider stops drawing current between reads.
  pinMode(ADC_CTRL, INPUT);

  return accum / static_cast<float>(kSamples);
}

static void reportBattery() {
  // ADC_CTRL polarity differs by board revision -- LOW enables the divider on
  // pre-V3.2 boards, HIGH on V3.2 and later. The wrong choice reads near zero,
  // which is indistinguishable from an empty JST connector. So probe both and
  // report which one actually connected the divider.
  const float mv_low = readDividerMillivolts(LOW);
  const float mv_high = readDividerMillivolts(HIGH);

  Serial.printf("  ADC_CTRL LOW : %.1f mV\n", mv_low);
  Serial.printf("  ADC_CTRL HIGH: %.1f mV\n", mv_high);

  const bool low_live = mv_low > 200.0f;
  const bool high_live = mv_high > 200.0f;

  if (!low_live && !high_live) {
    Serial.println("  -> both polarities read ~0.");
    Serial.println("     Nothing on the JST, and no charger rail to sense.");
    return;
  }
  if (low_live && high_live) {
    Serial.println("  -> both polarities read a voltage, which is unexpected;");
    Serial.println("     the gate may be absent on this board. Treat with care.");
  }

  const bool use_high = high_live && (mv_high >= mv_low);
  const float raw_mv = use_high ? mv_high : mv_low;
  const float raw_v = raw_mv / 1000.0f;

  Serial.printf("  -> divider enabled by ADC_CTRL %s\n",
                use_high ? "HIGH (V3.2 or later)" : "LOW (pre-V3.2)");
  Serial.printf("  VBAT_DIVIDER : %.3f  (include/board_pins.h)\n",
                VBAT_DIVIDER);
  Serial.printf("  sensed node  : %.3f V\n", raw_v * VBAT_DIVIDER);

  Serial.println("\n  With USB attached and NO pack fitted this still reads a");
  Serial.println("  voltage -- the charger output floats near 4.2 V with nothing");
  Serial.println("  to sink it. A reading here does NOT prove a battery exists.");

  Serial.println("\n  -- calibration (needs a real pack) --");
  Serial.println("  Measure the pack at the JST with a meter, then:");
  Serial.printf("      VBAT_DIVIDER = V_meter / %.4f\n", raw_v);
  for (float v = 3.60f; v <= 4.25f; v += 0.05f) {
    Serial.printf("      %.2f V -> %.3f\n", v, v / raw_v);
  }
}

void setup() {
  Serial.begin(115200);
  const uint32_t deadline = millis() + 2000;
  while (!Serial && millis() < deadline) {
    delay(10);
  }
  delay(200);

  pinMode(LED_WHITE, OUTPUT);
  digitalWrite(LED_WHITE, LOW);
  pinMode(BUTTON_PRG, INPUT_PULLUP);

  Serial.println("\n==== Heltec WiFi LoRa 32 V3 bring-up ====");
  reportChip();

  Serial.println("\n-- I2C / OLED --");
  const bool oledOk = scanOledBus();

  Serial.println("\n-- SX1262 --");
  const bool radioOk = initRadio();

  Serial.println("\n-- battery --");
  reportBattery();

  Serial.printf("\nresult: OLED %s, radio %s\n", oledOk ? "ok" : "MISSING",
                radioOk ? "ok" : "FAILED");
  Serial.println("LED blinks 1 Hz; hold PRG to see the button reported.\n");
}

void loop() {
  static bool lastButton = true;

  digitalWrite(LED_WHITE, HIGH);
  delay(100);
  digitalWrite(LED_WHITE, LOW);
  delay(900);

  const bool button = digitalRead(BUTTON_PRG);
  if (button != lastButton) {
    Serial.printf("PRG %s\n", button ? "released" : "pressed");
    lastButton = button;
  }
}
