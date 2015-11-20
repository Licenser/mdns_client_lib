REBAR = rebar3

.PHONY: all test

all: compile

include fifo.mk

clean:
	$(REBAR) clean

eunit:
	$(REBAR) eunit
