[![Build Status](https://travis-ci.org/gyounes/trcb_base.svg?branch=master)](https://travis-ci.org/gyounes/trcb_base)
[![Coverage Status](https://coveralls.io/repos/github/gyounes/trcb_base/badge.svg?branch=master)](https://coveralls.io/github/gyounes/trcb_base?branch=master)


# trcb_base
__A Tagged Reliable Causal Broadcast (TRCB) Middleware__

----------

### Description

This is a working implementation of the TRCB mentioned in [Making Operation-based CRDTs Operation-based](https://repositorio.inesctec.pt/bitstream/123456789/4208/1/P-00F-JRH.pdf)

### Features

- [x] Provides at-least-once message transfer.
- [x] Provides at-most-once message delivery.
- [x] Provides tagged causal delivery of messages.
- [ ] Provides causal stability to garbage-collect meta-data that became useless.
- [ ] Provides test cases that cover all code.