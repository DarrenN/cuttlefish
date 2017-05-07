#lang racket
(provide chunk-list)

;; Split a list into ct chunks as best you can
;; ex: (chunk-list (range 0 12) 3) -> '((0 1 2 3) (4 5 6 7) (8 9 10 11 12))
(define (chunk-list ls ct)
  (define n (round (/ (length ls) ct)))
  (define (loop ls ct ac)
    (cond [(empty? ls)
           (reverse ac)]
          [(< (length ls) n)
           (if (equal? (length ac) ct)
               (reverse (cons (append (car (take ac 1)) ls)
                              (drop ac 1)))
               (reverse (cons ls ac)))]
          [else
           (loop (drop ls n) ct (cons (take ls n) ac))]))
  (loop ls ct '()))

(module+ test
  (require rackunit)

  (check-equal?
   (chunk-list (range 0 12) 3)
   '((0 1 2 3) (4 5 6 7) (8 9 10 11)))

  (check-equal?
   (chunk-list '((1 . 2) (1 . 3) (1 . 4)) 3)
   '(((1 . 2)) ((1 . 3)) ((1 . 4))))

(check-equal?
   (chunk-list '((1 . 2) (1 . 3) (1 . 4) (1 . 5) (1 . 6) (1 . 7) (1 . 8)) 3)
   '(((1 . 2) (1 . 3)) ((1 . 4) (1 . 5)) ((1 . 6) (1 . 7) (1 . 8)))))