cuttlefish
==========

![cuttlefish](http://pwlconf.org/images/cuttlefish-48188_1280.png)

Gathers data for Papers We Love meetups from different services. Currently pulls from Meetup.com and Facebook.

### To install

```
$ brew cask install racket
$ cd cuttlefish
$ raco pkg install
```

### What it does

Cuttlefish consumes a `chapters.json` file (sample in `/private/data`) and spins
up workers to fetch API data for each chapter based on the `adapter` field
within each entry.

`/private/workers` has modules corresponding to each service we want to hit.
We currently have adapters for Meetup.com (`meetup.rkt`) and Facebook (`facebook.rkt`).

Worker functions are responsible for everything about their service (endpoints,
throttling, etc) and must adhere to the following contract:

```scheme
(define (worker-fooo logger id payload)

  ; ... code ....

  (cond [fail (list 'ERROR string?)]
        [success (list id jsexpr?)]))
```

Errors should be `(ERROR "reason for failure containing id for logging")`

Success should be a [jsexpr](http://docs.racket-lang.org/json/index.html?q=jsexpr#%28tech._jsexpr%29)
matching the specificed format for chapter events: `(id jsexpr)`

### Config file

1. Copy `cuttlefishrc.template` to `.cuttlefishrc`
1. Update the values inside to point to correct directories, provide API keys, etc.

### Run it

Currently in hackety-hack mode, so:

```
$ racket main.rkt
```

To run with a different config:

```
$ racket main.rkt path/to/config/file
```

Head over to `/tmp` (in your root) and you'll see some json files like
`london.json` and also a folder with a log file in it:

```
cuttlefish: 2017-03-22T18:52:19.133912109 ERROR: (boston HTTP/1.1 404 Not Found)
cuttlefish: 2017-03-22T18:52:19.168971924 WROTE: /tmp/portland.json
cuttlefish: 2017-03-22T18:52:19.480523926 WROTE: /tmp/stlouis.json
cuttlefish: 2017-03-22T18:52:19.53948291 WROTE: /tmp/london.json
cuttlefish: 2017-03-22T18:52:19.575353027 WROTE: /tmp/sanfrancisco.json
cuttlefish: 2017-03-22T18:52:20.340291016 WROTE: /tmp/newyork.json
```
