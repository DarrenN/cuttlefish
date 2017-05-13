#lang racket
(require json
         yaml)

(define CHAPTERS-YAML
  (build-path (current-directory) "private" "data" "chapters.yml"))

(define CHAPTERS-JSON-PATH
  (build-path (current-directory) "private" "data" "chapters.json"))

(define CHAPTERS
  (call-with-input-file CHAPTERS-YAML (λ (in) (read-yaml in))))

#|

JSON format

{
  "newyork": {
    "title": "New York",
    "dataService": {
      "adapter": "meetup",
      "id": "papers-we-love"
    }
  }
}
|#

(define CHAPTER-JSON
  (for/hasheq ([v CHAPTERS])
    (values (string->symbol (hash-ref v "name"))
            (hasheq 'title (hash-ref v "title")
                    'dataService (hasheq 'adapter "meetup"
                                         'id (hash-ref v "meetup_url"))))))

(define (convert)
  (with-output-to-file CHAPTERS-JSON-PATH #:mode 'text #:exists 'replace
    (λ () (display (jsexpr->string CHAPTER-JSON)))))