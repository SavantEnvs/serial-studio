// MDF4 replay-decode harness. Same body as app/tests/fuzz/fuzz_mdf4_reader.cpp plus one catch:
// mdflib's MdfReader constructor throws std::ios_base::failure on a file shorter than its 64-byte
// ID block, and MDF4::PlayerLoaderWorker::decodeFile (openStructure) does not catch it, so upstream's
// own harness aborts on the first one-byte input and the rest of the decoder never gets fuzzed.
// Only that exception type is swallowed; every other exception and every sanitizer report still aborts.
#include <cstdint>
#include <ios>
#include <QByteArray>
#include <QTemporaryFile>

#include "MDF4/PlayerLoaderWorker.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  if (size == 0 || size > (4u << 20))
    return 0;

  QTemporaryFile file;
  if (!file.open())
    return 0;

  file.write(reinterpret_cast<const char*>(data), static_cast<qint64>(size));
  file.flush();

  MDF4::PlayerLoaderWorker worker;
  try {
    worker.decodeFile(file.fileName(), 1, QVector<quint8>{});
  } catch (const std::ios_base::failure&) {
  }
  return 0;
}
