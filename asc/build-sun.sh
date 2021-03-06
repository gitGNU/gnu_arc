#! /bin/sh

# expects the following environment parameters set
# ASC_HOME   - gives the home directory where to install the asc init files 

# build script for unix environments
echo "#define ARC_HOME \"$ASC_HOME\"" > scmenv.h
echo "#define IMPLINIT \"$ASC_HOME/asc-init.scm\"" >> scmenv.h
echo "#define INIT_FILE_NAME \"asc-init.scm\"" >> scmenv.h

# Compile C source files
echo "Compiling asc source files ..."
gcc -O -c ioext.c continue.c scm.c scmmain.c findexec.c script.c time.c repl.c scl.c eval.c sys.c subr.c debug.c unif.c rope.c

# Link C object files
echo "Linking asc ..."
gcc -o asc ioext.o continue.o scm.o scmmain.o findexec.o script.o time.o repl.o scl.o eval.o sys.o subr.o debug.o unif.o rope.o -lm -lc

