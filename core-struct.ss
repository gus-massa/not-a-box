(define-record struct-type-prop (name table guard))

(define rtd-props (make-weak-eq-hashtable))
(define rtd-inspectors (make-weak-eq-hashtable))

(define make-struct-type-property
  (case-lambda
    [(name) (make-struct-type-property name #f '() #f)]
    [(name guard) (make-struct-type-property name guard '() #f)]
    [(name guard supers) (make-struct-type-property name guard supers #f)]
    [(name guard supers can-inpersonate?)
     (define table (make-weak-eq-hashtable))
     (values (make-struct-type-prop name table guard)
             (lambda (v) (and (record? v)
                         (not (eq? none (hashtable-ref table (record-rtd v) none)))))
             (lambda (v)
               (hashtable-ref table (record-rtd v) #f)))]))

(define-record-type (inspector new-inspector inspector?) (fields parent))

(define root-inspector (new-inspector #f))

(define (inspector-superior? sup-insp sub-insp)
  (if (eq? sub-insp root-inspector)
      #f
      (let ([parent (inspector-parent sub-insp)])
        (or (eq? parent sup-insp)
            (inspector-superior? sup-insp parent)))))

(define-record position-based-accessor (rtd offset field-count))
(define-record position-based-mutator (rtd offset field-count))

(define make-struct-type
  (case-lambda 
    [(name parent-rtd fields auto-fields)
     (make-struct-type name parent-rtd fields auto-fields #f '() (current-inspector) #f '() #f name)]
    [(name parent-rtd fields auto-fields auto-val)
     (make-struct-type name parent-rtd fields auto-fields auto-val '() (current-inspector) #f '() #f name)]
    [(name parent-rtd fields auto-fields auto-val props)
     (make-struct-type name parent-rtd fields auto-fields auto-val props (current-inspector) #f '() #f name)]
    [(name parent-rtd fields auto-fields auto-val props insp)
     (make-struct-type name parent-rtd fields auto-fields auto-val props insp #f '() #f name)]
    [(name parent-rtd fields auto-fields auto-val props insp proc-spec)
     (make-struct-type name parent-rtd fields auto-fields auto-val props insp proc-spec '() #f name)]
    [(name parent-rtd fields auto-fields auto-val props insp proc-spec immutables)
     (make-struct-type name parent-rtd fields auto-fields auto-val props insp proc-spec immutables #f name)]
    [(name parent-rtd fields auto-fields auto-val props insp proc-spec immutables guard)
     (make-struct-type name parent-rtd fields auto-fields auto-val props insp proc-spec immutables guard name)]
    [(name parent-rtd fields-count auto-fields auto-val props insp proc-spec immutables guard constructor-name)
     (unless (zero? auto-fields)
       (error 'make-struct-type "auto fields not supported"))
     (let* ([fields (let loop ([fields fields-count])
                      (if (zero? fields)
                          '()
                          (cons (string->symbol (format "a~a" fields))
                                (loop (sub1 fields)))))]
            [rtd (if parent-rtd
                     (make-record-type parent-rtd (symbol->string name) fields)
                     (make-record-type (symbol->string name) fields))]
            [parent-count (if parent-rtd
                              (struct-type-field-count parent-rtd)
                              0)])
       (struct-type-install-properties! rtd name fields-count auto-fields parent-rtd
                                        props insp proc-spec immutables guard name)
       (values rtd
               (record-constructor rtd)
               (lambda (v) (record? v rtd))
               (make-position-based-accessor rtd parent-count (+ fields-count auto-fields))
               (make-position-based-mutator rtd parent-count (+ fields-count auto-fields))))]))

(define struct-type-install-properties!
  (case-lambda
    [(rtd name fields auto-fields parent-rtd)
     (struct-type-install-properties! rtd parent-rtd '() (current-inspector) #f '() #f name)]
    [(rtd name fields auto-fields parent-rtd props)
     (struct-type-install-properties! rtd parent-rtd props '(current-inspector) #f '() #f name)]
    [(rtd name fields auto-fields parent-rtd props insp)
     (struct-type-install-properties! rtd parent-rtd props insp #f name)]
    [(rtd name fields auto-fields parent-rtd props insp proc-spec)
     (struct-type-install-properties! rtd parent-rtd props insp proc-spec '() #f name)]
    [(rtd name fields auto-fields parent-rtd props insp proc-spec immutables)
     (struct-type-install-properties! rtd parent-rtd props insp proc-spec immutables #f name)]
    [(rtd name fields auto-fields parent-rtd props insp proc-spec immutables guard)
     (struct-type-install-properties! rtd parent-rtd props insp proc-spec immutables guard name)]
    [(rtd name fields auto-fields parent-rtd props insp proc-spec immutables guard constructor-name)
     (define parent-props
       (cond
        [parent-rtd
         (let ([props (hashtable-ref rtd-props parent-rtd '())])
           (for-each (lambda (prop)
                       (define table (struct-type-prop-table prop))
                       (hashtable-set! table rtd (hashtable-ref table parent-rtd #f)))
                     props)
           props)]
        [else
         '()]))
     (hashtable-set! rtd-props rtd (let ([props (append (map car props) parent-props)])
                                     (if proc-spec
                                         (cons prop:procedure props)
                                         props)))
     (for-each (lambda (prop+val)
                 (let ([prop (car prop+val)]
                       [val (cdr prop+val)])
                   (hashtable-set! (struct-type-prop-table prop)
                                   rtd
                                   (let ([guard (struct-type-prop-guard prop)])
                                     (if guard
                                         (let ([parent-count (if parent-rtd
                                                                 (struct-type-field-count parent-rtd)
                                                                 0)])
                                           (guard val
                                                  (list name
                                                        fields
                                                        auto-fields
                                                        (make-position-based-accessor rtd parent-count (+ fields auto-fields))
                                                        (make-position-based-mutator rtd parent-count (+ fields auto-fields))
                                                        immutables
                                                        parent-rtd
                                                        #f)))
                                         val)))))
               props)
     (when proc-spec
       (hashtable-set! (struct-type-prop-table prop:procedure) rtd proc-spec))
     (hashtable-set! rtd-inspectors rtd insp)]))

(define make-struct-field-accessor
  (case-lambda
    [(pba pos)
     (record-field-accessor (position-based-accessor-rtd pba)
                            (+ pos (position-based-accessor-offset pba)))]
    [(pba pos name)
     (make-struct-field-accessor pba pos)]))
(define make-struct-field-mutator
  (case-lambda
    [(pbm pos)
     (record-field-mutator (position-based-mutator-rtd pbm)
                           (+ pos (position-based-mutator-offset pbm)))]
    [(pbm pos name)
     (make-struct-field-mutator pbm pos)]))

(define struct? record?)
(define struct-type? record-type-descriptor?)
(define struct-type record-rtd)

(define (struct-type-field-count rtd)
  (+ (let ([p-rtd (record-type-parent rtd)])
       (if p-rtd
           (struct-type-field-count p-rtd)
           0))
     (vector-length (record-type-field-names rtd))))

(define (struct-type-parent-field-count rtd)
  (let ([p-rtd (record-type-parent rtd)])
    (if p-rtd
        (struct-type-field-count p-rtd)
        0)))

(define (unsafe-struct-ref s i)
  (#3%vector-ref s i))
(define (unsafe-struct-set! s i v)
  (#3%vector-set! s i v))

(define-values (prop:equal+hash equal+hash? equal+hash-ref)
  (make-struct-type-property 'equal+hash
                             (lambda (val info)
                               (cons (gensym) val))))

(define (struct-type-equality rtd)
  (let ([v (hashtable-ref (struct-type-prop-table prop:equal+hash) rtd #f)])
    (if v
        (values (cadr v) (car v))
        (values #f #f))))

(define (struct-equal-hashity r)
  (let ([v (hashtable-ref (struct-type-prop-table prop:equal+hash) (record-rtd r) #f)])
    (and v
         (caddr v))))

(define (struct-type-transparent? rtd)
  (let ([insp (hashtable-ref rtd-inspectors rtd #f)])
    (and (or (not insp)
             (inspector-superior? (current-inspector) insp))
         (let ([p-rtd (record-type-parent rtd)])
           (or (not p-rtd)
               (struct-type-transparent? p-rtd))))))

(define (struct-transparent-type r)
  (let ([t (record-rtd r)])
    (and (struct-type-transparent? t)
         t)))

(define (struct->vector s)
  (if (record? s)
      (let ([rtd (record-rtd s)])
        ;; Create that vector that has '... for opaque ranges and each field
        ;; value otherwise
        (let-values ([(vec-len rec-len)
                      ;; First, get the vector and record sizes
                      (let loop ([vec-len 1] [rec-len 0] [rtd rtd] [dots-already? #f])
                        (cond
                         [(not rtd) (values vec-len rec-len)]
                         [else
                          (let ([insp (hashtable-ref rtd-inspectors rtd #f)]
                                [len (vector-length (record-type-field-names rtd))])
                            (cond
                             [(or (not insp)
                                  (inspector-superior? (current-inspector) insp))
                              ;; A transparent region
                              (loop (+ vec-len len) (+ rec-len len) (record-type-parent rtd) #f)]
                             [dots-already?
                              ;; An opaque region that follows an opaque region
                              (loop vec-len (+ rec-len len) (record-type-parent rtd) #t)]
                             [else
                              ;; The start of opaque regions
                              (loop (add1 vec-len) (+ rec-len len) (record-type-parent rtd) #t)]))]))])
          ;; Walk though the record's types again, this time filling in the vector
          (let ([vec (make-vector vec-len '...)])
            (vector-set! vec 0 (string->symbol (format "struct:~a" (record-type-name rtd))))
            (let loop ([vec-pos vec-len] [rec-pos rec-len] [rtd rtd] [dots-already? #f])
              (when rtd
                (let* ([insp (hashtable-ref rtd-inspectors rtd #f)]
                       [len (vector-length (record-type-field-names rtd))]
                       [rec-pos (- rec-pos len)])
                  (cond
                   [(or (not insp)
                        (inspector-superior? (current-inspector) insp))
                    ;; Copy over a transparent region
                    (let ([vec-pos (- vec-pos len)])
                      (let floop ([n 0])
                        (cond
                         [(= n len) (loop vec-pos rec-pos (record-type-parent rtd) #f)]
                         [else
                          (vector-set! vec (+ vec-pos n) (unsafe-struct-ref s (+ rec-pos n)))
                          (floop (add1 n))])))]
                   [dots-already?
                    ;; Skip another opaque region
                    (loop vec-pos rec-pos (record-type-parent rtd) #t)]
                   [else
                    ;; The vector already has '...
                    (loop (sub1 vec-pos) rec-pos (record-type-parent rtd) #t)]))))
            vec)))
      ;; Any value that is not implemented as a record is treated as
      ;; a fully opaque struct
      (vector (string->symbol (format "struct:~a" ((inspect/object s) 'type))) '...)))

;; ----------------------------------------

(define (exact-nonnegative-integer? v)
  (and (integer? v)
       (exact? v)
       (not (negative? v))))

(define (prefab-key? k)
  (or (symbol? k)
      (and (pair? k)
           (symbol? (car k))
           (let* ([k (cdr k)] ; skip name
                  [prev-k k]
                  ;; The initial field count can be omitted:
                  [k (if (and (pair? k)
                              (exact-nonnegative-integer? (car k)))
                         (cdr k)
                         k)]
                  [field-count (if (eq? prev-k k)
                                   #f
                                   (car prev-k))])
             (let loop ([field-count field-count] [k k]) ; `k` is after name and field count
               (or (null? k)
                   (and (pair? k)
                        (let* ([prev-k k]
                               [k (if (and (pair? (car k))
                                           (pair? (cdar k))
                                           (null? (cddar k))
                                           (exact-nonnegative-integer? (caar k)))
                                      ;; Has a (list <auto-count> <auto-val>) element
                                      (cdr k)
                                      ;; Doesn't have auto-value element:
                                      k)]
                               [auto-count (if (eq? prev-k k)
                                               0
                                               (caar prev-k))])
                          (or (null? k)
                              (and (pair? k)
                                   (let* ([k (if (and (pair? k)
                                                      (vector? (car k)))
                                                 ;; Make sure it's a vector of indices
                                                 ;; that are in range and distinct:
                                                 (let* ([vec (car k)]
                                                        [len (vector-length vec)])
                                                   (let loop ([i 0] [set 0])
                                                     (cond
                                                      [(= i len) (cdr k)]
                                                      [else
                                                       (let ([pos (vector-ref vec i)])
                                                         (and (exact-nonnegative-integer? pos)
                                                              (or (not field-count)
                                                                  (< pos (+ field-count auto-count)))
                                                              (not (bitwise-bit-set? set pos))
                                                              (loop (add1 i) (bitwise-ior set (bitwise-arithmetic-shift-left 1 pos)))))])))
                                                 k)])
                                     (or (null? k)
                                         (and (pair? k)
                                              ;; Supertype: make sure it's a pair with a
                                              ;; symbol and a field count, and loop:
                                              (symbol? (car k))
                                              (pair? (cdr k))
                                              (exact-nonnegative-integer? (cadr k))
                                              (loop (cadr k) (cddr k)))))))))))))))

(define (prefab-struct-key v) #f)
(define (prefab-key->struct-type key field-count) #f)
(define (make-prefab-struct key args) (error 'make-prefab-struct "not ready"))

;; ----------------------------------------

(define-values (prop:procedure procedure-struct? procedure-struct-ref)
  (make-struct-type-property 'procedure))

(define (procedure-or-applicable-struct? v)
  (or (procedure? v)
      (and (record? v)
           (hashtable-ref (struct-type-prop-table prop:procedure) (record-rtd v) #f))))

(define apply/extract
  (case-lambda
    [(proc args)
     (if (procedure? proc)
         (apply proc args)
         (apply (extract-procedure proc) args))]
    [(proc . argss)
     (if (procedure? proc)
         (apply apply proc argss)
         (apply apply (extract-procedure proc) argss))]))

(define-syntax |#%app|
  (syntax-rules ()
    [(_ rator rand ...)
     ((extract-procedure rator) rand ...)]))

(define (extract-procedure f)
  (cond
   [(procedure? f) f]
   [else (try-extract-procedure f)]))

(define (try-extract-procedure f)
  (cond
   [(record? f)
    (let ()
      (define rtd (record-rtd f))
      (define v (hashtable-ref (struct-type-prop-table prop:procedure) rtd #f))
      (cond
       [(procedure? v) (lambda args (apply v f args))]
       [(fixnum? v) (unsafe-struct-ref f v)]
       [else (not-a-procedure f)]))]
   [else (not-a-procedure f)]))

(define (not-a-procedure f)
  (error 'apply (format "not a procedure: ~s" f)))

;; ----------------------------------------

(define-values (prop:method-arity-error method-arity-error? method-arity-error-ref)
  (make-struct-type-property 'method-arity-error))

;; ----------------------------------------

(define (set-primitive-applicables!)
  (hashtable-set! (struct-type-prop-table prop:procedure)
                  (record-type-descriptor position-based-accessor)
                  (lambda (pba s p)
                    (if (and (record? s (position-based-accessor-rtd pba))
                             (< p (position-based-accessor-field-count pba)))
                        (unsafe-struct-ref s (+ p (position-based-accessor-offset pba)))
                        (error 'struct-ref "bad access"))))

  (hashtable-set! (struct-type-prop-table prop:procedure)
                  (record-type-descriptor position-based-mutator)
                  (lambda (pbm s p v)
                    (if (and (record? s (position-based-mutator-rtd pbm))
                             (< p (position-based-mutator-field-count pbm)))
                        (unsafe-struct-set! s (+ p (position-based-mutator-offset pbm)) v)
                        (error 'struct-set! "bad assignment")))))