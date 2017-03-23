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


;; Mash returned JSON into correct JSEXPR shape
(define (convert-json json)
  (for/hasheq ([event json])
    (values (string->symbol (get-in '(id) event))
            (hasheq 'url (get-in '(link) event)
                    'time (get-in '(time) event)
                    'utcOffset (get-in '(utc_offset) event)
                    'title (get-in '(name) event)
                    'description (get-in '(description) event)
                    'venue (hasheq 'name (get-in '(venue name) event 'null)
                                   'address1 (get-in '(venue address_1) event)
                                   'address2 (get-in '(venue address_2) event 'null)
                                   'country (get-in '(venue country) event)
                                   'city (get-in '(venue city) event)
                                   'postalCode (get-in '(venue zip) event 'null)
                                   'lon (get-in '(venue lon) event 'null)
                                   'lat (get-in '(venue lat) event 'null))
                    'photos (for/list
                                ([photo (get-in '(photo_album photo_sample) event '())])
                              (hasheq 'url (get-in '(photo_link) photo)
                                      'width 'null
                                      'height 'null))))))

;; Workers should respond with either:
;;
;; ('ERROR "error message in id") <- try to include id in message
;; (id jsexpr?)

(define (worker-meetup logger id payload)
  (apply-throttle logger)
  (define id (car payload))
  (define api-id (get-in '(dataService id) (cdr payload)))
  (define title (get-in '(title) (cdr payload)))

  (define response
    (get httpbin (format "/~a/events" api-id) #:params params))

  (update-throttle (json-response-headers response))

  ;; TODO: remove this
  (printf "remain: ~a | reset: ~a\n" (unbox remaining) (unbox reset))

  ;; Generate correct response, error or jsexpr?
  (cond
    [(exn:fail:network:http:read? response)
     (list 'ERROR (format "Could not read data for ~a" id))]
    [(http-error? response)
     (list 'ERROR (format "~a ~a" id (get-status response)))]
    [(http-success? response)
     (let ([json (list id (convert-json (json-response-body response)))])
       (if (jsexpr? json)
           json
           (list 'ERROR (format "Couldn nor format ~a into correct JSON" id))))]
    [else `(ERROR ,id)]))
