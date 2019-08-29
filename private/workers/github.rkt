#lang errortrace racket

(require simple-http
         json
         (except-in "../hash.rkt" get))

(provide worker-github)

(define api-github
  ; use raw.githack.com to get correct Content-Type: application/json 
  (update-ssl (update-host json-requester "raw.githack.com") #t))

;; Workers should respond with either:
;;
;; ('ERROR "error message in id") <- try to include id in message
;; (id jsexpr?)

(define (worker-github logger id config payload)
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
          (list 'ERROR (format "Could not read data for ~a: ~a" id e)))])

    (printf  "/~a/master/data/events.json\n" api-id)
    (define response
      (get api-github (format "/~a/master/data/events.json" api-id)))

    ;; TODO: remove this
    ;(printf "remain: ~a | reset: ~a\n" (unbox remaining) (unbox reset))

    ;; Return the converted JSON or an error
    (let ([json (json-response-body response)])
         (if (jsexpr? json)
             (list id json) ;; we need the id for the filename
             (list 'ERROR (format "Couldn't format ~a into correct JSON" id))))))
