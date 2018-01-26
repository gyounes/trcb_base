PACKAGE         ?= trcb_base
VERSION         ?= $(shell git describe --tags)
BASE_DIR         = $(shell pwd)
ERLANG_BIN       = $(shell dirname $(shell which erl))
REBAR            = $(shell pwd)/rebar3
MAKE						 = make

.PHONY: rel deps test eqc plots

all: compile

##
## Compilation targets
##

compile:
	$(REBAR) compile

clean: packageclean
	$(REBAR) clean

packageclean:
	rm -fr *.deb
	rm -fr *.tar.gz

##
## Test targets
##

check: test xref dialyzer lint

test: ct eunit
		${REBAR} cover -v

lint:
	${REBAR} as lint lint

eunit:
	${REBAR} eunit

ct:
	${REBAR} ct

shell:
	${REBAR} shell --apps trcb_base

logs:
	tail -F priv/lager/*/log/*.log

cover: test
	open _build/test/cover/index.html

##
## Release targets
##

rel:
	${REBAR} release

stage:
	${REBAR} release -d

DIALYZER_APPS = kernel stdlib erts sasl eunit syntax_tools compiler crypto

include tools.mk
