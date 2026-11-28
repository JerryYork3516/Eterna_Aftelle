#include "WaveFile.h"

#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

namespace probe_wave {
namespace {
constexpr size_t maxResidentBytes = 1024 * 1024;
constexpr size_t maxResidentFrames = 7 * residentRate;
constexpr uint32_t maxCaptureSeconds = 16;
constexpr std::array<uint8_t, CC_SHA256_DIGEST_LENGTH> residentDigest{
    0x77, 0x4e, 0x45, 0x0c, 0xe1, 0xff, 0x92, 0x40,
    0x20, 0x51, 0xf8, 0x9a, 0xe4, 0xfd, 0x53, 0x7d,
    0x74, 0x36, 0x7d, 0xe5, 0xff, 0x9c, 0x2f, 0x92,
    0x67, 0x0b, 0xa0, 0xf6, 0x63, 0x7d, 0x47, 0xea,
};

struct File {
  explicit File(int value) : fd(value) {}
  File(const File &) = delete;
  File &operator=(const File &) = delete;
  ~File() { if (fd >= 0) close(fd); }
  bool Finish() {
    const int result = close(fd);
    fd = -1;
    return result == 0;
  }
  int fd;
};

bool Reject(const char *message, const char *&error) {
  error = message;
  return false;
}

bool ReadAll(int file, uint8_t *out, size_t bytes) {
  while (bytes != 0) {
    const ssize_t count = read(file, out, bytes);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    out += count;
    bytes -= count;
  }
  return true;
}

bool WriteAll(int file, const uint8_t *data, size_t bytes) {
  while (bytes != 0) {
    const ssize_t count = write(file, data, bytes);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return false;
    data += count;
    bytes -= count;
  }
  return true;
}

uint16_t Read16(const uint8_t *data) {
  return static_cast<uint16_t>(data[0] | (data[1] << 8));
}

uint32_t Read32(const uint8_t *data) {
  return Read16(data) | (static_cast<uint32_t>(Read16(data + 2)) << 16);
}

void Put16(uint8_t *out, uint16_t value) {
  out[0] = static_cast<uint8_t>(value);
  out[1] = static_cast<uint8_t>(value >> 8);
}

void Put32(uint8_t *out, uint32_t value) {
  Put16(out, static_cast<uint16_t>(value));
  Put16(out + 2, static_cast<uint16_t>(value >> 16));
}

bool IsPcmMono(const uint8_t *format, size_t length, uint32_t rate) {
  return length >= 16 && Read16(format) == 1 && Read16(format + 2) == 1 &&
         Read32(format + 4) == rate && Read32(format + 8) == rate * 2 &&
         Read16(format + 12) == 2 && Read16(format + 14) == 16;
}

bool DecodeResident(const std::vector<uint8_t> &wave, std::vector<int16_t> &mono,
                    const char *&error) {
  if (wave.size() < 12 || std::memcmp(wave.data(), "RIFF", 4) != 0 ||
      Read32(wave.data() + 4) != wave.size() - 8 ||
      std::memcmp(wave.data() + 8, "WAVE", 4) != 0) {
    return Reject("resident asset is not a complete RIFF WAVE", error);
  }

  bool foundFormat = false;
  const uint8_t *samples = nullptr;
  size_t frames = 0;
  size_t offset = 12;
  while (wave.size() - offset >= 8) {
    const uint8_t *chunk = wave.data() + offset;
    const size_t length = Read32(chunk + 4);
    const size_t paddedLength = length + (length & 1);
    if (paddedLength > wave.size() - offset - 8) {
      return Reject("resident asset has a truncated WAVE chunk", error);
    }

    if (std::memcmp(chunk, "fmt ", 4) == 0) {
      if (foundFormat || !IsPcmMono(chunk + 8, length, residentRate)) {
        return Reject("resident asset must be 24 kHz mono PCM16LE", error);
      }
      foundFormat = true;
    } else if (std::memcmp(chunk, "data", 4) == 0) {
      if (samples || length == 0 || (length & 1) || length / 2 > maxResidentFrames) {
        return Reject("resident asset has an invalid PCM frame count", error);
      }
      samples = chunk + 8;
      frames = length / 2;
    }
    offset += 8 + paddedLength;
  }

  if (offset != wave.size() || !foundFormat || !samples) {
    return Reject("resident asset is missing WAVE format or PCM data", error);
  }
  mono.resize(frames);
  for (size_t frame = 0; frame < frames; ++frame) {
    const uint16_t value = Read16(samples + 2 * frame);
    mono[frame] = static_cast<int16_t>(value <= INT16_MAX ? value : static_cast<int>(value) - 65536);
  }
  return true;
}

std::array<uint8_t, 44> CaptureHeader(uint32_t dataBytes, uint32_t rate) {
  std::array<uint8_t, 44> header{};
  std::memcpy(header.data(), "RIFF", 4);
  Put32(header.data() + 4, dataBytes + 36);
  std::memcpy(header.data() + 8, "WAVEfmt ", 8);
  Put32(header.data() + 16, 16);
  Put16(header.data() + 20, 1);
  Put16(header.data() + 22, 1);
  Put32(header.data() + 24, rate);
  Put32(header.data() + 28, 2 * rate);
  Put16(header.data() + 32, 2);
  Put16(header.data() + 34, 16);
  std::memcpy(header.data() + 36, "data", 4);
  Put32(header.data() + 40, dataBytes);
  return header;
}

bool WritePcm(int file, const int16_t *mono, size_t frames) {
  std::array<uint8_t, 1024> bytes{};
  while (frames != 0) {
    const size_t count = frames < bytes.size() / 2 ? frames : bytes.size() / 2;
    for (size_t sample = 0; sample < count; ++sample) {
      Put16(bytes.data() + 2 * sample, static_cast<uint16_t>(mono[sample]));
    }
    if (!WriteAll(file, bytes.data(), 2 * count)) return false;
    mono += count;
    frames -= count;
  }
  return true;
}
struct CaptureTarget {
  File directory{-1};
  std::string name;
};

bool OpenCaptureTarget(const char *path, CaptureTarget &target, const char *&error) {
  if (!path) return Reject("capture filename invalid", error);
  const std::string output(path);
  const size_t split = output.rfind('/');
  const std::string parent = split == std::string::npos ? "." : output.substr(0, split == 0 ? 1 : split);
  target.name = split == std::string::npos ? output : output.substr(split + 1);
  if (target.name.empty() || target.name == "." || target.name == "..") {
    return Reject("capture filename invalid", error);
  }
  target.directory.fd = open(parent.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  struct stat info{};
  if (target.directory.fd < 0 || fstat(target.directory.fd, &info) != 0 ||
      info.st_uid != geteuid() || (info.st_mode & 0077) != 0 ||
      faccessat(target.directory.fd, ".", W_OK | X_OK, AT_EACCESS) != 0) {
    return Reject("capture directory must be writable, owned by the caller and private", error);
  }
  if (fstatat(target.directory.fd, target.name.c_str(), &info, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT) {
    return Reject("capture path is unavailable for exclusive creation", error);
  }
  return true;
}
}  // namespace

bool LoadResident(const char *path, std::vector<int16_t> &mono24k, const char *&error) {
  error = nullptr;
  if (!path) return Reject("resident asset path missing", error);
  File file(open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW));
  struct stat info{};
  if (file.fd < 0 || fstat(file.fd, &info) != 0 || !S_ISREG(info.st_mode) ||
      info.st_size < 44 || info.st_size > static_cast<off_t>(maxResidentBytes)) {
    return Reject("resident asset must be a bounded regular WAV file", error);
  }
  std::vector<uint8_t> wave(static_cast<size_t>(info.st_size));
  if (!ReadAll(file.fd, wave.data(), wave.size())) return Reject("resident asset read failed", error);
  uint8_t extra = 0;
  ssize_t remaining;
  do {
    remaining = read(file.fd, &extra, 1);
  } while (remaining < 0 && errno == EINTR);
  if (remaining != 0) return Reject("resident asset changed while being read", error);

  std::array<uint8_t, CC_SHA256_DIGEST_LENGTH> actual{};
  CC_SHA256(wave.data(), static_cast<CC_LONG>(wave.size()), actual.data());
  if (actual != residentDigest) return Reject("resident asset SHA-256 mismatch", error);
  return DecodeResident(wave, mono24k, error);
}

bool CheckCapturePath(const char *path, const char *&error) {
  error = nullptr;
  CaptureTarget target;
  return OpenCaptureTarget(path, target, error);
}

bool WriteCapture(const char *path, const int16_t *mono, size_t frames, uint32_t sampleRate,
                  const char *&error) {
  error = nullptr;
  if (!mono || sampleRate < 8000 || sampleRate > 192000 || frames == 0 ||
      frames > maxCaptureSeconds * sampleRate) {
    return Reject("capture format or frame count invalid", error);
  }
  CaptureTarget target;
  if (!OpenCaptureTarget(path, target, error)) return false;
  File file(openat(target.directory.fd, target.name.c_str(),
                   O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600));
  if (file.fd < 0) return Reject("capture file cannot be created exclusively", error);

  const auto header = CaptureHeader(static_cast<uint32_t>(frames * 2), sampleRate);
  const bool written = fchmod(file.fd, 0600) == 0 &&
      WriteAll(file.fd, header.data(), header.size()) && WritePcm(file.fd, mono, frames);
  const bool closed = file.Finish();
  if (written && closed) return true;
  if (unlinkat(target.directory.fd, target.name.c_str(), 0) != 0) {
    return Reject("capture write failed and partial file could not be removed", error);
  }
  return Reject("capture write failed", error);
}

namespace {
bool TestCaptureFile(const std::vector<int16_t> &expected) {
  const char *provided = std::getenv("TMPDIR");
  std::string directory = std::string(provided && *provided ? provided : "/tmp") + "/aftelle-wave-test.XXXXXX";
  if (!mkdtemp(directory.data())) return false;
  const std::string path = directory + "/synthetic.wav";
  const char *error = nullptr;
  const std::array<int16_t, 1> replacement{0};
  const bool written = CheckCapturePath(path.c_str(), error) &&
      WriteCapture(path.c_str(), expected.data(), expected.size(), residentRate, error) &&
      !CheckCapturePath(path.c_str(), error) &&
      !WriteCapture(path.c_str(), replacement.data(), replacement.size(), residentRate, error);
  std::vector<uint8_t> bytes(44 + 2 * expected.size());
  std::vector<int16_t> decoded;
  File file(open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW));
  struct stat info{};
  const bool valid = written && file.fd >= 0 && fstat(file.fd, &info) == 0 &&
      (info.st_mode & 0777) == 0600 && info.st_size == static_cast<off_t>(bytes.size()) &&
      ReadAll(file.fd, bytes.data(), bytes.size()) && DecodeResident(bytes, decoded, error) &&
      decoded == expected && !LoadResident(path.c_str(), decoded, error) &&
      std::strcmp(error, "resident asset SHA-256 mismatch") == 0;
  const bool removed = unlink(path.c_str()) == 0;
  const bool emptied = rmdir(directory.c_str()) == 0;
  return valid && removed && emptied;
}
}  // namespace

bool SelfTest() {
  constexpr std::array<int16_t, 3> expected{-32768, 1, 32767};
  const auto header = CaptureHeader(6, residentRate);
  std::vector<uint8_t> bytes(header.begin(), header.end());
  bytes.resize(bytes.size() + 6);
  for (size_t frame = 0; frame < expected.size(); ++frame) {
    Put16(bytes.data() + header.size() + 2 * frame, static_cast<uint16_t>(expected[frame]));
  }
  // Exercise an odd-length ancillary chunk and its required padding byte.
  bytes.insert(bytes.begin() + 12, {'J', 'U', 'N', 'K', 1, 0, 0, 0, 42, 0});
  Put32(bytes.data() + 4, static_cast<uint32_t>(bytes.size() - 8));
  const char *error = nullptr;
  std::vector<int16_t> samples;
  if (!DecodeResident(bytes, samples, error) ||
      samples != std::vector<int16_t>(expected.begin(), expected.end())) return false;

  Put16(bytes.data() + 32, 2);
  if (DecodeResident(bytes, samples, error)) return false;
  Put16(bytes.data() + 32, 1);
  Put32(bytes.data() + 34, 48000);
  if (DecodeResident(bytes, samples, error)) return false;
  Put32(bytes.data() + 34, residentRate);
  bytes.pop_back();
  Put32(bytes.data() + 4, static_cast<uint32_t>(bytes.size() - 8));
  return !DecodeResident(bytes, samples, error) &&
      TestCaptureFile(std::vector<int16_t>(expected.begin(), expected.end()));
}
}  // namespace probe_wave
