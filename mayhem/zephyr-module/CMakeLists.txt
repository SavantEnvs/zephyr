# Extra Zephyr module for the Mayhem build: it only touches the native_simulator runner, which is
# compiled outside the Zephyr image and is where the final fuzzer link happens.
if(TARGET native_simulator)
  # Disable LeakSanitizer (SPEC 6.2 item 15) in the final executable.
  target_sources(native_simulator INTERFACE ${MAYHEM_LSAN_OFF_SRC})

  # DWARF <= 3 for the runner objects (SPEC 6.2 item 10); applies after the runner's default -g.
  target_compile_options(native_simulator INTERFACE -g -gdwarf-3)

  # Standalone reproducer: the runner drops the libFuzzer engine and links a prebuilt run-once
  # main() object instead; the sanitizer runtimes still provide the coverage callbacks.
  if(MAYHEM_STANDALONE_MAIN_OBJ)
    foreach(prop INTERFACE_COMPILE_OPTIONS INTERFACE_LINK_OPTIONS)
      get_target_property(opts native_simulator ${prop})
      list(TRANSFORM opts REPLACE ",fuzzer" "")
      list(TRANSFORM opts REPLACE "=fuzzer$" "=address")
      set_property(TARGET native_simulator PROPERTY ${prop} ${opts})
    endforeach()
    target_link_options(native_simulator INTERFACE ${MAYHEM_STANDALONE_MAIN_OBJ})
  endif()
endif()
