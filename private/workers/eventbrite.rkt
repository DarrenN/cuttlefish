#lang racket

(require simple-http
         json
         (except-in "../hash.rkt" get))

(provide worker-eventbrite)

(define remaining (box #f)) ;; start as false to prevent false throttle
(define reset (box 0))

(define api-eventbrite-com
  (update-headers 
    (update-ssl (update-host json-requester "www.eventbriteapi.com") #t)
    '("Authorization: Bearer ????API_TOKEN???"))) ;; fixme: get API token from config


;; Mash returned JSON into correct JSEXPR shape
(define (convert-json json)
  (for/hasheq ([event (get-in '(events) json)])
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

(define (worker-eventbrite logger id config payload)
  (define id (car payload))
  (define api-id (get-in '(dataService id) (cdr payload)))
  (define title (get-in '(title) (cdr payload)))

  ;; Wrap API call with exception handlers that pass errors back up to the
  ;; worker for logging
  (with-handlers
      ([exn:fail:network:http:error?
        (λ (e)
          (list 'ERROR (format "Couldn't fetch ~a: ~a"
                               id (exn:fail:network:http:error-code e))))]
       [exn:fail:network:http:read?
        (λ (e)
          (list 'ERROR (format "Could not read data for ~a" id)))])

    (define response
      (get api-eventbrite-com (format "/v3/organizations/~a/events/" api-id) )) 
      
    ;; Return the converted JSON or an error
    (let ([json (convert-json (json-response-body response))])
         (if (jsexpr? json)
             (list id json) ;; we need the id for the filename
             (list 'ERROR (format "Couldn't format ~a into correct JSON" id))))))
