.SUFFIXES: .erl .beam .yrl

.erl.beam:
	erlc -W +native +'{parse_transform, smart_exceptions}' $<

.yrl.erl:
	erlc -W +native +'{parse_transform, smart_exceptions}' $<

ERL = erl 

MODS = gen_server_udp gen_server_udp_receive gen_server_udp_test

all: compile

compile: ${MODS:%=%.beam}

test: compile
	${ERL} -sname test +P 4000000 -noshell -s gen_server_udp_test test

clean:
	rm -rf *.beam erl_crash.dump
