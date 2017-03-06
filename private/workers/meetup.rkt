#lang racket

(require simple-http
         (except-in "../hash.rkt" get))

(provide worker-meetup)

(define throttle (box 0))

(define (make-throttle)
  (if (equal? (random 1 4) 3)
    (set-box! throttle (random 1 5))
    (set-box! throttle 0)))

(define (handle-throttle logger)
  (let ([t (unbox throttle)])
    (when (> t 0)
      (logger "~a" (format "throttled ant for ~a seconds" t))
      (sleep t)))
  (make-throttle))

(define httpbin
  (update-ssl (update-host json-requester "httpbin.org") #t))

(define (worker-meetup logger id payload)
  ;(handle-throttle logger)
  (define id (car payload))
  (define api-id (get-in '(dataService id) (cdr payload)))
  (define title (get-in '(title) (cdr payload)))

  (define response
    (get httpbin "/get" #:params `((id . ,api-id) (title . ,title))))

  ;; Workers should respond with either:
  ;;
  ;; ('ERROR "error message") <- try to include id in message
  ;; (id jsexpr?)
  (cond
    [(exn:fail:network:http:read? response)
     (list 'ERROR (format "Could not read data for ~a" id))]
    [(http-error? response)
     (list 'ERROR (format "~a ~a" id (get-status response)))]
    [(http-success? response)
     (list id (json-response-body response))]
    [else `(ERROR ,id)]))
