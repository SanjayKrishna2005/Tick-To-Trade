# Run from the repository root.   make test | make ports | make mutate | make clean
.PHONY: test ports mutate clean

test:            ## full regression (about 1 minute): needs iverilog + python3
	bash verification/run_all.sh ../rtl

ports:           ## compare every module's ports with the interface specification: needs yosys
	cd verification && echo 000 > feed.hex && yosys -q -p "read_verilog -sv ../rtl/*.v; proc; write_json ports.json" ; rc=$$?; rm -f feed.hex; [ $$rc -eq 0 ] && python3 port_check.py ports.json

mutate:          ## mutation campaign (20-40 min). Example: make mutate JOBS=4
	cd verification && python3 gen_vectors.py ref 1 vec_ref >/dev/null && python3 gen_vectors.py story 1 vec_story >/dev/null && \
	python3 gen_vectors.py edge 1 vec_edge >/dev/null && python3 gen_vectors.py gaps 1 vec_gaps >/dev/null && \
	python3 gen_vectors.py defaults 1 vec_defaults >/dev/null && python3 gen_vectors.py nofire 7 vec_nofire 300 >/dev/null && \
	python3 gen_vectors.py random 11 vec_m 600 >/dev/null && \
	JOBS=$(or $(JOBS),2) python3 mutate.py ../rtl vec_gaps:0:0 vec_defaults:0:0 vec_ref vec_story vec_edge:0:0 vec_edge:0:90:1 vec_nofire vec_m vec_m:20:70:1 | tee mut.log

clean:
	rm -rf verification/build_* verification/vec_* verification/__pycache__ verification/ports.json verification/mut.log
