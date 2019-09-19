#lang racket
(require racket/async-channel
         gregor
         json
         (except-in "hash.rkt" get)
         "chunk-list.rkt"
         "logger.rkt"
         "workers/meetup.rkt"
         "workers/facebook.rkt"
         "workers/eventbrite.rkt")

(provide run-workers)

;; ================
;; Worker Functions
;; ================
;; Define worker functions by their adapter key from the chapter.json files

(define WORKERS
  (hash "meetup" worker-meetup
        "facebook" worker-facebook
        "eventbrite" worker-eventbrite))

;; How many threads/channels to spin up to do work
(define THREAD-COUNT 3)

;; Mutable state
(define state (box '()))
(define logging-thread '())

;; Logging
;; =======
(define (create-logging-thread path)
  (set! logging-thread
        (launch-log-daemon (path->complete-path path) "cuttlefish.log")))

;; Write JSON to files
;; ====================
(define (write-chapter-response config response)
  (let* ([id (car response)]
         [resp (cadr response)]
         [path (build-path (hash-ref config 'json-out-path)
                           (format "~a.json" id))])
    (with-handlers ([exn:fail?
                     (λ (exn) (channel-put
                               result-channel
                               (format "ERROR: Could not write to ~a : ~a"
                                       path (exn-message exn))))])
      (begin
        (with-output-to-file path #:mode 'text #:exists 'replace
          (λ () (display (jsexpr->string resp))))
        (channel-put result-channel (format "WROTE: ~a" path))))))

;; Payload should be in the format (id jsexpr?) or an error
(define (write-response rsp)
  (let ([config (first rsp)]
        [resp (last rsp)])
    (case (car resp)
      ['ERROR
       (channel-put result-channel (format "ERROR: ~a" (cdr resp)))]
      [else (write-chapter-response config resp)])))

;; Keep tabs on how many 'DONE messages come in and terminate when they all
;; phone home
(define (maintain-done-state done)
  (let* ([s (unbox state)]
         [l THREAD-COUNT]
         [n (cons done s)])
    (if (equal? (length n) l)
        (begin
          (format-log
           "~a"
           (format "DONE: ~a of ~a threads completed" (length n) l))
          (format-log "~a" "=====")
          (sleep 2) ; allow time to flush the log
          (kill-thread logging-thread))
        (set-box! state n))))

;; Result channel - writes to log file
(define result-channel (make-channel))
(define result-thread
  (thread
   (λ ()
     (let loop ()
       (let ([r (channel-get result-channel)])
         (if (equal? r 'DONE)
             (maintain-done-state r)
             (format-log "~a" r)))
       (loop)))))

;; Read adapter key from chapter payload
(define (get-adapter payload)
  (if (equal? payload 'DONE)
      'DONE
      (get-in '(dataService adapter) (cdr payload))))


;; Worker Threads
;; ==============

#|

General outline:
----------------

1) Create a list of n work-channels
2) Create a worker-threads for each channel
3) Partition list of chapters into (length work-channels) lists
4) append 'DONE to the end of each chapters list
5) For each chapters list push chapter into a channel
6) Each thread should terminate on 'DONE

|#

;; Returns a thread bound to id which calls a function based on adapter
;; from the WORKERS hash. If a worker function is registered, its output is
;; tossed onto the file-channel. Errors are logged immediately.
(define (dispatch-worker thread-id chan)
  (thread
   (λ ()
     (let loop ()
       (define chapter (async-channel-get chan))
       (define config (car chapter))
       (define item (last chapter))
       (define adapter (get-adapter item))
       (cond
         [(equal? adapter 'DONE)
          (channel-put result-channel 'DONE)]
         [(hash-has-key? WORKERS adapter)
          (write-response (list config
                                ((hash-ref WORKERS adapter)
                                 format-log thread-id config item)))
          (loop)]
         [else
          (channel-put
           result-channel
           (format "ERROR: Adapter ~a not registered! [~a]" adapter (car item)))
          (loop)])))))

;; Build a list of chapter payloads with corresponding # of DONE symbols for
;; passing to threads
(define (prepare-chapter-payloads chapters)
  (let* ([pairs (hash->list chapters)]
         [chunks (chunk-list pairs THREAD-COUNT)])
    (map (λ (x) (append x '(DONE))) chunks)))

;; Create a list of async worker channels equal to THREAD-COUNT
;; Worker channel has a buffer size equal to # of items in chapters chunk
(define (prepare-work-channels chapter-payloads)
  (for/list ([i (range THREAD-COUNT)]
             [chapters chapter-payloads])
      (make-async-channel (length chapters))))

;; Spin up a worker thread on each channel
(define (prepare-work-threads work-channels)
  (for/list ([ch work-channels]
             [id (range (length work-channels))])
      (dispatch-worker id ch)))

;; Read JSON - If we can't open the chapters file then crash out
(define (read-chapter-json path)
  (if (file-exists? path)
      (call-with-input-file path (λ (in) (read-json in)))
      (begin
        (format-log "FATAL: Cannot open ~a" path)
        (printf "FATAL: Cannot open ~a" path)
        (kill-thread logging-thread)
        (exit 1))))

;; ============
;; Run workers
;; ============

(define (run-workers config)
  (create-logging-thread (hash-ref config 'logfile-path))
  (define CHAPTERS-JSON (build-path (hash-ref config 'chapter-json-file)))

  ;; Builds list of channels and load with worker threads
  (define chapter-payloads
    (prepare-chapter-payloads (read-chapter-json CHAPTERS-JSON)))

  (define work-channels (prepare-work-channels chapter-payloads))
  (define work-threads (prepare-work-threads work-channels))

  ;; Load payloads into the channels
  (for ([chan work-channels]
        [chapters chapter-payloads])
    (for ([chapter chapters])
      (async-channel-put chan (list config chapter))))

  (format-log "~a" "=====")
  (format-log "~a" (format "START: spinning up ~a threads"
                           THREAD-COUNT))

  ;; We have to explicitly drop a wait on each thread or it will immediately
  ;; close before it takes work off the channels (synchronization)
  (for-each thread-wait work-threads)
  (thread-wait logging-thread))
