#lang racket

;; Hash Utilities
;; ==============

;; Contracts

(provide (contract-out
          [hash-refs (->* ((listof any/c) hash?) (any/c) any)]
          [get-in (->* ((listof any/c)) (hash? any/c)
                       (or/c
                        (->* (hash?) (any/c) any)
                        any/c))]
          [get (-> any/c
                   (->* () () #:rest (or/c
                                      (list/c hash?)
                                      (list/c hash? any/c))
                        any))]))

;; hash-refs
;; =========
;;
;; Recursively call hash-ref from a list of keys
;; http://www.greghendershott.com/fear-of-macros/
;;
;; example:
;;    (hash-refs '(a b c) (hash 'a (hash 'b (hash 'c 2)))) -> 2
;;    (hash-refs '(a d) (hash 'a 2) 10) -> 10

(define (hash-refs ks h [def #f])
  (with-handlers ([exn:fail? (const (cond [(procedure? def) (def)]
                                          [else def]))])
    (for/fold ([h h])
              ([k (in-list ks)])
      (hash-ref h k))))

;; get-in
;; ======
;;
;; Extract a path of (nested) keys from a hash
;; If you omit the hash returns a lambda bound to keys
;; Has an optional "default" return value if key doesn't exist
;;
;; example:
;;    (get-in '(a b) (hasheq 'a (hasheq 'b 12))) -> 12
;;    (get-in '(c) (hasheq 'a 12)) -> #f
;;    (get-in '(c) (hasheq 'a 12) "boo") -> "boo"
;;    (define get-b (get-in '(a b)))
;;    (get-b (hash 'a (hash 'b (hash 'c 2)))) -> (hash 'c 2)

(define (get-in ks . h)
  (if (null? h)
      (curry get-in ks)
      (apply hash-refs (append (list ks) h))))

;; get
;; ===
;;
;; Partially apply a key and a default value to hash-ref
;;
;; example:
;;    (define get-a (get 'a))
;;    (get-a (hash 'a 12)) -> 12
;;    (get-a (hash 'b "wu")) -> #f
;;    (get-a (hash 'b "wu") "tang") -> "tang"

(define ((get ks) . args)
  (apply hash-ref (append '() (list (car args)) (list ks) (cdr args))))

;; Tests
;; ===============

(module+ test
  (require rackunit
           quickcheck)
  
  (define foo (hash 'a 1
                    'b (hash 'bb 1
                             'cc (hash 'ccc 12))
                    'c "foo"))
  
  ;; Returns #f is it cannot find the value
  (check-equal?
   (hash-refs '(b bb ccc) foo) #f)
  
  ;; Returns fall with invalid keys
  (check-equal?
   (hash-refs '(d zz) foo) #f)
  
  ;; Fails and returns failure-result
  (check-equal?
   (hash-refs '(b dd) foo "nope") "nope")
  
  ;; Gets value
  (check-equal?
   (hash-refs '(b cc ccc) foo) 12)
  
  ;; Non-list returns #f
  (check-equal? (hash-refs "foo" foo) #f)
  
  ;; Generate a hash from a list (must be non-empty) with a value of y
  (define (not-empty-hash xs y)
    (foldr (λ (l r)
             (hash-set r (first xs)
                       (hash l (hash-ref r (first xs)))))
           (hash (first xs) y)
           (rest xs)))
  
  ;; It will find a value in a validly-nested hash
  (define hash-ref-has-nest
    (property ([xs (arbitrary-list
                    arbitrary-ascii-char)]
               [y arbitrary-integer])
              (let* ([xss (if (empty? xs) '(1 2) xs)]
                     [hsh (not-empty-hash xss y)])
                (equal? (hash-refs xss hsh) y))))
  
  (quickcheck hash-ref-has-nest)
  
  ;; It will not find a value in a validly-nested hash
  (define hash-ref-not-has-nest
    (property ([xs (arbitrary-list
                    arbitrary-ascii-char)]
               [z arbitrary-integer])
              (let* ([xss (if (empty? xs) (list (random 100) (random 100)) xs)]
                     [hsh (not-empty-hash xss z)])
                (not (equal? (hash-refs (cdr xss) hsh "f") z)))))
  
  (quickcheck hash-ref-not-has-nest)
  
  ;; Passing en empty list will return the hash
  (define hash-ref-empty-list
    (property ([xs (arbitrary-list
                    arbitrary-ascii-char)]
               [y arbitrary-integer])
              (let* ([xss (if (empty? xs) '(1 2) xs)]
                     [hsh (not-empty-hash xss y)])
                (equal? (hash-refs '() hsh) hsh))))
  
  (quickcheck hash-ref-empty-list)
  
  (define j (hash 'a (hash 'b (hash 'c 2))))
  (define k (hash 'a (hash 'd (hash 'c 2))))

  (check-equal? (get-in '(a b c) j) 2)
  (check-equal? (get-in '(a b) j) (hash 'c 2))
  (check-equal? (get-in '(z) j "boo") "boo")
  
  (define get-a (get-in '(a)))
  (define get-b (get-in '(a b)))
  (define get-c (get-in '(a b c)))
  (define get-f (get-in '(a f)))
  
  (check-equal? ((get-in '(a b c)) j) 2)
  (check-equal? ((get-in '(a b c)) k) #f)
  (check-equal? ((get-in '(a b c)) k "boo") "boo")
  
  (check-equal? (get-a j) (hash-refs '(a) j))
  (check-equal? (get-b j) (hash-refs '(a b) j))
  (check-equal? (get-c j) (hash-refs '(a b c) j))
  (check-equal? (get-f j) #f)
  (check-equal? (get-f j "boo") "boo")
  
  (check-equal? ((get 'a) j) (hash-ref j 'a))
  (check-equal? ((get 'z) j "foo") "foo"))

