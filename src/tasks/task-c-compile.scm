;;  This file is part of the arc package
;;  Copyright (C) 2002, 2003, 2009 by Gregor Klinke
;;
;;  This library is free software: you can redistribute it and/or modify
;;  it under the terms of the GNU Lesser General Public License as published
;;  by the Free Software Foundation, either version 3 of the License, or
;;  (at your option) any later version.
;;
;;  This library is distributed in the hope that it will be useful,
;;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;  GNU Lesser General Public License for more details.
;;
;;  You should have received a copy of the GNU General Public License
;;  along with this program.  If not, see <http://www.gnu.org/licenses/>.

(arc:provide 'task-c-compile)
(arc:require 'task-c-deps)

(arc:log 'debug "loading 'c-compile' task")

;; compiles a set of C files into object files.
;;
;; the majority of settings, e.g. which c compiler to use, which default
;; flags to specify, etc. should be set by a system configuration and read
;; in by the master arc-script (if available)
;;
;; keywords:
;;
;; :sources STRLIST
;; a list of c sourcefile names which should be compiled
;;
;; :flags STRING-LIST
;; a list of strings which should be added as flags to the C compiler; this settings
;; depend on the real compiler used, so should be used with care, to ensure portability
;;
;; :includes STRING-LIST
;; a list of additional include directories
;;
;; :depends DEPENDENCIES
;; a list of dependencies as generated by the c-deps task (see there).
;; this target is optional and should normally not be used; if it is missing
;; the dependencies are calculated automatically from the sources
;;
;; :debug? BOOLEAN
;; indicates whether debug information should be compiled in. (default is #f)
;;
;; :ansi? BOOLEAN
;; indicates whether the c compiler should treat the code as pure ansi C. (default is #f)
;;
;; :signed-char? BOOLEAN
;; indicates whether the c compiler should treat chars as signed (default is #f)
;;
;; :warn-level (all|no)
;; specifies the warn level to use.  
;;
;; :opt-level (high|medium|no)
;; specifies the optimization level to be used by the compiler
;;
;; :outdir STRING
;; sets the directory to write the created object file to.  Optional, and defaults to the 
;; base directory of the source file
;;
;; :objext STRING
;; sets the object extension to use; optional and defaults to ".o"
;; 
;; :shared? BOOLEAN
;; should the object files be compiled for a shared library? Defaults to #f.  Settings this
;; property to #t, sets the :objext property automatically to .lo (linkable object), 
;; until :objext is set explicitly.  This is to be able to keep shared and non shared objects 
;; in the same output directory.  On platforms where objects for shared library are identical
;; to those for static libraries this may result in double compilation.
;;
;; the return value is a list of all object files controlled by this task
(define arc:c-compile-keywords '((sources (list attrval) required)
                                 (debug? boolean optional)
                                 (ansi? boolean optional)
                                 (signed-char? boolean optional)
                                 (warn-level symbol optional)
                                 (opt-level symbol optional)
                                 (flags strlist optional)
                                 (includes strlist optional)
                                 (outdir string optional)
                                 (objext string optional)
                                 (sobjext string optional)
                                 (shared? boolean optional)
                                 (static? boolean optional)
                                 (depends dependencies optional)))

(define (arc:c-compile props body)
  (let* ((outdir (arc:aval 'outdir props #f))
         (<backend> ((arc:handler-factory %arc:sysnm% 'task-c-compile) 'alloc))
         (cflags (string-append 
                  "" (arc:string-list->string*
                      (arc:aval 'flags props '())
                                               " ")
                  " "
                  (if (arc:aval 'debug? props #f) 
                      (string-append (<backend> 'debug-flag) " ") "")
                  (if (arc:aval 'ansi? props #f) 
                      (string-append (<backend> 'ansi-flag) " ") "") 
                  (if (arc:aval 'signed-char? props #f)
                      (string-append (<backend> 'signed-char-flag) " ") "")
                  (<backend> 'opt-level-flag (arc:aval 'opt-level props #f))
                  " "                  
                  (<backend> 'warn-level-flag 
                             (arc:aval 'warn-level props #f))))
         (sources (arc:-prepare-c-source-list
                   (arc:aval 'sources props '())))
         (depends (arc:aval 'depends props #f)) 
         (av (arc:attrval)) )
    
    (arc:log 'debug "compile ...")
    
    (for-each
     (lambda (fn)
       (let* ((compile-file 
               (lambda (av-slot av-slot2 objext cfl)
                 (let* ((on (<backend> 'make-objfile-name fn outdir objext))
                        (cincls (arc:string-list->string* 
                                 (arc:aval 'includes props '())
                                 " -I")))
                   
                   (let ((vv (arc:attrval-ref av av-slot) ))
                     (if vv
                         (arc:attrval-set! av av-slot (append vv (list on)))
                         (arc:attrval-set! av av-slot (list on))))
                   (if av-slot2
                       (let ((vv (arc:attrval-ref av av-slot2) ))
                         (if vv
                             (arc:attrval-set! av av-slot2 
                                               (append vv (list on)))
                             (arc:attrval-set! av av-slot2 (list on)))))
                   
                   (if (arc:deps-c-needs-recompile? depends
                                                    fn on 
                                                    (arc:aval 'includes props '())
                                                    (arc:aval 'flags props '())
                                                    objext
                                                    outdir)
                       (begin
                         (arc:log 'verbose "compile '" fn "' into '" on "'")
                         (<backend> 'compile-file
                                  fn     ; source file
                                  on     ; object file
                                  cincls ; c includes
                                  cfl    ; flags
                                  ))))) )
              )

         (if (and (arc:aval 'shared? props #f) 
                  (<backend> 'need-shared-build))
             (compile-file 'shared-objs #f
                           (arc:aval 'sobjext props 
                                     (<backend> 'shared-objfile-ext))
                           (string-append cflags " " 
                                          (<backend> 'shared-obj-flag))))
         (if (or (arc:aval 'static? props #t)
                 (not (<backend> 'need-shared-build)))
             (compile-file 'objs (if (<backend> 'need-shared-build)
                                     #f
                                     'shared-objs)
                           (arc:aval 'objext props 
                                     (<backend> 'objfile-ext))
                           cflags)) ))
     sources)
    av))

(define (arc:deps-c-needs-recompile? depends sfile ofile 
                                     incl flags objext outdir)
  (let ((deps (if depends
                  (let ((va (assoc ofile depends)))
                    (if va (list va) #f))
                  (arc:call-task 'c-deps
                                 (list 'sources (list sfile)
                                       'objext objext
                                       'outdir (if outdir 
                                                   outdir
                                                   '())
                                       'includes incl
                                       'flags flags)
                                 #f) )))
    (if (not (list? deps))
        ;; for some reason we didn't got a dependecy list. assume recompile
        #t
        ;; otherwise check if the object file needs recompilation.  this is
        ;; done generic.  probably once replace the modification time
        ;; method by a md5sum based method?
        (arc:mtime-file-changed? (car deps) ofile))))


(define (arc:-prepare-c-source-list lst)
  (cond
   ((string? lst) (list lst))
   ((list? lst) 
    (arc:reduce (lambda (elt lst)
                  (cond
                   ((string? elt) (cons elt lst))
                   ((arc:attrval? elt)
                    (let ((x (arc:attrval-ref elt 'c-source)))
                      (if (and x
                               (list? x))
                          (append x lst)
                          lst)))
                   ((list? elt)
                    (append (arc:-prepare-c-source-list elt)
                            lst))
                   (else
                    lst)))
                '() 
                lst))
   ((arc:attrval? lst)
    (let ((x (arc:attrval-ref lst 'c-source)))
      (if (and x
               (list? x))
          x
          '())))
   (else
    '())))

(arc:register-task 'c-compile arc:c-compile arc:c-compile-keywords)

;;Keep this comment at the end of the file 
;;Local variables:
;;mode: scheme
;;End:
