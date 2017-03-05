#lang racket
(require racket/async-channel
         gregor
         json
         (except-in "hash.rkt" get)
         "logger.rkt"
         "workers/meetup.rkt")

;; TODO: paths should be set by args or ENV vars
(define CHAPTERS_JSON (build-path (current-directory) "data" "chapters.json"))
(define CHAPTERS_OUTPUT (build-path "/tmp"))

;; Mutable state
(define chapters (box '()))

;; logging
;; TODO: path should be set by ARGS or ENV vars
(define logging-thread
  (launch-log-daemon (build-path "/tmp") "racket-test-logger"))

;; If we can't open the chapters file then crash out
(if (file-exists? CHAPTERS_JSON)
    (set-box! chapters
              (call-with-input-file CHAPTERS_JSON (λ (in) (read-json in))))
    (begin
      (format-log "FATAL: Cannot open ~a" CHAPTERS_JSON)
      (printf "FATAL: Cannot open ~a" CHAPTERS_JSON)
      (kill-thread logging-thread)
      (exit 1)))

;; Write response to file
(define (write-chapter-response response)
  (let* ([id (car response)]
         [resp (cadr response)]
         [path (build-path CHAPTERS_OUTPUT (format "~a.json" id))])
    (with-handlers ([exn:fail?
                     (λ (exn) (channel-put
                               result-channel
                               (format "ERROR: Could not write to ~a" path)))])
      (begin
        (with-output-to-file path #:mode 'binary #:exists 'replace
          (λ () (printf (jsexpr->string resp))))
        (channel-put result-channel (format "WROTE: ~a" path))))))

;; Result channel - writes to log file
(define result-channel (make-channel))
(define result-thread
  (thread
   (λ ()
     (let loop ()
       (let ([r (channel-get result-channel)])
         (format-log "~a" r))
       (loop)))))

;; File channel
;; Payload should be in the format (id jsexpr?) or an error
(define file-channel (make-channel))
(define file-thread
        (thread
         (λ ()
           (let loop ()
             (let ([r (channel-get file-channel)])
               (case (car r)
                 ['ERROR
                  (channel-put result-channel (format "ERROR: ~a" (cdr r)))]
                 [else (write-chapter-response r)]))
             (loop)))))

(define (get-adapter payload)
  (if (equal? (car payload) 'DONE)
      'DONE
      (get-in '(dataService adapter) (cdr payload))))

;; Work channel has a buffer size of 10
(define work-channel (make-async-channel 10))

;; Returns a thread bound to id which calls a function based on adapter
(define (dispatch-worker thread-id)
  (thread
   (λ ()
     (let loop ()
       (define item (async-channel-get work-channel))
       (case (get-adapter item)
         ['DONE
          (channel-put result-channel
                       (format "DONE: thread ~a" thread-id))]
         [("meetup")
          (channel-put file-channel (worker-ant format-log thread-id item))
          (loop)]
         [else (loop)])))))

;; Spin up 3 threads and load with data
(define work-threads (map dispatch-worker '(1 2 3)))

;; Build a list of chapter payloads with corresponding # of DONE symbols for
;; passing to threads
(define chapter-payloads
  (let* ([chapters (unbox chapters)]
         [pairs (hash->list chapters)]
         [dones (make-list (length pairs) '(DONE))])
    (append pairs dones)))

;;(displayln chapter-payloads)

;; Load payloads into the channels
(for ([item chapter-payloads])
  (async-channel-put work-channel item))

;; Create a thread for wach dispatch-thread function
(for-each thread-wait work-threads)
