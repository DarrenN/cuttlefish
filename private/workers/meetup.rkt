#lang racket

(require simple-http
         json
         (except-in "../hash.rkt" get))

(provide worker-meetup)

(define remaining (box #f)) ;; start as false to prevent false throttle
(define reset (box 0))

(define (apply-throttle logger)
  (let ([remain (unbox remaining)]
        [reset (unbox reset)])
    (when (and (not (false? remain)) (< remain 2))
      (logger "~a" (format "Throttled meetup for ~a from ~a seconds" reset remain))
      (sleep reset))))

(define (update-throttle headers)
  (let ([remain (car (get-in '(X-Ratelimit-Remaining) headers))]
        [res (car (get-in '(X-Ratelimit-Reset) headers))])
    (set-box! remaining (string->number remain))
    (set-box! reset res)))

(define httpbin
  (update-ssl (update-host json-requester "api.meetup.com") #t))

(define params
  '((photo-host . "public")
    (fields . "photo_album")
    (sign . "true")
    (status . "upcoming,past")))

(define (worker-meetup logger id payload)
  (apply-throttle logger)
  (define id (car payload))
  (define api-id (get-in '(dataService id) (cdr payload)))
  (define title (get-in '(title) (cdr payload)))

  (define response
    (get httpbin (format "/~a/events" api-id) #:params params))

  (update-throttle (json-response-headers response))

  ;; TODO: convert response into correct JSON schema

  ;; TODO: remove this
  (printf "remain: ~a | reset: ~a\n" (unbox remaining) (unbox reset))

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
