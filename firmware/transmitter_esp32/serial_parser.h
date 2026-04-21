// firmware/transmitter_esp32/serial_parser.h
//
// VERBATIM copy of firmware/transmitter/serial_parser.h. The parser is
// transport-agnostic: it walks a char* buffer that was already assembled
// by the caller. The only thing that changes between Nano and ESP32 is
// *how* bytes are fed into that buffer (HardwareSerial vs BLE characteristic).

#ifndef SERIAL_PARSER_H
#define SERIAL_PARSER_H

#include <Arduino.h>

// Parse a comma-separated list of ints like "1,11,21" into an array.
// Returns number of values parsed.
int parseIntList(const char* str, int* out, int maxCount) {
  int count = 0;
  const char* p = str;
  while (*p && count < maxCount) {
    out[count] = atoi(p);
    count++;
    while (*p && *p != ',') p++;
    if (*p == ',') p++;
  }
  return count;
}

// Parse a float from a string, advance pointer past the value.
float parseNextFloat(char** p) {
  float val = atof(*p);
  while (**p && **p != '/') (*p)++;
  if (**p == '/') (*p)++;
  return val;
}

// Parse an int from a string, advance pointer past the value.
int parseNextInt(char** p) {
  int val = atoi(*p);
  while (**p && **p != '/') (*p)++;
  if (**p == '/') (*p)++;
  return val;
}

// Parse a comma-separated int list field, advance pointer past it.
// Returns count of values parsed.
int parseNextIntList(char** p, int* out, int maxCount) {
  char* start = *p;
  while (**p && **p != '/') (*p)++;

  // Temporarily null-terminate
  char saved = **p;
  **p = '\0';
  int count = parseIntList(start, out, maxCount);
  **p = saved;

  if (**p == '/') (*p)++;
  return count;
}

#endif
