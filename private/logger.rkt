#lang racket

(require gregor)

(provide format-log
         launch-log-daemon)

;; logging

(define chlogger (make-logger 'cuttlefish))
(define rc (make-log-receiver chlogger 'info))

(define logger_thread #f)

;; Log listener for debug purposes. Should turn this off.
#|
(void
 (thread
  (λ ()
    (let loop ()
      (match (sync rc)
        [(vector l m v v1)
         (printf "~a\n" m)])
      (loop)))))
|#
(current-logger chlogger)

(define (format-log fmt . msg)
  (log-info fmt (string-append (datetime->iso8601 (now))
                               " " (apply format (cons fmt msg)))))

;; Write log messages to file

(define (start-logger log_path filename)
  (let ([r (make-log-receiver chlogger 'info)]
        [log-date (substring (datetime->iso8601 (now)) 0 10)])
    (set! logger_thread
          (thread
           (lambda ()
             (let ([log_dir (build-path log_path log-date)])
               (when (not (directory-exists? log_dir))
                 (make-directory log_dir))
               (with-output-to-file
                   (build-path log_path log-date
                               (format "~a-~a.log" filename log-date))
                 #:exists 'append
                   (lambda ()
                     (let loop ()
                       (match (sync r)
                         [(vector l m v v1)
                          (printf "~a\n" m)
                          (flush-output)])
                       (loop))))))))))

(define (restart-logger)
  (kill-thread logger_thread)
  (start-logger))

(define (launch-log-daemon log_path filename)
  (start-logger log_path filename)
  (thread
   (lambda ()
     (let loop ()
       (sync
        (alarm-evt (+ (current-inexact-milliseconds) (* 1000 60 60))))
       (when (= 0 (date-hour (seconds->date (current-seconds))))
         (restart-logger))
       (loop)))))
