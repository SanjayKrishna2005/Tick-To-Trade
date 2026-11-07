# verification/

Independent verification kit for `../rtl`. Everything is explained in the top-level README (sections 7, 8 and 11).

Quick start from the repository root: `make test`

| File | Purpose |
|---|---|
| `t2t_model.py` | golden model, written from the design specification only |
| `gen_vectors.py` | scenario generator: `ref`, `story`, `edge`, `gaps`, `defaults`, `random`, `nofire` |
| `tb_sys.v` | system testbench with per-boundary scoreboards and monitors |
| `tb_unit.v`, `tb_rom.v` | standalone tests for `axis_slice`/`axis_register` and `replay_rom` |
| `run_all.sh` | full regression; exit code 0 only if everything passes |
| `run_sys.sh`, `run_unit.sh`, `run_rom.sh` | single runs |
| `port_check.py` | port names, directions and widths vs the interface specification |
| `mutate.py`, `equivalent.txt` | mutation campaign and the reviewed harmless survivors |

Vectors and build folders (`vec_*`, `build_*`) are generated and git-ignored.
