REBAR = ./rebar3

.PHONY: all test

all: compile dialyzer

include fifo.mk

eunit:
	@$(REBAR) eunit
