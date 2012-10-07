REBAR=$(shell pwd)/rebar
all: compile

compile:
	@$(REBAR) compile

clean:
	@$(REBAR) clean

test: compile
	@$(REBAR) eunit

docs:
	@$(REBAR) doc

xref: compile
        @$(REBAR) xref skip_deps=true
