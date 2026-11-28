#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace probe_wave {
constexpr uint32_t residentRate = 24000;

// The format and SHA-256 must both match before samples are returned.
bool LoadResident(const char *path, std::vector<int16_t> &mono24k, const char *&error);

// Validate an unused output path in an existing caller-owned private directory.
bool CheckCapturePath(const char *path, const char *&error);

// Revalidate the path and create the file exclusively.
bool WriteCapture(const char *path, const int16_t *mono, size_t frames, uint32_t sampleRate,
                  const char *&error);

bool SelfTest();
}  // namespace probe_wave
