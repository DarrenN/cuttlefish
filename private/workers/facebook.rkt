#lang racket

(require simple-http
         gregor
         json
         racket/string
         (except-in "../hash.rkt" get))

(provide worker-facebook)

#|
"https://graph.facebook.com/v2.9/1535170340032623/events?since=n&access_token=n
|#

(define graph-facebook-com
  (update-ssl (update-host json-requester "graph.facebook.com") #t))

;; Convert FB's ISO8601 offset into a format Gregor can deal with, also
;; return utcOffset in milliseconds
;; `(Int Int)
(define (get-epoch str)
  (let* ([offset (substring str (- (string-length str) 4) (string-length str))]
         [iso-offset
          (format "~a:~a" (substring offset 0 2) (substring offset 2 4))]
         [new-iso-str (string-replace str offset iso-offset)])
    (list (* (->posix (iso8601->datetime new-iso-str)) 1000)
          (* (string->number (substring iso-offset 0 2)) 60 60 1000))))

;; Mash returned JSON into correct JSEXPR shape
(define (convert-json json)
  (let ([data (hash-ref json 'data)])
    (for/hasheq ([event data])
      (let ([epoch (get-epoch (get-in '(start_time) event))])
        (values
         (string->symbol (get-in '(id) event))
         (hasheq 'url (format "https://facebook.com/~a" (get-in '(id) event))
                 'time (car epoch)
                 'utcOffset (last epoch)
                 'title (get-in '(name) event)
                 'description (get-in '(description) event)
                 'venue (hasheq
                         'name (get-in '(place name) event 'null)
                         'address1 (get-in '(place location street) event)
                         'address2 'null
                         'country (get-in '(place location country) event)
                         'city (get-in '(place location city) event)
                         'postalCode (get-in '(place location zip) event 'null)
                         'lon (get-in '(place location longitude) event 'null)
                         'lat (get-in '(place location latitude) event 'null))
                 'photos 'null))))))

;; Workers should respond with either:
;;
;; ('ERROR "error message in id") <- try to include id in message
;; (id jsexpr?)

(define (worker-facebook logger id config payload)
  (let ([id (car payload)]
        [api-id (get-in '(dataService id) (cdr payload))]
        [title (get-in '(title) (cdr payload))])
    
    (define params
      `((since . "132001640")
        (access_token . ,(hash-ref config 'facebook-access-token))))

    ;; Wrap request in handlers to deal with errors gracefully
    (with-handlers
        ([exn:fail:network:http:error?
          (λ (e)
            (list 'ERROR (format "Couldn't fetch ~a: ~a"
                                 id (exn:fail:network:http:error-code e))))]
         [exn:fail:network:http:read?
          (λ (e)
            (list 'ERROR (format "Could not read data for ~a" id)))])
      
      (define response
        (get graph-facebook-com (format "/v2.9/~a/events" api-id)
             #:params params))
      
      ;; Return the converted JSON or an error
      (let ([json (convert-json (json-response-body response))])
        (if (jsexpr? json)
            (list id json) ;; we need the id for the filename
            (list 'ERROR
                  (format "Couldn't format ~a into correct JSON" id)))))))