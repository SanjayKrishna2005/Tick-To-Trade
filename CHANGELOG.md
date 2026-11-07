# Changelog

## v1.0-frozen
- 15 RTL modules: Ethernet/IPv4/UDP parser, byte FIFO, message assembler, router, config registers,
  book tracker, strategy, risk check with rate limiter, order encoder, event counters, latency counter,
  plus `axis_register`, `axis_slice`, `replay_rom` helpers.
- Independent Python golden model, per-boundary scoreboards, hold-while-stalled monitors, reset check,
  final-state read-back, throughput check.
- Scenarios: ref, story, edge, gaps, defaults, random, nofire.
- Mutation campaign: 325 mutants, 273 caught, 22 reviewed harmless, 0 unexplained (92.5 % raw).
- Idle tick-to-order latency: 7 cycles (4 cycles on-chip decision latency). Simulation only.
