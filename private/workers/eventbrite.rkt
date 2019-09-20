#lang racket

(require 
         gregor
         tzinfo
         simple-http
         json
         (except-in "../hash.rkt" get))

(provide worker-eventbrite)

#|
"https://www.eventbriteapi.com/v3/users/me/?token=PERSONAL_OAUTH_TOKEN
|#

(define remaining (box #f)) ;; start as false to prevent false throttle
(define reset (box 0))

(define api-eventbrite-com
    (update-ssl (update-host json-requester "www.eventbriteapi.com") #t))
    
;; Mash returned JSON into correct JSEXPR shape
(define (convert-json json)
  (for/hasheq ([event (get-in '(events) json)])
    (values (string->symbol (get-in '(id) event))
            (hasheq 'url (get-in '(url) event)
                    ;; convert local e.g. '2019-10-24T19:00:00' to posix timestamp
                    'time (->posix (iso8601->datetime 
                            (get-in '(start local) event)))
                    ;; convert named timezone e.g. 'Europe/Rome' into integer offset (e.g. 3600)
                    'utcOffset (tzoffset-utc-seconds 
                      (utc-seconds->tzoffset 
                        (get-in '(start timezone) event)
                        0))
                    
                    'title (get-in '(name text) event)
                    'description (get-in '(description html) event)
                    'venue (hasheq 'name (get-in '(venue name) event 'null)
                                   'address1 (get-in '(venue address address_1) event)
                                   'address2 (get-in '(venue address address_2) event 'null)
                                   'country (get-in '(venue address country) event)
                                   'city (get-in '(venue address city) event)
                                   'postalCode (get-in '(venue address postal_code) event 'null)
                                   'lon (get-in '(venue longitude) event 'null)
                                   'lat (get-in '(venue latitude) event 'null))
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

    (define params
      `(
        (expand . "venue.address")
        (token . ,(hash-ref config 'eventbrite-access-token))))

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
      (get api-eventbrite-com (format "/v3/organizations/~a/events/" api-id) #:params params))

      
    ;; Return the converted JSON or an error
    (let ([json (convert-json (json-response-body response))])
         (if (jsexpr? json)
             (list id json) ;; we need the id for the filename
             (list 'ERROR (format "Couldn't format ~a into correct JSON" id))))))
