;;  This file is part of the arc package
;;  Copyright (C) 2002, 2003 by Gregor Klinke
;;
;;  This library is free software; you can redistribute it and/or modify it
;;  under the terms of the GNU Lesser General Public License as published
;;  by the Free Software Foundation; either version 2.1 of the License, or
;;  (at your option) any later version.
;;
;;  This library is distributed in the hope that it will be useful, but
;;  WITHOUT ANY WARRANTY; without even the implied warranty of
;;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;  Lesser General Public License for more details.
;;
;;  You should have received a copy of the GNU Lesser General Public
;;  License along with this library; if not, write to the Free Software
;;  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA

;; $Id: task-lib.scm,v 1.1 2003/04/12 00:39:29 eyestep Exp $

(arc:provide 'task-lib)

(arc:require 'oop)

(arc:log 'debug "loading 'lib' task")

(case (car %arc:sysnm%)
  ((linux) (arc:require 'task-lib-linux "linux/task-lib-linux")) )


;; Creates a archive from objects files.  Both the functionality to create
;; static and dynamic libraries are supported.
;;
;; :files STRING-LIST
;; a list of object files to build the library from
;;
;; :static? BOOLEAN
;; if #t build a static library.
;; 
;; :shared? BOOLEAN
;; if #t build a shared library; building a
;; shared library needs a compiler to have produced shared objects (setting
;; an appropriate :shared?  property).
;;
;; :libnm STRING
;; the library name to use.  The real name is build from the platform
;; specific settings and other properties (e.g. version-info for shared
;; libraries) and returned as the task's value
;; 
;; :outdir STRING
;; the directory to build the library in
;;
;; :version-info LIST
;; this information is used for shared libraries on ELF systems.  It should
;; contain 3 integer or string values indicating the "version current",
;; "version revision" and "version age" information.  Ignored for static
;; libraries.
;;
;; :libdirs STRING-LIST
;; for shared libraries on ELF systems only.  A list of directories where
;; to look for depending shared objects/libraries.  Give only the directory
;; itself (without any additional option, e.g. without "-L" for gcc)
;;
;; :addlibs STRING-LIST
;; for shared libraries on ELF systems only.  A list of additional
;; libraries the build library depends on.  The entries has to give the
;; "base library name" only, so for e.g.  libAbcX.so give "AbcX".
;; 
;; RETURNS
;; a attrval containing all created libraries and their used applied
;; (short-)names.  The attrval slot ids are: ':shared (the shared library's
;; main file), ':shared-add-names (additional names [symlinks] for the
;; shared library, a list of strings), ':static (the static library's
;; file).  If the host system supports shared libraries the attrval's
;; default is ':shared.  Additional the slot ':shared-name
;; resp. ':static-name is set, which contains the library name (a library
;; libABC.so's name is ABC)

(define arc:lib-keywords '((files        (strlist attrval) required)
                           (static?      boolean           (req-or shared?))
                           (shared?      boolean           (req-or static?))
                           (libnm        string            required)
                           (outdir       string            optional)
                           (version-info list              optional)
                           (libdirs      strlist           optional)
                           (addlibs      strlist           optional)) )
(define (arc:lib props body)
  (let* ((files* (arc:aval 'files props ()))
         (libnm (arc:aval 'libnm props ""))
         (outdir (arc:aval 'outdir props #f))
         (av (arc:attrval)) 
         
         (<handler> (case (car %arc:sysnm%)
                      ((linux) (arc:make-instance <arc:linux-lib>))
                      (else (begin
                              (arc:log 'error "library support on " 
                                       (car %arc:sysnm%) " is not checked yet")
                              (lambda (x . prms) #f))))) )
    (if (= (string-length libnm) 0)
        (arc:log 'fatal "bad or empty library name"))
    
    (if (arc:aval 'static? props #t)
        (let ((la (<handler> 'make-static-name outdir libnm))
              (files (if (arc:attrval? files*)
                         (arc:attrval-ref files* 'objs)
                         files*)))
          (if (= (length files) 0)
              (arc:log 'info "no object files for library!"))
          
          ;; let the handler build the library
          (if (arc:deps-lib-needs-rebuild? la files)
              (begin
                (arc:log 'debug "make static " la " ...")
                (<handler> 'make-static-lib la files)))

          ;; set the return value
          (arc:attrval-set! av 'static la)
          (arc:attrval-set! av 'static-name libnm)
          (arc:attrval-default-id! av 'static) ))
    
    (if (arc:aval 'shared? props #f)
        (let ((files (if (arc:attrval? files*)
                         (arc:attrval-ref files* 'shared-objs)
                         files*)))
          (if (= (length files) 0)
              (arc:log 'info "no object files for library!"))
          
          (let* ((vi (arc:aval 'version-info props '(0 0 0)))
                 (fullnm (<handler> 'make-shared-name outdir libnm
                                    (car vi) (cadr vi) (caddr vi)))
                 (shnm (<handler> 'make-shared-name-no-version outdir libnm)))
            
            (if (arc:deps-lib-needs-rebuild? fullnm files)
                (begin
                  (arc:log 'debug "make dll " fullnm " ...")
                
                  (<handler> 'make-shared-lib 
                             fullnm files
                             (arc:aval 'libdirs props ())
                             (arc:aval 'addlibs props ()))
                  ;; create additional links for this library (i.e. the
                  ;; short name without the version info added.  This is to
                  ;; support linking against shared libs in the local build
                  ;; directory; note that starting applications linked
                  ;; against shared libs in the local could not be start
                  ;; unless the library is registered with the system
                  ;; e.g. calling ldconfig
                  (arc:sys.symlink 
                   (arc:path->string (arc:path-absolutize 
                                      (arc:string->path fullnm)))
                   (arc:path->string (arc:path-absolutize 
                                      (arc:string->path shnm)))) ))
            (arc:attrval-set! av 'shared fullnm)
            (arc:attrval-set! av 'shared-name libnm)
            (arc:attrval-set! av 'shared-add-names (list shnm))
            (arc:attrval-default-id! av 'shared)))
        )
    av))


(define (arc:deps-lib-needs-rebuild? libnm objs)
  (if (not (arc:sys.file-exists? libnm))
      #t
      (let ((libmt (arc:sys.get-mtime libnm)))
        (let loop ((obj objs))
          (if (null? obj)
              #f
              (or (< libmt (arc:sys.get-mtime (car obj)))
                  (loop (cdr obj))))))))


(arc:register-task 'lib arc:lib arc:lib-keywords)

;; compile: gcc -c -fpic -DPIC srcfile -o outfile     X
;; link to .so: gcc -shared -o libxxx.so objects      X
;; link to app: gcc -lxx -o app obj files

;;Keep this comment at the end of the file 
;;Local variables:
;;mode: scheme
;;End:
