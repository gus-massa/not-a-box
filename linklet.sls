(library (linklet)
  (export linklet?
          compile-linklet
          recompile-linklet
          eval-linklet
          read-compiled-linklet
          instantiate-linklet
              
          linklet-import-variables
          linklet-export-variables
          
          instance?
          make-instance
          instance-name
          instance-data
          instance-variable-names
          instance-variable-value
          instance-set-variable-value!
          instance-unset-variable!

          linklet-directory?
          hash->linklet-directory
          linklet-directory->hash

          linklet-bundle?
          hash->linklet-bundle
          linklet-bundle->hash
          
          variable-reference?
          variable-reference->instance
          variable-reference-constant?)
  (import (except (chezscheme)
                  error)
          (hash)
          (error)
          (struct)
          (regexp)
          (bytes)
          (schemify))

  (define (primitive->compiled-position prim) #f)
  (define (compiled-position->primitive pos) #f)

  (define-record-type linklet (fields code name importss exports))
              
  (define compile-linklet
    (case-lambda
     [(c) (compile-linklet c #f #f (lambda (key) (values #f #f)))]
     [(c name) (compile-linklet c name #f (lambda (key) (values #f #f)))]
     [(c name import-keys) (compile-linklet c name import-keys (lambda (key) (values #f #f)))]
     [(c name import-keys get-import)
      (define (get-external-names l)
        (map (lambda (p) (if (pair? p) (cadr p) p)) l))
      (make-linklet (expand (schemify-linklet c primitive-procs))
                    name
                    (map get-external-names (cdadr c))
                    (get-external-names (cdaddr c)))]))

  (define (recompile-linklet . args)
    (error 'recompile-linklet "no"))
  
  (define (eval-linklet linklet)
    (make-linklet (eval (linklet-code linklet))
                  (linklet-name linklet)
                  (linklet-importss linklet)
                  (linklet-exports linklet)))

  (define (read-compiled-linklet in)
    (read in))

  (define instantiate-linklet
    (case-lambda
     [(linklet import-instances)
      (instantiate-linklet linklet import-instances #f #f)]
     [(linklet import-instances target-instance)
      (instantiate-linklet linklet import-instances target-instance #f)]
     [(linklet import-instances target-instance use-prompt?)
      (cond
       [target-instance
        (apply
         (eval (linklet-code linklet))
         (append (apply append
                        (map extract-variables
                             import-instances
                             (linklet-importss linklet)))
                 (create-variables target-instance
                                   (linklet-exports linklet))))]
       [else
        (let ([i (make-instance (linklet-name linklet))])
          (instantiate-linklet linklet import-instances i use-prompt?)
          i)])]))
              
  (define (linklet-import-variables linklet)
    (linklet-importss linklet))

  (define (linklet-export-variables linklet)
    (linklet-exports linklet))

  (define undefined (gensym "undefined"))
  
  (define-record-type variable (fields (mutable val) name))

  (define (variable-set! var val)
    (variable-val-set! var val))

  (define (variable-ref var)
    (define v (variable-val var))
    (if (eq? v undefined)
        (error (variable-name var)
               "undefined;\n cannot reference undefined identifier")
        v))

  (define (extract-variables inst syms)
    (define ht (instance-hash inst))
    (map (lambda (sym)
           (or (hash-ref ht sym #f)
               (error 'instantiate-linklet
                      (string-append
                       "variable not found in imported instance\n"
                       "  instance: ~a\n"
                       "  name: ~a")
                      inst
                      sym)))
         syms))
  
  (define (create-variables inst syms)
    (define ht (instance-hash inst))
    (map (lambda (sym)
           (or (hash-ref ht sym #f)
               (let ([var (make-variable undefined sym)])
                 (hash-set! ht sym var)
                 var)))
         syms))

  (define-record-type (instance new-instance instance?)
    (fields name data hash))

  (define make-instance
    (case-lambda
     [(name) (make-instance name #f)]
     [(name data . content)
      (let ([ht (make-hasheq)])
        (let loop ([content content])
          (cond
           [(null? content) (void)]
           [(null? (cdr content))
            (raise-arguments-error 'make-instance "odd number of arguments")]
           [else
            (hash-set! ht (car content) (cdar content))
            (loop (cdr content))]))
        (new-instance name data ht))]))

  (define (instance-variable-names i)
    (hash-map (instance-hash i) (lambda (k v) k)))

  (define instance-variable-value
    (case-lambda
     [(i sym fail-k)
      (hash-ref (instance-hash i) sym fail-k)]
     [(i sym)
      (instance-variable-value i sym (lambda () (error "instance variable not found:" sym)))]))
  
  (define (instance-set-variable-value! i k v)
    (hash-set! (instance-hash i) k v))

  (define (instance-unset-variable! i k)
    (hash-remove! (instance-hash i) k))

  (define-record-type linklet-directory (fields hash))

  (define (hash->linklet-directory ht)
    (make-linklet-directory ht))
  
  (define (linklet-directory->hash ld)
    (linklet-directory-hash ld))

  (define-record-type linklet-bundle (fields hash))

  (define (hash->linklet-bundle ht)
    (make-linklet-bundle ht))

  (define (linklet-bundle->hash b)
    (linklet-bundle-hash b))

  (define-record variable-reference (var constant? instance-link))
              
  (define (variable-reference->instance vr)
    (car (variable-reference-instance-link vr)))

  (eval `(import (error) (hash-code) (hash) (struct) (bytes) (path) (port)))
  (eval `(define null '()))
  (eval `(define variable-set! ',variable-set!))
  (eval `(define variable-ref ',variable-ref)))