// Leak detection is off for every fuzz and -standalone binary; ASan and UBSan stay fully active.
extern "C" int __lsan_is_turned_off() { return 1; }
