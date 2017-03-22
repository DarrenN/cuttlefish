cuttlefish
==========

![Mr. Cuddlesworth](http://pre14.deviantart.net/049e/th/pre/f/2013/365/f/a/cuttlefish_by_naeomi-d709r4p.png)

### To install

```
$ brew cask install racket
$ raco pkg install
```

### What it does

Cuttlefish consumes a `chapters.json` file (sample in `/private/data`) and spins
up workers to fetch API data for each chapter based on the `adapter` field
within each entry.

`/private/workers` has modules corresponding to each service we want to hit.
Currently there is only `meetup.rkt`.

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


### Run it

Currently in hackety-hack mode, so:

```
$ cd private
$ racket api-runner.rkt
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

---

Image from [Naeomi](http://naeomi.deviantart.com/art/Prize-Mr-Cuddlesworth-423718297)
