REBAR = rebar3

compile:
	$(REBAR) compile

clean:
	$(REBAR) clean

test:
	$(REBAR) eunit

###
### Docs
###
docs:
	$(REBAR) doc

##
## Developer targets
##

xref:
	$(REBAR) xref
